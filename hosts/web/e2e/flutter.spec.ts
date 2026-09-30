import { expect, test, type CDPSession, type Locator, type Page } from "@playwright/test";
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

async function save(page: Page): Promise<void> {
  await page.getByRole("button", { name: "More", exact: true }).click();
  await page.getByRole("button", { name: "Save", exact: true }).click();
}

async function addTag(page: Page, tag: string): Promise<void> {
  await enterText(page.getByRole("textbox", { name: "Add a tag…", exact: true }), tag);
  await page.getByRole("button", { name: "Add tag", exact: true }).click();
}

async function createTestNotebook(page: Page, name = "Test Notebook"): Promise<void> {
  await page.getByRole("button", { name: "New Notebook", exact: true }).click();
  await enterText(page.getByRole("textbox", { name: "Notebook Title", exact: true }), name);
  await page.getByRole("button", { name: "Create Notebook", exact: true }).click();
}

async function openTestNotebook(page: Page, name = "Test Notebook"): Promise<void> {
  await page.getByRole("button", { name: `Open ${name}`, exact: false }).click();
  await expect(page.getByRole("heading", { name, exact: true })).toBeVisible();
}

async function beginTestNote(page: Page, title: string, notebook = "Test Notebook"): Promise<void> {
  await createTestNotebook(page, notebook);
  await page.getByRole("button", { name: "New Note", exact: true }).click();
  await enterText(page.getByRole("textbox", { name: "Title", exact: true }), title);
}

