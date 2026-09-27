// The deployed web app in Chromium: pen input through CDP, saving to the
// origin-private file system (?root=opfs), reload, and offline start.
/// <reference path="../src/window.d.ts" />
import { expect, test, type Page } from "@playwright/test";
import { readFile } from "node:fs/promises";

const APP = "?root=opfs";

// Opens the app on an empty origin-private file system. The clearing runs on
// a page of the origin without the app, which holds no file of it open.
async function startEmpty(page: Page): Promise<void> {
  await page.goto("favicon.svg");
  await page.evaluate(async () => {
    const root = await navigator.storage.getDirectory();
    for await (const name of root.keys()) await root.removeEntry(name, { recursive: true });
  });
  await page.goto(APP);
}

// A pen stroke through CDP Input.dispatchMouseEvent, in page coordinates.
async function drawWithPen(page: Page, points: { x: number; y: number }[]): Promise<void> {
  const cdp = await page.context().newCDPSession(page);
  const pen = { pointerType: "pen" as const, force: 0.6, tiltX: 20, tiltY: -10 };
  await cdp.send("Input.dispatchMouseEvent", { type: "mousePressed", button: "left", clickCount: 1, ...points[0], ...pen });
  for (const p of points.slice(1)) {
    await cdp.send("Input.dispatchMouseEvent", { type: "mouseMoved", button: "left", buttons: 1, ...p, ...pen });
  }
  const last = points[points.length - 1];
  await cdp.send("Input.dispatchMouseEvent", { type: "mouseReleased", button: "left", clickCount: 1, ...last, ...pen });
}

// RGBA of page pixel (x, y), read from a screenshot.
async function pixel(page: Page, x: number, y: number): Promise<number[]> {
  const png = (await page.screenshot({ clip: { x, y, width: 1, height: 1 } })).toString("base64");
  return page.evaluate(async (data) => {
    const image = new Image();
    image.src = `data:image/png;base64,${data}`;
    await image.decode();
    const context = new OffscreenCanvas(1, 1).getContext("2d")!;
    context.drawImage(image, 0, 0);
    return Array.from(context.getImageData(0, 0, 1, 1).data);
  }, png);
}

async function readOpfsFile(page: Page, path: string): Promise<string> {
  return page.evaluate(async (parts) => {
    let dir = await navigator.storage.getDirectory();
    for (const part of parts.slice(0, -1)) dir = await dir.getDirectoryHandle(part);
    const file = await (await dir.getFileHandle(parts[parts.length - 1])).getFile();
    return btoa(String.fromCharCode(...new Uint8Array(await file.arrayBuffer())));
  }, path.split("/"));
}

// Opens a folder of the path to the open folder ("My Notes" is the root).
async function openFolder(page: Page, name: string): Promise<void> {
  await page.getByRole("navigation", { name: "Folder path" }).getByRole("button", { name, exact: true }).click();
}

// New Note from the library: in the open folder, the root by default.
async function newNote(page: Page, title: string, paper = "Plain Paper"): Promise<void> {
  await page.getByRole("button", { name: "New Note", exact: true }).click();
  await page.getByRole("textbox", { name: "Title" }).fill(title);
  await page.getByText(paper, { exact: true }).click(); // the tile's label
  await page.getByRole("button", { name: "Create Note" }).click();
  await expect(page.locator("#ink-canvas")).toBeVisible();
}

// Opens a note from the selected folder's note list.
async function openNote(page: Page, title: string): Promise<void> {
  await page.getByRole("list", { name: "Notes" }).getByRole("listitem").filter({ hasText: title }).getByRole("button").first().click();
  await expect(page.locator("#ink-canvas")).toBeVisible();
}

// The last saved write of `path` that has a stroke, as text.
async function savedStrokes(page: Page, path: string): Promise<string> {
  const written = await page.waitForFunction(
    (p) => window.mathNotesWrites?.findLast((f) => f.path === p && new TextDecoder().decode(f.bytes).includes('<path id="s-')),
    path,
    { timeout: 5000 },
  );
  return written.evaluate((f) => new TextDecoder().decode(f!.bytes));
}

test("a pen stroke is saved, byte for byte as the engine wrote it, and renders after a reload", async ({ page }) => {
  await startEmpty(page);
  await newNote(page, "Algebra");
  const canvas = page.locator("#ink-canvas");
  await expect(canvas).toBeVisible();

  const box = (await canvas.boundingBox())!;
  const y = box.y + 120;
  const points = Array.from({ length: 30 }, (_, i) => ({ x: box.x + 200 + i * 6, y: y + 4 * Math.sin(i / 3) }));
  await drawWithPen(page, points);

  // The save lands 1 s after the pen lifts.
  const written = await page.waitForFunction(
    () => window.mathNotesWrites?.findLast((f) => f.path === "pages/0001.svg" && new TextDecoder().decode(f.bytes).includes('<path id="s-')),
    undefined,
    { timeout: 5000 },
  );
  const engineBytes = await written.evaluate((f) => btoa(String.fromCharCode(...f!.bytes)));
  expect(await readOpfsFile(page, "Algebra/pages/0001.svg")).toBe(engineBytes);
  const svg = Buffer.from(engineBytes, "base64").toString();
  expect(svg).toContain('mn:brush="pressure-pen"');
  expect(svg).toMatch(/<inkml:trace contextRef="#[a-z]+">[^<]+<\/inkml:trace>/);

  await page.reload();
  await openNote(page, "Algebra");
  await expect(canvas).toBeVisible();
  const [r, g, b] = await pixel(page, points[15].x, points[15].y);
  expect(Math.max(r, g, b)).toBeLessThan(80); // ink, not paper
  const [pr, pg, pb] = await pixel(page, points[15].x, points[15].y + 40);
  expect(Math.min(pr, pg, pb)).toBeGreaterThan(240); // paper
});

test("Drawing mode saves a bounded TikZ figure and reopens its scene after reload", async ({ page }, testInfo) => {
  await startEmpty(page);
  await newNote(page, "Figure");
  const box = (await page.locator("#ink-canvas").boundingBox())!;
  await page.getByRole("button", { name: "Drawing", exact: true }).click();
  await drawWithPen(page, Array.from({ length: 20 }, (_, i) => ({
    x: box.x + 150 + i * 8,
    y: box.y + 110 + 4 * Math.sin(i / 3),
  })));
  await expect(page.getByRole("textbox", { name: "Generated TikZ source" })).toHaveValue(/\\draw/);
  await page.getByRole("button", { name: "Drawing", exact: true }).click();
  await expect(page.locator(".figure-page-bounds")).toBeVisible();
  await page.screenshot({ path: testInfo.outputPath("completed-figure.png") });
  await expect.poll(async () => Buffer.from(await readOpfsFile(page, "Figure/pages/0001.svg"), "base64").toString(), { timeout: 5000 }).toContain('class="mn-figure"');
  const saved = Buffer.from(await readOpfsFile(page, "Figure/pages/0001.svg"), "base64").toString();
  const id = saved.match(/id="(f-[a-z2-7]+)" class="mn-figure"/)?.[1];
  expect(id).toBeTruthy();
  const scene = Buffer.from(await readOpfsFile(page, `Figure/assets/${id}.scene.json`), "base64").toString();
  const source = Buffer.from(await readOpfsFile(page, `Figure/assets/${id}.tikz`), "base64").toString();
  expect(JSON.parse(scene).objects).toHaveLength(1);
  expect(source).toContain("\\begin{tikzpicture}");

  await page.reload();
  await openNote(page, "Figure");
  await page.getByRole("button", { name: "Lasso", exact: true }).click();
  const loop = [
    ...Array.from({ length: 10 }, (_, i) => ({ x: 130 + i * 22, y: 75 })),
    ...Array.from({ length: 5 }, (_, i) => ({ x: 350, y: 75 + i * 18 })),
    ...Array.from({ length: 10 }, (_, i) => ({ x: 350 - i * 22, y: 165 })),
    ...Array.from({ length: 5 }, (_, i) => ({ x: 130, y: 165 - i * 18 })),
  ].map((p) => ({ x: box.x + p.x, y: box.y + p.y }));
  await drawWithPen(page, loop);
  await expect(page.getByRole("complementary", { name: "TikZ drawing preview" })).toBeVisible();
  await expect(page.getByRole("textbox", { name: "Generated TikZ source" })).toHaveValue(source);
});

