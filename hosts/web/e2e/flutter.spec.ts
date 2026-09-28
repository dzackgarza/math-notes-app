import { expect, test, type Locator } from "@playwright/test";
import { execFileSync } from "node:child_process";
import { readFile } from "node:fs/promises";

// Flutter activates its text input channel after semantic focus is delivered.
// Use actual keyboard input after clicking, rather than fill's synchronous DOM
// value assignment. See Flutter web_ui semantics/text_field.dart, activate.
async function enterText(field: Locator, value: string): Promise<void> {
  await field.click();
  await field.press("ControlOrMeta+a");
  await field.pressSequentially(value);
}

test("Flutter notebook cards retain their notes and metadata after rename", async ({ page }, info) => {
  test.setTimeout(90_000);
  await page.goto("flutter/?root=opfs");
  await page.getByRole("button", { name: "New Notebook", exact: true }).click();
  await enterText(page.getByRole("textbox", { name: "Title", exact: true }), "Algebra");
  await enterText(page.getByRole("textbox", { name: "Description", exact: true }), "Lecture notes");
  await enterText(page.getByRole("textbox", { name: "Tags, separated by commas", exact: true }), "groups");
  await page.getByRole("button", { name: "Ruled", exact: true }).click();
  await page.getByRole("button", { name: "Create", exact: true }).click();
  await expect(page.getByRole("button", { name: "Algebra", exact: true })).toBeVisible();
  await page.getByRole("button", { name: "New Note", exact: true }).click();
  await enterText(page.getByRole("textbox", { name: "Title", exact: true }), "Rings");
  await page.getByRole("button", { name: "Create", exact: true }).click();
  await page.getByRole("button", { name: "Save", exact: true }).waitFor();
  await page.getByRole("button", { name: "Library", exact: true }).click();
  await expect(page.getByRole("button", { name: "Info", exact: true })).toBeVisible();
  await page.getByRole("button", { name: "Info", exact: true }).click();
  await expect(page.getByText("Lecture notes", { exact: true })).toBeVisible();
  await page.screenshot({ path: info.outputPath("notebook-info.png") });
  await page.getByRole("button", { name: "Algebra notebook actions", exact: true }).click();
  await page.getByRole("button", { name: "Rename", exact: true }).click();
  await enterText(page.getByRole("textbox", { name: "Name", exact: true }), "Field theory");
  await page.getByRole("button", { name: "Rename", exact: true }).click();
  await expect(page.getByRole("button", { name: "Field theory notebook actions", exact: true })).toBeVisible();
  await page.reload();
  await page.getByRole("button", { name: "Select Field theory", exact: true }).click();
  await page.getByRole("button", { name: "Rings", exact: true }).click();
  await page.getByRole("button", { name: "Save", exact: true }).waitFor();
  const stored = await page.evaluate(async () => {
    const root = await navigator.storage.getDirectory();
    const folder = await root.getDirectoryHandle("Field theory");
    const note = await folder.getDirectoryHandle("Rings");
    return {
      manifest: await (await (await note.getFileHandle("notebook.json")).getFile()).text(),
      metadata: await (await (await root.getFileHandle(".library.json")).getFile()).text(),
      folders: await Array.fromAsync(root.keys()),
    };
  });
  expect(stored.folders).not.toContain("Algebra");
  expect(JSON.parse(stored.manifest).template).toBe("lined-medium");
  const metadata = JSON.parse(stored.metadata);
  expect(metadata.folders["Field theory"].description).toBe("Lecture notes");
  expect(metadata.notes["Field theory/Rings"].tags).toEqual(["groups"]);
  expect(metadata.folders.Algebra).toBeUndefined();
  expect(metadata.notes["Algebra/Rings"]).toBeUndefined();
});