test("Flutter notebook cards retain their notes and metadata after rename", async ({ page }, info) => {
  test.setTimeout(90_000);
  await page.goto("?root=opfs");
  await page.getByRole("button", { name: "New Notebook", exact: true }).click();
  await enterText(page.getByRole("textbox", { name: "Notebook Title", exact: true }), "Algebra");
  await enterText(page.getByRole("textbox", { name: "Description", exact: true }), "Lecture notes");
  await addTag(page, "groups");
  await page.getByRole("button", { name: "Ruled", exact: true }).click();
  await page.getByRole("button", { name: "Create Notebook", exact: true }).click();
  await page.getByRole("button", { name: "New Note", exact: true }).click();
  await enterText(page.getByRole("textbox", { name: "Title", exact: true }), "Rings");
  await page.getByRole("button", { name: "Create Note", exact: true }).click();
  await page.getByRole("button", { name: "More", exact: true }).waitFor();
  await page.getByRole("button", { name: "Library", exact: true }).click();
  await expect(page.getByText("Lecture notes", { exact: true })).toBeVisible();
  await page.screenshot({ path: info.outputPath("notebook-info.png") });
  await page.getByRole("button", { name: "Algebra notebook actions", exact: true }).click();
  await page.getByRole("button", { name: "Rename", exact: true }).click();
  await enterText(page.getByRole("textbox", { name: "Name", exact: true }), "Field theory");
  await page.getByRole("button", { name: "Rename", exact: true }).click();
  await expect(page.getByRole("button", { name: "Field theory notebook actions", exact: true })).toBeVisible();
  await page.reload();
  await openTestNotebook(page, "Field theory");
  await page.getByRole("button", { name: "Open Rings", exact: false }).click();
  await page.getByRole("button", { name: "More", exact: true }).waitFor();
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

test("Flutter moves, finds, trashes, and restores a note with its metadata", async ({ page }) => {
  test.setTimeout(120_000);
  await page.goto("?root=opfs");

  await createTestNotebook(page, "Inbox");
  await page.getByRole("button", { name: "New Note", exact: true }).click();
  await enterText(page.getByRole("textbox", { name: "Title", exact: true }), "Movable");
  await addTag(page, "algebra");
  await page.getByRole("button", { name: "Create Note", exact: true }).click();
  await page.getByRole("button", { name: "Close Movable", exact: true }).click();
  await expect(page.getByRole("heading", { name: "Inbox", exact: true })).toBeVisible();

  await page.getByRole("button", { name: "Notebooks", exact: true }).click();
  await createTestNotebook(page, "Archive");
  await page.getByRole("button", { name: "Notebooks", exact: true }).click();
  await openTestNotebook(page, "Inbox");

  await page.getByRole("button", { name: "Movable actions", exact: true }).click();
  await page.getByRole("button", { name: "Move", exact: true }).click();
  await page.getByRole("button", { name: "Archive", exact: true }).click();
  await expect(page.getByRole("button", { name: "Movable actions", exact: true })).toHaveCount(0);

  await page.getByRole("button", { name: "Notebooks", exact: true }).click();
  await openTestNotebook(page, "Archive");
  await expect(page.getByRole("button", { name: "Open Movable", exact: false })).toBeVisible();

  await page.getByRole("button", { name: "Notebooks", exact: true }).click();
  await page.getByRole("button", { name: "Search", exact: true }).click();
  await enterText(
    page.getByRole("textbox", { name: "Search notebooks and notes", exact: true }),
    "Movable",
  );
  await expect(page.getByRole("button", { name: "Open Movable", exact: false })).toBeVisible();

  await page.getByRole("button", { name: "Recent", exact: true }).click();
  await expect(page.getByRole("button", { name: "Open Movable", exact: false })).toBeVisible();
  await page.getByRole("button", { name: "Movable actions", exact: true }).click();
  await page.getByRole("button", { name: "Move to trash", exact: true }).click();

  await page.getByRole("button", { name: "Trash", exact: true }).click();
  await expect(page.getByRole("button", { name: "Movable actions", exact: true })).toBeVisible();
  await page.getByRole("button", { name: "Movable actions", exact: true }).click();
  await page.getByRole("button", { name: "Restore", exact: true }).click();
  await page.getByRole("button", { name: "Archive", exact: true }).click();

  await page.getByRole("button", { name: "Library", exact: true }).click();
  await openTestNotebook(page, "Archive");
  await expect(page.getByRole("button", { name: "Open Movable", exact: false })).toBeVisible();

  const metadata = JSON.parse(
    await page.evaluate(async () => {
      const root = await navigator.storage.getDirectory();
      return (await (await root.getFileHandle(".library.json")).getFile()).text();
    }),
  );
  expect(metadata.notes["Archive/Movable"].tags).toEqual(["algebra"]);
  expect(metadata.notes["Inbox/Movable"]).toBeUndefined();
  expect(metadata.notes[".trash/Movable"]).toBeUndefined();
});

test("Flutter connects an empty notes folder and shows the empty library", async ({ page }) => {
  test.setTimeout(60_000);
  await page.goto("version.json");
  await page.evaluate(async () => {
    const root = await navigator.storage.getDirectory();
    for await (const name of root.keys()) await root.removeEntry(name, { recursive: true });
  });
  await page.addInitScript(() => {
    Object.defineProperty(window, "showDirectoryPicker", {
      configurable: true,
      value: async () => navigator.storage.getDirectory(),
    });
  });
  await page.goto("");
  const choose = page.getByRole("button", { name: "Choose notes folder", exact: true });
  await expect(choose).toBeVisible();
  await choose.click();
  await expect(page.getByRole("button", { name: "New Notebook", exact: true })).toBeVisible();
  await expect(page.getByText("No notebooks. Tap New Notebook to make one.", { exact: true })).toBeVisible();
});

test("Flutter reconnects a saved folder and retains edits on every page", async ({ page }) => {
  test.setTimeout(120_000);
  await page.goto("version.json");
  await page.evaluate(async () => {
    const root = await navigator.storage.getDirectory();
    for await (const name of root.keys()) await root.removeEntry(name, { recursive: true });
  });
  await page.goto("?root=opfs");
  await createTestNotebook(page, "Reconnect");
  await page.getByRole("button", { name: "New Note", exact: true }).click();
  await enterText(page.getByRole("textbox", { name: "Title", exact: true }), "Persistent");
  await page.getByRole("button", { name: "Create Note", exact: true }).click();
  const canvas = page.locator('canvas[id^="ink-canvas-"]:visible');
  await canvas.waitFor({ timeout: 30_000 });
  const box = await canvas.boundingBox();
  if (!box) throw new Error("Notebook canvas has no bounds");
  const cdp = await page.context().newCDPSession(page);
  const draw = async (y: number) => {
    const pen = { pointerType: "pen" as const, force: 0.6 };
    await cdp.send("Input.dispatchMouseEvent", {
      type: "mousePressed", button: "left", clickCount: 1, x: box.x + 150, y, ...pen,
    });
    await cdp.send("Input.dispatchMouseEvent", {
      type: "mouseMoved", button: "left", buttons: 1, x: box.x + 250, y, ...pen,
    });
    await cdp.send("Input.dispatchMouseEvent", {
      type: "mouseReleased", button: "left", clickCount: 1, x: box.x + 250, y, ...pen,
    });
  };
  await draw(box.y + 180);
  await page.getByRole("button", { name: "Pages", exact: true }).click();
  await page.getByRole("button", { name: "Add page", exact: true }).click();
  await page.getByRole("button", { name: "Pages", exact: true }).click();
  await page.getByRole("button", { name: "Next page", exact: true }).click();
  await draw(box.y + 260);
  await save(page);
  await expect(page.getByRole("status")).toHaveAccessibleName("Notebook save Saved");

  await page.addInitScript(() => {
    Object.defineProperty(window, "mathNotes", {
      configurable: true,
      set(value) {
        Object.assign(value, {
          startRoot: async () => ({
            root: await navigator.storage.getDirectory(),
            needsGesture: true,
          }),
          requestPermission: async () => true,
        });
        Object.defineProperty(window, "mathNotes", {
          configurable: true,
          writable: true,
          value,
        });
      },
    });
  });
  await page.goto("");
  await expect(page.getByRole("button", { name: "Reconnect folder", exact: true })).toBeVisible();
  await page.getByRole("button", { name: "Reconnect folder", exact: true }).click();
  await openTestNotebook(page, "Reconnect");
  await page.getByRole("button", { name: "Open Persistent", exact: false }).click();
  await expect(page.getByText("1 / 2", { exact: true })).toBeVisible();

  const strokeCounts = await page.evaluate(async () => {
    const root = await navigator.storage.getDirectory();
    const notebook = await root.getDirectoryHandle("Reconnect");
    const dir = await notebook.getDirectoryHandle("Persistent");
    const manifest = JSON.parse(await (await (await dir.getFileHandle("notebook.json")).getFile()).text());
    const pages = await dir.getDirectoryHandle("pages");
    const counts = [];
    for (const entry of manifest.pages as { file: string }[]) {
      const svg = await (await (await pages.getFileHandle(entry.file.replace("pages/", ""))).getFile()).text();
      counts.push(svg.match(/<path id="s-/g)?.length ?? 0);
    }
    return counts;
  });
  expect(strokeCounts).toEqual([1, 1]);
});

test("Flutter opens a library note on the first tap without a delayed canvas", async ({ page }) => {
  test.setTimeout(60_000);
  await page.goto("?root=opfs");
  await createTestNotebook(page, "Open timing");
  await page.getByRole("button", { name: "New Note", exact: true }).click();
  await enterText(page.getByRole("textbox", { name: "Title", exact: true }), "Immediate");
  await page.getByRole("button", { name: "Create Note", exact: true }).click();
  await page.getByRole("button", { name: "Close Immediate", exact: true }).click();

  for (let attempt = 0; attempt < 3; attempt++) {
    const card = page.getByRole("button", { name: "Open Immediate", exact: false });
    const box = await card.boundingBox();
    if (!box) throw new Error("Immediate note card has no bounds");
    const started = Date.now();
    await page.mouse.click(box.x + box.width / 2, box.y + box.height / 2);
    await expect(
      page.getByRole("heading", { name: "Immediate", exact: true }),
    ).toBeVisible({ timeout: 2_000 });
    await expect(page.locator('canvas[id^="ink-canvas-"]:visible')).toBeVisible({
      timeout: 2_000,
    });
    expect(Date.now() - started).toBeLessThan(2_000);
    await page.getByRole("button", { name: "Close Immediate", exact: true }).click();
    await expect(
      page.getByRole("heading", { name: "Open timing", exact: true }),
    ).toBeVisible();
  }
});

test("Flutter opens another note from the tab plus and preserves each tab state", async ({ page }) => {
  test.setTimeout(120_000);
  await page.goto("?root=opfs");
  await createTestNotebook(page);
  await page.getByRole("button", { name: "New Note", exact: true }).click();
  await enterText(page.getByRole("textbox", { name: "Title", exact: true }), "Second");
  await page.getByRole("button", { name: "Create Note", exact: true }).click();
  await page.getByRole("button", { name: "Close Second", exact: true }).click();
  await expect(
    page.getByRole("heading", { name: "Test Notebook", exact: true }),
  ).toBeVisible();
  await page.getByRole("button", { name: "New Note", exact: true }).click();
  await enterText(page.getByRole("textbox", { name: "Title", exact: true }), "First");
  await page.getByRole("button", { name: "Create Note", exact: true }).click();
  await expect(page.getByRole("heading", { name: "First", exact: true })).toBeVisible();

  let canvas = page.locator('canvas[id^="ink-canvas-"]:visible');
  await canvas.waitFor({ timeout: 30_000 });
  let box = await canvas.boundingBox();
  if (!box) throw new Error("First note canvas has no bounds");
  const cdp = await page.context().newCDPSession(page);
  const pen = { pointerType: "pen" as const, force: 0.6 };
  await cdp.send("Input.dispatchMouseEvent", {
    type: "mousePressed",
    button: "left",
    clickCount: 1,
    x: box.x + 160,
    y: box.y + 150,
    ...pen,
  });
  await cdp.send("Input.dispatchMouseEvent", {
    type: "mouseMoved",
    button: "left",
    buttons: 1,
    x: box.x + 240,
    y: box.y + 190,
    ...pen,
  });
  await cdp.send("Input.dispatchMouseEvent", {
    type: "mouseReleased",
    button: "left",
    clickCount: 1,
    x: box.x + 240,
    y: box.y + 190,
    ...pen,
  });
  await page.getByRole("button", { name: "Pages", exact: true }).click();
  await page.getByRole("button", { name: "Add page", exact: true }).click();
  await page.getByRole("button", { name: "Pages", exact: true }).click();
  await page.getByRole("button", { name: "Next page", exact: true }).click();
  await expect(page.getByText("2 / 2", { exact: true })).toBeVisible();

  await page.getByRole("button", { name: "Open note", exact: true }).click();
  await page.getByRole("group", { name: "Second Test Notebook", exact: true }).click();
  await expect(
    page.getByRole("heading", { name: "Second", exact: true }),
  ).toBeVisible();
  canvas = page.locator('canvas[id^="ink-canvas-"]:visible');
  await canvas.waitFor({ timeout: 30_000 });
  box = await canvas.boundingBox();
  if (!box) throw new Error("Second note canvas has no bounds");
  await cdp.send("Input.dispatchMouseEvent", {
    type: "mousePressed",
    button: "left",
    clickCount: 1,
    x: box.x + 180,
    y: box.y + 220,
    ...pen,
  });
  await cdp.send("Input.dispatchMouseEvent", {
    type: "mouseMoved",
    button: "left",
    buttons: 1,
    x: box.x + 260,
    y: box.y + 260,
    ...pen,
  });
  await cdp.send("Input.dispatchMouseEvent", {
    type: "mouseReleased",
    button: "left",
    clickCount: 1,
    x: box.x + 260,
    y: box.y + 260,
    ...pen,
  });
  await expect(page.getByText("1 / 1", { exact: true })).toBeVisible();
  await page.getByRole("button", { name: "First", exact: true }).click();
  await expect(page.getByText("2 / 2", { exact: true })).toBeVisible();
  await save(page);
  await page.getByRole("button", { name: "Second", exact: true }).click();
  await expect(page.getByText("1 / 1", { exact: true })).toBeVisible();
  await save(page);

  const strokes = await page.evaluate(async () => {
    const root = await navigator.storage.getDirectory();
    const notebook = await root.getDirectoryHandle("Test Notebook");
    const count = async (noteName: string) => {
      const note = await notebook.getDirectoryHandle(noteName);
      const pages = await note.getDirectoryHandle("pages");
      const svg = await (await (await pages.getFileHandle("0001.svg")).getFile()).text();
      return svg.match(/<path id="s-/g)?.length ?? 0;
    };
    return { first: await count("First"), second: await count("Second") };
  });
  expect(strokes).toEqual({ first: 1, second: 1 });
});

test("Flutter finds an image note through persistent tags and its page thumbnail", async ({ page }, info) => {
  test.setTimeout(90_000);
  await page.goto("?root=opfs");
  await beginTestNote(page, "Diagram");
  await addTag(page, "topology");
  await page.getByRole("button", { name: "Create Note", exact: true }).click();
  await page.getByRole("button", { name: "More", exact: true }).waitFor();
  const chooser = page.waitForEvent("filechooser");
  await page.getByRole("button", { name: "Image", exact: true }).click();
  await (await chooser).setFiles("../../core/tests/fixtures/render/full/0001.png");
  await expect(page.getByRole("button", { name: "Delete selection", exact: true })).toBeAttached();
  await save(page);
  await expect(page.getByRole("status")).toHaveAccessibleName("Notebook save Saved");
  await page.getByRole("button", { name: "Library", exact: true }).click();
  await page.reload();
  await page.getByRole("button", { name: /^topology/ }).click();
  await expect(page.getByRole("img", { name: "Diagram first page", exact: true })).toBeVisible();
  await page.screenshot({ path: info.outputPath("tagged-image-card.png") });
  await page.getByRole("button", { name: "Open Diagram", exact: false }).click();
  await page.getByRole("button", { name: "More", exact: true }).waitFor();
  const saved = await page.evaluate(async () => {
    const root = await navigator.storage.getDirectory();
    const notebook = await root.getDirectoryHandle("Test Notebook");
    const dir = await notebook.getDirectoryHandle("Diagram");
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
  await page.goto("?root=opfs");
  await beginTestNote(page, "Navigation");
  await page.getByRole("button", { name: "Create Note", exact: true }).click();
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
    const notebook = await root.getDirectoryHandle("Test Notebook");
    const dir = await notebook.getDirectoryHandle("Navigation");
    return (await (await dir.getFileHandle("notebook.json")).getFile()).text();
  });
  expect(JSON.parse(manifest).pages).toHaveLength(2);
});

test("Flutter creation resumes a draft and applies saved note settings, including landscape Letter", async ({ page }, info) => {
  test.setTimeout(120_000);
  page.on("pageerror", error => console.error(error.stack));
  page.on("console", message => { if (message.type() === "error") console.error(message.text()); });
  await page.goto("?root=opfs");
  await beginTestNote(page, "Seminar");
  await page.getByRole("button", { name: "Lined Paper", exact: true }).click();
  await addTag(page, "analysis");
  await page.getByRole("button", { name: "Letter", exact: true }).click();
  await page.getByRole("button", { name: "Landscape", exact: true }).click();
  await page.getByRole("button", { name: "Save as Draft", exact: true }).click();
  await expect(page.getByRole("status", { name: "Draft saved", exact: true })).toBeVisible();
  await page.reload();
  await openTestNotebook(page);
  await page.getByRole("button", { name: "New Note", exact: true }).click();
  await expect(page.getByRole("textbox", { name: "Title", exact: true })).toHaveValue("Seminar");
  await enterText(page.getByRole("textbox", { name: "Settings name", exact: true }), "Proof paper");
  await page.getByRole("button", { name: "Save as template", exact: true }).click();
  await expect(page.getByRole("status", { name: "Template saved", exact: true })).toBeVisible();
  await page.reload();
  await openTestNotebook(page);
  await page.getByRole("button", { name: "New Note", exact: true }).click();
  await page.getByRole("button", { name: "Plain Paper", exact: true }).click();
  await addTag(page, "temporary");
  await page.getByRole("button", { name: "Proof paper", exact: false }).click();
  await expect(page.getByRole("img", { name: "First page preview", exact: true })).toBeVisible();
  await page.screenshot({ path: info.outputPath("settings-selected.png") });
  await expect(page.getByRole("button", { name: "Remove tag analysis", exact: true })).toBeVisible();
  await expect(page.getByRole("button", { name: "Remove tag temporary", exact: true })).toHaveCount(0);
  await page.getByRole("button", { name: "Create Note", exact: true }).click();
  await page.getByRole("button", { name: "More", exact: true }).waitFor();
  const stored = await page.evaluate(async () => {
    const root = await navigator.storage.getDirectory();
    const notebook = await root.getDirectoryHandle("Test Notebook");
    const note = await notebook.getDirectoryHandle("Seminar");
    return {
      manifest: await (await (await note.getFileHandle("notebook.json")).getFile()).text(),
      metadata: await (await (await root.getFileHandle(".library.json")).getFile()).text(),
    };
  });
  expect(JSON.parse(stored.manifest).template).toBe("lined-medium");
  expect(JSON.parse(stored.manifest).pageSize).toEqual([792, 612]);
  expect(JSON.parse(stored.metadata).notes["Test Notebook/Seminar"].tags).toEqual(["analysis"]);
  expect(JSON.parse(stored.metadata).draft).toBeUndefined();
});

test("Flutter ignores a palm that drags during a pen stroke", async ({ page }) => {
  test.setTimeout(60_000);
  await page.goto("?root=opfs");
  await beginTestNote(page, "Palm");
  await page.getByRole("button", { name: "Create Note", exact: true }).click();
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
  await save(page);
  await expect(page.getByRole("status")).toHaveAccessibleName("Notebook save Saved");
  const trace = await page.evaluate(async () => {
    const root = await navigator.storage.getDirectory();
    const notebook = await root.getDirectoryHandle("Test Notebook");
    const pages = await (await notebook.getDirectoryHandle("Palm")).getDirectoryHandle("pages");
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

test("Flutter modal dialogs block pen ink underneath them", async ({ page }) => {
  test.setTimeout(60_000);
  await page.goto("?root=opfs");
  await beginTestNote(page, "Modal input");
  await page.getByRole("button", { name: "Create Note", exact: true }).click();
  const canvas = page.locator('canvas[id^="ink-canvas-"]:visible');
  await canvas.waitFor({ timeout: 30_000 });
  const box = await canvas.boundingBox();
  if (!box) throw new Error("Notebook canvas has no bounds");

  await page.getByRole("button", { name: "More", exact: true }).click();
  await page.getByRole("button", { name: "Go to page", exact: true }).click();
  await expect(page.getByText("Go to page", { exact: true })).toBeVisible();

  const cdp = await page.context().newCDPSession(page);
  const pen = { pointerType: "pen" as const, force: 0.6, tiltX: 20, tiltY: -10 };
  await cdp.send("Input.dispatchMouseEvent", {
    type: "mousePressed", button: "left", clickCount: 1,
    x: box.x + 150, y: box.y + 180, ...pen,
  });
  await cdp.send("Input.dispatchMouseEvent", {
    type: "mouseMoved", button: "left", buttons: 1,
    x: box.x + 250, y: box.y + 220, ...pen,
  });
  await cdp.send("Input.dispatchMouseEvent", {
    type: "mouseReleased", button: "left", clickCount: 1,
    x: box.x + 250, y: box.y + 220, ...pen,
  });
  await page.getByRole("button", { name: "Cancel", exact: true }).click();
  await save(page);
  await expect(page.getByRole("status")).toHaveAccessibleName("Notebook save Saved");
  const strokes = await page.evaluate(async () => {
    const root = await navigator.storage.getDirectory();
    const notebook = await root.getDirectoryHandle("Test Notebook");
    const pages = await (await notebook.getDirectoryHandle("Modal input")).getDirectoryHandle("pages");
    const svg = await (await (await pages.getFileHandle("0001.svg")).getFile()).text();
    return svg.match(/<path id="s-/g)?.length ?? 0;
  });
  expect(strokes).toBe(0);
});

test("Flutter undoes on a two-finger tap and redoes on a three-finger tap", async ({ page }) => {
  test.setTimeout(60_000);
  await page.goto("?root=opfs");
  await beginTestNote(page, "Taps");
  await page.getByRole("button", { name: "Create Note", exact: true }).click();
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
    await save(page);
    await expect(page.getByRole("status")).toHaveAccessibleName("Notebook save Saved");
    return page.evaluate(async () => {
      const root = await navigator.storage.getDirectory();
      const notebook = await root.getDirectoryHandle("Test Notebook");
      const pages = await (await notebook.getDirectoryHandle("Taps")).getDirectoryHandle("pages");
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
  await page.goto("?root=opfs");
  await beginTestNote(page, "Fingers");
  await page.getByRole("button", { name: "Create Note", exact: true }).click();
  const canvas = page.locator('canvas[id^="ink-canvas-"]');
  await canvas.waitFor({ timeout: 30_000 });
  const box = await canvas.boundingBox();
  if (!box) throw new Error("Notebook canvas has no bounds");
  const cdp = await page.context().newCDPSession(page);
  const strokes = async () => {
    await save(page);
    await expect(page.getByRole("status")).toHaveAccessibleName("Notebook save Saved");
    return page.evaluate(async () => {
      const root = await navigator.storage.getDirectory();
      const notebook = await root.getDirectoryHandle("Test Notebook");
      const pages = await (await notebook.getDirectoryHandle("Fingers")).getDirectoryHandle("pages");
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
  await openTestNotebook(page);
  await page.getByRole("button", { name: "Open Fingers", exact: false }).click();
  await canvas.waitFor({ timeout: 30_000 });
  await page.getByRole("button", { name: "More", exact: true }).click();
  // The selected item carries the checkmark glyph in its name.
  await expect(page.getByRole("button", { name: /^\S+ Draw with finger$/ })).toHaveAttribute("aria-current", "true");
});

test("Flutter partial and whole-stroke erases each undo and redo", async ({ page }) => {
  test.setTimeout(120_000);
  await page.goto("?root=opfs");
  await beginTestNote(page, "Erase history");
  await page.getByRole("button", { name: "Create Note", exact: true }).click();
  const canvas = page.locator('canvas[id^="ink-canvas-"]:visible');
  await canvas.waitFor({ timeout: 30_000 });
  const box = await canvas.boundingBox();
  if (!box) throw new Error("Notebook canvas has no bounds");
  const cdp = await page.context().newCDPSession(page);
  const drag = async (from: [number, number], to: [number, number]) => {
    const pen = { pointerType: "pen" as const, force: 0.6 };
    await cdp.send("Input.dispatchMouseEvent", {
      type: "mousePressed", button: "left", clickCount: 1,
      x: box.x + from[0], y: box.y + from[1], ...pen,
    });
    await cdp.send("Input.dispatchMouseEvent", {
      type: "mouseMoved", button: "left", buttons: 1,
      x: box.x + (from[0] + to[0]) / 2, y: box.y + (from[1] + to[1]) / 2, ...pen,
    });
    await cdp.send("Input.dispatchMouseEvent", {
      type: "mouseMoved", button: "left", buttons: 1,
      x: box.x + to[0], y: box.y + to[1], ...pen,
    });
    await cdp.send("Input.dispatchMouseEvent", {
      type: "mouseReleased", button: "left", clickCount: 1,
      x: box.x + to[0], y: box.y + to[1], ...pen,
    });
  };
  const savedStrokeCount = () => page.evaluate(async () => {
    try {
      const root = await navigator.storage.getDirectory();
      const notebook = await root.getDirectoryHandle("Test Notebook");
      const pages = await (await notebook.getDirectoryHandle("Erase history")).getDirectoryHandle("pages");
      const svg = await (await (await pages.getFileHandle("0001.svg")).getFile()).text();
      return svg.match(/<path id="s-/g)?.length ?? 0;
    } catch (error) {
      if (error instanceof DOMException && error.name === "NotFoundError") return -1;
      throw error;
    }
  });
  const expectStrokes = async (count: number) => {
    await expect.poll(savedStrokeCount, { timeout: 8_000 }).toBe(count);
  };
  const dismissPopover = async () => {
    const viewport = page.viewportSize();
    if (!viewport) throw new Error("Page has no viewport");
    await page.mouse.click(viewport.width - 20, viewport.height - 20);
  };

  await drag([150, 220], [350, 220]);
  await expectStrokes(1);
  await page.getByRole("button", { name: "Eraser", exact: true }).click();
  await page.getByRole("button", { name: "Eraser", exact: true }).click();
  await page.getByRole("button", { name: "Partial", exact: true }).click();
  await dismissPopover();
  await drag([250, 170], [250, 270]);
  await expectStrokes(2);
  await page.getByRole("button", { name: "Undo", exact: true }).click();
  await expectStrokes(1);
  await page.getByRole("button", { name: "Redo", exact: true }).click();
  await expectStrokes(2);
  await page.getByRole("button", { name: "Undo", exact: true }).click();
  await expectStrokes(1);

  await page.getByRole("button", { name: "Eraser", exact: true }).click();
  await page.getByRole("button", { name: "Stroke", exact: true }).click();
  await dismissPopover();
  await drag([250, 170], [250, 270]);
  await expectStrokes(0);
  await page.getByRole("button", { name: "Undo", exact: true }).click();
  await expectStrokes(1);
  await page.getByRole("button", { name: "Redo", exact: true }).click();
  await expectStrokes(0);
});

test("Flutter page overview duplicates, deletes, reorders, and opens pages", async ({ page }, info) => {
  test.setTimeout(90_000);
  await page.goto("?root=opfs");
  await beginTestNote(page, "Overview");
  await page.getByRole("button", { name: "Create Note", exact: true }).click();
  await page.locator('canvas[id^="ink-canvas-"]').waitFor();
  for (let added = 0; added < 2; added++) {
    await page.getByRole("button", { name: "Pages", exact: true }).click();
    await page.getByRole("button", { name: "Add page", exact: true }).click();
  }
  await expect(page.getByText(/^\d \/ 3$/)).toBeVisible();
  await page.getByRole("button", { name: "Pages", exact: true }).click();
  await page.getByRole("button", { name: "Page overview", exact: true }).click();
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
  await save(page);
  await expect(page.getByRole("status")).toHaveAccessibleName("Notebook save Saved");
  const manifest = await page.evaluate(async () => {
    const root = await navigator.storage.getDirectory();
    const notebook = await root.getDirectoryHandle("Test Notebook");
    const dir = await notebook.getDirectoryHandle("Overview");
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

test("Flutter writes on three pages and returns to page one", async ({ page }) => {
  test.setTimeout(90_000);
  await page.goto("?root=opfs");
  await beginTestNote(page, "Three pages");
  await page.getByRole("button", { name: "Create Note", exact: true }).click();
  const canvas = page.locator('canvas[id^="ink-canvas-"]:visible');
  await canvas.waitFor({ timeout: 30_000 });
  const box = await canvas.boundingBox();
  if (!box) throw new Error("Notebook canvas has no bounds");
  const cdp = await page.context().newCDPSession(page);
  const draw = async (offset: number) => {
    const pen = { pointerType: "pen" as const, force: 0.6 };
    const y = box.y + 180 + offset;
    await cdp.send("Input.dispatchMouseEvent", {
      type: "mousePressed", button: "left", clickCount: 1, x: box.x + 150, y, ...pen,
    });
    await cdp.send("Input.dispatchMouseEvent", {
      type: "mouseMoved", button: "left", buttons: 1, x: box.x + 230, y, ...pen,
    });
    await cdp.send("Input.dispatchMouseEvent", {
      type: "mouseReleased", button: "left", clickCount: 1, x: box.x + 230, y, ...pen,
    });
  };

  await draw(0);
  for (let pageNumber = 2; pageNumber <= 3; pageNumber++) {
    await page.getByRole("button", { name: "Pages", exact: true }).click();
    await page.getByRole("button", { name: "Add page", exact: true }).click();
    await expect(page.getByText(`${pageNumber - 1} / ${pageNumber}`, { exact: true })).toBeVisible();
    await page.getByRole("button", { name: "Pages", exact: true }).click();
    await page.getByRole("button", { name: "Next page", exact: true }).click();
    await expect(page.getByText(`${pageNumber} / ${pageNumber}`, { exact: true })).toBeVisible();
    await draw((pageNumber - 1) * 30);
  }
  await page.getByRole("button", { name: "Pages", exact: true }).click();
  await page.getByRole("button", { name: "Page overview", exact: true }).click();
  await page.getByRole("button", { name: "Page 1", exact: true }).click();
  await expect(page.getByText("1 / 3", { exact: true })).toBeVisible();
  await save(page);
  await expect(page.getByRole("status")).toHaveAccessibleName("Notebook save Saved");

  const strokeCounts = await page.evaluate(async () => {
    const root = await navigator.storage.getDirectory();
    const notebook = await root.getDirectoryHandle("Test Notebook");
    const dir = await notebook.getDirectoryHandle("Three pages");
    const manifest = JSON.parse(await (await (await dir.getFileHandle("notebook.json")).getFile()).text());
    const pages = await dir.getDirectoryHandle("pages");
    const counts = [];
    for (const entry of manifest.pages as { file: string }[]) {
      const svg = await (await (await pages.getFileHandle(entry.file.replace("pages/", ""))).getFile()).text();
      counts.push(svg.match(/<path id="s-/g)?.length ?? 0);
    }
    return counts;
  });
  expect(strokeCounts).toEqual([1, 1, 1]);
});

test("Flutter recolors a lasso selection from the palette and keeps the pen color", async ({ page }) => {
  test.setTimeout(60_000);
  await page.goto("?root=opfs");
  await beginTestNote(page, "Recolor");
  await page.getByRole("button", { name: "Create Note", exact: true }).click();
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
  await page.getByRole("button", { name: "Pen", exact: true }).click();
  // A pen-down away from a selection only clears it (Write, clearSelOnly).
  await gesture([[600, 500], [600, 500]]);
  await expect(page.getByRole("button", { name: "Delete selection", exact: true })).toHaveCount(0);
  await gesture([[160, 350], [200, 370], [240, 390]]);
  await save(page);
  await expect(page.getByRole("status")).toHaveAccessibleName("Notebook save Saved");
  const fills = await page.evaluate(async () => {
    const root = await navigator.storage.getDirectory();
    const notebook = await root.getDirectoryHandle("Test Notebook");
    const pages = await (await notebook.getDirectoryHandle("Recolor")).getDirectoryHandle("pages");
    const svg = await (await (await pages.getFileHandle("0001.svg")).getFile()).text();
    return [...svg.matchAll(/<path id="s-[^"]*"[^>]* fill="(#[0-9A-F]{6})"/g)].map((match) => match[1]);
  });
  expect(fills).toEqual(["#D92D39", "#1A1A1A"]);
});

type Box = { x: number; y: number; width: number; height: number };
type PenPoint = { x: number; y: number };

// One CDP pen stroke through the points, at one pressure.
async function penStroke(cdp: CDPSession, points: PenPoint[], force: number): Promise<void> {
  const pen = { pointerType: "pen" as const, force, tiltX: 20, tiltY: -10 };
  const [first, ...rest] = points;
  const last = points[points.length - 1];
  await cdp.send("Input.dispatchMouseEvent", {
    type: "mousePressed", button: "left", clickCount: 1, ...first, ...pen,
  });
  for (const point of rest) {
    await cdp.send("Input.dispatchMouseEvent", {
      type: "mouseMoved", button: "left", buttons: 1, ...point, ...pen,
    });
  }
  await cdp.send("Input.dispatchMouseEvent", {
    type: "mouseReleased", button: "left", clickCount: 1, ...last, ...pen,
  });
}

function line(x0: number, x1: number, y: number, steps = 10): PenPoint[] {
  return Array.from({ length: steps + 1 }, (_, i) => ({ x: x0 + ((x1 - x0) * i) / steps, y }));
}

type Rgb = [number, number, number];

// The on-screen pixels of a rectangle, row by row, from a clipped capture: a
// full-viewport capture can show the WebGL canvas displaced (TRAPS.md).
async function capture(page: Page, clip: Box): Promise<Rgb[]> {
  const png = await page.screenshot({ clip });
  return page.evaluate(async (base64) => {
    const bytes = Uint8Array.from(atob(base64), (c) => c.charCodeAt(0));
    const bitmap = await createImageBitmap(new Blob([bytes], { type: "image/png" }));
    const context = new OffscreenCanvas(bitmap.width, bitmap.height).getContext("2d");
    if (!context) throw new Error("No 2D context");
    context.drawImage(bitmap, 0, 0);
    const data = context.getImageData(0, 0, bitmap.width, bitmap.height).data;
    return Array.from({ length: data.length / 4 }, (_, i): [number, number, number] =>
      [data[4 * i], data[4 * i + 1], data[4 * i + 2]]);
  }, png.toString("base64"));
}

// The 9 × 9 square around a point.
function screenPixels(page: Page, center: PenPoint): Promise<Rgb[]> {
  return capture(page, { x: center.x - 4, y: center.y - 4, width: 9, height: 9 });
}

const brightness = (rgb: Rgb) => rgb[0] + rgb[1] + rgb[2];

// Pen ink is near black; the paper, its dots, and its rules are much lighter.
const isInk = (rgb: Rgb) => brightness(rgb) < 250;

// The screen row of the darkest pixel in a column between two rows.
async function inkRow(page: Page, x: number, top: number, bottom: number): Promise<number> {
  const column = await capture(page, { x, y: top, width: 1, height: bottom - top });
  const darkest = column.reduce((best, rgb, i) => (brightness(rgb) < brightness(column[best]) ? i : best), 0);
  expect(isInk(column[darkest]), "a column crosses the handwriting").toBe(true);
  return top + darkest;
}

// How many pixels of a screen row between two columns are ink.
async function inkLength(page: Page, y: number, left: number, right: number): Promise<number> {
  return (await capture(page, { x: left, y, width: right - left, height: 1 })).filter(isInk).length;
}

async function darkestPixel(page: Page, center: PenPoint): Promise<Rgb> {
  const pixels = await screenPixels(page, center);
  return pixels.reduce((darkest, rgb) => (brightness(rgb) < brightness(darkest) ? rgb : darkest));
}

// How much ink is on screen around a point: the total darkening of the
// square since `paper`, its capture before writing.
async function inkAt(page: Page, center: PenPoint, paper: Rgb[]): Promise<number> {
  const pixels = await screenPixels(page, center);
  return pixels.reduce((sum, rgb, i) => sum + brightness(paper[i]) - brightness(rgb), 0);
}

async function centerPixel(page: Page, center: PenPoint): Promise<Rgb> {
  return (await screenPixels(page, center))[40];
}

async function openNewNote(page: Page, title: string, paper?: string): Promise<{ box: Box; cdp: CDPSession }> {
  await page.goto("?root=opfs");
  // Each paper gets its own notebook: the storage keeps earlier notebooks.
  await beginTestNote(page, title, paper);
  if (paper) await page.getByRole("button", { name: paper, exact: true }).click();
  await page.getByRole("button", { name: "Create Note", exact: true }).click();
  const canvas = page.locator('canvas[id^="ink-canvas-"]:visible');
  await canvas.waitFor({ timeout: 30_000 });
  const box = await canvas.boundingBox();
  if (!box) throw new Error("Notebook canvas has no bounds");
  return { box, cdp: await page.context().newCDPSession(page) };
}

test("Flutter shows ruled, grid, dotted, and blank paper as chosen at creation", async ({ page }, info) => {
  test.setTimeout(180_000);
  // The marks in a square of the page: full rows are rules, full columns
  // are grid verticals, and marks in neither are dots.
  const pattern = async (paper: string) => {
    const { box } = await openNewNote(page, paper, paper);
    const side = 200;
    const pixels = await capture(page, { x: box.x + 150, y: box.y + 150, width: side, height: side });
    await page.screenshot({ path: info.outputPath(`${paper}.png`) });
    const white = pixels.reduce((best, rgb) => (brightness(rgb) > brightness(best) ? rgb : best));
    const marked = pixels.map((rgb) => brightness(white) - brightness(rgb) > 20);
    const at = (x: number, y: number) => marked[y * side + x];
    const range = [...Array(side).keys()];
    return {
      marks: marked.filter(Boolean).length,
      rows: range.filter((y) => range.every((x) => at(x, y))).length,
      columns: range.filter((x) => range.every((y) => at(x, y))).length,
    };
  };
  const lined = await pattern("Lined Paper");
  expect(lined.rows, "lined paper has rules").toBeGreaterThan(0);
  expect(lined.columns, "lined paper has no verticals").toBe(0);
  for (const paper of ["Grid Paper", "Graph Paper"]) {
    const grid = await pattern(paper);
    expect(grid.rows, `${paper} has horizontal lines`).toBeGreaterThan(0);
    expect(grid.columns, `${paper} has vertical lines`).toBeGreaterThan(0);
  }
  const dotted = await pattern("Dot Paper");
  expect(dotted.marks, "dot paper has dots").toBeGreaterThan(0);
  expect(dotted.rows + dotted.columns, "dot paper has no lines").toBe(0);
  const blank = await pattern("Plain Paper");
  expect(blank.marks, "plain paper is blank").toBe(0);
});

test("Flutter lasso moves, cuts, pastes, copies, and deletes handwriting", async ({ page, context }, info) => {
  test.setTimeout(90_000);
  await context.grantPermissions(["clipboard-read", "clipboard-write"]);
  const { box, cdp } = await openNewNote(page, "Selections");
  const written = { x: box.x + 220, y: box.y + 170 };
  const moved = { x: written.x, y: written.y + 150 };
  const lower = { x: written.x, y: moved.y + 150 };
  const paper = new Map<PenPoint, Rgb[]>();
  for (const spot of [written, moved, lower]) paper.set(spot, await screenPixels(page, spot));
  const shot = (name: string) => page.screenshot({ path: info.outputPath(`${name}.png`) });
  const dragDown = (from: PenPoint) =>
    penStroke(cdp, [0, 50, 100, 150].map((dy) => ({ x: from.x, y: from.y + dy })), 0.6);
  // Where handwriting shows: each spot has the full stroke's ink or none.
  let stroke = 0;
  const inked = async () => {
    const spots = [];
    for (const spot of [written, moved, lower]) {
      const ink = await inkAt(page, spot, paper.get(spot)!);
      expect(ink < 0.1 * stroke || ink > 0.8 * stroke, `ink ${ink} of ${stroke}`).toBe(true);
      spots.push(ink > 0.8 * stroke);
    }
    return spots;
  };

  await penStroke(cdp, line(written.x - 40, written.x + 40, written.y), 0.6);
  stroke = await inkAt(page, written, paper.get(written)!);
  await page.getByRole("button", { name: "Lasso", exact: true }).click();
  await penStroke(cdp, [
    { x: written.x - 70, y: written.y - 40 }, { x: written.x + 70, y: written.y - 40 },
    { x: written.x + 70, y: written.y + 40 }, { x: written.x - 70, y: written.y + 40 },
    { x: written.x - 70, y: written.y - 40 },
  ], 0.6);
  await dragDown(written);
  await shot("moved");
  expect(await inked()).toEqual([false, true, false]);

  await page.getByRole("button", { name: "Cut", exact: true }).click();
  await shot("cut");
  expect(await inked()).toEqual([false, false, false]);
  const paste = async () => {
    await page.getByRole("button", { name: "More", exact: true }).click();
    await page.getByRole("button", { name: "Paste", exact: true }).click();
  };
  await paste();
  expect(await inked()).toEqual([false, true, false]);

  // Copy leaves the selected handwriting in place; it then moves away, and
  // a paste puts the copy where the handwriting was copied from.
  await page.getByRole("button", { name: "Copy", exact: true }).click();
  await dragDown(moved);
  expect(await inked()).toEqual([false, false, true]);
  await paste();
  await shot("copied");
  expect(await inked()).toEqual([false, true, true]);

  await page.getByRole("button", { name: "Delete selection", exact: true }).click();
  await shot("deleted");
  expect(await inked()).toEqual([false, false, true]);
});

test("Flutter pans the page with one finger and zooms it with a pinch", async ({ page }, info) => {
  test.setTimeout(90_000);
  const { box, cdp } = await openNewNote(page, "Touch navigation");
  const written = { x: box.x + 500, y: box.y + 320 };
  await penStroke(cdp, line(written.x - 40, written.x + 40, written.y), 0.6);
  // A column through the handwriting, between two columns of paper dots.
  const column = written.x + 18;
  const top = box.y + 120;
  const bottom = box.y + box.height - 40;
  const before = await inkRow(page, column, top, bottom);
  const touch = (type: "touchStart" | "touchMove" | "touchEnd", points: PenPoint[]) =>
    cdp.send("Input.dispatchTouchEvent", { type, touchPoints: points.map((p, id) => ({ id, ...p })) });

  // A finger drags 150 px up; the page follows it past the touch slop.
  const finger = { x: box.x + 900, y: box.y + 450 };
  await touch("touchStart", [finger]);
  for (let dy = 30; dy <= 150; dy += 30) await touch("touchMove", [{ x: finger.x, y: finger.y - dy }]);
  await touch("touchEnd", []);
  await page.screenshot({ path: info.outputPath("panned.png") });
  const panned = await inkRow(page, column, top, bottom);
  expect(before - panned).toBeGreaterThan(100);
  expect(before - panned).toBeLessThanOrEqual(150);

  // Two fingers spread from 100 to 240 px apart below the handwriting.
  const length = await inkLength(page, panned, written.x - 200, written.x + 200);
  const spread = (half: number) => [{ x: written.x - half, y: panned + 60 }, { x: written.x + half, y: panned + 60 }];
  await touch("touchStart", spread(50));
  for (let half = 60; half <= 120; half += 10) await touch("touchMove", spread(half));
  await touch("touchEnd", []);
  await page.screenshot({ path: info.outputPath("zoomed.png") });
  const zoomed = await inkRow(page, column, top, bottom);
  expect(await inkLength(page, zoomed, written.x - 300, written.x + 300)).toBeGreaterThan(1.5 * length);
});

test("Flutter rewinds handwriting with Ctrl+Z and the undo dial", async ({ page }, info) => {
  test.setTimeout(90_000);
  const { box, cdp } = await openNewNote(page, "Rewind");
  const spots = [180, 260, 340].map((dy) => ({ x: box.x + 220, y: box.y + dy }));
  const paper: Rgb[][] = [];
  for (const spot of spots) paper.push(await screenPixels(page, spot));
  const strokes: number[] = [];
  for (const [i, spot] of spots.entries()) {
    await penStroke(cdp, line(spot.x - 40, spot.x + 40, spot.y), 0.6);
    strokes.push(await inkAt(page, spot, paper[i]));
  }
  // Which of the three lines of handwriting show: each is whole or gone.
  const shown = async () => {
    const lines = [];
    for (const [i, spot] of spots.entries()) {
      const ink = await inkAt(page, spot, paper[i]);
      expect(ink < 0.1 * strokes[i] || ink > 0.8 * strokes[i], `ink ${ink} of ${strokes[i]}`).toBe(true);
      lines.push(ink > 0.8 * strokes[i]);
    }
    return lines;
  };
  expect(await shown()).toEqual([true, true, true]);

  await page.keyboard.press("Control+z");
  expect(await shown()).toEqual([true, true, false]);
  await page.keyboard.press("Control+Shift+z");
  expect(await shown()).toEqual([true, true, true]);

  // A drag from the undo button turns the dial below it (undo_dial.dart):
  // each 1/32 turn counterclockwise undoes a step, clockwise redoes one.
  const button = await page.getByRole("button", { name: "Undo", exact: true }).boundingBox();
  if (!button) throw new Error("Undo button has no bounds");
  const start = { x: button.x + button.width / 2, y: button.y + button.height / 2 };
  const center = { x: start.x, y: button.y + 1.3 * button.height + 2.5 * button.height };
  const radius = center.y - start.y;
  const at = (degrees: number) => {
    const angle = -Math.PI / 2 + (degrees * Math.PI) / 180;
    return { x: center.x + radius * Math.cos(angle), y: center.y + radius * Math.sin(angle) };
  };
  await page.mouse.move(start.x, start.y);
  await page.mouse.down();
  for (let degrees = -4; degrees >= -28; degrees -= 4) await page.mouse.move(at(degrees).x, at(degrees).y);
  await page.screenshot({ path: info.outputPath("dial-rewound.png") });
  expect(await shown()).toEqual([true, false, false]);
  for (let degrees = -24; degrees <= -8; degrees += 4) await page.mouse.move(at(degrees).x, at(degrees).y);
  await page.mouse.up();
  expect(await shown()).toEqual([true, true, false]);
});

test("Flutter writes a hard pen stroke visibly thicker than a light one", async ({ page }, info) => {
  test.setTimeout(60_000);
  const { box, cdp } = await openNewNote(page, "Pressure");
  const light = { x: box.x + 240, y: box.y + 180 };
  const hard = { x: box.x + 240, y: box.y + 260 };
  const paper = [await screenPixels(page, light), await screenPixels(page, hard)];

  await penStroke(cdp, line(box.x + 140, box.x + 340, light.y), 0.15);
  await penStroke(cdp, line(box.x + 140, box.x + 340, hard.y), 1);
  await page.screenshot({ path: info.outputPath("pressure.png") });

  // Ink on screen: how much each stroke darkened the paper across its width.
  const ratio = (await inkAt(page, hard, paper[1])) / (await inkAt(page, light, paper[0]));
  expect(ratio).toBeGreaterThan(1.3);
  expect(ratio).toBeLessThan(3);
});

test("Flutter highlighting handwriting leaves the handwriting dark", async ({ page }, info) => {
  test.setTimeout(60_000);
  const { box, cdp } = await openNewNote(page, "Highlight");
  const y = box.y + 200;
  await penStroke(cdp, line(box.x + 140, box.x + 340, y), 0.6);
  const plainInk = await darkestPixel(page, { x: box.x + 180, y });
  const x = box.x + 280;
  const paper = await centerPixel(page, { x, y: y - 25 });

  await page.getByRole("button", { name: "Highlighter", exact: true }).click();
  await penStroke(cdp, [{ x, y: y - 40 }, { x, y: y - 20 }, { x, y }, { x, y: y + 20 }, { x, y: y + 40 }], 0.6);
  await page.screenshot({ path: info.outputPath("highlighted.png") });

  // The highlight tints the bare paper, and the handwriting it crosses keeps its own color.
  const highlight = await centerPixel(page, { x, y: y - 25 });
  expect(brightness(paper) - brightness(highlight)).toBeGreaterThan(30);
  const crossing = await darkestPixel(page, { x, y });
  for (const channel of [0, 1, 2]) expect(Math.abs(crossing[channel] - plainInk[channel])).toBeLessThan(24);
});

// Rows of a column through a stroke that the stroke darkens.
async function inkThickness(page: Page, center: PenPoint): Promise<number> {
  const column = await capture(page, { x: center.x, y: center.y - 20, width: 1, height: 41 });
  return column.filter((rgb) => brightness(rgb) < 600).length;
}

// A tap outside a popover closes it.
async function closePopover(page: Page): Promise<void> {
  const viewport = page.viewportSize();
  if (!viewport) throw new Error("Page has no viewport");
  await page.mouse.click(viewport.width - 20, viewport.height - 20);
}

test("Flutter tool popovers set size, opacity, and the brush of each pen type", async ({ page }, info) => {
  test.setTimeout(120_000);
  const { box, cdp } = await openNewNote(page, "Tool popover");
  const tool = (name: string) => page.getByRole("button", { name, exact: true });
  const sample = page.getByRole("img", { name: "Stroke sample", exact: true });
  const sampleInk = async () => {
    const bounds = await sample.boundingBox();
    if (!bounds) throw new Error("The stroke sample has no bounds");
    return (await capture(page, bounds)).filter((rgb) => brightness(rgb) < 600).length;
  };
  const at = (y: number) => ({ x: box.x + 240, y: box.y + y });
  const write = (y: number, force = 0.6) => penStroke(cdp, line(box.x + 140, box.x + 340, box.y + y), force);

  // The pen is selected, so a tap on it opens its popover.
  await tool("Pen").click();
  await tool("0.6 pt").click();
  const thinSample = await sampleInk();
  await tool("3.6 pt").click();
  await expect.poll(sampleInk, { message: "the stroke sample follows the size" }).toBeGreaterThan(2.5 * thinSample);
  await tool("0.6 pt").click();
  await closePopover(page);
  await write(160);
  await tool("Pen").click();
  await tool("3.6 pt").click();
  await closePopover(page);
  await write(220);

  await tool("Pen").click();
  await tool("Advanced").click();
  const opacity = page.getByRole("slider");
  const track = await opacity.boundingBox();
  if (!track) throw new Error("The opacity slider has no bounds");
  // A Cupertino slider moves by a drag of its thumb, here at 100%.
  const middle = track.y + track.height / 2;
  await page.mouse.move(track.x + track.width - 14, middle);
  await page.mouse.down();
  await page.mouse.move(track.x, middle, { steps: 10 });
  await page.mouse.up();
  await expect(page.getByText("10%", { exact: true })).toBeVisible();
  await closePopover(page);
  await write(280);

  // The marker keeps a constant width under light and hard pressure.
  await tool("Marker").click();
  await write(340, 0.15);
  await write(400, 1);
  await page.screenshot({ path: info.outputPath("tool-popover.png") });

  const thin = await inkThickness(page, at(160));
  expect(await inkThickness(page, at(220)), "the 3.6 pt preset writes thicker").toBeGreaterThan(2.5 * thin);
  const solid = brightness(await darkestPixel(page, at(220)));
  const faint = brightness(await darkestPixel(page, at(280)));
  expect(faint - solid, "10% opacity writes faint ink").toBeGreaterThan(300);
  expect(await inkThickness(page, at(340)), "the marker ignores pressure").toBe(await inkThickness(page, at(400)));
});

test("Flutter palette edits a swatch on the HSV wheel, and adds and removes swatches", async ({ page }, info) => {
  test.setTimeout(150_000);
  const { box, cdp } = await openNewNote(page, "Palette");
  const swatches = page.getByRole("button", { name: /^Color #/ });
  const swatchColor = async (index: number) => {
    const bounds = await swatches.nth(index).boundingBox();
    if (!bounds) throw new Error("A swatch has no bounds");
    return centerPixel(page, { x: bounds.x + bounds.width / 2, y: bounds.y + bounds.height / 2 });
  };
  // A short drag at an offset from the wheel's center: the hue ring is the outer
  // 20 px of the 228 px wheel, and the saturation and value square is inside it.
  const wheelDrag = async (dx: number, dy: number) => {
    const bounds = await page.getByRole("button", { name: "Color wheel", exact: true }).boundingBox();
    if (!bounds) throw new Error("The color wheel has no bounds");
    const x = bounds.x + bounds.width / 2 + dx;
    const y = bounds.y + bounds.height / 2 + dy;
    await page.mouse.move(x, y);
    await page.mouse.down();
    await page.mouse.move(x + 3, y + 3, { steps: 3 });
    await page.mouse.up();
  };
  const saturation = (rgb: Rgb) => Math.max(...rgb) - Math.min(...rgb);
  const near = (a: Rgb, b: Rgb) => a.every((channel, i) => Math.abs(channel - b[i]) < 30);

  await page.getByRole("button", { name: "Pen", exact: true }).click();
  await page.getByRole("button", { name: "3.6 pt", exact: true }).click();
  await closePopover(page);
  // A tap on the pen's current swatch opens the wheel for that swatch.
  await swatches.first().click();
  await wheelDrag(45, -45);
  await wheelDrag(0, 104);
  await closePopover(page);
  const edited = await swatchColor(0);
  expect(saturation(edited), "the wheel makes the gray swatch a saturated color").toBeGreaterThan(100);
  const stroke = { x: box.x + 240, y: box.y + 200 };
  await penStroke(cdp, line(box.x + 140, box.x + 340, stroke.y), 0.6);
  const ink = await darkestPixel(page, stroke);
  expect(near(ink, edited), `the pen writes the swatch color: ink ${ink}, swatch ${edited}`).toBe(true);

  await page.getByRole("button", { name: "Edit colors", exact: true }).click();
  await page.getByRole("button", { name: "Remove color #ffcf26", exact: true }).click();
  await wheelDrag(0, -104);
  await page.getByRole("button", { name: "Add color", exact: true }).click();
  await closePopover(page);
  await expect(page.getByRole("button", { name: "Color #ffcf26", exact: true })).toHaveCount(0);
  await expect(swatches).toHaveCount(5);
  const added = await swatchColor(4);
  expect(saturation(added), "the added swatch is a saturated color").toBeGreaterThan(100);
  expect(near(added, edited), "the added swatch differs from the edited one").toBe(false);

  await page.reload();
  await openTestNotebook(page);
  await page.getByRole("button", { name: "Open Palette", exact: false }).click();
  await page.locator('canvas[id^="ink-canvas-"]:visible').waitFor({ timeout: 30_000 });
  await page.screenshot({ path: info.outputPath("palette.png") });
  await expect(swatches).toHaveCount(5);
  expect(near(await swatchColor(0), edited), "the edited swatch persists").toBe(true);
  expect(near(await swatchColor(4), added), "the added swatch persists").toBe(true);
});

test("Flutter floats the toolbar over the page under dark chrome and moves it from the menus", async ({ page }, info) => {
  test.setTimeout(120_000);
  const { box } = await openNewNote(page, "Chrome");
  const button = (name: string) => page.getByRole("button", { name, exact: true });
  const pageCenter = box.x + box.width / 2;
  const dark = (rgb: Rgb) => brightness(rgb) < 150;
  // The dark ribbon on the light page: its middle row in the page's center
  // column, then its extent along that row.
  const ribbon = async () => {
    const column = await capture(page, { x: pageCenter, y: box.y, width: 1, height: box.height });
    const rows = column.flatMap((rgb, i) => (dark(rgb) ? [i] : []));
    if (rows.length === 0) throw new Error("No toolbar crosses the page's center column");
    const y = box.y + (rows[0] + rows[rows.length - 1]) / 2;
    const row = await capture(page, { x: box.x, y, width: box.width, height: 1 });
    const columns = row.flatMap((rgb, i) => (dark(rgb) ? [i] : []));
    return { left: box.x + columns[0], right: box.x + columns[columns.length - 1], y };
  };

  const topBar = await centerPixel(page, { x: 300, y: 74 });
  expect(brightness(topBar), "the top bar is dark").toBeLessThan(150);
  const top = await ribbon();
  expect(Math.abs((top.left + top.right) / 2 - pageCenter), "the toolbar is centered on the page").toBeLessThan(4);
  expect(top.y - box.y, "the toolbar floats over the top edge of the page").toBeLessThan(80);
  const beside = await centerPixel(page, { x: top.left - 40, y: top.y });
  expect(brightness(beside), "the page shows beside the toolbar").toBeGreaterThan(600);

  await button("View").click();
  await button("Toolbar at bottom").click();
  await expect.poll(async () => (await ribbon()).y, { message: "the toolbar moves to the bottom edge" })
    .toBeGreaterThan(box.y + box.height - 80);

  await button("Pages").click();
  await button("Add page").click();
  await expect(page.getByText("1 / 2", { exact: true })).toBeVisible();

  await button("More").click();
  await button("Customize toolbar").click();
  // One switch per tool kind, in toolbar order; Insert space is the eighth.
  await page.getByRole("switch").nth(7).click();
  await page.getByRole("button", { name: "Done", exact: true }).click();
  await expect(button("Insert space")).toHaveCount(0);

  await page.reload();
  await openTestNotebook(page);
  await page.getByRole("button", { name: "Open Chrome", exact: false }).click();
  await page.locator('canvas[id^="ink-canvas-"]:visible').waitFor({ timeout: 30_000 });
  await page.screenshot({ path: info.outputPath("chrome.png") });
  expect((await ribbon()).y, "the toolbar stays at the bottom after a reload").toBeGreaterThan(box.y + box.height - 80);
  await expect(button("Insert space")).toHaveCount(0);
});

test("Flutter saved pen in the toolbar restores its color and width after a reload", async ({ page }, info) => {
  test.setTimeout(120_000);
  const { box, cdp } = await openNewNote(page, "Saved pens");
  const penSize = async (label: string) => {
    await page.getByRole("button", { name: "Pen", exact: true }).click();
    await page.getByRole("button", { name: label, exact: true }).click();
  };
  const plainPen = async () => {
    await page.getByRole("button", { name: "Color #1a1a1a", exact: true }).click();
    await penSize("0.6 pt");
    await closePopover(page);
  };
  const saved = page.getByRole("button", { name: "Saved pen 3.6 pt #d92d39", exact: true });
  const write = (y: number) => penStroke(cdp, line(box.x + 140, box.x + 340, y), 0.6);

  await page.getByRole("button", { name: "Color #d92d39", exact: true }).click();
  await penSize("3.6 pt");
  await page.getByRole("button", { name: "Save pen", exact: true }).click();
  await expect(saved).toBeVisible();
  await plainPen();
  const plain = { x: box.x + 240, y: box.y + 180 };
  await write(plain.y);
  await saved.click();
  const shortcut = { x: box.x + 240, y: box.y + 260 };
  await write(shortcut.y);
  await plainPen();

  await page.reload();
  await openTestNotebook(page);
  await page.getByRole("button", { name: "Open Saved pens", exact: false }).click();
  await page.locator('canvas[id^="ink-canvas-"]:visible').waitFor({ timeout: 30_000 });
  await saved.click();
  const reloaded = { x: box.x + 240, y: box.y + 340 };
  await write(reloaded.y);
  await page.screenshot({ path: info.outputPath("saved-pens.png") });

  // The saved pen writes thick red strokes; the plain pen a thin gray one.
  const thin = await inkThickness(page, plain);
  const dark = await darkestPixel(page, plain);
  expect(Math.max(...dark) - Math.min(...dark), "the plain stroke is gray, not red").toBeLessThan(30);
  expect(brightness(dark), "the plain stroke is dark").toBeLessThan(450);
  for (const spot of [shortcut, reloaded]) {
    const [red, green, blue] = await darkestPixel(page, spot);
    expect(red - Math.max(green, blue), "the saved pen stroke is red").toBeGreaterThan(100);
    expect(await inkThickness(page, spot), "the saved pen stroke is thick").toBeGreaterThan(2.5 * thin);
  }
});

test("Flutter pen color and width changes affect only later strokes", async ({ page }) => {
  test.setTimeout(90_000);
  await page.goto("?root=opfs");
  await beginTestNote(page, "Pen settings");
  await page.getByRole("button", { name: "Create Note", exact: true }).click();
  const canvas = page.locator('canvas[id^="ink-canvas-"]:visible');
  await canvas.waitFor({ timeout: 30_000 });
  const box = await canvas.boundingBox();
  if (!box) throw new Error("Notebook canvas has no bounds");
  const cdp = await page.context().newCDPSession(page);
  const draw = async (y: number) => {
    const pen = { pointerType: "pen" as const, force: 0.6, tiltX: 20, tiltY: -10 };
    await cdp.send("Input.dispatchMouseEvent", {
      type: "mousePressed", button: "left", clickCount: 1, x: box.x + 140, y, ...pen,
    });
    await cdp.send("Input.dispatchMouseEvent", {
      type: "mouseMoved", button: "left", buttons: 1, x: box.x + 240, y, ...pen,
    });
    await cdp.send("Input.dispatchMouseEvent", {
      type: "mouseReleased", button: "left", clickCount: 1, x: box.x + 240, y, ...pen,
    });
  };

  await draw(box.y + 180);
  await page.getByRole("button", { name: "Pen", exact: true }).click();
  await page.getByRole("button", { name: "3.6 pt", exact: true }).click();
  const viewport = page.viewportSize();
  if (!viewport) throw new Error("Page has no viewport");
  await page.mouse.click(viewport.width - 20, viewport.height - 20);
  await page.getByRole("button", { name: "Color #d92d39", exact: true }).click();
  await expect.poll(() => page.evaluate(async () => {
    try {
      const root = await navigator.storage.getDirectory();
      const pens = JSON.parse(await (await (await root.getFileHandle(".pens.json")).getFile()).text());
      return { size: pens.pen.size, color: pens.pen.color };
    } catch (error) {
      if (error instanceof DOMException && error.name === "NotFoundError") return null;
      throw error;
    }
  })).toEqual({ size: 3.6, color: "#D92D39" });

  await draw(box.y + 260);
  await save(page);
  await expect(page.getByRole("status")).toHaveAccessibleName("Notebook save Saved");
  const strokes = await page.evaluate(async () => {
    const root = await navigator.storage.getDirectory();
    const notebook = await root.getDirectoryHandle("Test Notebook");
    const pages = await (await notebook.getDirectoryHandle("Pen settings")).getDirectoryHandle("pages");
    const svg = await (await (await pages.getFileHandle("0001.svg")).getFile()).text();
    const doc = new DOMParser().parseFromString(svg, "image/svg+xml");
    return [...doc.querySelectorAll('path[id^="s-"]')].map((path) => ({
      fill: path.getAttribute("fill"),
      size: Number(path.getAttribute("mn:size")),
    }));
  });
  expect(strokes).toEqual([
    { fill: "#1A1A1A", size: 1.2 },
    { fill: "#D92D39", size: 3.6 },
  ]);
});

test("Chrome opens a saved page SVG directly with the same stroke", async ({ page, context }) => {
  test.setTimeout(60_000);
  await page.goto("?root=opfs");
  await beginTestNote(page, "Standalone page");
  await page.getByRole("button", { name: "Create Note", exact: true }).click();
  const canvas = page.locator('canvas[id^="ink-canvas-"]:visible');
  await canvas.waitFor({ timeout: 30_000 });
  const box = await canvas.boundingBox();
  if (!box) throw new Error("Notebook canvas has no bounds");
  const cdp = await context.newCDPSession(page);
  const pen = { pointerType: "pen" as const, force: 0.6, tiltX: 20, tiltY: -10 };
  await cdp.send("Input.dispatchMouseEvent", {
    type: "mousePressed", button: "left", clickCount: 1, x: box.x + 150, y: box.y + 180, ...pen,
  });
  await cdp.send("Input.dispatchMouseEvent", {
    type: "mouseMoved", button: "left", buttons: 1, x: box.x + 250, y: box.y + 220, ...pen,
  });
  await cdp.send("Input.dispatchMouseEvent", {
    type: "mouseReleased", button: "left", clickCount: 1, x: box.x + 250, y: box.y + 220, ...pen,
  });
  await save(page);
  await expect(page.getByRole("status")).toHaveAccessibleName("Notebook save Saved");

  const saved = await page.evaluate(async () => {
    const root = await navigator.storage.getDirectory();
    const notebook = await root.getDirectoryHandle("Test Notebook");
    const pages = await (await notebook.getDirectoryHandle("Standalone page")).getDirectoryHandle("pages");
    const file = await (await pages.getFileHandle("0001.svg")).getFile();
    const svg = await file.text();
    const doc = new DOMParser().parseFromString(svg, "image/svg+xml");
    const stroke = doc.querySelector('path[id^="s-"]');
    if (!stroke) throw new Error("Saved page has no stroke");
    return {
      url: URL.createObjectURL(file),
      type: file.type,
      stroke: {
        d: stroke.getAttribute("d"),
        fill: stroke.getAttribute("fill"),
        size: stroke.getAttribute("mn:size"),
      },
    };
  });
  expect(saved.type).toBe("image/svg+xml");

  const standalone = await context.newPage();
  await standalone.goto(saved.url);
  const direct = await standalone.locator('path[id^="s-"]').evaluate((stroke) => ({
    d: stroke.getAttribute("d"),
    fill: stroke.getAttribute("fill"),
    size: stroke.getAttribute("mn:size"),
  }));
  expect(direct).toEqual(saved.stroke);
  await standalone.close();
});

test("Flutter notebook retains pen input and pages after save and reopen", async ({ page }, info) => {
  test.setTimeout(180_000);
  await page.goto("version.json");
  await page.evaluate(async () => {
    const root = await navigator.storage.getDirectory();
    for await (const name of root.keys()) await root.removeEntry(name, { recursive: true });
  });
  await page.goto("?root=opfs");
  await beginTestNote(page, "Lecture");
  await page.getByRole("button", { name: "Create Note", exact: true }).click();
  const canvas = page.locator('canvas[id^="ink-canvas-"]');
  await expect(canvas).toBeVisible();
  const box = await canvas.boundingBox();
  if (!box) throw new Error("Notebook canvas has no bounds");
  const cdp = await page.context().newCDPSession(page);
  const pen = { pointerType: "pen" as const, force: 0.6, tiltX: 20, tiltY: -10 };
  await cdp.send("Input.dispatchMouseEvent", { type: "mousePressed", button: "left", clickCount: 1, x: box.x + 160, y: box.y + 150, ...pen });
  await cdp.send("Input.dispatchMouseEvent", { type: "mouseMoved", button: "left", buttons: 1, x: box.x + 240, y: box.y + 190, ...pen });
  await cdp.send("Input.dispatchMouseEvent", { type: "mouseReleased", button: "left", clickCount: 1, x: box.x + 240, y: box.y + 190, ...pen });
  await page.getByRole("button", { name: "Pages", exact: true }).click();
  await page.getByRole("button", { name: "Add page", exact: true }).click();
  await save(page);
  await expect(page.getByRole("status")).toHaveAccessibleName("Notebook save Saved");
  const saved = await page.evaluate(async () => {
    const root = await navigator.storage.getDirectory();
    const notebook = await root.getDirectoryHandle("Test Notebook");
    const dir = await notebook.getDirectoryHandle("Lecture");
    const pages = await dir.getDirectoryHandle("pages");
    return (await (await pages.getFileHandle("0001.svg")).getFile()).text();
  });
  expect(saved).toContain('<path id="s-');
  expect(saved).toContain("inkml:trace");
  await page.getByRole("button", { name: "Text", exact: true }).click();
  await enterText(page.getByRole("textbox", { name: "Text", exact: true }), "Lemma\nEvery basis spans the space.");
  await page.getByRole("button", { name: "Done", exact: true }).click();
  await save(page);
  await expect.poll(() => page.evaluate(async () => {
    const root = await navigator.storage.getDirectory();
    const notebook = await root.getDirectoryHandle("Test Notebook");
    const dir = await notebook.getDirectoryHandle("Lecture");
    const pages = await dir.getDirectoryHandle("pages");
    return (await (await pages.getFileHandle("0001.svg")).getFile()).text();
  })).toContain("Every basis spans the space.");
  await page.getByRole("button", { name: "More", exact: true }).click();
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
  await openTestNotebook(page);
  await page.getByRole("button", { name: "Open Lecture", exact: false }).click();
  await expect(canvas).toBeVisible();
  await expect(page.getByText("1 / 2", { exact: true })).toBeVisible();
  await page.getByRole("button", { name: "Pages", exact: true }).click();
  await page.getByRole("button", { name: "Next page", exact: true }).click();
  await expect(page.getByText("2 / 2", { exact: true })).toBeVisible();
  await page.getByRole("button", { name: "Library", exact: true }).click();
  await page.getByRole("button", { name: "New Note", exact: true }).click();
  await enterText(page.getByRole("textbox", { name: "Title" }), "Exercises");
  await page.getByRole("button", { name: "Create Note", exact: true }).click();
  await page.getByRole("button", { name: "Lecture", exact: true }).click();
  await expect(page.getByText("2 / 2", { exact: true })).toBeVisible();
  await page.getByRole("button", { name: "Library", exact: true }).click();
  await page.getByRole("button", { name: "Lecture actions", exact: true }).click();
  await page.getByRole("button", { name: "Add favorite", exact: true }).click();
  await page.getByText("Favorites", { exact: true }).click();
  await expect(page.getByRole("button", { name: "Open Lecture", exact: false })).toBeVisible();
  await expect(page.getByRole("button", { name: "Open Exercises", exact: false })).not.toBeVisible();
  await expect.poll(() => page.evaluate(async () => {
    const root = await navigator.storage.getDirectory();
    const metadata = JSON.parse(await (await (await root.getFileHandle(".library.json")).getFile()).text());
    return metadata.notes["Test Notebook/Lecture"]?.favorite;
  })).toBe(true);
  await page.context().setOffline(true);
  await page.reload();
  await openTestNotebook(page);
  await page.getByRole("button", { name: "Open Lecture", exact: false }).click();
  await expect(page.getByText("1 / 2", { exact: true })).toBeVisible();
  await page.getByRole("button", { name: "Pages", exact: true }).click();
  await page.getByRole("button", { name: "Add page", exact: true }).click();
  await save(page);
  await expect(page.getByRole("status")).toHaveAccessibleName("Notebook save Saved");
  await page.reload();
  await openTestNotebook(page);
  await page.getByRole("button", { name: "Open Lecture", exact: false }).click();
  await expect(page.getByText("1 / 3", { exact: true })).toBeVisible();
  await page.context().setOffline(false);
  await page.reload();
  await page.getByText("Favorites", { exact: true }).click();
  await expect(page.getByRole("button", { name: "Open Lecture", exact: false })).toBeVisible();
});

test("Flutter exports a ten-page notebook as a ten-page PDF", async ({ page }, info) => {
  test.setTimeout(120_000);
  await page.goto("?root=opfs");
  await beginTestNote(page, "Ten pages");
  await page.getByRole("button", { name: "Create Note", exact: true }).click();
  await page.locator('canvas[id^="ink-canvas-"]').waitFor({ timeout: 30_000 });

  for (let pageNumber = 2; pageNumber <= 10; pageNumber++) {
    await page.getByRole("button", { name: "Pages", exact: true }).click();
    await page.getByRole("button", { name: "Add page", exact: true }).click();
  }
  await expect(page.getByText(/^[0-9]+ \/ 10$/)).toBeVisible();

  await page.getByRole("button", { name: "More", exact: true }).click();
  await page.getByRole("button", { name: "Export PDF", exact: true }).click();
  const download = page.waitForEvent("download");
  await page.getByRole("button", { name: "Export", exact: true }).click();
  const pdf = await download;
  const pdfPath = info.outputPath("ten-pages.pdf");
  await pdf.saveAs(pdfPath);

  expect(execFileSync("qpdf", ["--check", pdfPath], { encoding: "utf8" })).toContain(
    "No syntax or stream encoding errors found",
  );
  const infoText = execFileSync("pdfinfo", [pdfPath], { encoding: "utf8" });
  expect(infoText).toMatch(/Pages:\s+10/);
  expect(infoText).toMatch(/Page size:\s+595 x 842 pts \(A4\)/);
});

test("Flutter marker popover changes the size of the marker only", async ({ page }, info) => {
  test.setTimeout(120_000);
  await page.goto("version.json");
  await page.evaluate(async () => {
    const root = await navigator.storage.getDirectory();
    for await (const name of root.keys()) await root.removeEntry(name, { recursive: true });
  });
  await page.goto("?root=opfs");
  await page.getByRole("button", { name: "New Notebook", exact: true }).click();
  await enterText(page.getByRole("textbox", { name: "Notebook Title", exact: true }), "Tools");
  await page.getByRole("button", { name: "Create Notebook", exact: true }).click();
  await page.getByRole("button", { name: "New Note", exact: true }).click();
  await enterText(page.getByRole("textbox", { name: "Title", exact: true }), "Pens");
  await page.getByRole("button", { name: "Create Note", exact: true }).click();
  await page.locator('canvas[id^="ink-canvas-"]').waitFor();
  // The first tap selects the marker; a tap on the selected marker opens its settings.
  await page.getByRole("button", { name: "Marker", exact: true }).click();
  await page.getByRole("button", { name: "Marker", exact: true }).click();
  await page.getByRole("button", { name: "3.6 pt", exact: true }).click();
  await page.screenshot({ path: info.outputPath("marker-popover.png") });
  const viewport = page.viewportSize();
  if (!viewport) throw new Error("Page has no viewport");
  await page.mouse.click(viewport.width - 20, viewport.height - 20);
  await expect.poll(() => page.evaluate(async () => {
    const root = await navigator.storage.getDirectory();
    const pens = JSON.parse(await (await (await root.getFileHandle(".pens.json")).getFile()).text());
    return { pen: pens.pen, marker: pens.marker };
  })).toMatchObject({ pen: { brush: "pressure-pen", size: 1.2 }, marker: { brush: "marker", size: 3.6 } });
});

test("Flutter two-page layout puts pen input on the right page and shares a PDF", async ({ page }) => {
  test.setTimeout(120_000);
  await page.goto("?root=opfs");
  await page.evaluate(() => localStorage.removeItem("pageArrangement"));
  await beginTestNote(page, "Spread");
  await page.getByRole("button", { name: "Create Note", exact: true }).click();
  const canvas = page.locator('canvas[id^="ink-canvas-"]');
  await canvas.waitFor({ timeout: 30_000 });
  for (let added = 0; added < 2; added++) {
    await page.getByRole("button", { name: "Pages", exact: true }).click();
    await page.getByRole("button", { name: "Add page", exact: true }).click();
  }
  await expect(page.getByText(/^\d \/ 3$/)).toBeVisible();
  await page.getByRole("button", { name: "View", exact: true }).click();
  await page.getByRole("button", { name: "Two pages", exact: true }).click();
  await page.waitForTimeout(500);
  const box = await canvas.boundingBox();
  if (!box) throw new Error("Notebook canvas has no bounds");
  const cdp = await page.context().newCDPSession(page);
  const pen = { pointerType: "pen" as const, force: 0.6, button: "left" as const };
  const x = box.x + box.width * 0.75;
  const y = box.y + 200;
  await cdp.send("Input.dispatchMouseEvent", { type: "mousePressed", clickCount: 1, x, y, ...pen, buttons: 1 });
  await cdp.send("Input.dispatchMouseEvent", { type: "mouseMoved", x: x + 40, y, ...pen, buttons: 1 });
  await cdp.send("Input.dispatchMouseEvent", { type: "mouseMoved", x: x + 80, y, ...pen, buttons: 1 });
  await cdp.send("Input.dispatchMouseEvent", { type: "mouseReleased", clickCount: 1, x: x + 80, y, ...pen, buttons: 0 });
  await save(page);
  await expect(page.getByRole("status")).toHaveAccessibleName("Notebook save Saved");
  const counts = await page.evaluate(async () => {
    const root = await navigator.storage.getDirectory();
    const notebook = await root.getDirectoryHandle("Test Notebook");
    const dir = await notebook.getDirectoryHandle("Spread");
    const manifest = JSON.parse(await (await (await dir.getFileHandle("notebook.json")).getFile()).text());
    const pages = await dir.getDirectoryHandle("pages");
    const counts = [];
    for (const entry of manifest.pages as { file: string }[]) {
      const name = entry.file.replace("pages/", "");
      const svg = await (await (await pages.getFileHandle(name)).getFile()).text();
      counts.push(svg.match(/<path id="s-/g)?.length ?? 0);
    }
    return counts;
  });
  expect(counts).toEqual([0, 1, 0]);

  await page.evaluate(() => {
    const shared: string[] = [];
    Object.assign(window, { shared });
    navigator.canShare = () => true;
    navigator.share = async (data) => {
      for (const file of data?.files ?? []) shared.push(`${file.name} ${file.type}`);
    };
  });
  await page.getByRole("button", { name: "More", exact: true }).click();
  await page.getByRole("button", { name: "Share", exact: true }).click();
  await page.getByRole("button", { name: "Share", exact: true }).click();
  await expect.poll(() => page.evaluate(() => (window as unknown as { shared: string[] }).shared)).toEqual([
    "Spread.pdf application/pdf",
  ]);

  await page.reload();
  await openTestNotebook(page);
  await page.getByRole("button", { name: "Open Spread", exact: false }).click();
  await canvas.waitFor({ timeout: 30_000 });
  await page.getByRole("button", { name: "View", exact: true }).click();
  await expect(page.getByRole("button", { name: /^\S+ Two pages$/ })).toHaveAttribute("aria-current", "true");
});