test("pages have a narrow desk gap and one finger moves the view", async ({ page }, testInfo) => {
  await startEmpty(page);
  await newNote(page, "Two Pages");
  await page.getByRole("button", { name: "Page actions" }).click();
  await page.getByText("Insert page after", { exact: true }).click();
  await expect(page.locator("ion-popover")).toBeHidden();
  const box = (await page.locator("#ink-canvas").boundingBox())!;
  const x = box.x + box.width / 2;
  const y = box.y + box.height / 2;
  const scale = box.width / 595.28;
  await page.mouse.move(x, y);
  await page.mouse.wheel(0, 841.89 * scale - box.height / 2);
  const gapColor = async (at: number) => (await pixel(page, x, at))[0];
  await expect.poll(() => gapColor(y + 3 * scale)).toBeLessThan(242);
  await page.screenshot({ path: testInfo.outputPath("page-gap.png") });
  expect(await gapColor(y - 4)).toBeGreaterThan(245);
  expect(await gapColor(y + 7 * scale)).toBeGreaterThan(245);

  const cdp = await page.context().newCDPSession(page);
  await cdp.send("Emulation.setTouchEmulationEnabled", { enabled: true, maxTouchPoints: 2 });
  await cdp.send("Input.dispatchTouchEvent", { type: "touchStart", touchPoints: [{ x, y: y + 80, id: 1 }] });
  await cdp.send("Input.dispatchTouchEvent", { type: "touchMove", touchPoints: [{ x, y, id: 1 }] });
  await cdp.send("Input.dispatchTouchEvent", { type: "touchEnd", touchPoints: [] });
  await expect.poll(() => gapColor(y + 3 * scale - 80)).toBeLessThan(242);
});

test("nginx serves the engine as application/wasm", async ({ page }) => {
  const wasm = page.waitForResponse((r) => r.url().endsWith(".wasm"));
  await page.goto(APP);
  const response = await wasm;
  expect(response.headers()["content-type"]).toBe("application/wasm");
});

test("after one visit the app starts offline", async ({ page, context }) => {
  await page.goto(APP);
  await page.evaluate(async () => {
    await navigator.serviceWorker.ready;
  });
  await page.reload(); // now controlled by the service worker
  await expect(page.getByRole("heading", { name: "Library" })).toBeVisible();
  await context.setOffline(true);
  await page.reload();
  await expect(page.getByRole("heading", { name: "Library" })).toBeVisible();
  await expect(page.getByRole("button", { name: "New Note", exact: true })).toBeEnabled(); // the library shows once the engine loaded from the cache
});

test("Ctrl+Z undoes a stroke and the save removes it from the page file", async ({ page }) => {
  await startEmpty(page);
  await newNote(page, "Undo");
  const box = (await page.locator("#ink-canvas").boundingBox())!;
  await drawWithPen(page, Array.from({ length: 10 }, (_, i) => ({ x: box.x + 150 + i * 8, y: box.y + 100 })));
  await page.keyboard.press("Control+z");
  await expect
    .poll(async () => Buffer.from(await readOpfsFile(page, "Undo/pages/0001.svg"), "base64").toString(), { timeout: 5000 })
    .not.toContain('<path id="s-');
  await page.keyboard.press("Control+Shift+z");
  await expect
    .poll(async () => Buffer.from(await readOpfsFile(page, "Undo/pages/0001.svg"), "base64").toString(), { timeout: 5000 })
    .toContain('<path id="s-');
});

test("a note created in a new folder with the dotted template is listed in its folder, before and after a reload", async ({ page }) => {
  await startEmpty(page);
  await page.getByRole("button", { name: "New Notebook" }).click();
  await page.getByRole("textbox", { name: "Notebook Title" }).fill("Topology");
  await page.getByRole("button", { name: "Create Notebook" }).click();
  await page.getByRole("button", { name: "New Note in Topology" }).click();
  await page.getByRole("textbox", { name: "Title" }).fill("Knots");
  await page.getByText("Dot Paper", { exact: true }).click();
  await page.getByRole("button", { name: "Create Note" }).click();
  const box = (await page.locator("#ink-canvas").boundingBox())!;
  await drawWithPen(page, Array.from({ length: 20 }, (_, i) => ({ x: box.x + 150 + i * 8, y: box.y + 100 })));
  await savedStrokes(page, "pages/0001.svg");
  await page.getByRole("button", { name: "Library" }).click();

  const card = page.getByRole("list", { name: "Notebooks" }).getByRole("listitem").filter({
    has: page.getByRole("button", { name: "Topology", exact: true }),
  });
  const notes = page.getByRole("list", { name: "Notes" });
  for (const phase of ["before reload", "after reload"]) {
    await openFolder(page, "My Notes");
    await expect(card, phase).toContainText("1 note");
    await card.getByRole("button", { name: "Topology", exact: true }).click();
    await expect(notes.getByRole("listitem"), phase).toHaveCount(1);
    await expect(notes, phase).toContainText("Knots");
    if (phase === "before reload") await page.reload();
  }
  const notebook = JSON.parse(Buffer.from(await readOpfsFile(page, "Topology/Knots/notebook.json"), "base64").toString());
  expect(notebook.template).toBe("dotted");
  const svg = Buffer.from(await readOpfsFile(page, "Topology/Knots/pages/0001.svg"), "base64").toString();
  expect(svg).toContain('mn:ruling="dotted"');
  expect(svg).toContain('<path id="s-');
});

test("the editor opens a searched library note in a tab and preserves each note's ink", async ({ page }, testInfo) => {
  await startEmpty(page);
  await newNote(page, "Algebra");
  const box = (await page.locator("#ink-canvas").boundingBox())!;
  await drawWithPen(page, Array.from({ length: 20 }, (_, i) => ({ x: box.x + 150 + i * 8, y: box.y + 100 })));
  await savedStrokes(page, "pages/0001.svg");
  const algebra = await savedStrokeIds(page, "Algebra/pages/0001.svg");
  await page.getByRole("button", { name: "Library" }).click();

  await page.getByRole("button", { name: "New Notebook" }).click();
  await page.getByRole("textbox", { name: "Notebook Title" }).fill("Topology");
  await page.getByRole("button", { name: "Create Notebook" }).click();
  await page.getByRole("button", { name: "New Note in Topology" }).click();
  await page.getByRole("textbox", { name: "Title" }).fill("Knots");
  await page.getByRole("button", { name: "Create Note" }).click();
  await page.locator("#ink-canvas").waitFor();
  const knotsBox = (await page.locator("#ink-canvas").boundingBox())!;
  await drawWithPen(page, Array.from({ length: 20 }, (_, i) => ({ x: knotsBox.x + 150 + i * 8, y: knotsBox.y + 180 })));
  await expect.poll(async () => savedStrokeIds(page, "Topology/Knots/pages/0001.svg")).not.toEqual([]);
  const knots = await savedStrokeIds(page, "Topology/Knots/pages/0001.svg");
  await page.getByRole("button", { name: "Library" }).click();
  await openFolder(page, "My Notes");
  await openNote(page, "Algebra");

  await page.getByRole("button", { name: "Open another note" }).click();
  await page.getByRole("search", { name: "Search library notes" }).getByRole("searchbox").fill("Knots");
  await page.screenshot({ path: testInfo.outputPath("note-picker.png") });
  await page.locator("ion-modal").getByText("Knots", { exact: true }).click();
  await expect(page.getByRole("tab", { name: "Knots" })).toHaveAttribute("aria-selected", "true");
  await page.getByRole("tab", { name: "Algebra" }).click();
  await expect(page.getByRole("tab", { name: "Algebra" })).toHaveAttribute("aria-selected", "true");
  expect(await savedStrokeIds(page, "Algebra/pages/0001.svg")).toEqual(algebra);
  expect(await savedStrokeIds(page, "Topology/Knots/pages/0001.svg")).toEqual(knots);
  expect(algebra).not.toEqual(knots);
});