test("Flutter finds an image note through persistent tags and its page thumbnail", async ({ page }, info) => {
  test.setTimeout(90_000);
  await page.goto("flutter/?root=opfs");
  await page.getByRole("button", { name: "New Note", exact: true }).click();
  await enterText(page.getByRole("textbox", { name: "Title", exact: true }), "Diagram");
  await enterText(page.getByRole("textbox", { name: "Tags, separated by commas", exact: true }), "topology");
  await page.getByRole("button", { name: "Create", exact: true }).click();
  await page.getByRole("button", { name: "Save", exact: true }).waitFor();
  const chooser = page.waitForEvent("filechooser");
  await page.getByRole("button", { name: "More", exact: true }).click();
  await page.getByRole("button", { name: "Image", exact: true }).click();
  await (await chooser).setFiles("../../core/tests/fixtures/render/full/0001.png");
  await expect(page.getByRole("button", { name: "Delete selection", exact: true })).toBeAttached();
  await page.getByRole("button", { name: "Save", exact: true }).click();
  await expect(page.getByRole("status")).toHaveAccessibleName("Notebook save Saved");
  await page.getByRole("button", { name: "Library", exact: true }).click();
  await page.reload();
  await page.getByRole("button", { name: /^topology/ }).click();
  await page.getByRole("button", { name: "Grid", exact: true }).click();
  await expect(page.getByRole("img", { name: "Diagram first page", exact: true })).toBeVisible();
  await page.screenshot({ path: info.outputPath("tagged-image-card.png") });
  await page.getByRole("button", { name: "Diagram first page", exact: true }).click();
  await page.getByRole("button", { name: "Save", exact: true }).waitFor();
  const saved = await page.evaluate(async () => {
    const root = await navigator.storage.getDirectory();
    const dir = await root.getDirectoryHandle("Diagram");
    const pages = await dir.getDirectoryHandle("pages");
    const svg = await (await (await pages.getFileHandle("0001.svg")).getFile()).text();
    const name = svg.match(/href="\.\.\/assets\/([0-9a-f]+\.png)"/)?.[1];
    if (!name) throw new Error("Saved image has no PNG asset reference");
    const assets = await dir.getDirectoryHandle("assets");
    const file = await (await assets.getFileHandle(name)).getFile();
    return {
      image: btoa(String.fromCharCode(...new Uint8Array(await file.arrayBuffer()))),
      metadata: await (await (await root.getFileHandle(".library.json")).getFile()).text(),
    };
  });
  expect(Buffer.from(saved.image, "base64")).toEqual(await readFile("../../core/tests/fixtures/render/full/0001.png"));
  expect(JSON.parse(saved.metadata).tags).toContainEqual({ name: "topology", color: "#2F6FEB" });
  await page.screenshot({ path: info.outputPath("image-note-reopened.png") });
});

test("Flutter adds a page only after a held edge pull and preserves keyboard history", async ({ page }) => {
  test.setTimeout(60_000);
  await page.goto("flutter/?root=opfs");
  await page.getByRole("button", { name: "New Note", exact: true }).click();
  await enterText(page.getByRole("textbox", { name: "Title", exact: true }), "Navigation");
  await page.getByRole("button", { name: "Create", exact: true }).click();
  const canvas = page.locator('canvas[id^="ink-canvas-"]');
  await canvas.waitFor();
  const box = await canvas.boundingBox();
  if (!box) throw new Error("Notebook canvas has no bounds");
  await page.mouse.move(box.x + box.width / 2, box.y + box.height / 2);
  await page.mouse.wheel(0, 4000);
  await expect(page.getByText("Pull and hold to add a page", { exact: true })).toBeVisible();
  const cdp = await page.context().newCDPSession(page);
  const x = box.x + box.width / 2;
  const y = box.y + box.height - 40;
  for (const held of [false, true]) {
    await cdp.send("Input.dispatchTouchEvent", { type: "touchStart", touchPoints: [{ id: 1, x, y }] });
    for (const distance of [20, 360]) {
      await cdp.send("Input.dispatchTouchEvent", { type: "touchMove", touchPoints: [{ id: 1, x, y: y - distance }] });
    }
    if (held) await expect(page.getByText("Release to add a page", { exact: true })).toBeVisible();
    await cdp.send("Input.dispatchTouchEvent", { type: "touchEnd", touchPoints: [] });
    if (!held) {
      await expect(page.getByText("1 / 1", { exact: true })).toBeVisible();
      await expect(page.getByText("Pull and hold to add a page", { exact: true })).toBeVisible();
    }
  }
  await expect(page.getByText(/^[12] \/ 2$/)).toBeVisible();
  await page.keyboard.press("Control+z");
  await expect(page.getByText("1 / 1", { exact: true })).toBeVisible();
  await page.keyboard.press("Control+Shift+z");
  await expect(page.getByText(/^[12] \/ 2$/)).toBeVisible();
  await page.keyboard.press("Control+s");
  await expect(page.getByRole("status")).toHaveAccessibleName("Notebook save Saved");
  const manifest = await page.evaluate(async () => {
    const root = await navigator.storage.getDirectory();
    const dir = await root.getDirectoryHandle("Navigation");
    return (await (await dir.getFileHandle("notebook.json")).getFile()).text();
  });
  expect(JSON.parse(manifest).pages).toHaveLength(2);
});

