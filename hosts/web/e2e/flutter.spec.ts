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
  await page.getByRole("button", { name: "Pen settings", exact: true }).click();
  await page.getByRole("button", { name: "Cancel", exact: true }).click();
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