test("New Note restores its saved draft after reload and removes the draft when the note is created", async ({ page }, testInfo) => {
  await startEmpty(page);
  await page.getByRole("button", { name: "New Notebook" }).click();
  await page.getByRole("textbox", { name: "Notebook Title" }).fill("Topology");
  await page.getByRole("button", { name: "Create Notebook" }).click();
  await page.getByRole("button", { name: "New Note in Topology" }).click();
  await page.getByRole("textbox", { name: "Title" }).fill("Knots");
  await page.getByText("Grid Paper, medium", { exact: true }).click();
  await page.locator("ion-chip[aria-label='Add Tag']").click();
  await page.getByText("New Tag…", { exact: true }).click();
  await page.locator("ion-alert").getByRole("textbox", { name: "Name" }).fill("Research");
  await page.locator("ion-alert").getByRole("button", { name: "Add Tag" }).click();
  await expect(page.locator("ion-chip.tag-chip")).toContainText("Research");
  await page.getByRole("button", { name: "Save as Draft" }).click();
  await expect.poll(async () => JSON.parse(Buffer.from(await readOpfsFile(page, ".library.json"), "base64").toString()).draft).toEqual({
    folder: ["Topology"], title: "Knots", template: "grid-medium", tags: ["Research"], pageSize: "a4",
  });
  await page.reload();
  await page.getByRole("button", { name: "New Note", exact: true }).click();
  await expect(page.getByRole("textbox", { name: "Title" })).toHaveValue("Knots");
  await expect(page.getByText("Grid Paper, medium", { exact: true }).locator("..")).toHaveAttribute("aria-pressed", "true");
  await expect(page.locator("ion-chip.tag-chip")).toContainText("Research");
  await expect(page.locator(".target-name")).toHaveText("Topology");
  await page.screenshot({ path: testInfo.outputPath("restored-draft.png") });
  await page.getByRole("button", { name: "Create Note" }).click();
  await page.locator("#ink-canvas").waitFor();
  const metadata = JSON.parse(Buffer.from(await readOpfsFile(page, ".library.json"), "base64").toString());
  expect(metadata.draft).toBeUndefined();
  expect(metadata.notes["Topology/Knots"].tags).toEqual(["Research"]);
  const notebook = JSON.parse(Buffer.from(await readOpfsFile(page, "Topology/Knots/notebook.json"), "base64").toString());
  expect(notebook.template).toBe("grid-medium");
});

test("notebook fields persist, appear in the library, and set the new-note paper", async ({ page }, testInfo) => {
  await startEmpty(page);
  await page.getByRole("button", { name: "New Notebook" }).click();
  await page.getByRole("textbox", { name: "Notebook Title" }).fill("Topology");
  await page.getByRole("textbox", { name: "Description" }).fill("Spaces and knots");
  await page.getByText("Graph Paper", { exact: true }).click();
  await page.getByRole("button", { name: "Cover #C9B8F0" }).click();
  await page.getByText("Spine", { exact: true }).click();
  await page.locator("ion-chip[aria-label='Add a tag']").click();
  await page.getByText("New Tag…", { exact: true }).click();
  await page.locator("ion-alert").getByRole("textbox", { name: "Name" }).fill("Research");
  await page.locator("ion-alert").getByRole("button", { name: "Add Tag" }).click();
  await expect(page.locator("ion-chip.tag-chip")).toContainText("Research");
  await page.screenshot({ path: testInfo.outputPath("notebook-form.png") });
  await page.getByRole("button", { name: "Create Notebook" }).click();
  await expect.poll(async () => JSON.parse(Buffer.from(await readOpfsFile(page, ".library.json"), "base64").toString()).folders?.Topology).toEqual({
    description: "Spaces and knots", paper: "grid-coarse", coverColor: "#C9B8F0", coverStyle: "spine", tags: ["Research"],
  });
  await page.reload();
  const metadata = JSON.parse(Buffer.from(await readOpfsFile(page, ".library.json"), "base64").toString());
  expect(metadata.folders.Topology).toEqual({
    description: "Spaces and knots", paper: "grid-coarse", coverColor: "#C9B8F0", coverStyle: "spine", tags: ["Research"],
  });
  await openFolder(page, "My Notes");
  const card = page.getByRole("list", { name: "Notebooks" }).getByRole("listitem").filter({ hasText: "Topology" });
  await expect(card).toContainText("Spaces and knots");
  await card.getByRole("button", { name: "Topology", exact: true }).click();
  await expect(page.locator(".detail-description")).toHaveText("Spaces and knots");
  await expect(page.locator(".detail")).toContainText("Research");
  await page.screenshot({ path: testInfo.outputPath("notebook-library.png") });
  await page.getByRole("button", { name: "Add notebook tag" }).click();
  await page.getByText("New Tag…", { exact: true }).click();
  await page.locator("ion-alert").getByRole("textbox", { name: "Name" }).fill("Review");
  await page.locator("ion-alert").getByRole("button", { name: "Add Tag" }).click();
  await expect(page.locator(".detail")).toContainText("Review");
  await page.getByRole("button", { name: "New Note in Topology" }).click();
  await expect(page.getByText("Grid Paper, coarse", { exact: true }).locator("..")).toHaveAttribute("aria-pressed", "true");
});

test("a saved starting template applies its folder, paper, page size and tags after reload", async ({ page }) => {
  await startEmpty(page);
  await page.getByRole("button", { name: "New Notebook" }).click();
  await page.getByRole("textbox", { name: "Notebook Title" }).fill("Topology");
  await page.getByRole("button", { name: "Create Notebook" }).click();
  await page.getByRole("button", { name: "New Note in Topology" }).click();
  await page.getByText("Grid Paper, medium", { exact: true }).click();
  await page.getByRole("button", { name: "Page Size" }).click();
  await page.getByText("Letter", { exact: true }).click();
  await page.locator("ion-chip[aria-label='Add Tag']").click();
  await page.getByText("New Tag…", { exact: true }).click();
  await page.locator("ion-alert").getByRole("textbox", { name: "Name" }).fill("Research");
  await page.locator("ion-alert").getByRole("button", { name: "Add Tag" }).click();
  await page.getByRole("button", { name: "Save as template" }).click();
  await page.locator("ion-alert").getByRole("textbox", { name: "Template name" }).fill("Seminar");
  await expect(page.locator("ion-alert").getByRole("textbox", { name: "Template name" })).toHaveValue("Seminar");
  await page.locator("ion-alert").getByRole("button", { name: "Save" }).click();
  await expect.poll(async () => JSON.parse(Buffer.from(await readOpfsFile(page, ".library.json"), "base64").toString()).startingTemplates?.[0]?.name).toBe("Seminar");
  await page.reload();
  await page.getByRole("button", { name: "New Note", exact: true }).click();
  await page.getByText("Seminar", { exact: true }).click();
  await expect(page.locator(".target-name")).toHaveText("Topology");
  await expect(page.getByText("Grid Paper, medium", { exact: true }).locator("..")).toHaveAttribute("aria-pressed", "true");
  await expect(page.locator("ion-chip.tag-chip")).toContainText("Research");
  await page.getByRole("textbox", { name: "Title" }).fill("Lecture");
  await page.getByRole("button", { name: "Create Note" }).click();
  await page.locator("#ink-canvas").waitFor();
  const notebook = JSON.parse(Buffer.from(await readOpfsFile(page, "Topology/Lecture/notebook.json"), "base64").toString());
  const metadata = JSON.parse(Buffer.from(await readOpfsFile(page, ".library.json"), "base64").toString());
  expect(notebook.template).toBe("grid-medium");
  expect(notebook.pageSize).toBe("Letter");
  expect(metadata.notes["Topology/Lecture"].tags).toEqual(["Research"]);
  const page1 = Buffer.from(await readOpfsFile(page, "Topology/Lecture/pages/0001.svg"), "base64").toString();
  expect(page1).toContain('viewBox="0 0 612 792"');
});