test("Flutter creation resumes a draft and applies saved note settings", async ({ page }, info) => {
  test.setTimeout(60_000);
  page.on("pageerror", error => console.error(error.stack));
  page.on("console", message => { if (message.type() === "error") console.error(message.text()); });
  await page.goto("flutter/?root=opfs");
  await page.getByRole("button", { name: "New Note", exact: true }).click();
  await enterText(page.getByRole("textbox", { name: "Title", exact: true }), "Seminar");
  await page.getByRole("button", { name: "Ruled", exact: true }).click();
  await enterText(page.getByRole("textbox", { name: "Tags, separated by commas", exact: true }), "analysis");
  await page.getByRole("button", { name: "Letter", exact: true }).click();
  await page.getByRole("button", { name: "Save as Draft", exact: true }).click();
  await expect(page.getByRole("status", { name: "Draft saved", exact: true })).toBeVisible();
  await page.reload();
  await page.getByRole("button", { name: "New Note", exact: true }).click();
  await expect(page.getByRole("textbox", { name: "Title", exact: true })).toHaveValue("Seminar");
  await enterText(page.getByRole("textbox", { name: "Settings name", exact: true }), "Proof paper");
  await page.getByRole("button", { name: "Save as template", exact: true }).click();
  await expect(page.getByRole("status", { name: "Template saved", exact: true })).toBeVisible();
  await page.reload();
  await page.getByRole("button", { name: "New Note", exact: true }).click();
  await page.getByRole("button", { name: "Plain", exact: true }).click();
  await enterText(page.getByRole("textbox", { name: "Tags, separated by commas", exact: true }), "temporary");
  await page.getByRole("button", { name: "Proof paper", exact: true }).click();
  await expect(page.getByRole("img", { name: "First page preview", exact: true })).toBeVisible();
  await page.screenshot({ path: info.outputPath("settings-selected.png") });
  await page.getByRole("textbox", { name: "Tags, separated by commas", exact: true }).click();
  await expect(page.getByRole("textbox", { name: "Tags, separated by commas", exact: true })).toHaveValue("analysis");
  await page.getByRole("button", { name: "Create", exact: true }).click();
  await page.getByRole("button", { name: "Save", exact: true }).waitFor();
  const stored = await page.evaluate(async () => {
    const root = await navigator.storage.getDirectory();
    const note = await root.getDirectoryHandle("Seminar");
    return {
      manifest: await (await (await note.getFileHandle("notebook.json")).getFile()).text(),
      metadata: await (await (await root.getFileHandle(".library.json")).getFile()).text(),
    };
  });
  expect(JSON.parse(stored.manifest).template).toBe("lined-medium");
  expect(JSON.parse(stored.metadata).notes.Seminar.tags).toEqual(["analysis"]);
  expect(JSON.parse(stored.metadata).draft).toBeUndefined();
});

test("Flutter ignores a palm that drags during a pen stroke", async ({ page }) => {
  test.setTimeout(60_000);
  await page.goto("flutter/?root=opfs");
  await page.getByRole("button", { name: "New Note", exact: true }).click();
  await enterText(page.getByRole("textbox", { name: "Title", exact: true }), "Palm");
  await page.getByRole("button", { name: "Create", exact: true }).click();
  const canvas = page.locator('canvas[id^="ink-canvas-"]');
  await canvas.waitFor();
  const box = await canvas.boundingBox();
  if (!box) throw new Error("Notebook canvas has no bounds");
  const cdp = await page.context().newCDPSession(page);
  const pen = { pointerType: "pen" as const, force: 0.6 };
  const palm = { id: 1, x: box.x + box.width - 80, y: box.y + box.height - 60 };
  await cdp.send("Input.dispatchMouseEvent", { type: "mousePressed", button: "left", clickCount: 1, x: box.x + 160, y: box.y + 150, ...pen });
  await cdp.send("Input.dispatchTouchEvent", { type: "touchStart", touchPoints: [palm] });
  for (const distance of [40, 150, 300]) {
    await cdp.send("Input.dispatchTouchEvent", { type: "touchMove", touchPoints: [{ ...palm, y: palm.y - distance }] });
    await cdp.send("Input.dispatchMouseEvent", { type: "mouseMoved", button: "left", buttons: 1, x: box.x + 160 + distance / 4, y: box.y + 150 + distance / 8, ...pen });
  }
  await cdp.send("Input.dispatchTouchEvent", { type: "touchEnd", touchPoints: [] });
  await cdp.send("Input.dispatchMouseEvent", { type: "mouseReleased", button: "left", clickCount: 1, x: box.x + 235, y: box.y + 187, ...pen });
  await page.getByRole("button", { name: "Save", exact: true }).click();
  await expect(page.getByRole("status")).toHaveAccessibleName("Notebook save Saved");
  const trace = await page.evaluate(async () => {
    const root = await navigator.storage.getDirectory();
    const pages = await (await root.getDirectoryHandle("Palm")).getDirectoryHandle("pages");
    const svg = await (await (await pages.getFileHandle("0001.svg")).getFile()).text();
    const text = new DOMParser().parseFromString(svg, "image/svg+xml").getElementsByTagName("inkml:trace")[0]?.textContent;
    if (!text) throw new Error("Saved page has no stroke trace");
    return text.split(",").map((sample) => sample.trim().split(" ").slice(0, 2).map(Number));
  });
  const xs = trace.map(([x]) => x);
  const ys = trace.map(([, y]) => y);
  // The pen moved 75 px right and 37 px down. A page that scrolled with the
  // palm would stretch the stroke 300 px vertically.
  expect(Math.max(...ys) - Math.min(...ys)).toBeLessThan(Math.max(...xs) - Math.min(...xs));
});