test("the Image tool stores a PNG asset and shows it after reload", async ({ page }, testInfo) => {
  await startEmpty(page);
  await newNote(page, "Diagram");
  await page.locator("input[type=file]").setInputFiles("../../core/tests/fixtures/render/full/0001.png");
  await expect.poll(async () => {
    const svg = Buffer.from(await readOpfsFile(page, "Diagram/pages/0001.svg"), "base64").toString();
    return svg.match(/<image[^>]+/)?.[0];
  }).toMatch(/href="\.\.\/assets\/[0-9a-f]+\.png"/);
  const svg = Buffer.from(await readOpfsFile(page, "Diagram/pages/0001.svg"), "base64").toString();
  const asset = svg.match(/href="\.\.\/assets\/([0-9a-f]+\.png)"/)![1];
  expect((await readOpfsFile(page, `Diagram/assets/${asset}`)).length).toBeGreaterThan(100);
  await page.reload();
  await openNote(page, "Diagram");
  await expect(page.locator("#ink-canvas")).toBeVisible();
  await page.screenshot({ path: testInfo.outputPath("image-reopened.png") });
  const png = (await page.locator("#ink-canvas").screenshot()).toString("base64");
  const red = await page.evaluate(async (data) => {
    const image = new Image();
    image.src = `data:image/png;base64,${data}`;
    await image.decode();
    const context = new OffscreenCanvas(image.width, image.height).getContext("2d")!;
    context.drawImage(image, 0, 0);
    const pixels = context.getImageData(0, 0, image.width, image.height).data;
    let count = 0;
    for (let i = 0; i < pixels.length; i += 4) {
      if (pixels[i] > 245 && pixels[i + 1] > 90 && pixels[i + 1] < 160 && pixels[i + 2] > 90 && pixels[i + 2] < 160) count++;
    }
    return count;
  }, png);
  expect(red).toBeGreaterThan(50);
});

test("the Image tool renders an imported JPEG after reload", async ({ page }, testInfo) => {
  await startEmpty(page);
  await newNote(page, "Photo");
  const jpeg = await page.locator(".tools").screenshot({ type: "jpeg" });
  await page.locator("input[type=file]").setInputFiles({ name: "tools.jpg", mimeType: "image/jpeg", buffer: jpeg });
  await expect.poll(async () => {
    const svg = Buffer.from(await readOpfsFile(page, "Photo/pages/0001.svg"), "base64").toString();
    return svg.match(/href="\.\.\/assets\/[0-9a-f]+\.jpg"/)?.[0];
  }).toMatch(/\.jpg"/);
  await page.reload();
  await openNote(page, "Photo");
  await page.screenshot({ path: testInfo.outputPath("jpeg-reopened.png") });
  const png = (await page.locator("#ink-canvas").screenshot()).toString("base64");
  const dark = await page.evaluate(async (data) => {
    const image = new Image();
    image.src = `data:image/png;base64,${data}`;
    await image.decode();
    const context = new OffscreenCanvas(image.width, image.height).getContext("2d")!;
    context.drawImage(image, 0, 0);
    const pixels = context.getImageData(200, 100, 500, 450).data;
    let count = 0;
    for (let i = 0; i < pixels.length; i += 4) if (pixels[i] < 80 && pixels[i + 1] < 80 && pixels[i + 2] < 80) count++;
    return count;
  }, png);
  expect(dark).toBeGreaterThan(50);
});

test("the Text tool saves editable SVG text that renders after reload", async ({ page }, testInfo) => {
  await startEmpty(page);
  await newNote(page, "Definitions");
  const box = (await page.locator("#ink-canvas").boundingBox())!;
  await page.getByRole("button", { name: "Text", exact: true }).click();
  await page.mouse.click(box.x + 250, box.y + 200);
  await page.getByRole("textbox", { name: "Page text" }).fill("Homotopy group");
  await page.getByRole("button", { name: "Save Text" }).click();
  await expect.poll(async () => Buffer.from(await readOpfsFile(page, "Definitions/pages/0001.svg"), "base64").toString()).toContain("Homotopy group");
  await page.reload();
  await openNote(page, "Definitions");
  await page.screenshot({ path: testInfo.outputPath("text-reopened.png") });
  const png = (await page.locator("#ink-canvas").screenshot()).toString("base64");
  const dark = await page.evaluate(async (data) => {
    const image = new Image();
    image.src = `data:image/png;base64,${data}`;
    await image.decode();
    const context = new OffscreenCanvas(image.width, image.height).getContext("2d")!;
    context.drawImage(image, 0, 0);
    const pixels = context.getImageData(240, 190, 180, 60).data;
    let count = 0;
    for (let i = 0; i < pixels.length; i += 4) if (pixels[i] < 100 && pixels[i + 1] < 100 && pixels[i + 2] < 100) count++;
    return count;
  }, png);
  expect(dark).toBeGreaterThan(20);
  await page.getByRole("button", { name: "Text", exact: true }).click();
  const reopened = (await page.locator("#ink-canvas").boundingBox())!;
  await page.mouse.click(reopened.x + 270, reopened.y + 210);
  await expect(page.getByRole("textbox", { name: "Page text" })).toHaveValue("Homotopy group");
  await page.getByRole("textbox", { name: "Page text" }).fill("Fundamental group");
  await page.getByRole("button", { name: "Save Text" }).click();
  await expect.poll(async () => Buffer.from(await readOpfsFile(page, "Definitions/pages/0001.svg"), "base64").toString()).toContain("Fundamental group");
});

test("the tool rail's presets and palette color reach the saved strokes", async ({ page }) => {
  await startEmpty(page);
  await newNote(page, "Tools");
  const box = (await page.locator("#ink-canvas").boundingBox())!;
  const line = (y: number) => Array.from({ length: 20 }, (_, i) => ({ x: box.x + 150 + i * 8, y: box.y + y }));

  await page.getByRole("button", { name: "Highlighter", exact: true }).click();
  await page.getByRole("button", { name: "#2BB3C0" }).click();
  await drawWithPen(page, line(100));
  await page.getByRole("button", { name: "Black pen", exact: true }).click();
  await page.getByRole("button", { name: "#D6455D" }).click();
  await drawWithPen(page, line(200));

  await expect
    .poll(async () => {
      const svg = Buffer.from(await readOpfsFile(page, "Tools/pages/0001.svg"), "base64").toString();
      return [...svg.matchAll(/<path id="s-[^>]*? fill="(#[0-9A-F]{6})"[^>]*? mn:brush="([a-z-]+)"/g)].map((m) => [m[2], m[1]]);
    }, { timeout: 5000 })
    .toEqual([
      ["highlighter", "#2BB3C0"],
      ["pressure-pen", "#D6455D"],
    ]);
});

// The strokes of a saved page: brush, fill and size, in document order.
async function strokeAttributes(page: Page, path: string): Promise<string[][]> {
  const svg = Buffer.from(await readOpfsFile(page, path), "base64").toString();
  return [...svg.matchAll(/<path id="s-[^>]*? fill="(#[0-9A-F]{6})"[^>]*? mn:brush="([a-z-]+)"[^>]*? mn:size="([0-9.]+)"/g)].map((m) => [
    m[2],
    m[1],
    m[3],
  ]);
}

test("an edited pen is written to .pens.json in FORMAT.md key order, and earlier strokes keep their own pen", async ({ page }) => {
  await startEmpty(page);
  await newNote(page, "Pens");
  const box = (await page.locator("#ink-canvas").boundingBox())!;
  const line = (y: number) => Array.from({ length: 20 }, (_, i) => ({ x: box.x + 150 + i * 8, y: box.y + y }));

  const blue = page.getByRole("button", { name: "Blue pen", exact: true });
  await blue.click();
  await drawWithPen(page, line(100));
  await blue.click(); // the selected pen again: its editor
  const editor = page.locator("ion-popover");
  await editor.getByRole("button", { name: "Marker" }).click();
  await editor.getByRole("textbox", { name: "Hex" }).fill("#3FA35B");
  await editor.getByRole("textbox", { name: "Hex" }).press("Tab");
  await editor.getByRole("slider", { name: "Size" }).focus();
  for (let i = 0; i < 8; i++) await page.keyboard.press("ArrowRight"); // 1.2 + 8 × 0.1 pt
  await page.keyboard.press("Escape");
  await drawWithPen(page, line(200));

  const pen = (id: string, name: string, brush: string, color: string, opacity: string, size: string) =>
    `  {\n    "id": "${id}",\n    "name": "${name}",\n    "brush": "${brush}",\n    "brushVersion": 1,\n` +
    `    "color": "${color}",\n    "opacity": ${opacity},\n    "size": ${size}\n  }`;
  const expected =
    "[\n" +
    [
      pen("black-pen", "Black pen", "pressure-pen", "#1A1A1A", "1", "1.2"),
      pen("blue-pen", "Blue pen", "marker", "#3FA35B", "1", "2"),
      pen("red-pen", "Red pen", "pressure-pen", "#B51F1F", "1", "1.2"),
      pen("marker", "Marker", "marker", "#1A1A1A", "1", "2.4"),
      pen("highlighter", "Highlighter", "highlighter", "#FFE066", "0.35", "9.6"),
    ].join(",\n") +
    "\n]\n";
  await expect
    .poll(async () => Buffer.from(await readOpfsFile(page, ".pens.json"), "base64").toString(), { timeout: 5000 })
    .toBe(expected);
  await expect
    .poll(() => strokeAttributes(page, "Pens/pages/0001.svg"), { timeout: 5000 })
    .toEqual([
      ["pressure-pen", "#1F4FB5", "1.2"],
      ["marker", "#3FA35B", "2"],
    ]);
});

test("a .pens.json changed by another device is read when the note opens again", async ({ page }) => {
  await startEmpty(page);
  await newNote(page, "Shared");
  await expect
    .poll(async () => Buffer.from(await readOpfsFile(page, ".pens.json"), "base64").toString(), { timeout: 5000 })
    .toContain('"id": "red-pen"');
  // Another device on the same root renames the red pen and makes it thicker.
  await page.evaluate(async () => {
    const root = await navigator.storage.getDirectory();
    const file = await (await root.getFileHandle(".pens.json")).getFile();
    const text = (await file.text()).replace('"name": "Red pen"', '"name": "Proof red"').replace(/("id": "red-pen"[^}]*"size": )1.2/, "$13");
    const writable = await (await root.getFileHandle(".pens.json")).createWritable();
    await writable.write(text);
    await writable.close();
  });
  await page.getByRole("button", { name: "Library" }).click();
  await openNote(page, "Shared");

  await page.getByRole("button", { name: "Proof red", exact: true }).click();
  const box = (await page.locator("#ink-canvas").boundingBox())!;
  await drawWithPen(page, Array.from({ length: 20 }, (_, i) => ({ x: box.x + 150 + i * 8, y: box.y + 100 })));
  await expect
    .poll(() => strokeAttributes(page, "Shared/pages/0001.svg"), { timeout: 5000 })
    .toEqual([["pressure-pen", "#B51F1F", "3"]]);
});

test("pulling past the last page adds a page only past the threshold, and the view stops at the pages", async ({ page }) => {
  await startEmpty(page);
  await newNote(page, "Pull");
  const box = (await page.locator("#ink-canvas").boundingBox())!;
  const indicator = page.getByLabel("Page", { exact: true });
  const pull = page.locator(".pull-indicator");
  // Paper, not desk, at the canvas's top and bottom edges.
  const paperAt = async (y: number) => Math.min(...(await pixel(page, box.x + 5, y)).slice(0, 3)) > 240;
  // The A4 page fills the canvas width: this far down its end meets the canvas's.
  const toEnd = (box.width * 841.89) / 595.28 - box.height;

  await page.mouse.move(box.x + box.width / 2, box.y + box.height / 2);
  await page.mouse.wheel(0, -500);
  expect(await paperAt(box.y + 1)).toBe(true);

  await page.mouse.wheel(0, toEnd + 40); // 40 px of pull, under the threshold
  await expect(pull).toHaveText("Pull to add a page");
  await expect(pull).toHaveCSS("height", "0px"); // released: springs back
  await expect(indicator).toHaveText(/\/ 1$/);
  expect(await paperAt(box.y + box.height - 2)).toBe(true);

  await page.mouse.wheel(0, 150);
  await expect(pull).toHaveText("Release to add a page");
  await expect(indicator).toHaveText(/\/ 2$/);
  await expect(pull).toHaveCSS("height", "0px");
});

// The ids of the strokes in a saved page file, in document order.
async function savedStrokeIds(page: Page, path: string): Promise<string[]> {
  const svg = Buffer.from(await readOpfsFile(page, path), "base64").toString();
  return [...svg.matchAll(/<path id="(s-[a-z2-7]+)"/g)].map((m) => m[1]);
}

test("the eraser tool deletes a touched stroke whole, Partial cuts one in two, and each is one undo step", async ({ page }, testInfo) => {
  await startEmpty(page);
  await newNote(page, "Erase");
  const box = (await page.locator("#ink-canvas").boundingBox())!;
  const line = (y: number) => Array.from({ length: 20 }, (_, i) => ({ x: box.x + 150 + i * 8, y: box.y + y }));
  const across = (y: number) => Array.from({ length: 9 }, (_, i) => ({ x: box.x + 226, y: box.y + y - 40 + i * 10 }));
  await drawWithPen(page, line(100));
  await drawWithPen(page, line(200));
  await expect.poll(() => savedStrokeIds(page, "Erase/pages/0001.svg"), { timeout: 5000 }).toHaveLength(2);
  const [first, second] = await savedStrokeIds(page, "Erase/pages/0001.svg");

  await page.getByRole("button", { name: "Eraser", exact: true }).click();
  await drawWithPen(page, across(100));
  await expect.poll(() => savedStrokeIds(page, "Erase/pages/0001.svg"), { timeout: 5000 }).toEqual([second]);

  await page.getByRole("button", { name: "Partial" }).click();
  await drawWithPen(page, across(200));
  await expect.poll(() => savedStrokeIds(page, "Erase/pages/0001.svg"), { timeout: 5000 }).toHaveLength(2);
  const pieces = await savedStrokeIds(page, "Erase/pages/0001.svg");
  expect(pieces).not.toContain(second);
  await page.screenshot({ path: testInfo.outputPath("partial-erase.png") });
  const ink = async (x: number) => Math.max(...(await pixel(page, box.x + x, box.y + 200)).slice(0, 3)) < 120;
  expect(await ink(170)).toBe(true);
  expect(await ink(226)).toBe(false); // the cut
  expect(await ink(290)).toBe(true);

  await page.keyboard.press("Control+z");
  await expect.poll(() => savedStrokeIds(page, "Erase/pages/0001.svg"), { timeout: 5000 }).toEqual([second]);
  await page.keyboard.press("Control+z");
  await expect.poll(() => savedStrokeIds(page, "Erase/pages/0001.svg"), { timeout: 5000 }).toEqual([first, second]);
});

test("the pen's eraser end erases while the pen is selected", async ({ page }) => {
  await startEmpty(page);
  await newNote(page, "Eraser End");
  const canvas = page.locator("#ink-canvas");
  const box = (await canvas.boundingBox())!;
  await drawWithPen(page, Array.from({ length: 20 }, (_, i) => ({ x: box.x + 150 + i * 8, y: box.y + 100 })));
  await expect.poll(() => savedStrokeIds(page, "Eraser End/pages/0001.svg"), { timeout: 5000 }).toHaveLength(1);

  // CDP input has no eraser button: the eraser end's events (button 5, buttons
  // bit 32) are dispatched on the canvas, as the pen digitizer delivers them.
  await canvas.evaluate((element, b) => {
    const at = (type: string, y: number, buttons: number) =>
      element.dispatchEvent(
        new PointerEvent(type, {
          bubbles: true, pointerId: 1, pointerType: "pen", isPrimary: true, button: type === "pointermove" ? -1 : 5,
          buttons, pressure: 0.5, clientX: b.x + 226, clientY: b.y + y,
        }),
      );
    at("pointerdown", 60, 32);
    for (let y = 70; y <= 140; y += 10) at("pointermove", y, 32);
    at("pointerup", 140, 0);
  }, box);
  await expect.poll(() => savedStrokeIds(page, "Eraser End/pages/0001.svg"), { timeout: 5000 }).toEqual([]);
});

// The transform attribute of each saved ink path, by id ("" for none).
async function savedTransforms(page: Page, path: string): Promise<Record<string, string>> {
  const svg = Buffer.from(await readOpfsFile(page, path), "base64").toString();
  return Object.fromEntries(
    [...svg.matchAll(/<path id="(s-[a-z2-7]+)"( transform="([^"]*)")?/g)].map((m) => [m[1], m[3] ?? ""]),
  );
}

test("the lasso selects a stroke, a drag moves it by the pen's offset, and one undo puts it back", async ({ page }, testInfo) => {
  await startEmpty(page);
  await newNote(page, "Lasso");
  const box = (await page.locator("#ink-canvas").boundingBox())!;
  const scale = box.width / 595.28; // CSS px per pt: the A4 page fills the canvas width
  const line = (y: number) => Array.from({ length: 20 }, (_, i) => ({ x: box.x + 150 + i * 8, y: box.y + y }));
  await drawWithPen(page, line(100));
  await drawWithPen(page, line(200));
  await expect.poll(() => savedStrokeIds(page, "Lasso/pages/0001.svg"), { timeout: 5000 }).toHaveLength(2);
  const [first, second] = await savedStrokeIds(page, "Lasso/pages/0001.svg");

  await page.getByRole("button", { name: "Lasso", exact: true }).click();
  const loop = [
    ...Array.from({ length: 10 }, (_, i) => ({ x: 130 + i * 22, y: 75 })),
    ...Array.from({ length: 5 }, (_, i) => ({ x: 350, y: 75 + i * 12 })),
    ...Array.from({ length: 10 }, (_, i) => ({ x: 350 - i * 22, y: 130 })),
    ...Array.from({ length: 5 }, (_, i) => ({ x: 130, y: 130 - i * 12 })),
  ].map((p) => ({ x: box.x + p.x, y: box.y + p.y }));
  await drawWithPen(page, loop);
  await page.screenshot({ path: testInfo.outputPath("lasso-selection.png") });
  // From the middle of the selected stroke, 60 px right and 80 px down.
  await drawWithPen(page, Array.from({ length: 11 }, (_, i) => ({ x: box.x + 226 + i * 6, y: box.y + 100 + i * 8 })));
  await page.screenshot({ path: testInfo.outputPath("lasso-moved.png") });

  const translate = (t: string) => t.match(/^translate\(([-\d.]+),([-\d.]+)\)$/)?.slice(1).map(Number);
  await expect
    .poll(async () => translate((await savedTransforms(page, "Lasso/pages/0001.svg"))[first] ?? ""), { timeout: 5000 })
    .toBeDefined();
  const moved = await savedTransforms(page, "Lasso/pages/0001.svg");
  const [dx, dy] = translate(moved[first])!;
  expect(Math.abs(dx - 60 / scale)).toBeLessThan(0.05);
  expect(Math.abs(dy - 80 / scale)).toBeLessThan(0.05);
  expect(moved[second]).toBe("");

  await page.keyboard.press("Control+z");
  await expect.poll(async () => (await savedTransforms(page, "Lasso/pages/0001.svg"))[first], { timeout: 5000 }).toBe("");
});

test("ink copied in one note and pasted into another keeps its path data and gets new ids", async ({ page, context }) => {
  await context.grantPermissions(["clipboard-read", "clipboard-write"]);
  await startEmpty(page);
  await newNote(page, "Source");
  const box = (await page.locator("#ink-canvas").boundingBox())!;
  await drawWithPen(page, Array.from({ length: 20 }, (_, i) => ({ x: box.x + 150 + i * 8, y: box.y + 120 + 6 * Math.sin(i / 2) })));
  await drawWithPen(page, Array.from({ length: 12 }, (_, i) => ({ x: box.x + 180 + i * 5, y: box.y + 180 + i * 4 })));
  await expect.poll(() => savedStrokeIds(page, "Source/pages/0001.svg"), { timeout: 5000 }).toHaveLength(2);
  await page.keyboard.press("Control+a");
  await page.keyboard.press("Control+c");
  await expect.poll(() => page.evaluate(() => navigator.clipboard.readText()), { timeout: 5000 }).toContain("<svg");

  await page.getByRole("button", { name: "Library" }).click();
  await newNote(page, "Target");
  await page.keyboard.press("Control+v");
  await expect.poll(() => savedStrokeIds(page, "Target/pages/0001.svg"), { timeout: 5000 }).toHaveLength(2);

  const paths = async (path: string) => {
    const svg = Buffer.from(await readOpfsFile(page, path), "base64").toString();
    return [...svg.matchAll(/<path id="(s-[a-z2-7]+)"[^>]*? d="([^"]+)"/g)].map((m) => ({ id: m[1], d: m[2] }));
  };
  const source = await paths("Source/pages/0001.svg");
  const target = await paths("Target/pages/0001.svg");
  expect(target.map((p) => p.d)).toEqual(source.map((p) => p.d));
  for (const { id } of target) expect(source.map((p) => p.id)).not.toContain(id);
});

// Whether each path (from the notes root) is a directory in the
// origin-private file system.
async function directoriesExist(page: Page, paths: string[]): Promise<boolean[]> {
  return page.evaluate(async (all) => {
    const exists = async (path: string) => {
      let dir = await navigator.storage.getDirectory();
      try {
        for (const part of path.split("/")) dir = await dir.getDirectoryHandle(part);
        return true;
      } catch {
        return false;
      }
    };
    return Promise.all(all.map(exists));
  }, paths);
}

// The window gets focus, as when the user comes back from another program.
async function focusWindow(page: Page): Promise<void> {
  await page.evaluate(() => window.dispatchEvent(new Event("focus")));
}

// Chooses `item` in the ⋯ menu of the note or folder `name`.
async function entryMenu(page: Page, name: string, item: string): Promise<void> {
  await page.getByRole("button", { name: `${name} actions` }).first().click();
  await page.locator("ion-popover").getByRole("button", { name: item }).click();
}

test("a notebook renamed outside the app is listed at its new path once the window regains focus", async ({ page }) => {
  await startEmpty(page);
  await newNote(page, "Knots");
  await page.getByRole("button", { name: "Library" }).click();
  await page.getByRole("button", { name: "My Notes", exact: true }).click();
  const notes = page.getByRole("list", { name: "Notes" });
  await expect(notes).toContainText("Knots");

  // `mv Knots Braids` by another program.
  await page.evaluate(async () => {
    const copy = async (from: FileSystemDirectoryHandle, to: FileSystemDirectoryHandle) => {
      for await (const [name, handle] of from.entries()) {
        if (handle.kind === "directory") {
          await copy(handle, await to.getDirectoryHandle(name, { create: true }));
          continue;
        }
        const writable = await (await to.getFileHandle(name, { create: true })).createWritable();
        await writable.write(await handle.getFile());
        await writable.close();
      }
    };
    const root = await navigator.storage.getDirectory();
    await copy(await root.getDirectoryHandle("Knots"), await root.getDirectoryHandle("Braids", { create: true }));
    await root.removeEntry("Knots", { recursive: true });
  });
  await focusWindow(page);
  await expect(notes).toContainText("Braids");
  await expect(notes).not.toContainText("Knots");
  await openNote(page, "Braids");
});

test("rename, move and delete from the ⋯ menus change the notebook and folder directories", async ({ page }) => {
  await startEmpty(page);
  await page.getByRole("button", { name: "New Notebook" }).click();
  await page.getByRole("textbox", { name: "Notebook Title" }).fill("Topology");
  await page.getByRole("button", { name: "Create Notebook" }).click();
  await page.getByRole("button", { name: "Topology", exact: true }).click();
  await page.getByRole("button", { name: "New Note in Topology" }).click();
  await page.getByRole("textbox", { name: "Title" }).fill("Knots");
  await page.getByRole("button", { name: "Create Note" }).click();
  await expect(page.locator("#ink-canvas")).toBeVisible();
  await page.getByRole("button", { name: "Library" }).click();
  await page.getByRole("button", { name: "Topology", exact: true }).click();

  await entryMenu(page, "Knots", "Rename…");
  await page.getByRole("textbox", { name: "Name" }).fill("Braids");
  await page.getByRole("button", { name: "Rename", exact: true }).click();
  await expect.poll(() => directoriesExist(page, ["Topology/Braids/pages", "Topology/Knots"])).toEqual([true, false]);

  await entryMenu(page, "Braids", "Move to…");
  await page.locator("ion-action-sheet").getByRole("button", { name: "My Notes" }).click();
  await expect.poll(() => directoriesExist(page, ["Braids/pages", "Topology/Braids"])).toEqual([true, false]);

  await openFolder(page, "My Notes");
  await entryMenu(page, "Topology", "Rename…");
  await page.getByRole("textbox", { name: "Name" }).fill("Geometry");
  await page.getByRole("button", { name: "Rename", exact: true }).click();
  await expect.poll(() => directoriesExist(page, ["Geometry", "Topology"])).toEqual([true, false]);

  await page.getByRole("button", { name: "My Notes", exact: true }).click();
  await entryMenu(page, "Braids", "Move to…");
  await page.locator("ion-action-sheet").getByRole("button", { name: "Geometry" }).click();
  await expect.poll(() => directoriesExist(page, ["Geometry/Braids/pages", "Braids"])).toEqual([true, false]);

  await entryMenu(page, "Geometry", "Move to Trash");
  await expect.poll(() => directoriesExist(page, [".trash/Geometry/Braids/pages", "Geometry"])).toEqual([true, false]);
  const notebook = JSON.parse(Buffer.from(await readOpfsFile(page, ".trash/Geometry/Braids/notebook.json"), "base64").toString());
  expect(notebook.format).toBe("math-notes");
});

test("deleting a notebook moves it to Notes/.trash/", async ({ page }) => {
  await startEmpty(page);
  await newNote(page, "Knots");
  const svg = await readOpfsFile(page, "Knots/pages/0001.svg");
  await page.getByRole("button", { name: "Library" }).click();
  await page.getByRole("button", { name: "My Notes", exact: true }).click();
  await entryMenu(page, "Knots", "Move to Trash");
  await expect.poll(() => directoriesExist(page, [".trash/Knots", "Knots"])).toEqual([true, false]);
  expect(await readOpfsFile(page, ".trash/Knots/pages/0001.svg")).toBe(svg);
});

test("a thumbnail shows page 1's ink and is rendered again only when page 1's file changes", async ({ page }) => {
  await startEmpty(page);
  await newNote(page, "Knots");
  const box = (await page.locator("#ink-canvas").boundingBox())!;
  for (let line = 0; line < 6; line++) {
    await drawWithPen(page, Array.from({ length: 30 }, (_, i) => ({ x: box.x + 80 + i * 12, y: box.y + 100 + line * 12 })));
  }
  await savedStrokes(page, "pages/0001.svg");
  await page.getByRole("button", { name: "Library" }).click();
  await page.getByRole("button", { name: "My Notes", exact: true }).click();
  const stats = () => page.evaluate(() => ({ ...window.mathNotesThumbnails! }));
  await expect.poll(async () => (await stats()).renders).toBe(1);

  // The cached PNG is 240 px wide and holds the strokes' dark pixels.
  const ink = await page.evaluate(async () => {
    const cache = await (await navigator.storage.getDirectory()).getDirectoryHandle(".thumbnail-cache");
    for await (const [, entry] of cache.entries()) {
      for await (const [, file] of (entry as FileSystemDirectoryHandle).entries()) {
        const bitmap = await createImageBitmap(await (file as FileSystemFileHandle).getFile());
        const context = new OffscreenCanvas(bitmap.width, bitmap.height).getContext("2d")!;
        context.drawImage(bitmap, 0, 0);
        const data = context.getImageData(0, 0, bitmap.width, bitmap.height).data;
        let dark = 0;
        for (let i = 0; i < data.length; i += 4) if (Math.max(data[i], data[i + 1], data[i + 2]) < 200) dark++;
        return { width: bitmap.width, dark };
      }
    }
    return null;
  });
  expect(ink?.width).toBe(240);
  expect(ink?.dark).toBeGreaterThan(100);

  // A rescan reads the cache.
  const before = await stats();
  await focusWindow(page);
  await expect.poll(async () => (await stats()).hits).toBeGreaterThan(before.hits);
  expect((await stats()).renders).toBe(1);

  // Another program changes page 1: the next rescan renders it again.
  await page.evaluate(async () => {
    const pages = await (await (await navigator.storage.getDirectory()).getDirectoryHandle("Knots")).getDirectoryHandle("pages");
    const handle = await pages.getFileHandle("0001.svg");
    const text = await (await handle.getFile()).text();
    const writable = await handle.createWritable();
    await writable.write(`${text}\n`);
    await writable.close();
  });
  await focusWindow(page);
  await expect.poll(async () => (await stats()).renders).toBe(2);
});

// Copies directory `from` to `to` (paths from the notes root) in the
// origin-private file system, as another program would.
async function copyDirectory(page: Page, from: string, to: string): Promise<void> {
  await page.evaluate(
    async ([source, target]) => {
      const copy = async (from: FileSystemDirectoryHandle, to: FileSystemDirectoryHandle) => {
        for await (const [name, handle] of from.entries()) {
          if (handle.kind === "directory") {
            await copy(handle, await to.getDirectoryHandle(name, { create: true }));
            continue;
          }
          const writable = await (await to.getFileHandle(name, { create: true })).createWritable();
          await writable.write(await handle.getFile());
          await writable.close();
        }
      };
      const at = async (path: string, create: boolean) => {
        let dir = await navigator.storage.getDirectory();
        for (const part of path.split("/")) dir = await dir.getDirectoryHandle(part, { create });
        return dir;
      };
      await copy(await at(source, false), await at(target, true));
    },
    [from, to],
  );
}

test("folders open into their subfolders and notebooks, and the path leads back", async ({ page }) => {
  await startEmpty(page);
  await expect(page.getByRole("button", { name: "New Note", exact: true })).toBeEnabled(); // templates written
  // Algebra/Rings/ holds notebook Ideals; Algebra/ holds notebook Groups.
  await copyDirectory(page, ".templates/blank", "Algebra/Groups");
  await copyDirectory(page, ".templates/blank", "Algebra/Rings/Ideals");
  await focusWindow(page);
  const grid = page.getByRole("list", { name: "Notebooks" });
  const path = page.getByRole("navigation", { name: "Folder path" });

  await grid.getByRole("button", { name: "Algebra", exact: true }).click();
  await expect(path).toHaveText(/My Notes.*Algebra/);
  await expect(grid.getByRole("button", { name: "Rings", exact: true })).toBeVisible();
  await expect(grid.getByRole("button", { name: "Groups", exact: true })).toBeVisible();
  await expect(grid).not.toContainText("Ideals");

  await grid.getByRole("button", { name: "Rings", exact: true }).click();
  await expect(grid.getByRole("button", { name: "Ideals", exact: true })).toBeVisible();
  await expect(grid).not.toContainText("Groups");

  await openFolder(page, "Algebra");
  await expect(grid.getByRole("button", { name: "Groups", exact: true })).toBeVisible();
  await openFolder(page, "My Notes");
  await expect(grid.getByRole("button", { name: "Algebra", exact: true })).toBeVisible();
  await expect(grid).not.toContainText("Groups");
});

test("a thumbnail is rendered again when an image that page 1 shows changes", async ({ page }) => {
  await startEmpty(page);
  await expect(page.getByRole("button", { name: "New Note", exact: true })).toBeEnabled();
  await copyDirectory(page, ".templates/blank", "Scan");
  // A full-page image in page 1's background, as an imported PDF page is
  // stored (docs/FORMAT.md, Background), in one color.
  const setImage = (color: string) =>
    page.evaluate(async (fill) => {
      const canvas = new OffscreenCanvas(8, 8);
      const context = canvas.getContext("2d")!;
      context.fillStyle = fill;
      context.fillRect(0, 0, 8, 8);
      const note = await (await navigator.storage.getDirectory()).getDirectoryHandle("Scan");
      const assets = await note.getDirectoryHandle("assets", { create: true });
      const writable = await (await assets.getFileHandle("p0001.png", { create: true })).createWritable();
      await writable.write(await canvas.convertToBlob({ type: "image/png" }));
      await writable.close();
    }, color);
  await setImage("#FF0000");
  await page.evaluate(async () => {
    const pages = await (await (await navigator.storage.getDirectory()).getDirectoryHandle("Scan")).getDirectoryHandle("pages");
    const handle = await pages.getFileHandle("0001.svg");
    const svg = (await (await handle.getFile()).text()).replace(
      /(<g id="background"[^>]*>\s*<rect[^>]*\/>)/,
      '$1\n    <image href="../assets/p0001.png" x="0" y="0" width="595.28" height="841.89"/>',
    );
    const writable = await handle.createWritable();
    await writable.write(svg);
    await writable.close();
  });
  // The color at the middle of the cached thumbnail.
  const cachedColor = () =>
    page.evaluate(async () => {
      const cache = await (await navigator.storage.getDirectory()).getDirectoryHandle(".thumbnail-cache");
      for await (const [, entry] of cache.entries()) {
        for await (const [, file] of (entry as FileSystemDirectoryHandle).entries()) {
          const bitmap = await createImageBitmap(await (file as FileSystemFileHandle).getFile());
          const context = new OffscreenCanvas(bitmap.width, bitmap.height).getContext("2d")!;
          context.drawImage(bitmap, 0, 0);
          return Array.from(context.getImageData(bitmap.width / 2, bitmap.height / 2, 1, 1).data.slice(0, 3));
        }
      }
      return null;
    });
  const stats = () => page.evaluate(() => ({ ...window.mathNotesThumbnails! }));

  await focusWindow(page);
  await expect.poll(async () => (await stats()).renders).toBe(1);
  expect(await cachedColor()).toEqual([255, 0, 0]);

  await setImage("#0000FF");
  await focusWindow(page);
  await expect.poll(async () => (await stats()).renders).toBe(2);
  expect(await cachedColor()).toEqual([0, 0, 255]);
});

test("Share exports the open notebook as a PDF", async ({ page }) => {
  await startEmpty(page);
  await newNote(page, "Algebra");
  await drawWithPen(page, [
    { x: 300, y: 200 },
    { x: 330, y: 210 },
    { x: 360, y: 200 },
  ]);
  await expect.poll(async () => {
    const svg = Buffer.from(await readOpfsFile(page, "Algebra/pages/0001.svg"), "base64").toString();
    return svg.includes('<path id="s-');
  }).toBe(true);

  await page.getByRole("button", { name: "Share" }).click();
  const downloadPromise = page.waitForEvent("download");
  await page.getByRole("button", { name: "Export PDF" }).click();
  const download = await downloadPromise;
  expect(download.suggestedFilename()).toBe("Algebra.pdf");
  const pdf = await readFile((await download.path())!);
  expect(pdf.subarray(0, 5).toString()).toBe("%PDF-");
  expect(pdf.length).toBeGreaterThan(1000);
});

test("Share exports only the selected PDF page range", async ({ page }) => {
  await startEmpty(page);
  await newNote(page, "Range");
  await drawWithPen(page, [
    { x: 300, y: 200 },
    { x: 330, y: 210 },
    { x: 360, y: 200 },
  ]);
  await page.getByRole("button", { name: "Page actions" }).click();
  await page.getByText("Insert page after", { exact: true }).click();
  await expect(page.getByLabel("Page", { exact: true })).toHaveText(/\/ 2$/);

  await page.getByRole("button", { name: "Share" }).click();
  await page.getByLabel("From page").fill("2");
  const secondDownload = page.waitForEvent("download");
  await page.getByRole("button", { name: "Export PDF" }).click();
  const second = await readFile((await (await secondDownload).path())!);

  await page.getByRole("button", { name: "Share" }).click();
  await page.getByLabel("Through page").fill("1");
  const firstDownload = page.waitForEvent("download");
  await page.getByRole("button", { name: "Export PDF" }).click();
  const first = await readFile((await (await firstDownload).path())!);
  expect(first.subarray(0, 5).toString()).toBe("%PDF-");
  expect(second.subarray(0, 5).toString()).toBe("%PDF-");
  expect(first).not.toEqual(second);
});