test("Flutter undoes on a two-finger tap and redoes on a three-finger tap", async ({ page }) => {
  test.setTimeout(60_000);
  await page.goto("flutter/?root=opfs");
  await page.getByRole("button", { name: "New Note", exact: true }).click();
  await enterText(page.getByRole("textbox", { name: "Title", exact: true }), "Taps");
  await page.getByRole("button", { name: "Create", exact: true }).click();
  const canvas = page.locator('canvas[id^="ink-canvas-"]');
  await canvas.waitFor();
  const box = await canvas.boundingBox();
  if (!box) throw new Error("Notebook canvas has no bounds");
  const cdp = await page.context().newCDPSession(page);
  const pen = { pointerType: "pen" as const, force: 0.6 };
  await cdp.send("Input.dispatchMouseEvent", { type: "mousePressed", button: "left", clickCount: 1, x: box.x + 160, y: box.y + 150, ...pen });
  await cdp.send("Input.dispatchMouseEvent", { type: "mouseMoved", button: "left", buttons: 1, x: box.x + 240, y: box.y + 190, ...pen });
  await cdp.send("Input.dispatchMouseEvent", { type: "mouseReleased", button: "left", clickCount: 1, x: box.x + 240, y: box.y + 190, ...pen });
  const strokes = async () => {
    await page.getByRole("button", { name: "Save", exact: true }).click();
    await expect(page.getByRole("status")).toHaveAccessibleName("Notebook save Saved");
    return page.evaluate(async () => {
      const root = await navigator.storage.getDirectory();
      const pages = await (await root.getDirectoryHandle("Taps")).getDirectoryHandle("pages");
      const svg = await (await (await pages.getFileHandle("0001.svg")).getFile()).text();
      return svg.match(/<path id="s-/g)?.length ?? 0;
    });
  };
  const tap = async (fingers: number) => {
    const touchPoints = Array.from({ length: fingers }, (_, id) => ({ id, x: box.x + 400 + 60 * id, y: box.y + 300 }));
    await cdp.send("Input.dispatchTouchEvent", { type: "touchStart", touchPoints });
    await cdp.send("Input.dispatchTouchEvent", { type: "touchEnd", touchPoints: [] });
  };
  expect(await strokes()).toBe(1);
  await tap(2);
  expect(await strokes()).toBe(0);
  await tap(3);
  expect(await strokes()).toBe(1);
});

test("Flutter erases with the pen side button and draws with a finger on request", async ({ page }) => {
  test.setTimeout(120_000);
  await page.goto("flutter/?root=opfs");
  await page.getByRole("button", { name: "New Note", exact: true }).click();
  await enterText(page.getByRole("textbox", { name: "Title", exact: true }), "Fingers");
  await page.getByRole("button", { name: "Create", exact: true }).click();
  const canvas = page.locator('canvas[id^="ink-canvas-"]');
  await canvas.waitFor({ timeout: 30_000 });
  const box = await canvas.boundingBox();
  if (!box) throw new Error("Notebook canvas has no bounds");
  const cdp = await page.context().newCDPSession(page);
  const strokes = async () => {
    await page.getByRole("button", { name: "Save", exact: true }).click();
    await expect(page.getByRole("status")).toHaveAccessibleName("Notebook save Saved");
    return page.evaluate(async () => {
      const root = await navigator.storage.getDirectory();
      const pages = await (await root.getDirectoryHandle("Fingers")).getDirectoryHandle("pages");
      const svg = await (await (await pages.getFileHandle("0001.svg")).getFile()).text();
      return svg.match(/<path id="s-/g)?.length ?? 0;
    });
  };
  const penDrag = async (button: "left" | "right", from: [number, number], to: [number, number]) => {
    const pen = { pointerType: "pen" as const, force: 0.6, button, buttons: button === "left" ? 1 : 2 };
    await cdp.send("Input.dispatchMouseEvent", { type: "mousePressed", clickCount: 1, x: box.x + from[0], y: box.y + from[1], ...pen });
    await cdp.send("Input.dispatchMouseEvent", { type: "mouseMoved", x: box.x + (from[0] + to[0]) / 2, y: box.y + (from[1] + to[1]) / 2, ...pen });
    await cdp.send("Input.dispatchMouseEvent", { type: "mouseMoved", x: box.x + to[0], y: box.y + to[1], ...pen });
    await cdp.send("Input.dispatchMouseEvent", { type: "mouseReleased", clickCount: 1, x: box.x + to[0], y: box.y + to[1], ...pen, buttons: 0 });
  };
  await penDrag("left", [160, 150], [300, 150]);
  expect(await strokes()).toBe(1);
  await penDrag("right", [230, 100], [230, 200]);
  expect(await strokes()).toBe(0);

  await page.getByRole("button", { name: "More", exact: true }).click();
  await page.getByRole("button", { name: "Draw with finger", exact: true }).click();
  const finger = (id: number, x: number, y: number) => ({ id, x: box.x + x, y: box.y + y });
  await cdp.send("Input.dispatchTouchEvent", { type: "touchStart", touchPoints: [finger(1, 160, 250)] });
  for (const x of [200, 260, 320]) {
    await cdp.send("Input.dispatchTouchEvent", { type: "touchMove", touchPoints: [finger(1, x, 250)] });
  }
  await cdp.send("Input.dispatchTouchEvent", { type: "touchEnd", touchPoints: [] });
  expect(await strokes()).toBe(1);
  // A second finger turns the stroke in progress into a pan.
  await cdp.send("Input.dispatchTouchEvent", { type: "touchStart", touchPoints: [finger(1, 160, 350)] });
  await cdp.send("Input.dispatchTouchEvent", { type: "touchMove", touchPoints: [finger(1, 200, 350)] });
  await cdp.send("Input.dispatchTouchEvent", { type: "touchStart", touchPoints: [finger(1, 200, 350), finger(2, 260, 350)] });
  for (const y of [320, 290, 260]) {
    await cdp.send("Input.dispatchTouchEvent", { type: "touchMove", touchPoints: [finger(1, 200, y), finger(2, 260, y)] });
  }
  await cdp.send("Input.dispatchTouchEvent", { type: "touchEnd", touchPoints: [] });
  expect(await strokes()).toBe(1);

  await page.reload();
  await page.getByRole("button", { name: "Fingers", exact: true }).click();
  await canvas.waitFor({ timeout: 30_000 });
  await page.getByRole("button", { name: "More", exact: true }).click();
  await expect(page.getByRole("button", { name: "Stop drawing with finger", exact: true })).toBeVisible();
});

test("Flutter page overview duplicates, deletes, reorders, and opens pages", async ({ page }, info) => {
  test.setTimeout(90_000);
  await page.goto("flutter/?root=opfs");
  await page.getByRole("button", { name: "New Note", exact: true }).click();
  await enterText(page.getByRole("textbox", { name: "Title", exact: true }), "Overview");
  await page.getByRole("button", { name: "Create", exact: true }).click();
  await page.locator('canvas[id^="ink-canvas-"]').waitFor();
  for (let added = 0; added < 2; added++) await page.getByRole("button", { name: "Add page", exact: true }).click();
  await expect(page.getByText(/^\d \/ 3$/)).toBeVisible();
  await page.getByRole("button", { name: "Pages", exact: true }).click();
  const tile = (n: number) => page.getByRole("button", { name: `Page ${n}`, exact: true });
  await expect(tile(3)).toBeVisible();

  const act = async (n: number, action: string) => {
    await page.getByRole("button", { name: `Page ${n} actions`, exact: true }).click();
    await page.getByRole("button", { name: action, exact: true }).click();
  };
  await act(1, "Duplicate");
  await expect(tile(4)).toBeVisible();
  await act(4, "Delete");
  await expect(tile(4)).toHaveCount(0);

  const from = await tile(1).boundingBox();
  const to = await tile(3).boundingBox();
  if (!from || !to) throw new Error("Page tiles have no bounds");
  await page.mouse.move(from.x + from.width / 2, from.y + from.height / 2);
  await page.mouse.down();
  await page.waitForTimeout(800);
  await page.mouse.move(to.x + to.width / 2, to.y + to.height / 2, { steps: 20 });
  await page.waitForTimeout(400);
  await page.mouse.up();
  await page.screenshot({ path: info.outputPath("page-overview.png") });

  await tile(2).click();
  await expect(page.getByText("2 / 3", { exact: true })).toBeVisible();
  await page.getByRole("button", { name: "Save", exact: true }).click();
  await expect(page.getByRole("status")).toHaveAccessibleName("Notebook save Saved");
  const manifest = await page.evaluate(async () => {
    const root = await navigator.storage.getDirectory();
    const dir = await root.getDirectoryHandle("Overview");
    return (await (await dir.getFileHandle("notebook.json")).getFile()).text();
  });
  // Pages 0001-0003; the copy of page 1 is 0004 after it; page 3 (0003)
  // is deleted; page 1 moves to the end.
  expect(JSON.parse(manifest).pages.map((entry: { file: string }) => entry.file)).toEqual([
    "pages/0004.svg",
    "pages/0002.svg",
    "pages/0001.svg",
  ]);
});

test("Flutter recolors a lasso selection from the palette and keeps the pen color", async ({ page }) => {
  test.setTimeout(60_000);
  await page.goto("flutter/?root=opfs");
  await page.getByRole("button", { name: "New Note", exact: true }).click();
  await enterText(page.getByRole("textbox", { name: "Title", exact: true }), "Recolor");
  await page.getByRole("button", { name: "Create", exact: true }).click();
  const canvas = page.locator('canvas[id^="ink-canvas-"]');
  await canvas.waitFor();
  const box = await canvas.boundingBox();
  if (!box) throw new Error("Notebook canvas has no bounds");
  const cdp = await page.context().newCDPSession(page);
  const pen = { pointerType: "pen" as const, force: 0.6 };
  const gesture = async (points: [number, number][]) => {
    const [[x0, y0], ...rest] = points;
    await cdp.send("Input.dispatchMouseEvent", { type: "mousePressed", button: "left", clickCount: 1, x: box.x + x0, y: box.y + y0, ...pen });
    for (const [x, y] of rest) await cdp.send("Input.dispatchMouseEvent", { type: "mouseMoved", button: "left", buttons: 1, x: box.x + x, y: box.y + y, ...pen });
    const [x, y] = points[points.length - 1];
    await cdp.send("Input.dispatchMouseEvent", { type: "mouseReleased", button: "left", clickCount: 1, x: box.x + x, y: box.y + y, ...pen });
  };
  await gesture([[160, 150], [200, 170], [240, 190]]);
  await page.getByRole("button", { name: "Lasso", exact: true }).click();
  await gesture([[130, 120], [200, 115], [270, 120], [275, 170], [270, 220], [200, 225], [130, 220], [125, 170], [130, 120]]);
  await expect(page.getByRole("button", { name: "Delete selection", exact: true })).toBeAttached();
  await page.getByRole("button", { name: "Color #d92d39", exact: true }).click();
  await page.getByRole("button", { name: "Pen 1.2 pt", exact: true }).click();
  // A pen-down away from a selection only clears it (Write, clearSelOnly).
  await gesture([[600, 500], [600, 500]]);
  await expect(page.getByRole("button", { name: "Delete selection", exact: true })).toHaveCount(0);
  await gesture([[160, 350], [200, 370], [240, 390]]);
  await page.getByRole("button", { name: "Save", exact: true }).click();
  await expect(page.getByRole("status")).toHaveAccessibleName("Notebook save Saved");
  const fills = await page.evaluate(async () => {
    const root = await navigator.storage.getDirectory();
    const pages = await (await root.getDirectoryHandle("Recolor")).getDirectoryHandle("pages");
    const svg = await (await (await pages.getFileHandle("0001.svg")).getFile()).text();
    return [...svg.matchAll(/<path id="s-[^"]*"[^>]* fill="(#[0-9A-F]{6})"/g)].map((match) => match[1]);
  });
  expect(fills).toEqual(["#D92D39", "#1A1A1A"]);
});

test("Flutter notebook retains pen input and pages after save and reopen", async ({ page }, info) => {
  test.setTimeout(120_000);
  await page.goto("favicon.svg");
  await page.evaluate(async () => {
    const root = await navigator.storage.getDirectory();
    for await (const name of root.keys()) await root.removeEntry(name, { recursive: true });
  });
  await page.goto("flutter/?root=opfs");
  await page.getByRole("button", { name: "New Note", exact: true }).click();
  await enterText(page.getByRole("textbox", { name: "Title" }), "Lecture");
  await page.getByRole("button", { name: "Create", exact: true }).click();
  const canvas = page.locator('canvas[id^="ink-canvas-"]');
  await expect(canvas).toBeVisible();
  const box = await canvas.boundingBox();
  if (!box) throw new Error("Notebook canvas has no bounds");
  const cdp = await page.context().newCDPSession(page);
  const pen = { pointerType: "pen" as const, force: 0.6, tiltX: 20, tiltY: -10 };
  await cdp.send("Input.dispatchMouseEvent", { type: "mousePressed", button: "left", clickCount: 1, x: box.x + 160, y: box.y + 150, ...pen });
  await cdp.send("Input.dispatchMouseEvent", { type: "mouseMoved", button: "left", buttons: 1, x: box.x + 240, y: box.y + 190, ...pen });
  await cdp.send("Input.dispatchMouseEvent", { type: "mouseReleased", button: "left", clickCount: 1, x: box.x + 240, y: box.y + 190, ...pen });
  await page.getByText("Add page", { exact: true }).click();
  await page.getByRole("button", { name: "Save", exact: true }).click();
  await expect(page.getByRole("status")).toHaveAccessibleName("Notebook save Saved");
  const saved = await page.evaluate(async () => {
    const root = await navigator.storage.getDirectory();
    const dir = await root.getDirectoryHandle("Lecture");
    const pages = await dir.getDirectoryHandle("pages");
    return (await (await pages.getFileHandle("0001.svg")).getFile()).text();
  });
  expect(saved).toContain('<path id="s-');
  expect(saved).toContain("inkml:trace");
  await page.getByRole("button", { name: "More", exact: true }).click();
  await page.getByRole("button", { name: "Text", exact: true }).click();
  await enterText(page.getByRole("textbox", { name: "Text", exact: true }), "Lemma\nEvery basis spans the space.");
  await page.getByRole("button", { name: "Done", exact: true }).click();
  await page.getByRole("button", { name: "Save", exact: true }).click();
  await expect.poll(() => page.evaluate(async () => {
    const root = await navigator.storage.getDirectory();
    const dir = await root.getDirectoryHandle("Lecture");
    const pages = await dir.getDirectoryHandle("pages");
    return (await (await pages.getFileHandle("0001.svg")).getFile()).text();
  })).toContain("Every basis spans the space.");
  await page.getByRole("button", { name: "Export PDF", exact: true }).click();
  const exported = page.waitForEvent("download");
  await page.getByRole("button", { name: "Export", exact: true }).click();
  const pdf = await exported;
  const pdfPath = info.outputPath("lecture.pdf");
  await pdf.saveAs(pdfPath);
  expect(execFileSync("pdfinfo", [pdfPath], { encoding: "utf8" })).toMatch(/Pages:\s+2/);
  expect(execFileSync("pdftotext", [pdfPath, "-"], { encoding: "utf8" })).toContain("Every basis spans the space.");
  await page.screenshot({ path: info.outputPath("notebook.png") });
  await page.reload();
  await page.getByRole("button", { name: "Lecture", exact: true }).click();
  await expect(canvas).toBeVisible();
  await expect(page.getByText("1 / 2", { exact: true })).toBeVisible();
  await page.getByRole("button", { name: "Next", exact: true }).click();
  await expect(page.getByText("2 / 2", { exact: true })).toBeVisible();
  await page.getByRole("button", { name: "Library", exact: true }).click();
  await page.getByRole("button", { name: "New Note", exact: true }).click();
  await enterText(page.getByRole("textbox", { name: "Title" }), "Exercises");
  await page.getByRole("button", { name: "Create", exact: true }).click();
  await page.getByRole("button", { name: "Lecture", exact: true }).click();
  await expect(page.getByText("2 / 2", { exact: true })).toBeVisible();
  await page.getByRole("button", { name: "Library", exact: true }).click();
  await page.getByRole("button", { name: "Lecture actions", exact: true }).click();
  await page.getByRole("button", { name: "Add favorite", exact: true }).click();
  await page.getByText("Favorites", { exact: true }).click();
  await expect(page.getByRole("button", { name: "Lecture", exact: true })).toBeVisible();
  await expect(page.getByRole("button", { name: "Exercises", exact: true })).not.toBeVisible();
  await page.context().setOffline(true);
  await page.reload();
  await page.getByRole("button", { name: "Lecture", exact: true }).click();
  await expect(page.getByText("1 / 2", { exact: true })).toBeVisible();
  await page.getByRole("button", { name: "Add page", exact: true }).click();
  await page.getByRole("button", { name: "Save", exact: true }).click();
  await expect(page.getByRole("status")).toHaveAccessibleName("Notebook save Saved");
  await page.reload();
  await page.getByRole("button", { name: "Lecture", exact: true }).click();
  await expect(page.getByText("1 / 3", { exact: true })).toBeVisible();
  await page.context().setOffline(false);
  await page.reload();
  await page.getByText("Favorites", { exact: true }).click();
  await expect(page.getByRole("button", { name: "Lecture", exact: true })).toBeVisible();
});

test("Flutter pen popover changes the brush and size of the selected preset", async ({ page }, info) => {
  test.setTimeout(120_000);
  await page.goto("favicon.svg");
  await page.evaluate(async () => {
    const root = await navigator.storage.getDirectory();
    for await (const name of root.keys()) await root.removeEntry(name, { recursive: true });
  });
  await page.goto("flutter/?root=opfs");
  await page.getByRole("button", { name: "New Note", exact: true }).click();
  await enterText(page.getByRole("textbox", { name: "Title", exact: true }), "Pens");
  await page.getByRole("button", { name: "Create", exact: true }).click();
  await page.locator('canvas[id^="ink-canvas-"]').waitFor();
  // A tap on the selected pen opens its settings beside the rail.
  await page.getByRole("button", { name: "Pen 1.2 pt", exact: true }).click();
  await page.getByRole("button", { name: "Marker", exact: true }).click();
  await page.getByRole("button", { name: "3.6 pt", exact: true }).click();
  await page.screenshot({ path: info.outputPath("pen-popover.png") });
  const viewport = page.viewportSize();
  if (!viewport) throw new Error("Page has no viewport");
  await page.mouse.click(viewport.width - 20, viewport.height - 20);
  await expect(page.getByRole("button", { name: "Pen 3.6 pt", exact: true })).toBeVisible();
  const pens = await page.evaluate(async () => {
    const root = await navigator.storage.getDirectory();
    return JSON.parse(await (await (await root.getFileHandle(".pens.json")).getFile()).text());
  });
  expect(pens[0]).toMatchObject({ id: "pen", brush: "marker", size: 3.6 });
});
