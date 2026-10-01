import { expect, test, type CDPSession, type Locator, type Page } from "@playwright/test";
import { execFileSync } from "node:child_process";
import { readFile } from "node:fs/promises";
import { networkInterfaces } from "node:os";

// A failed workflow keeps the bridge's pointer log (window.mathNotesPointers):
// whether each pen event reached Flutter and the engine, for a stroke that
// left no ink (#72).
test.afterEach(async ({ page }, info) => {
  if (info.status === info.expectedStatus) return;
  const log = await page.evaluate(() => (window as unknown as { mathNotesPointers?: string[] }).mathNotesPointers ?? [])
    .catch(() => ["the page is gone"]);
  await info.attach("pointers.txt", { body: log.join("\n"), contentType: "text/plain" });
});

// Two animation frames: Flutter has drawn and sent what the last input
// changed.
async function frames(page: Page): Promise<void> {
  await page.evaluate(() => new Promise<void>((done) => requestAnimationFrame(() => requestAnimationFrame(() => done()))));
}

// Flutter activates its text input channel after semantic focus is delivered.
// Use actual keyboard input after clicking, rather than fill's synchronous DOM
// value assignment. See Flutter web_ui semantics/text_field.dart, activate.
// The framework then sends the caret of the click to the input; a select-all
// before that arrives is undone (TRAPS.md).
async function focusText(field: Locator): Promise<void> {
  await field.click();
  await frames(field.page());
}

async function enterText(field: Locator, value: string): Promise<void> {
  await focusText(field);
  await field.press("ControlOrMeta+a");
  await field.pressSequentially(value);
}

async function save(page: Page): Promise<void> {
  await page.getByRole("button", { name: "More", exact: true }).click();
  await page.getByRole("button", { name: "Save", exact: true }).click();
}

async function goToPage(page: Page, number: number): Promise<void> {
  await page.getByRole("button", { name: "Pages", exact: true }).click();
  await page.getByRole("button", { name: "Go to page", exact: true }).click();
  await enterText(page.getByRole("textbox"), `${number}`);
  await page.getByRole("button", { name: "Go", exact: true }).click();
  // Pen events before the alert's barrier is gone never reach the page
  // (TRAPS.md). Split view shows a Library button in each pane.
  await expect(page.getByRole("button", { name: "Library", exact: true }).first()).toBeVisible();
}

async function closeNote(page: Page): Promise<void> {
  await page.getByRole("button", { name: "More", exact: true }).click();
  await page.getByRole("button", { name: "Close note", exact: true }).click();
}

// A read of a saved file while the app may be saving it again. `getFile()`
// snapshots the file, and Chromium refuses the snapshot with NotReadableError
// once the app's writable stream has swapped a new file in (storage/browser/
// blob/blob_reader.cc compares the modification time). The next read opens
// the new file.
async function whenSaved<T>(read: () => Promise<T>): Promise<T> {
  for (;;) {
    try {
      return await read();
    } catch (error) {
      if (!(error instanceof Error && error.message.includes("NotReadableError"))) throw error;
    }
  }
}

async function addTag(page: Page, tag: string): Promise<void> {
  await enterText(page.getByRole("textbox", { name: "Add a tag…", exact: true }), tag);
  await page.getByRole("button", { name: "Add tag", exact: true }).click();
}

async function createTestNotebook(page: Page, name = "Test Notebook"): Promise<void> {
  await page.getByRole("button", { name: "New notebook", exact: true }).click();
  await enterText(page.getByRole("textbox", { name: "Notebook title", exact: true }), name);
  await page.getByRole("button", { name: "Create", exact: true }).click();
}

async function openTestNotebook(page: Page, name = "Test Notebook"): Promise<void> {
  await page.getByRole("button", { name: `Open ${name}`, exact: false }).click();
  await expect(page.getByRole("heading", { name, exact: true })).toBeVisible();
}

async function beginTestNote(page: Page, title: string, notebook = "Test Notebook"): Promise<void> {
  await createTestNotebook(page, notebook);
  await page.getByRole("button", { name: "New note", exact: true }).click();
  await enterText(page.getByRole("textbox", { name: "Title", exact: true }), title);
}

test("Flutter creation sheets close on Escape and ask before they discard a change", async ({ page }) => {
  await page.goto("?root=opfs");
  const button = (name: string) => page.getByRole("button", { name, exact: true });
  const title = page.getByRole("textbox", { name: "Notebook title", exact: true });

  await button("New notebook").click();
  await title.waitFor();
  expect(await contrastIn(page, page.getByRole("textbox", { name: "Description", exact: true })), "the Description placeholder is legible").toBeGreaterThan(4.5);
  const field = await boxOf(page.getByRole("textbox", { name: "Description", exact: true }));
  expect(await capture(page, { x: field.x + 4, y: field.y + 4, width: 1, height: 1 }), "the field is paper").toEqual([[0xfb, 0xfa, 0xf6]]);
  const heading = await boxOf(page.getByRole("heading", { name: "New notebook", exact: true }));
  expect(await capture(page, { x: heading.x - 6, y: heading.y + heading.height / 2, width: 1, height: 1 }), "the sheet is leaf").toEqual([[0xee, 0xf0, 0xea]]);
  expect(await contrastIn(page, button("Cancel")), "Cancel is legible").toBeGreaterThan(4.5);
  await page.keyboard.press("Escape");
  await expect(title, "an unchanged sheet closes at once").toHaveCount(0);

  await button("New notebook").click();
  await enterText(title, "Scratch");
  await page.keyboard.press("Escape");
  await expect(page.getByText("Discard new notebook?", { exact: true })).toBeVisible();
  await button("Keep editing").click();
  await expect(title, "Keep editing returns to the form as it was").toHaveValue("Scratch");
  await button("Cancel").click();
  await button("Discard").click();
  await expect(title).toHaveCount(0);
  await expect(page.getByRole("button", { name: /^Open Scratch/ })).toHaveCount(0);
});

test("Flutter notebook cards retain their notes and metadata after rename", async ({ page }, info) => {
  test.setTimeout(90_000);
  await page.goto("?root=opfs");
  await page.getByRole("button", { name: "New notebook", exact: true }).click();
  await enterText(page.getByRole("textbox", { name: "Notebook title", exact: true }), "Algebra");
  await enterText(page.getByRole("textbox", { name: "Description", exact: true }), "Lecture notes");
  await addTag(page, "groups");
  await page.getByRole("button", { name: "Lined", exact: true }).click();
  await page.getByRole("button", { name: "Create", exact: true }).click();
  await page.getByRole("button", { name: "New note", exact: true }).click();
  await enterText(page.getByRole("textbox", { name: "Title", exact: true }), "Rings");
  await page.getByRole("button", { name: "Create", exact: true }).click();
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
  await page.getByRole("button", { name: "New note", exact: true }).click();
  await enterText(page.getByRole("textbox", { name: "Title", exact: true }), "Movable");
  await addTag(page, "algebra");
  await page.getByRole("button", { name: "Create", exact: true }).click();
  await closeNote(page);
  await expect(page.getByRole("heading", { name: "Inbox", exact: true })).toBeVisible();

  await page.getByRole("button", { name: "Back to library", exact: true }).click();
  await createTestNotebook(page, "Archive");
  await page.getByRole("button", { name: "Back to library", exact: true }).click();
  await openTestNotebook(page, "Inbox");

  await page.getByRole("button", { name: "Movable actions", exact: true }).click();
  await page.getByRole("button", { name: "Move", exact: true }).click();
  await page.getByRole("button", { name: "Archive", exact: true }).click();
  await expect(page.getByRole("button", { name: "Movable actions", exact: true })).toHaveCount(0);

  await page.getByRole("button", { name: "Back to library", exact: true }).click();
  await openTestNotebook(page, "Archive");
  await expect(page.getByRole("button", { name: "Open Movable", exact: false })).toBeVisible();

  await page.getByRole("button", { name: "Back to library", exact: true }).click();
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

  // A tag made from the sidebar, then given to the note with its description
  // from the card menu; the sidebar tag lists the note.
  await page.getByRole("button", { name: "New tag", exact: true }).click();
  await enterText(page.getByRole("textbox", { name: "Tag name", exact: true }), "geometry");
  await page.getByRole("button", { name: "Add tag", exact: true }).click();
  await expect(page.getByRole("button", { name: /^geometry/ })).toBeVisible();
  await page.getByRole("button", { name: "Movable actions", exact: true }).click();
  await page.getByRole("button", { name: "Details and tags", exact: true }).click();
  await enterText(page.getByRole("textbox", { name: "Description", exact: true }), "Moved from Inbox");
  await addTag(page, "geometry");
  await page.getByRole("button", { name: "Save details", exact: true }).click();
  await page.getByRole("button", { name: /^geometry/ }).click();
  await expect(page.getByRole("button", { name: "Open Movable", exact: false })).toBeVisible();

  const metadata = JSON.parse(
    await page.evaluate(async () => {
      const root = await navigator.storage.getDirectory();
      return (await (await root.getFileHandle(".library.json")).getFile()).text();
    }),
  );
  expect(metadata.notes["Archive/Movable"].tags).toEqual(["algebra", "geometry"]);
  expect(metadata.notes["Archive/Movable"].description).toBe("Moved from Inbox");
  expect(metadata.tags.map(({ name }: { name: string }) => name)).toContain("geometry");
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
  await expect(page.getByRole("button", { name: "New notebook", exact: true })).toBeVisible();
  await expect(page.getByText("Your notebooks appear here.", { exact: true })).toBeVisible();
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
  await page.getByRole("button", { name: "New note", exact: true }).click();
  await enterText(page.getByRole("textbox", { name: "Title", exact: true }), "Persistent");
  await page.getByRole("button", { name: "Create", exact: true }).click();
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
  await goToPage(page, 2);
  await expect(page.getByText("2 / 2", { exact: true })).toBeVisible();
  await draw(box.y + 260);
  await save(page);
  await expect(page.getByRole("status", { name: /^Notebook save/ })).toHaveAccessibleName("Notebook save Saved");

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
  await page.getByRole("button", { name: "New note", exact: true }).click();
  await enterText(page.getByRole("textbox", { name: "Title", exact: true }), "Immediate");
  await page.getByRole("button", { name: "Create", exact: true }).click();
  await closeNote(page);

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
    await closeNote(page);
    await expect(
      page.getByRole("heading", { name: "Open timing", exact: true }),
    ).toBeVisible();
  }
});

test("Flutter opens another note from the Open note button and preserves each tab state", async ({ page }) => {
  test.setTimeout(120_000);
  await page.goto("?root=opfs");
  await createTestNotebook(page);
  await page.getByRole("button", { name: "New note", exact: true }).click();
  await enterText(page.getByRole("textbox", { name: "Title", exact: true }), "Second");
  await page.getByRole("button", { name: "Create", exact: true }).click();
  await closeNote(page);
  await expect(
    page.getByRole("heading", { name: "Test Notebook", exact: true }),
  ).toBeVisible();
  await page.getByRole("button", { name: "New note", exact: true }).click();
  await enterText(page.getByRole("textbox", { name: "Title", exact: true }), "First");
  await page.getByRole("button", { name: "Create", exact: true }).click();
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
  await goToPage(page, 2);
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
  await page.getByRole("button", { name: "Create", exact: true }).click();
  await page.getByRole("button", { name: "More", exact: true }).waitFor();
  const chooser = page.waitForEvent("filechooser");
  await page.getByRole("button", { name: "Image", exact: true }).click();
  await (await chooser).setFiles("../../core/tests/fixtures/render/full/0001.png");
  await expect(page.getByRole("button", { name: "Delete selection", exact: true })).toBeAttached();
  await save(page);
  await expect(page.getByRole("status", { name: /^Notebook save/ })).toHaveAccessibleName("Notebook save Saved");
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
  await page.getByRole("button", { name: "Create", exact: true }).click();
  const canvas = page.locator('canvas[id^="ink-canvas-"]');
  await canvas.waitFor();
  const box = await canvas.boundingBox();
  if (!box) throw new Error("Notebook canvas has no bounds");
  await page.mouse.move(box.x + box.width / 2, box.y + box.height / 2);
  await page.mouse.wheel(0, 4000);
  await expect(page.getByText("Pull and hold to add a page", { exact: true })).toBeVisible();
  expect((await textIn(page, await boxOf(page.getByText("Pull and hold to add a page", { exact: true })))).contrast,
    "the hint is legible over the paper").toBeGreaterThan(4.5);
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
  await expect(page.getByRole("status", { name: /^Notebook save/ })).toHaveAccessibleName("Notebook save Saved");
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
  await page.getByRole("button", { name: "Lined", exact: true }).click();
  await addTag(page, "analysis");
  await page.getByRole("button", { name: "Letter", exact: true }).click();
  await page.getByRole("button", { name: "Landscape", exact: true }).click();
  await page.getByRole("button", { name: "Save as draft", exact: true }).click();
  await expect(page.getByRole("status", { name: "Draft saved", exact: true })).toBeVisible();
  await page.reload();
  await openTestNotebook(page);
  await page.getByRole("button", { name: "New note", exact: true }).click();
  await expect(page.getByRole("textbox", { name: "Title", exact: true })).toHaveValue("Seminar");
  await (await inView(page.getByRole("button", { name: "Save as template", exact: true }))).click();
  await enterText(page.getByRole("textbox", { name: "Template name", exact: true }), "Proof paper");
  await page.getByRole("button", { name: "Save template", exact: true }).click();
  await expect(page.getByRole("status", { name: "Template saved", exact: true })).toBeVisible();
  await page.reload();
  await openTestNotebook(page);
  await page.getByRole("button", { name: "New note", exact: true }).click();
  await page.getByRole("button", { name: "Plain", exact: true }).click();
  await addTag(page, "temporary");
  await (await inView(page.getByRole("button", { name: "Proof paper", exact: false }))).click();
  await expect(page.getByRole("img", { name: "First page preview", exact: true })).toBeVisible();
  await page.screenshot({ path: info.outputPath("settings-selected.png") });
  await expect(page.getByRole("button", { name: "Remove tag analysis", exact: true })).toBeVisible();
  await expect(page.getByRole("button", { name: "Remove tag temporary", exact: true })).toHaveCount(0);
  await page.getByRole("button", { name: "Create", exact: true }).click();
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
  await save(page);
  await expect(page.getByRole("status", { name: /^Notebook save/ })).toHaveAccessibleName("Notebook save Saved");
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

test("Flutter modal dialogs block pen ink underneath them, and a cancelled pen stroke leaves no ink", async ({ page }) => {
  test.setTimeout(90_000);
  await page.goto("?root=opfs");
  await beginTestNote(page, "Modal input");
  await page.getByRole("button", { name: "Create", exact: true }).click();
  const canvas = page.locator('canvas[id^="ink-canvas-"]:visible');
  await canvas.waitFor({ timeout: 30_000 });
  const box = await canvas.boundingBox();
  if (!box) throw new Error("Notebook canvas has no bounds");

  await page.getByRole("button", { name: "Pages", exact: true }).click();
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
  const strokes = async () => {
    await save(page);
    await expect(page.getByRole("status", { name: /^Notebook save/ })).toHaveAccessibleName("Notebook save Saved");
    return page.evaluate(async () => {
      const root = await navigator.storage.getDirectory();
      const notebook = await root.getDirectoryHandle("Test Notebook");
      const pages = await (await notebook.getDirectoryHandle("Modal input")).getDirectoryHandle("pages");
      const svg = await (await (await pages.getFileHandle("0001.svg")).getFile()).text();
      return svg.match(/<path id="s-/g)?.length ?? 0;
    });
  };
  expect(await strokes(), "the dialog blocks the ink").toBe(0);

  // The browser cancels a pen stroke (a palm gesture, a lost pen): the page
  // receives pointercancel, as CDP cannot send it.
  await page.evaluate(async ({ x, y }) => {
    const send = async (type: string, clientX: number, buttons: number) => {
      document.elementFromPoint(clientX, y)!.dispatchEvent(new PointerEvent(type, {
        pointerId: 7, pointerType: "pen", isPrimary: true, bubbles: true, cancelable: true, composed: true,
        clientX, clientY: y, pressure: buttons ? 0.6 : 0, button: buttons ? 0 : -1, buttons,
      }));
      await new Promise((resolve) => setTimeout(resolve, 20));
    };
    await send("pointerdown", x, 1);
    for (const offset of [40, 80, 120, 160]) await send("pointermove", x + offset, 1);
    await send("pointercancel", x + 160, 0);
  }, { x: box.x + 150, y: box.y + 300 });
  expect(await strokes(), "the cancelled stroke leaves no ink").toBe(0);
  await penStroke(cdp, line(box.x + 150, box.x + 310, box.y + 360, 4), 0.6);
  expect(await strokes(), "the next stroke draws").toBe(1);
});

test("Flutter undoes on a two-finger tap and redoes on a three-finger tap", async ({ page }) => {
  test.setTimeout(60_000);
  await page.goto("?root=opfs");
  await beginTestNote(page, "Taps");
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
    await save(page);
    await expect(page.getByRole("status", { name: /^Notebook save/ })).toHaveAccessibleName("Notebook save Saved");
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

test("Flutter erases with the pen side button and eraser end and draws with a finger on request", async ({ page }) => {
  test.setTimeout(120_000);
  await page.goto("?root=opfs");
  await beginTestNote(page, "Fingers");
  await page.getByRole("button", { name: "Create", exact: true }).click();
  const canvas = page.locator('canvas[id^="ink-canvas-"]');
  await canvas.waitFor({ timeout: 30_000 });
  const box = await canvas.boundingBox();
  if (!box) throw new Error("Notebook canvas has no bounds");
  const cdp = await page.context().newCDPSession(page);
  const strokes = async () => {
    await save(page);
    await expect(page.getByRole("status", { name: /^Notebook save/ })).toHaveAccessibleName("Notebook save Saved");
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
  // CDP has no button for the eraser end of a pen, so the page receives the
  // pointer events that the eraser end makes: button 5, buttons 32.
  await penDrag("left", [160, 150], [300, 150]);
  expect(await strokes()).toBe(1);
  await page.evaluate(async ({ x, y }) => {
    const send = async (type: string, clientY: number, button: number, buttons: number) => {
      document.elementFromPoint(x, clientY)!.dispatchEvent(new PointerEvent(type, {
        pointerId: 9, pointerType: "pen", isPrimary: true, bubbles: true, cancelable: true, composed: true,
        clientX: x, clientY, pressure: buttons ? 0.6 : 0, button, buttons,
      }));
      await new Promise((resolve) => setTimeout(resolve, 20));
    };
    await send("pointerdown", y + 100, 5, 32);
    for (const offset of [125, 150, 175, 200]) await send("pointermove", y + offset, -1, 32);
    await send("pointerup", y + 200, 5, 0);
  }, { x: box.x + 230, y: box.y });
  expect(await strokes(), "the eraser end of the pen erases").toBe(0);

  await page.getByRole("button", { name: "More", exact: true }).click();
  await page.getByRole("button", { name: "Settings", exact: true }).click();
  await page.getByRole("switch", { name: "Draw with finger", exact: true }).click();
  await page.getByRole("button", { name: "Done", exact: true }).click();
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
  await page.getByRole("button", { name: "Settings", exact: true }).click();
  await expect(page.getByRole("switch", { name: "Draw with finger", exact: true })).toBeChecked();
});

test("Flutter partial and whole-stroke erases each undo and redo", async ({ page }) => {
  test.setTimeout(120_000);
  await page.goto("?root=opfs");
  await beginTestNote(page, "Erase history");
  await page.getByRole("button", { name: "Create", exact: true }).click();
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
  const savedStrokeCount = () => whenSaved(() => page.evaluate(async () => {
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
  }));
  const expectStrokes = async (count: number) => {
    await expect.poll(savedStrokeCount, { timeout: 8_000 }).toBe(count);
  };

  await drag([150, 220], [350, 220]);
  await expectStrokes(1);
  await page.getByRole("button", { name: "Eraser", exact: true }).click();
  await page.getByRole("button", { name: "Eraser", exact: true }).click();
  await page.getByRole("button", { name: "Partial", exact: true }).click();
  await closePopover(page);
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
  await closePopover(page);
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
  await page.getByRole("button", { name: "Create", exact: true }).click();
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
  await expect(page.getByRole("status", { name: /^Notebook save/ })).toHaveAccessibleName("Notebook save Saved");
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
  await page.getByRole("button", { name: "Create", exact: true }).click();
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
    await goToPage(page, pageNumber);
    await expect(page.getByText(`${pageNumber} / ${pageNumber}`, { exact: true })).toBeVisible();
    await draw((pageNumber - 1) * 30);
  }
  await page.getByRole("button", { name: "Pages", exact: true }).click();
  await page.getByRole("button", { name: "Page overview", exact: true }).click();
  await page.getByRole("button", { name: "Page 1", exact: true }).click();
  await expect(page.getByText("1 / 3", { exact: true })).toBeVisible();
  await save(page);
  await expect(page.getByRole("status", { name: /^Notebook save/ })).toHaveAccessibleName("Notebook save Saved");

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
  await pickColor(page, "#d92d39");
  await page.getByRole("button", { name: "Pen", exact: true }).click();
  // A pen-down away from a selection only clears it (Write, clearSelOnly).
  await gesture([[600, 500], [600, 500]]);
  await expect(page.getByRole("button", { name: "Delete selection", exact: true })).toHaveCount(0);
  await gesture([[160, 350], [200, 370], [240, 390]]);
  await save(page);
  await expect(page.getByRole("status", { name: /^Notebook save/ })).toHaveAccessibleName("Notebook save Saved");
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

// The pixels of a PNG, row by row. The page decodes the PNG and returns the
// RGBA bytes as one base64 string: an array of pixels takes seconds to cross
// the protocol.
async function pngPixels(page: Page, png: Buffer): Promise<Rgb[]> {
  const rgba = Buffer.from(await page.evaluate(async (base64) => {
    const bytes = Uint8Array.from(atob(base64), (c) => c.charCodeAt(0));
    const bitmap = await createImageBitmap(new Blob([bytes], { type: "image/png" }));
    const context = new OffscreenCanvas(bitmap.width, bitmap.height).getContext("2d");
    if (!context) throw new Error("No 2D context");
    context.drawImage(bitmap, 0, 0);
    const data = context.getImageData(0, 0, bitmap.width, bitmap.height).data;
    let binary = "";
    for (let i = 0; i < data.length; i += 0x8000) binary += String.fromCharCode(...data.subarray(i, i + 0x8000));
    return btoa(binary);
  }, png.toString("base64")), "base64");
  return Array.from({ length: rgba.length / 4 }, (_, i): Rgb => [rgba[4 * i], rgba[4 * i + 1], rgba[4 * i + 2]]);
}

// The on-screen pixels of a rectangle, row by row, from a clipped capture: a
// full-viewport capture can show the WebGL canvas displaced (TRAPS.md).
async function capture(page: Page, clip: Box): Promise<Rgb[]> {
  return pngPixels(page, await page.screenshot({ clip }));
}

// Waits for the motion in a rectangle to end: two captures in a row alike.
async function settled(page: Page, clip: Box): Promise<void> {
  await expect(async () => {
    const before = await capture(page, clip);
    expect(await capture(page, clip)).toEqual(before);
  }, "the view comes to rest").toPass({ timeout: 10_000 });
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

type Bounds = { left: number; right: number; top: number; bottom: number };

// The screen bounds of the pixels in a region that pass a test.
async function pixelBounds(page: Page, region: Box, test: (rgb: Rgb) => boolean): Promise<Bounds> {
  const pixels = await capture(page, region);
  const bounds = { left: Infinity, right: -Infinity, top: Infinity, bottom: -Infinity };
  pixels.forEach((rgb, i) => {
    if (!test(rgb)) return;
    const x = region.x + (i % region.width);
    const y = region.y + Math.floor(i / region.width);
    bounds.left = Math.min(bounds.left, x);
    bounds.right = Math.max(bounds.right, x);
    bounds.top = Math.min(bounds.top, y);
    bounds.bottom = Math.max(bounds.bottom, y);
  });
  expect(bounds.left, "the region shows the pixels").toBeLessThanOrEqual(bounds.right);
  return bounds;
}

const size = (bounds: Bounds) => ({ width: bounds.right - bounds.left, height: bounds.bottom - bounds.top });

// The blue outline and round handles of a selection.
const isOutline = ([red, , blue]: Rgb) => blue - red > 60;

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
  await page.getByRole("button", { name: "Create", exact: true }).click();
  const canvas = page.locator('canvas[id^="ink-canvas-"]:visible');
  await canvas.waitFor({ timeout: 30_000 });
  const box = await canvas.boundingBox();
  if (!box) throw new Error("Notebook canvas has no bounds");
  return { box, cdp: await page.context().newCDPSession(page) };
}

// The editor leaves a desk margin around the pages at zoom 1 (deskMargin and
// deskLeft in editor_screen.dart); on the left it clears the floating rail.
// The first page's screen rectangle in a canvas.
const DESK_MARGIN = 16;
const DESK_LEFT = 8 + 60 + DESK_MARGIN;
function pageIn(canvas: Box): Box {
  return { x: canvas.x + DESK_LEFT, y: canvas.y + DESK_MARGIN, width: canvas.width - DESK_LEFT - DESK_MARGIN, height: canvas.height - DESK_MARGIN };
}

// WCAG relative luminance: https://www.w3.org/TR/WCAG22/#dfn-relative-luminance
function luminance(rgb: Rgb): number {
  const [red, green, blue] = rgb.map((channel) => {
    const value = channel / 255;
    return value <= 0.04045 ? value / 12.92 : ((value + 0.055) / 1.055) ** 2.4;
  });
  return 0.2126 * red + 0.7152 * green + 0.0722 * blue;
}

// WCAG contrast ratio; 4.5 is the minimum for legible body text:
// https://www.w3.org/TR/WCAG22/#contrast-minimum
const contrast = (a: Rgb, b: Rgb) =>
  (Math.max(luminance(a), luminance(b)) + 0.05) / (Math.min(luminance(a), luminance(b)) + 0.05);

// The text drawn in a screen region: its left edge, and its contrast with
// the background, which is the top-left pixel of the region.
async function textIn(page: Page, box: Box): Promise<{ left: number; contrast: number }> {
  const region = { x: Math.round(box.x), y: Math.round(box.y), width: Math.round(box.width), height: Math.round(box.height) };
  const pixels = await capture(page, region);
  const ratios = pixels.map((rgb) => contrast(rgb, pixels[0]));
  const first = ratios.reduce((left, ratio, i) => (ratio > 2 ? Math.min(left, i % region.width) : left), region.width);
  return { left: region.x + first, contrast: Math.max(...ratios) };
}

// The contrast of the text inside a control, measured from 4 px inside its
// rounded corners, where its own fill is the background.
async function contrastIn(page: Page, locator: Locator): Promise<number> {
  const box = await boxOf(locator);
  return (await textIn(page, { x: box.x + 4, y: box.y + 4, width: box.width - 8, height: box.height - 8 })).contrast;
}

// Scrolls a control into view and waits until Flutter has drawn the scroll.
// Playwright scrolls the semantics DOM at once; Flutter scrolls its content
// in a later frame, and a click before that frame lands on the control that
// was drawn at that point (TRAPS.md).
async function inView(locator: Locator): Promise<Locator> {
  await locator.scrollIntoViewIfNeeded();
  await frames(locator.page());
  return locator;
}

async function boxOf(locator: Locator): Promise<Box> {
  await inView(locator);
  const box = await locator.boundingBox();
  if (!box) throw new Error("The element has no bounds");
  return box;
}

// The ribbon (#9E2A2B) that marks the current selection; no cover color is
// as red with as little green and blue.
// Binder's board (#DADDD5): the desk and the chrome.
const BOARD: Rgb = [0xda, 0xdd, 0xd5];

const isRibbon = ([red, green, blue]: Rgb) => red > 130 && green < 80 && blue < 80;

// Taps an anchor whose pull-down menu opens at it: the items start within a
// finger's width of the anchor, and the menu is much narrower than the screen.
async function openMenuAt(anchor: Locator, items: Locator[]): Promise<void> {
  const at = await boxOf(anchor);
  await anchor.click();
  // The menu grows from the anchor; the assertions hold when it is open.
  await expect(async () => {
    const boxes = await Promise.all(items.map(async (item) => {
      const box = await item.boundingBox();
      if (!box) throw new Error("The menu item has no bounds");
      return box;
    }));
    const left = Math.min(...boxes.map((box) => box.x));
    const right = Math.max(...boxes.map((box) => box.x + box.width));
    const top = Math.min(...boxes.map((box) => box.y));
    const bottom = Math.max(...boxes.map((box) => box.y + box.height));
    expect(right - left, "the menu is narrower than a bottom sheet").toBeLessThan(400);
    expect(right - left, "the menu is wider than its anchor's icon").toBeGreaterThan(150);
    expect(Math.max(left - (at.x + at.width), at.x - right), "the menu is beside the anchor").toBeLessThan(44);
    expect(Math.max(top - (at.y + at.height), at.y - bottom), "the menu is above or below the anchor").toBeLessThan(44);
  }).toPass({ timeout: 5_000 });
}

test("Flutter library shows board chrome, buckram cover colors, aligned creation controls, and card menus at the cards", async ({ page }, info) => {
  test.setTimeout(150_000);
  await page.goto("?root=opfs");
  const button = (name: string) => page.getByRole("button", { name, exact: true });
  const text = (content: string) => page.getByText(content, { exact: true });

  expect(await contrastIn(page, button("New notebook")), "New notebook is legible").toBeGreaterThan(4.5);
  await button("New notebook").click();
  await enterText(page.getByRole("textbox", { name: "Notebook title", exact: true }), "Covers");
  await addTag(page, "groups");
  await expect(text("Cover color")).toBeVisible();
  const covers: Record<string, Rgb> = {
    Navy: [0x24, 0x32, 0x4a], Oxblood: [0x5b, 0x23, 0x28], Forest: [0x2f, 0x4a, 0x3a], Ochre: [0xa8, 0x7b, 0x2c],
  };
  const swatch = async (name: string) => {
    const box = await boxOf(button(name));
    const pixels = await capture(page, { x: Math.round(box.x), y: Math.round(box.y), width: 44, height: 44 });
    // The ring lies outside the 28 px fill.
    const ring = pixels.filter((rgb, i) => Math.hypot((i % 44) - 21.5, Math.floor(i / 44) - 21.5) > 15.5 && isRibbon(rgb));
    return { center: pixels[22 * 44 + 22], ring: ring.length };
  };
  for (const [name, color] of Object.entries(covers)) {
    expect((await swatch(name)).center, `the ${name} swatch shows its color`).toEqual(color);
  }
  expect((await swatch("Navy")).ring, "the ring is on the selected swatch").toBeGreaterThan(50);
  expect((await swatch("Ochre")).ring).toBe(0);
  await button("Ochre").click();
  await expect.poll(async () => (await swatch("Ochre")).ring, { message: "the ring moves to the chosen swatch" }).toBeGreaterThan(50);
  expect((await swatch("Navy")).ring).toBe(0);

  const location = await textIn(page, await boxOf(button("My Notes")));
  expect(location.left, "the location control starts under its heading")
    .toBeCloseTo((await textIn(page, await boxOf(text("Location")))).left, -1);
  const later = await textIn(page, await boxOf(text("You can move this notebook later.")));
  expect(later.contrast, "the location note is legible").toBeGreaterThan(4.5);
  await page.screenshot({ path: info.outputPath("new-notebook.png") });
  expect(await contrastIn(page, button("Create")), "Create is legible").toBeGreaterThan(4.5);
  await button("Create").click();

  // A new notebook opens; its New Note sheet takes the notebook's tags.
  expect(await contrastIn(page, button("New note")), "New note is legible").toBeGreaterThan(4.5);
  await button("New note").click();
  await enterText(page.getByRole("textbox", { name: "Title", exact: true }), "Rings");
  const change = await textIn(page, await boxOf(button("Change notebook · Covers")));
  expect(change.left, "the notebook control starts under its heading")
    .toBeCloseTo((await textIn(page, await boxOf(text("Notebook")))).left, -1);
  // Save as template first: its scroll into view moves the heading.
  const save = await boxOf(button("Save as template"));
  const heading = await boxOf(text("Starting template"));
  for (const name of ["Save as template", "Save as draft", "Cancel", "Portrait", "Landscape"]) {
    expect(await contrastIn(page, button(name)), `${name} is legible`).toBeGreaterThan(4.5);
  }
  expect(save.y - (heading.y + heading.height), "Save as template is under the Starting template heading").toBeGreaterThanOrEqual(0);
  expect(save.y - (heading.y + heading.height)).toBeLessThan(30);
  await (await inView(button("Save as template"))).click();
  await enterText(page.getByRole("textbox", { name: "Template name", exact: true }), "Proof paper");
  await button("Save template").click();
  await expect(page.getByRole("status", { name: "Template saved", exact: true })).toBeVisible();
  await button("New note").click();
  await enterText(page.getByRole("textbox", { name: "Title", exact: true }), "Rings");
  const template = await boxOf(page.getByRole("button", { name: "Proof paper", exact: false }));
  const summary = await textIn(page, { ...template, y: template.y + template.height / 2, height: template.height / 2 });
  expect(summary.contrast, "the template summary is legible").toBeGreaterThan(4.5);
  await page.screenshot({ path: info.outputPath("new-note.png") });
  await button("Create").click();
  await closeNote(page);

  const noteMenu = ["Add favorite", "Details and tags", "Rename", "Move", "Move to trash"].map(button);
  await openMenuAt(button("Rings actions"), noteMenu);
  await page.screenshot({ path: info.outputPath("note-menu.png") });
  await button("Move to trash").click();
  await expect(button("Rings actions")).toHaveCount(0);

  await button("Back to library").click();
  const card = await boxOf(page.getByRole("button", { name: "Open Covers", exact: false }));
  // The card shows the trashed note's thumbnail until the library lists the
  // notebook again.
  await expect.poll(() => centerPixel(page, { x: card.x + card.width / 2, y: card.y + card.height / 3 }), { message: "the card has the chosen cover color" })
    .toEqual(covers.Ochre);
  expect(await centerPixel(page, { x: 105, y: 560 }), "the sidebar is board").toEqual(BOARD);
  expect((await textIn(page, await boxOf(text("Math Notes")))).contrast, "the sidebar title is legible").toBeGreaterThan(4.5);
  expect((await textIn(page, await boxOf(text("Tags")))).contrast, "the Tags heading is legible").toBeGreaterThan(4.5);
  for (const name of ["Library", "Recent", "Trash"]) {
    expect(await contrastIn(page, button(name)), `the ${name} row is legible`).toBeGreaterThan(4.5);
  }
  const tag = await boxOf(page.getByRole("button", { name: "groups", exact: false }).first());
  expect((await textIn(page, { ...tag, x: tag.x + tag.width - 40, width: 40 })).contrast, "the tag count is legible").toBeGreaterThan(4.5);
  await page.screenshot({ path: info.outputPath("library.png") });

  await openMenuAt(button("Covers notebook actions"), [button("Rename"), button("Move to trash")]);
  await page.screenshot({ path: info.outputPath("notebook-menu.png") });
  await button("Rename").click();
  await button("Cancel").click();

  await button("Trash").click();
  await openMenuAt(page.getByRole("button", { name: "Open Rings", exact: false }), [button("Restore")]);
  await page.screenshot({ path: info.outputPath("trash-menu.png") });
  await button("Restore").click();
  await button("Covers").click();
  await button("Library").click();
  await openTestNotebook(page, "Covers");
  await expect(page.getByRole("button", { name: "Open Rings", exact: false })).toBeVisible();
});

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
  const lined = await pattern("Lined");
  expect(lined.rows, "lined paper has rules").toBeGreaterThan(0);
  expect(lined.columns, "lined paper has no verticals").toBe(0);
  for (const paper of ["Grid", "Graph"]) {
    const grid = await pattern(paper);
    expect(grid.rows, `${paper} has horizontal lines`).toBeGreaterThan(0);
    expect(grid.columns, `${paper} has vertical lines`).toBeGreaterThan(0);
  }
  const dotted = await pattern("Dot");
  expect(dotted.marks, "dot paper has dots").toBeGreaterThan(0);
  expect(dotted.rows + dotted.columns, "dot paper has no lines").toBe(0);
  const blank = await pattern("Plain");
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
    await page.mouse.click(written.x, written.y, { button: "right" });
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

test("Flutter rectangle and oval selections take the handwriting inside their shapes", async ({ page }, info) => {
  test.setTimeout(90_000);
  const { box, cdp } = await openNewNote(page, "Shapes");
  const left = { x: box.x + 220, y: box.y + 180 };
  const right = { x: box.x + 460, y: box.y + 180 };
  const below = { x: box.x + 220, y: box.y + 330 };
  // Inside the oval's bounding box, but outside the oval.
  const corner = { x: right.x + 54, y: right.y + 26 };
  const spots = [left, right, below, corner];
  const paper = new Map<PenPoint, Rgb[]>();
  for (const spot of spots) paper.set(spot, await screenPixels(page, spot));
  const ink = new Map<PenPoint, number>();
  for (const spot of [left, right, below]) {
    await penStroke(cdp, line(spot.x - 40, spot.x + 40, spot.y), 0.6);
    ink.set(spot, await inkAt(page, spot, paper.get(spot)!));
  }
  await penStroke(cdp, line(corner.x - 6, corner.x + 6, corner.y, 4), 0.6);
  ink.set(corner, await inkAt(page, corner, paper.get(corner)!));
  // Where handwriting shows: each spot has its full stroke's ink or none.
  const inked = async () => {
    const shown = [];
    for (const spot of spots) {
      const now = await inkAt(page, spot, paper.get(spot)!);
      const full = ink.get(spot)!;
      expect(now < 0.1 * full || now > 0.8 * full, `ink ${now} of ${full}`).toBe(true);
      shown.push(now > 0.8 * full);
    }
    return shown;
  };
  // A tap on the selected lasso opens its modes.
  const lassoMode = async (mode: string) => {
    await page.getByRole("button", { name: "Lasso", exact: true }).click();
    await page.getByRole("button", { name: mode, exact: true }).click();
    await closePopover(page);
  };
  // A drag from corner to corner of the shape's bounding box.
  const dragBox = (center: PenPoint) =>
    penStroke(cdp, [0, 0.25, 0.5, 0.75, 1].map((t) => ({ x: center.x - 60 + 120 * t, y: center.y - 30 + 60 * t })), 0.6);
  const remove = () => page.getByRole("button", { name: "Delete selection", exact: true }).click();

  await page.getByRole("button", { name: "Lasso", exact: true }).click();
  await lassoMode("Rectangle");
  await dragBox(left);
  await remove();
  await page.screenshot({ path: info.outputPath("rectangle.png") });
  expect(await inked()).toEqual([false, true, true, true]);

  await lassoMode("Oval");
  await dragBox(right);
  await remove();
  await page.screenshot({ path: info.outputPath("oval.png") });
  expect(await inked()).toEqual([false, false, true, true]);
});

test("Flutter resizes a selection by its corner handles and duplicates it", async ({ page }, info) => {
  test.setTimeout(150_000);
  const { box, cdp } = await openNewNote(page, "Resize");
  const region = { x: Math.round(box.x) + 150, y: Math.round(box.y) + 130, width: 600, height: 450 };
  const ink = () => pixelBounds(page, region, isInk);
  const lassoAround = (b: Bounds) =>
    penStroke(cdp, [
      { x: b.left - 30, y: b.top - 30 }, { x: b.right + 30, y: b.top - 30 },
      { x: b.right + 30, y: b.bottom + 30 }, { x: b.left - 30, y: b.bottom + 30 },
      { x: b.left - 30, y: b.top - 30 },
    ], 0.6);
  const drag = (from: PenPoint, dx: number, dy: number) =>
    penStroke(cdp, [0, 0.25, 0.5, 0.75, 1].map((t) => ({ x: from.x + dx * t, y: from.y + dy * t })), 0.6);
  // The selection rectangle around the handwriting `b`. The outline's
  // bottom-right corner is 5 px inside its handle's edge; the rotate handle
  // above the rectangle hides the outline's top.
  const selectionRect = async (b: Bounds): Promise<Bounds> => {
    const outline = await pixelBounds(page, region, isOutline);
    const pad = outline.bottom - 5 - b.bottom;
    return { left: b.left - pad, right: outline.right - 5, top: b.top - pad, bottom: outline.bottom - 5 };
  };
  const clear = () => page.getByRole("button", { name: "Clear selection", exact: true }).click();

  // A slanted stroke, 80 px wide and 60 px high.
  await drag({ x: box.x + 260, y: box.y + 230 }, 80, 60);
  const written = await ink();
  await page.getByRole("button", { name: "Lasso", exact: true }).click();

  // The bottom-right handle keeps the aspect ratio.
  await lassoAround(written);
  const first = await selectionRect(written);
  await drag({ x: first.right, y: first.bottom }, size(first).width, size(first).height);
  await clear();
  await page.screenshot({ path: info.outputPath("doubled.png") });
  const doubled = await ink();
  expect(size(doubled).width / size(written).width, "the handwriting is twice as wide").toBeCloseTo(2, 0);
  expect(size(doubled).height / size(written).height, "the handwriting is twice as high").toBeCloseTo(2, 0);
  expect(Math.abs(doubled.left - written.left), "the opposite corner stays in place").toBeLessThan(6);
  expect(Math.abs(doubled.top - written.top), "the opposite corner stays in place").toBeLessThan(6);

  // The other handles scale each direction on its own: a level drag of the
  // top-right handle widens the handwriting at the same height.
  await lassoAround(doubled);
  const second = await selectionRect(doubled);
  await drag({ x: second.right, y: second.top }, size(second).width / 2, 0);
  await clear();
  await page.screenshot({ path: info.outputPath("widened.png") });
  const widened = await ink();
  expect(size(widened).width / size(doubled).width, "the handwriting is half as wide again").toBeCloseTo(1.5, 1);
  expect(size(widened).height / size(doubled).height, "the height stays").toBeCloseTo(1, 1);
  expect(Math.abs(widened.left - doubled.left), "the opposite corner stays in place").toBeLessThan(6);
  expect(Math.abs(widened.bottom - doubled.bottom), "the opposite corner stays in place").toBeLessThan(6);

  await page.getByRole("button", { name: "Undo", exact: true }).click();
  expect(await ink(), "undo restores the size before the drag").toEqual(doubled);

  // The copy appears selected, the same distance right of and below the
  // original. A drag moves it 150 px farther down.
  await lassoAround(doubled);
  await page.getByRole("button", { name: "Duplicate", exact: true }).click();
  const middle = { x: (doubled.left + doubled.right) / 2, y: (doubled.top + doubled.bottom) / 2 };
  await drag(middle, 0, 150);
  await clear();
  await page.screenshot({ path: info.outputPath("duplicated.png") });
  const both = await ink();
  const offset = both.right - doubled.right;
  expect(offset, "the copy is offset from the original").toBeGreaterThan(5);
  expect(Math.abs(both.bottom - doubled.bottom - 150 - offset), "the copy is offset the same way down").toBeLessThan(3);
  expect({ left: both.left, top: both.top }, "the original stays in place").toEqual({ left: doubled.left, top: doubled.top });
  const column = await capture(page, { x: Math.round(middle.x), y: region.y, width: 1, height: region.height });
  const runs = column.filter((rgb, i) => isInk(rgb) && !isInk(column[i - 1] ?? [255, 255, 255])).length;
  expect(runs, "a column crosses the original and the copy").toBe(2);
});

// The salmon square of fixtures/figure.jpg: 90 px wide, 15 px right of and
// 80 px below the top-left corner of the 230 × 200 px image.
const isSalmon = ([red, green, blue]: Rgb) => red > 230 && Math.abs(green - 128) < 30 && Math.abs(blue - 129) < 30;

test("Flutter inserts a JPEG figure, moves, resizes, and deletes it, and keeps it after a reload", async ({ page }, info) => {
  test.setTimeout(150_000);
  const { box, cdp } = await openNewNote(page, "Figure", "Plain");
  const region = { x: Math.round(box.x) + 100, y: Math.round(box.y) + 80, width: 900, height: 520 };
  const square = () => pixelBounds(page, region, isSalmon);
  const drag = (from: PenPoint, dx: number, dy: number) =>
    penStroke(cdp, [0, 0.25, 0.5, 0.75, 1].map((t) => ({ x: from.x + dx * t, y: from.y + dy * t })), 0.6);
  // The left, right, and bottom of the selection rectangle: its outline is
  // 5 px inside the edges of its corner handles.
  const selectionRect = async () => {
    const outline = await pixelBounds(page, region, isOutline);
    return { left: outline.left + 5, right: outline.right - 5, bottom: outline.bottom - 5 };
  };
  // Screen pixels for each point of the A4 page.
  const scale = pageIn(box).width / 595;

  // The image arrives selected, one point for each of its pixels.
  const chooser = page.waitForEvent("filechooser");
  await page.getByRole("button", { name: "Image", exact: true }).click();
  await (await chooser).setFiles("e2e/fixtures/figure.jpg");
  await expect(page.getByRole("button", { name: "Delete selection", exact: true })).toBeAttached();
  await page.screenshot({ path: info.outputPath("inserted.png") });
  const inserted = await square();
  const frame = await selectionRect();
  expect(Math.abs(size(inserted).width - 90 * scale), "the square is 90 pt wide").toBeLessThan(4);
  expect(Math.abs(size(inserted).height - 90 * scale), "the square is 90 pt high").toBeLessThan(4);
  expect(Math.abs(frame.right - frame.left - 230 * scale), "the image is 230 pt wide").toBeLessThan(4);
  expect(Math.abs(inserted.left - frame.left - 15 * scale), "the square is 15 pt from the image's left edge").toBeLessThan(4);

  // A drag inside the selection moves the image.
  await drag({ x: (inserted.left + inserted.right) / 2, y: (inserted.top + inserted.bottom) / 2 }, -180, -20);
  await page.screenshot({ path: info.outputPath("moved.png") });
  const moved = await square();
  expect(moved).toEqual({ left: inserted.left - 180, right: inserted.right - 180, top: inserted.top - 20, bottom: inserted.bottom - 20 });

  // The bottom-right handle, dragged halfway to the opposite corner, halves the image.
  const held = await selectionRect();
  const width = held.right - held.left;
  await drag({ x: held.right, y: held.bottom }, -width / 2, (-width / 2) * (200 / 230));
  await page.screenshot({ path: info.outputPath("halved.png") });
  const halved = await square();
  expect(Math.abs(size(halved).width - 45 * scale), "the square is 45 pt wide").toBeLessThan(4);
  expect(Math.abs(size(halved).height - 45 * scale), "the square is 45 pt high").toBeLessThan(4);
  expect(Math.abs(halved.left - held.left - 7.5 * scale), "the image's left edge stays in place").toBeLessThan(4);

  const salmon = async () => (await capture(page, region)).filter(isSalmon).length;
  await page.getByRole("button", { name: "Delete selection", exact: true }).click();
  expect(await salmon(), "the image is deleted").toBe(0);
  await page.getByRole("button", { name: "Undo", exact: true }).click();
  expect(await square(), "undo restores the image").toEqual(halved);

  await save(page);
  await expect(page.getByRole("status", { name: /^Notebook save/ })).toHaveAccessibleName("Notebook save Saved");
  const asset = await page.evaluate(async () => {
    const root = await navigator.storage.getDirectory();
    const notebook = await root.getDirectoryHandle("Plain");
    const dir = await notebook.getDirectoryHandle("Figure");
    const pages = await dir.getDirectoryHandle("pages");
    const svg = await (await (await pages.getFileHandle("0001.svg")).getFile()).text();
    const name = svg.match(/href="\.\.\/assets\/([0-9a-f]+\.jpg)"/)?.[1];
    if (!name) throw new Error("Saved image has no JPEG asset reference");
    const assets = await dir.getDirectoryHandle("assets");
    const file = await (await assets.getFileHandle(name)).getFile();
    return btoa(String.fromCharCode(...new Uint8Array(await file.arrayBuffer())));
  });
  expect(Buffer.from(asset, "base64")).toEqual(await readFile("e2e/fixtures/figure.jpg"));

  await page.reload();
  await openTestNotebook(page, "Plain");
  await page.getByRole("button", { name: "Open Figure", exact: false }).click();
  await page.locator('canvas[id^="ink-canvas-"]:visible').waitFor({ timeout: 30_000 });
  await page.getByRole("button", { name: "More", exact: true }).waitFor();
  await page.screenshot({ path: info.outputPath("reopened.png") });
  expect(await square(), "the image reopens at the same place and size").toEqual(halved);
});

test("Flutter places typed text boxes, wraps them at a width, and edits and deletes them", async ({ page }, info) => {
  test.setTimeout(150_000);
  const { box } = await openNewNote(page, "Typed", "Plain");
  // The page view below the toolbar, split at the middle: the wrapped box is
  // in the left half and the one-word box in the right half.
  const top = Math.round(box.y) + 120;
  const left = { x: Math.round(box.x) + 20, y: top, width: 610 - Math.round(box.x), height: 460 };
  const right = { x: 630, y: top, width: 610, height: 460 };
  const text = page.getByRole("textbox", { name: "Text", exact: true });
  const boxWidth = page.getByRole("textbox", { name: "Width (pt)", exact: true });
  const done = () => page.getByRole("button", { name: "Done", exact: true }).click();
  const clear = () => page.getByRole("button", { name: "Clear selection", exact: true }).click();
  const sentence = "Every vector space has a basis.";
  // Screen pixels for each point of the A4 page.
  const scale = pageIn(box).width / 595;

  await page.getByRole("button", { name: "Text", exact: true }).click();
  await expect(page.getByText("Insert text", { exact: true })).toBeVisible();
  await enterText(text, "Lemma");
  await done();
  await clear();
  await page.screenshot({ path: info.outputPath("inserted.png") });
  const lemma = await pixelBounds(page, right, isInk);
  const tap = { x: 120, y: top + 30 };
  await page.mouse.click(tap.x, tap.y);
  await expect(page.getByText("Insert text", { exact: true })).toBeVisible();
  await boxWidth.click();
  await expect(boxWidth).toHaveValue("300");
  await enterText(text, sentence);
  await enterText(boxWidth, "100");
  await done();
  await clear();
  await page.screenshot({ path: info.outputPath("wrapped.png") });
  const wrapped = await pixelBounds(page, left, isInk);
  // The "E" that starts the sentence.
  const firstLetter = () => pixelBounds(page, { x: tap.x - 5, y: tap.y, width: 25, height: 50 }, isInk);
  const letter = await firstLetter();
  // The last of the wrapped lines: the rows 30 px above the box's bottom.
  const lastLine = (b: Bounds) => pixelBounds(page, { x: left.x, y: b.bottom - 30, width: left.width, height: 30 }, isInk);
  const boxRight = tap.x + 100 * scale;
  expect(Math.abs(wrapped.left - tap.x), "the box starts at the tap").toBeLessThan(6);
  expect(wrapped.top - tap.y, "the box starts at the tap").toBeGreaterThanOrEqual(0);
  expect(wrapped.top - tap.y, "the box starts at the tap").toBeLessThan(25);
  expect(wrapped.right, "the lines end inside the box's width").toBeLessThan(boxRight + 2);
  expect(Math.abs((await lastLine(wrapped)).left - tap.x), "the last line starts at the box's left edge").toBeLessThan(6);

  // A tap on a box edits it. Width 0 puts the sentence on one line.
  const edit = async (at: PenPoint, content: string, width: string) => {
    await page.mouse.click(at.x, at.y);
    await expect(page.getByText("Edit text", { exact: true })).toBeVisible();
    await expect(text).toHaveValue(content);
    await boxWidth.click();
    await expect(boxWidth).toHaveValue(width);
  };
  const inside = { x: tap.x + 30, y: tap.y + 30 };
  await edit(inside, sentence, "100");
  await enterText(boxWidth, "0");
  await done();
  await clear();
  await page.screenshot({ path: info.outputPath("one-line.png") });
  // The rows of the sentence on one line, across both halves of the view.
  const firstRows = { x: left.x, y: top, width: 1200, height: 150 };
  const oneLine = await pixelBounds(page, firstRows, isInk);
  expect(size(wrapped).height, "the 100 pt box has at least three lines").toBeGreaterThan(3 * size(oneLine).height);
  expect(size(oneLine).width, "the single line is wider than 100 pt").toBeGreaterThan(100 * scale + 50);
  expect(await firstLetter(), "the box stays in place").toEqual(letter);

  // A width outside the range keeps the dialog open; Cancel keeps the box.
  await edit(inside, sentence, "0");
  await enterText(boxWidth, "-5");
  await done();
  await expect(page.getByText("Use a width from 0 to 100000 pt.", { exact: true })).toBeVisible();
  await page.screenshot({ path: info.outputPath("width-rejected.png") });
  await page.getByRole("button", { name: "Cancel", exact: true }).click();
  await clear();
  expect(await pixelBounds(page, firstRows, isInk)).toEqual(oneLine);

  // A box with no text is deleted; undo restores it.
  await edit({ x: lemma.left + 30, y: lemma.top + 10 }, "Lemma", "300");
  await focusText(text);
  await text.press("ControlOrMeta+a");
  await text.press("Backspace");
  await done();
  await page.screenshot({ path: info.outputPath("deleted.png") });
  const word = { x: lemma.left - 10, y: lemma.top - 10, width: size(lemma).width + 20, height: size(lemma).height + 20 };
  expect((await capture(page, word)).filter(isInk).length, "the empty box is deleted").toBe(0);
  await page.getByRole("button", { name: "Undo", exact: true }).click();
  expect(await pixelBounds(page, word, isInk), "undo restores the box").toEqual(lemma);

  // A right-to-left box ends its lines at the box's right edge.
  await edit(inside, sentence, "0");
  await enterText(boxWidth, "100");
  await page.getByRole("switch").click();
  await done();
  await clear();
  await page.screenshot({ path: info.outputPath("right-to-left.png") });
  const rightToLeft = await pixelBounds(page, left, isInk);
  const lastRtlLine = await lastLine(rightToLeft);
  expect(Math.abs(lastRtlLine.right - boxRight), "the last line ends at the box's right edge").toBeLessThan(8);
  expect(lastRtlLine.left, "the last line starts away from the left edge").toBeGreaterThan(tap.x + 50);

  await save(page);
  await expect(page.getByRole("status", { name: /^Notebook save/ })).toHaveAccessibleName("Notebook save Saved");
  await page.reload();
  await openTestNotebook(page, "Plain");
  await page.getByRole("button", { name: "Open Typed", exact: false }).click();
  await page.locator('canvas[id^="ink-canvas-"]:visible').waitFor({ timeout: 30_000 });
  await page.getByRole("button", { name: "More", exact: true }).waitFor();
  await expect.poll(() => pixelBounds(page, left, isInk), "the wrapped box reopens unchanged").toEqual(rightToLeft);
  await page.screenshot({ path: info.outputPath("reopened.png") });
  expect(await pixelBounds(page, word, isInk), "the one-word box reopens unchanged").toEqual(lemma);
});

test("Flutter imports a PDF, annotates its pages, and exports them with the annotations", async ({ page }, info) => {
  test.setTimeout(240_000);
  await page.goto("?root=opfs");
  await createTestNotebook(page, "Papers");
  const chooser = page.waitForEvent("filechooser");
  await page.getByRole("button", { name: "Import PDF", exact: true }).click();
  await (await chooser).setFiles("e2e/fixtures/paper.pdf");
  const canvas = page.locator('canvas[id^="ink-canvas-"]:visible');
  await canvas.waitFor({ timeout: 60_000 });
  await expect(page.getByText("1 / 2", { exact: true })).toBeVisible();
  const canvasBox = await canvas.boundingBox();
  if (!canvasBox) throw new Error("Notebook canvas has no bounds");
  const box = pageIn(canvasBox);
  const cdp = await page.context().newCDPSession(page);
  const button = (name: string) => page.getByRole("button", { name, exact: true });
  // Screen pixels for each point of the Letter page.
  const scale = box.width / 612;
  // The black bar at the top of a fixture page (paper.tex), 1 cm tall: the
  // first tall dark run in a column through it, and the bar's length along
  // the middle row of that run. The glyphs of the text are shorter runs.
  const bar = async () => {
    const dark = (await capture(page, { x: Math.round(box.x + 0.3 * box.width), y: box.y, width: 1, height: box.height })).map(isInk);
    const top = dark.findIndex((_, row) => row + 40 <= dark.length && dark.slice(row, row + 40).every(Boolean));
    if (top < 0) throw new Error("No bar crosses the column");
    const bottom = dark.indexOf(false, top);
    const y = box.y + (top + bottom) / 2;
    return { y, height: bottom - top, length: await inkLength(page, y, Math.round(box.x), Math.round(box.x + box.width)) };
  };
  // The ink in the left margin of the page around a row. The fixture's margin is blank.
  const marginInk = async (y: number) =>
    (await capture(page, { x: Math.round(box.x) + 10, y: y - 10, width: 140, height: 20 })).filter(isInk).length;

  let first = await bar();
  await expect(async () => {
    first = await bar();
    expect(first.length / box.width, "the bar of page 1 spans half the page width").toBeCloseTo(0.5, 2);
  }).toPass({ timeout: 15_000 });
  expect(first.height / first.length, "the page keeps its proportions").toBeCloseTo(28.35 / 306, 2);
  await page.screenshot({ path: info.outputPath("imported.png") });

  const note = first.y + 150;
  expect(await marginInk(note)).toBe(0);
  await penStroke(cdp, line(box.x + 20, box.x + 120, note), 0.6);
  expect(await marginInk(note), "the pen writes in the margin").toBeGreaterThan(80);

  const x = 400;
  const above = { x, y: first.y - 45 };
  const paper = await centerPixel(page, above);
  await button("Highlighter").click();
  await penStroke(cdp, [-60, -30, 0, 30, 60].map((dy) => ({ x, y: first.y + dy })), 0.6);
  const tint = await centerPixel(page, above);
  expect(brightness(paper) - brightness(tint), "the highlighter tints the page").toBeGreaterThan(30);
  expect(isInk(tint)).toBe(false);
  expect(isInk(await centerPixel(page, { x, y: first.y })), "the highlighted bar stays dark").toBe(true);
  await page.screenshot({ path: info.outputPath("annotated.png") });

  // The stroke eraser removes handwriting and leaves the imported page.
  await button("Eraser").click();
  await button("Eraser").click();
  await button("Stroke").click();
  await closePopover(page);
  await penStroke(cdp, [-40, 0, 40].map((dy) => ({ x: box.x + 70, y: note + dy })), 0.6);
  expect(await marginInk(note), "the eraser removes the pen stroke").toBe(0);
  await penStroke(cdp, [-50, 0, 50].map((dy) => ({ x: 300, y: first.y + dy })), 0.6);
  expect(await bar(), "the eraser leaves the imported page").toEqual(first);
  await button("Undo").click();
  await expect.poll(() => marginInk(note), { message: "undo restores the pen stroke" }).toBeGreaterThan(80);

  await goToPage(page, 2);
  await expect(page.getByText("2 / 2", { exact: true })).toBeVisible();
  let second = first;
  await expect(async () => {
    second = await bar();
    expect(second.length / box.width, "the bar of page 2 spans a quarter of the page width").toBeCloseTo(0.25, 2);
  }).toPass({ timeout: 15_000 });
  await button("Pen").click();
  const secondNote = second.y + 150;
  await penStroke(cdp, line(box.x + 20, box.x + 120, secondNote), 0.6);
  expect(await marginInk(secondNote), "the pen writes on page 2").toBeGreaterThan(80);
  await page.screenshot({ path: info.outputPath("second-page.png") });
  await save(page);
  await expect(page.getByRole("status", { name: /^Notebook save/ })).toHaveAccessibleName("Notebook save Saved");

  await button("More").click();
  await button("Export PDF").click();
  const download = page.waitForEvent("download");
  await button("Export").click();
  const pdfPath = info.outputPath("paper.pdf");
  await (await download).saveAs(pdfPath);
  expect(execFileSync("qpdf", ["--check", pdfPath], { encoding: "utf8" })).toContain("No syntax or stream encoding errors found");
  const infoText = execFileSync("pdfinfo", [pdfPath], { encoding: "utf8" });
  expect(infoText).toMatch(/Pages:\s+2/);
  expect(infoText).toMatch(/Page size:\s+612 x 792 pts \(letter\)/);
  // An exported page at 72 dpi: one pixel for each point, 612 in each row.
  const exported = async (pageNumber: number) => {
    const prefix = info.outputPath(`exported-${pageNumber}`);
    execFileSync("pdftoppm", ["-r", "72", "-png", "-f", `${pageNumber}`, "-l", `${pageNumber}`, "-singlefile", pdfPath, prefix]);
    const pixels = await pngPixels(page, await readFile(`${prefix}.png`));
    expect(pixels.length).toBe(612 * 792);
    return pixels;
  };
  const inkIn = (pixels: Rgb[], y: number, left: number, right: number) =>
    pixels.slice(612 * y + left, 612 * y + right).filter(isInk).length;
  // pdftoppm shows the bar of paper.pdf on rows 95 to 123; row 109 is its middle.
  for (const [pageNumber, fraction] of [[1, 0.5], [2, 0.25]]) {
    const pixels = await exported(pageNumber);
    expect(Math.abs(inkIn(pixels, 109, 0, 612) - 612 * fraction), `the bar of exported page ${pageNumber}`).toBeLessThan(4);
    // The pen stroke is 1 pt thick: gray at this resolution, on one or two rows.
    const row = 109 + Math.round(150 / scale);
    const margin = pixels.slice(612 * (row - 5), 612 * (row + 6))
      .filter((rgb, i) => i % 612 >= 20 && i % 612 < 86 && brightness(rgb) < 600).length;
    expect(margin, `the pen stroke of exported page ${pageNumber}`).toBeGreaterThan(30);
  }
  const highlighted = (await exported(1))[612 * (109 - Math.round(45 / scale)) + Math.round((x - box.x) / scale)];
  expect(isInk(highlighted)).toBe(false);
  expect(brightness(highlighted), "the exported highlight").toBeLessThan(735);

  await page.reload();
  await openTestNotebook(page, "Papers");
  await page.getByRole("button", { name: "Open paper", exact: false }).click();
  await canvas.waitFor({ timeout: 30_000 });
  await expect(page.getByText("1 / 2", { exact: true })).toBeVisible();
  await expect(async () => {
    expect(await bar(), "page 1 returns after a reload").toEqual(first);
    expect(await marginInk(note)).toBeGreaterThan(80);
  }).toPass({ timeout: 15_000 });
  await goToPage(page, 2);
  await expect(async () => {
    expect(await bar(), "page 2 returns after a reload").toEqual(second);
    expect(await marginInk(secondNote)).toBeGreaterThan(80);
  }).toPass({ timeout: 15_000 });
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

  // A drag from the undo button turns the dial to the right of it, over the
  // page (undo_dial.dart): each 1/32 turn counterclockwise undoes a step,
  // clockwise redoes one.
  const button = await page.getByRole("button", { name: "Undo", exact: true }).boundingBox();
  if (!button) throw new Error("Undo button has no bounds");
  const start = { x: button.x + button.width / 2, y: button.y + button.height / 2 };
  const center = { x: button.x + 1.3 * button.width + 2.5 * button.height, y: start.y };
  const radius = center.x - start.x;
  const at = (degrees: number) => {
    const angle = Math.PI + (degrees * Math.PI) / 180;
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

// A tap outside a popover closes it. The popover's barrier takes every pointer
// event and hides the screen behind it from the accessibility tree until the
// close transition ends, so the editor's own buttons coming back is the sign
// that the next pen event reaches the page.
async function closePopover(page: Page): Promise<void> {
  const viewport = page.viewportSize();
  if (!viewport) throw new Error("Page has no viewport");
  await page.mouse.click(viewport.width - 20, viewport.height - 20);
  await expect(page.getByRole("button", { name: "Library", exact: true })).toBeVisible();
}

// The rail's current-color dot opens the Colors popover: the swatches, the
// palette editor, and the saved pens.
// The current-color dot. Its accessible name carries the color: "Colors #1a1a1a".
const COLORS = /^Colors #[0-9a-f]{6}$/;

async function openColors(page: Page): Promise<void> {
  await page.getByRole("button", { name: COLORS }).click();
  await expect(page.getByRole("button", { name: "Edit colors", exact: true })).toBeVisible();
}

// A tap outside a popover that opened over the Colors popover closes only
// the top one.
async function backToColors(page: Page): Promise<void> {
  const viewport = page.viewportSize();
  if (!viewport) throw new Error("Page has no viewport");
  await page.mouse.click(viewport.width - 20, viewport.height - 20);
  await expect(page.getByRole("button", { name: "Edit colors", exact: true })).toBeVisible();
}

// A tap on a swatch that is not the current color chooses it and closes the
// Colors popover.
async function pickColor(page: Page, hex: string): Promise<void> {
  await openColors(page);
  await page.getByRole("button", { name: `Color ${hex}`, exact: true }).click();
  await expect(page.getByRole("button", { name: "Library", exact: true })).toBeVisible();
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
  expect((await textIn(page, await boxOf(page.getByText("Size", { exact: true })))).contrast, "the Size heading is legible").toBeGreaterThan(4.5);
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
  // Flutter web puts a slider's label on its semantics host, not on the
  // range input that has the slider role (TRAPS.md).
  const opacity = page.getByLabel("Opacity", { exact: true });
  const track = await boxOf(opacity);
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
    const bounds = await page.getByRole("img", { name: "Color wheel", exact: true }).boundingBox();
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
  await openColors(page);
  await swatches.first().click();
  await wheelDrag(45, -45);
  await wheelDrag(0, 104);
  await backToColors(page);
  const edited = await swatchColor(0);
  await closePopover(page);
  expect(saturation(edited), "the wheel makes the gray swatch a saturated color").toBeGreaterThan(100);
  const stroke = { x: box.x + 240, y: box.y + 200 };
  await penStroke(cdp, line(box.x + 140, box.x + 340, stroke.y), 0.6);
  const ink = await darkestPixel(page, stroke);
  expect(near(ink, edited), `the pen writes the swatch color: ink ${ink}, swatch ${edited}`).toBe(true);

  await openColors(page);
  await page.getByRole("button", { name: "Edit colors", exact: true }).click();
  await page.getByRole("button", { name: "Remove color #ffcf26", exact: true }).click();
  await wheelDrag(0, -104);
  await page.getByRole("button", { name: "Add color", exact: true }).click();
  await backToColors(page);
  await expect(page.getByRole("button", { name: "Color #ffcf26", exact: true })).toHaveCount(0);
  await expect(swatches).toHaveCount(5);
  const added = await swatchColor(4);
  expect(saturation(added), "the added swatch is a saturated color").toBeGreaterThan(100);
  expect(near(added, edited), "the added swatch differs from the edited one").toBe(false);

  await page.reload();
  await openTestNotebook(page);
  await page.getByRole("button", { name: "Open Palette", exact: false }).click();
  await page.locator('canvas[id^="ink-canvas-"]:visible').waitFor({ timeout: 30_000 });
  await openColors(page);
  await page.screenshot({ path: info.outputPath("palette.png") });
  await expect(swatches).toHaveCount(5);
  expect(near(await swatchColor(0), edited), "the edited swatch persists").toBe(true);
  expect(near(await swatchColor(4), added), "the added swatch persists").toBe(true);
});

// The accessible names of the controls that Tab focuses, in order, from the
// current focus.
async function tabOrder(page: Page, presses: number): Promise<string[]> {
  const names: string[] = [];
  for (let i = 0; i < presses; i++) {
    // Flutter creates a text field's input element after its focus moves, so
    // each press waits for the document focus to move.
    const before = await page.evaluateHandle(() => document.activeElement);
    await page.keyboard.press("Tab");
    await page.waitForFunction((element) => document.activeElement !== element, before);
    names.push(await page.evaluate(() => {
      const focused = document.activeElement;
      return (focused?.getAttribute("aria-label") ?? focused?.textContent ?? "").trim();
    }));
  }
  return names;
}

test("Flutter Tab reaches every editor control and finishes each library region before the next", async ({ page }) => {
  test.setTimeout(90_000);
  await page.goto("?root=opfs");
  await createTestNotebook(page);
  await page.getByRole("button", { name: "Back to library", exact: true }).click();
  await page.getByRole("button", { name: "Library", exact: true }).click();
  const library = await tabOrder(page, 16);
  const sidebar = library.indexOf("Recent"), search = library.indexOf("Search notebooks and notes");
  expect(sidebar, `the sidebar is in the Tab order: ${library}`).toBeGreaterThanOrEqual(0);
  expect(search, `the toolbar is in the Tab order: ${library}`).toBeGreaterThan(sidebar);
  expect(library.slice(sidebar, search), "Tab finishes the sidebar before the toolbar").toContain("Settings");
  // A hovered sidebar row shows a tint.
  const recent = await boxOf(page.getByRole("button", { name: "Recent", exact: true }));
  const tint = { x: recent.x + recent.width - 6, y: recent.y + recent.height / 2 };
  const idle = brightness(await centerPixel(page, tint));
  await page.getByRole("button", { name: "Recent", exact: true }).hover();
  await expect.poll(async () => brightness(await centerPixel(page, tint)), "a hovered sidebar row is tinted").toBeLessThan(idle - 10);

  await openTestNotebook(page);
  await page.getByRole("button", { name: "New note", exact: true }).click();
  await enterText(page.getByRole("textbox", { name: "Title", exact: true }), "Keys");
  await page.getByRole("button", { name: "Create", exact: true }).click();
  await page.locator('canvas[id^="ink-canvas-"]:visible').waitFor({ timeout: 30_000 });
  const editor = await tabOrder(page, 30);
  for (const name of ["Library", "Open note", "Pages", "View", "More", "Pen", "Lasso", "Insert space", "Undo", "Redo"]) {
    expect(editor, `Tab reaches ${name}`).toContain(name);
  }
  expect(editor.some((name) => COLORS.test(name)), `Tab reaches Colors: ${editor}`).toBe(true);
  expect(editor.indexOf("More"), "Tab finishes the top bar before the rail").toBeLessThan(editor.indexOf("Pen"));
});

test("Flutter floats the tool rail at the left edge beside the page and hides tools from the menus", async ({ page }, info) => {
  test.setTimeout(120_000);
  const { box } = await openNewNote(page, "Chrome");
  const button = (name: string) => page.getByRole("button", { name, exact: true });

  // The rail is a leaf panel that floats over the desk at the left edge of
  // the canvas. Each tool and history control is in it, and at zoom 1 none
  // of them covers the page.
  const pen = await boxOf(button("Pen"));
  expect(pen.x - box.x, "the rail is at the left edge of the canvas").toBeLessThan(24);
  const controls = ["Pen", "Lasso", "Insert space", "Undo", "Redo"].map((name) => [name, button(name)] as const);
  for (const [name, locator] of [...controls, ["Colors", page.getByRole("button", { name: COLORS })] as const]) {
    const control = await boxOf(locator);
    expect(control.width, `${name} is a 44 px target`).toBeGreaterThanOrEqual(44);
    expect(control.x + control.width, `${name} does not cover the page`).toBeLessThanOrEqual(pageIn(box).x);
  }
  // The whole rail fits the 720 px window without scrolling, 8 px between targets.
  const marker = await boxOf(button("Marker"));
  expect(marker.y - (pen.y + pen.height), "8 px between targets").toBeGreaterThanOrEqual(8);
  const colors = await page.getByRole("button", { name: COLORS }).boundingBox();
  if (!colors) throw new Error("Colors has no bounds");
  expect(colors.y + colors.height, "the rail fits the window").toBeLessThanOrEqual(720);
  expect(pen.y, "the rail starts below the top bar").toBeGreaterThanOrEqual(box.y);
  const rail = await centerPixel(page, { x: pen.x - 4, y: pen.y + pen.height / 2 });
  expect(rail, "the rail is leaf").toEqual([0xee, 0xf0, 0xea]);
  // The rail floats: the desk, darkened only by the rail's shadow, shows on
  // each side of it and below it.
  for (const at of [{ x: box.x + 3, y: pen.y + pen.height / 2 }, { x: pen.x + pen.width + 14, y: pen.y + pen.height / 2 }, { x: pen.x + pen.width / 2, y: colors.y + colors.height + 30 }]) {
    expect(brightness(await centerPixel(page, at)), `the desk shows around the rail at ${at.x}, ${at.y}`).toBeGreaterThan(500);
  }
  // A hovered rail button shows a tint behind its icon.
  const tint = { x: marker.x + marker.width / 2, y: marker.y + 4 };
  const idle = brightness(await centerPixel(page, tint));
  await button("Marker").hover();
  await expect.poll(async () => brightness(await centerPixel(page, tint)), "a hovered rail button is tinted").toBeLessThan(idle - 10);
  await page.mouse.move(box.x + box.width / 2, box.y + box.height / 2);
  const library = await boxOf(button("Library"));
  const topBar = await centerPixel(page, { x: 300, y: library.y + library.height / 2 });
  expect(topBar, "the top bar is board").toEqual(BOARD);
  const firstRow = await centerPixel(page, { x: box.x + 100, y: box.y + 100 });
  expect(brightness(firstRow), "the first writing row of the page is clear").toBeGreaterThan(600);
  // The page is a sheet on the desk: a desk margin shows on each side.
  for (const at of [{ x: box.x + box.width - 4, y: box.y + 200 }, { x: box.x + 200, y: box.y + 4 }]) {
    const desk = await centerPixel(page, at);
    expect(desk.every((channel, i) => Math.abs(channel - BOARD[i]) < 6), `the desk shows at ${at.x}, ${at.y}: ${desk}`).toBe(true);
  }

  await button("More").click();
  await button("Settings").click();
  await page.getByRole("switch", { name: "Insert space", exact: true }).click();
  await page.getByRole("button", { name: "Done", exact: true }).click();
  await expect(button("Insert space")).toHaveCount(0);

  await page.reload();
  await openTestNotebook(page);
  await page.getByRole("button", { name: "Open Chrome", exact: false }).click();
  await page.locator('canvas[id^="ink-canvas-"]:visible').waitFor({ timeout: 30_000 });
  await page.screenshot({ path: info.outputPath("chrome.png") });
  await expect(button("Insert space")).toHaveCount(0);
});

test("Flutter saved pen in the color menu restores its color and width after a reload", async ({ page }, info) => {
  test.setTimeout(120_000);
  const { box, cdp } = await openNewNote(page, "Saved pens");
  const penSize = async (label: string) => {
    await page.getByRole("button", { name: "Pen", exact: true }).click();
    await page.getByRole("button", { name: label, exact: true }).click();
  };
  const plainPen = async () => {
    await pickColor(page, "#1a1a1a");
    await penSize("0.6 pt");
    await closePopover(page);
  };
  const saved = page.getByRole("button", { name: "Saved pen 3.6 pt #d92d39", exact: true });
  const write = (y: number) => penStroke(cdp, line(box.x + 140, box.x + 340, y), 0.6);

  await pickColor(page, "#d92d39");
  await penSize("3.6 pt");
  await page.getByRole("button", { name: "Save pen", exact: true }).click();
  await closePopover(page);
  await openColors(page);
  await expect(saved).toBeVisible();
  await closePopover(page);
  await plainPen();
  const plain = { x: box.x + 240, y: box.y + 180 };
  await write(plain.y);
  await openColors(page);
  await saved.click();
  // The pen waits for the popover to close (TRAPS.md).
  await expect(page.getByRole("button", { name: "Library", exact: true })).toBeVisible();
  const shortcut = { x: box.x + 240, y: box.y + 260 };
  await write(shortcut.y);
  await plainPen();

  await page.reload();
  await openTestNotebook(page);
  await page.getByRole("button", { name: "Open Saved pens", exact: false }).click();
  await page.locator('canvas[id^="ink-canvas-"]:visible').waitFor({ timeout: 30_000 });
  await openColors(page);
  await saved.click();
  // The pen waits for the popover to close (TRAPS.md).
  await expect(page.getByRole("button", { name: "Library", exact: true })).toBeVisible();
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
  await page.getByRole("button", { name: "Create", exact: true }).click();
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
  await pickColor(page, "#d92d39");
  await expect.poll(() => whenSaved(() => page.evaluate(async () => {
    try {
      const root = await navigator.storage.getDirectory();
      const pens = JSON.parse(await (await (await root.getFileHandle(".pens.json")).getFile()).text());
      return { size: pens.pen.size, color: pens.pen.color };
    } catch (error) {
      if (error instanceof DOMException && error.name === "NotFoundError") return null;
      throw error;
    }
  }))).toEqual({ size: 3.6, color: "#D92D39" });

  await draw(box.y + 260);
  await save(page);
  await expect(page.getByRole("status", { name: /^Notebook save/ })).toHaveAccessibleName("Notebook save Saved");
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
  await page.getByRole("button", { name: "Create", exact: true }).click();
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
  await expect(page.getByRole("status", { name: /^Notebook save/ })).toHaveAccessibleName("Notebook save Saved");

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
  await page.getByRole("button", { name: "Pages", exact: true }).click();
  await page.getByRole("button", { name: "Add page", exact: true }).click();
  await save(page);
  await expect(page.getByRole("status", { name: /^Notebook save/ })).toHaveAccessibleName("Notebook save Saved");
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
  await expect.poll(() => whenSaved(() => page.evaluate(async () => {
    const root = await navigator.storage.getDirectory();
    const notebook = await root.getDirectoryHandle("Test Notebook");
    const dir = await notebook.getDirectoryHandle("Lecture");
    const pages = await dir.getDirectoryHandle("pages");
    return (await (await pages.getFileHandle("0001.svg")).getFile()).text();
  }))).toContain("Every basis spans the space.");
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
  await goToPage(page, 2);
  await expect(page.getByText("2 / 2", { exact: true })).toBeVisible();
  await page.getByRole("button", { name: "Library", exact: true }).click();
  await page.getByRole("button", { name: "New note", exact: true }).click();
  await enterText(page.getByRole("textbox", { name: "Title" }), "Exercises");
  await page.getByRole("button", { name: "Create", exact: true }).click();
  await page.getByRole("button", { name: "Lecture", exact: true }).click();
  await expect(page.getByText("2 / 2", { exact: true })).toBeVisible();
  await page.getByRole("button", { name: "Library", exact: true }).click();
  await page.getByRole("button", { name: "Lecture actions", exact: true }).click();
  await page.getByRole("button", { name: "Add favorite", exact: true }).click();
  await page.getByText("Favorites", { exact: true }).click();
  await expect(page.getByRole("button", { name: "Open Lecture", exact: false })).toBeVisible();
  await expect(page.getByRole("button", { name: "Open Exercises", exact: false })).not.toBeVisible();
  await expect.poll(() => whenSaved(() => page.evaluate(async () => {
    const root = await navigator.storage.getDirectory();
    const metadata = JSON.parse(await (await (await root.getFileHandle(".library.json")).getFile()).text());
    return metadata.notes["Test Notebook/Lecture"]?.favorite;
  }))).toBe(true);
  await page.context().setOffline(true);
  await page.reload();
  await openTestNotebook(page);
  await page.getByRole("button", { name: "Open Lecture", exact: false }).click();
  await expect(page.getByText("1 / 2", { exact: true })).toBeVisible();
  await page.getByRole("button", { name: "Pages", exact: true }).click();
  await page.getByRole("button", { name: "Add page", exact: true }).click();
  await save(page);
  await expect(page.getByRole("status", { name: /^Notebook save/ })).toHaveAccessibleName("Notebook save Saved");
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
  await page.getByRole("button", { name: "Create", exact: true }).click();
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
  await page.getByRole("button", { name: "New notebook", exact: true }).click();
  await enterText(page.getByRole("textbox", { name: "Notebook title", exact: true }), "Tools");
  await page.getByRole("button", { name: "Create", exact: true }).click();
  await page.getByRole("button", { name: "New note", exact: true }).click();
  await enterText(page.getByRole("textbox", { name: "Title", exact: true }), "Pens");
  await page.getByRole("button", { name: "Create", exact: true }).click();
  await page.locator('canvas[id^="ink-canvas-"]').waitFor();
  // The first tap selects the marker; a tap on the selected marker opens its settings.
  await page.getByRole("button", { name: "Marker", exact: true }).click();
  await page.getByRole("button", { name: "Marker", exact: true }).click();
  await page.getByRole("button", { name: "3.6 pt", exact: true }).click();
  await page.screenshot({ path: info.outputPath("marker-popover.png") });
  const viewport = page.viewportSize();
  if (!viewport) throw new Error("Page has no viewport");
  await page.mouse.click(viewport.width - 20, viewport.height - 20);
  // A read during the app's write of the file throws; the next read succeeds.
  await expect(async () => expect(await page.evaluate(async () => {
    const root = await navigator.storage.getDirectory();
    const pens = JSON.parse(await (await (await root.getFileHandle(".pens.json")).getFile()).text());
    return { pen: pens.pen, marker: pens.marker };
  })).toMatchObject({ pen: { brush: "pressure-pen", size: 1.2 }, marker: { brush: "marker", size: 3.6 } })).toPass({ timeout: 15_000 });
});

test("Flutter two-page layout puts pen input on the right page and shares a PDF", async ({ page }) => {
  test.setTimeout(120_000);
  await page.goto("?root=opfs");
  await page.evaluate(() => localStorage.removeItem("pageArrangement"));
  await beginTestNote(page, "Spread");
  await page.getByRole("button", { name: "Create", exact: true }).click();
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
  await expect(page.getByRole("status", { name: /^Notebook save/ })).toHaveAccessibleName("Notebook save Saved");
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

// The pages in the files of a note, in document order: the file of each page,
// its SVG size, and its stroke count.
function storedPages(page: Page, title: string, notebook = "Test Notebook") {
  return whenSaved(() => page.evaluate(async ({ title, notebook }) => {
    const root = await navigator.storage.getDirectory();
    const dir = await (await root.getDirectoryHandle(notebook)).getDirectoryHandle(title);
    const manifest = JSON.parse(await (await (await dir.getFileHandle("notebook.json")).getFile()).text());
    const pages = await dir.getDirectoryHandle("pages");
    const saved = [];
    for (const entry of manifest.pages as { file: string }[]) {
      const svg = await (await (await pages.getFileHandle(entry.file.replace("pages/", ""))).getFile()).text();
      const parsed = new DOMParser().parseFromString(svg, "image/svg+xml");
      saved.push({
        file: entry.file,
        size: parsed.documentElement.getAttribute("viewBox")?.split(" ").slice(2).map(Number),
        strokes: svg.match(/<path id="s-/g)?.length ?? 0,
        ruling: parsed.getElementById("background")?.getAttribute("mn:ruling"),
        text: Array.from(parsed.querySelectorAll("text"), (box) => box.textContent).join("\n"),
      });
    }
    return saved;
  }, { title, notebook }));
}

async function savedPages(page: Page, title: string, notebook = "Test Notebook") {
  await save(page);
  await expect(page.getByRole("status", { name: /^Notebook save/ })).toHaveAccessibleName("Notebook save Saved");
  return storedPages(page, title, notebook);
}

test("Flutter inserts pages before and after a page, deletes a page, and sizes new pages", async ({ page }, info) => {
  test.setTimeout(240_000);
  const { box, cdp } = await openNewNote(page, "Inserts");
  const button = (name: string) => page.getByRole("button", { name, exact: true });
  const choose = async (menu: string, item: string) => {
    await button(menu).click();
    await button(item).click();
  };
  const goTo = async (number: number) => {
    await choose("Pages", "Go to page");
    await enterText(page.getByRole("textbox"), `${number}`);
    await page.screenshot({ path: info.outputPath("go-to-page.png") });
    await button("Go").click();
    await expect(page.getByText(new RegExp(`^${number} / \\d$`))).toBeVisible();
  };
  await penStroke(cdp, line(box.x + 150, box.x + 300, box.y + 250), 0.6);

  await choose("Pages", "Insert page before");
  await expect(page.getByText(/^\d \/ 2$/)).toBeVisible();
  await goTo(2);
  await choose("Pages", "Insert page after");
  await expect(page.getByText("2 / 3", { exact: true })).toBeVisible();
  expect((await savedPages(page, "Inserts")).map(({ file, strokes }) => ({ file, strokes }))).toEqual([
    { file: "pages/0002.svg", strokes: 0 },
    { file: "pages/0001.svg", strokes: 1 },
    { file: "pages/0003.svg", strokes: 0 },
  ]);
  const strokes = async () => (await savedPages(page, "Inserts")).map(({ strokes }) => strokes);
  await choose("Pages", "Clear page");
  expect(await strokes(), "Clear page removes the handwriting of the current page").toEqual([0, 0, 0]);
  await button("Undo").click();
  expect(await strokes(), "undo restores the cleared page").toEqual([0, 1, 0]);
  await goTo(1);
  await goTo(2);

  const a4 = [595.28, 841.89], letter = [612, 792];
  // One control changes at a time: the sheet shows the current size and
  // orientation, and the other control keeps its value.
  const papers: [string, number[]][] = [
    ["Letter", letter],
    ["Landscape", letter.toReversed()],
    ["A4", a4.toReversed()],
    ["Portrait", a4],
  ];
  for (const [index, [control]] of papers.entries()) {
    await choose("Pages", "Paper for new pages");
    await expect(button("Done")).toBeVisible();
    if (index === 1) await page.screenshot({ path: info.outputPath("paper-sheet.png") });
    await button(control).click();
    await button("Done").click();
    await choose("Pages", "Add page");
    await expect(page.getByText(`2 / ${4 + index}`, { exact: true })).toBeVisible();
  }
  expect((await savedPages(page, "Inserts")).map(({ size }) => size), "a new page takes the chosen size")
    .toEqual([a4, a4, a4, ...papers.map(([, size]) => size)]);
  await goTo(4);
  await page.screenshot({ path: info.outputPath("letter-landscape.png") });

  await button("Pages").click();
  expect(await contrastIn(page, button("Delete page")), "Delete page is legible").toBeGreaterThan(4.5);
  await button("Delete page").click();
  await expect(page.getByText(/^\d \/ 6$/)).toBeVisible();
  // The pointer rests on the toast, which holds it open.
  const toast = page.getByRole("status", { name: "Page 4 deleted", exact: true });
  await toast.hover();
  expect((await savedPages(page, "Inserts")).map(({ size }) => size), "the landscape Letter page is deleted")
    .toEqual([a4, a4, a4, ...papers.slice(1).map(([, size]) => size)]);
  await page.screenshot({ path: info.outputPath("delete-toast.png") });
  // The toast's Undo restores the page.
  await expect(toast).toBeVisible();
  await button("Undo").last().click();
  await expect(page.getByText(/^\d \/ 7$/)).toBeVisible();
  await goTo(2);
  await choose("Pages", "Delete page");
  await expect(page.getByText("2 / 6", { exact: true })).toBeVisible();
  expect((await savedPages(page, "Inserts")).map(({ strokes }) => strokes), "the written page is deleted").toEqual([0, 0, 0, 0, 0, 0]);

  // The paper style of new pages; the pages that exist keep theirs.
  const rulings = async () => (await savedPages(page, "Inserts")).map(({ ruling }) => ruling);
  const before = await rulings();
  await choose("Pages", "Paper for new pages");
  await button("Lined paper").click();
  await button("Done").click();
  await choose("Pages", "Add page");
  await expect(page.getByText("2 / 7", { exact: true })).toBeVisible();
  expect(await rulings(), "the new page is lined").toEqual([...before, "lined"]);
});

test("Flutter horizontal scroll puts the pages side by side, pans across them, and persists", async ({ page }, info) => {
  test.setTimeout(120_000);
  const { box, cdp } = await openNewNote(page, "Sideways");
  const button = (name: string) => page.getByRole("button", { name, exact: true });
  for (const count of [2, 3, 4, 5]) {
    await button("Pages").click();
    await button("Add page").click();
    await expect(page.getByText(`1 / ${count}`, { exact: true })).toBeVisible();
  }
  await button("View").click();
  await button("Horizontal scroll").click();
  await expect(button("Library"), "the menu closes before the pen writes (TRAPS.md)").toBeVisible();
  const strokes = async () => (await savedPages(page, "Sideways")).map((saved) => saved.strokes);
  // A page fits the view height, so the view holds more than two A4 pages.
  const pageWidth = box.height * 595.28 / 841.89;
  const y = box.y + box.height / 2;
  await penStroke(cdp, line(box.x + 100, box.x + 200, y), 0.6);
  await penStroke(cdp, line(box.x + pageWidth + 100, box.x + pageWidth + 200, y), 0.6);
  expect(await strokes(), "the second page is beside the first").toEqual([1, 1, 0, 0, 0]);
  await page.screenshot({ path: info.outputPath("horizontal.png") });
  const shown = await page.getByText(/^\d \/ 5$/).textContent();
  // One finger pans the pages to the left, to the end of the row.
  for (let pan = 0; pan < 2; ++pan) {
    await cdp.send("Input.dispatchTouchEvent", { type: "touchStart", touchPoints: [{ id: 1, x: 1100, y }] });
    for (const x of [1000, 800, 600, 400, 200]) {
      await cdp.send("Input.dispatchTouchEvent", { type: "touchMove", touchPoints: [{ id: 1, x, y }] });
    }
    await cdp.send("Input.dispatchTouchEvent", { type: "touchEnd", touchPoints: [] });
  }
  await expect(page.getByText(/^\d \/ 5$/), "the pan changes the shown page").not.toHaveText(shown!);
  // The pan overscrolls past the last page, and the bounce back takes a
  // moment; a pen-down beyond the page draws nothing.
  await settled(page, { x: box.x, y, width: box.width, height: 1 });
  await penStroke(cdp, line(box.x + box.width - 300, box.x + box.width - 200, y), 0.6);
  expect(await strokes(), "the last page is at the right edge after the pan").toEqual([1, 1, 0, 0, 1]);
  await page.screenshot({ path: info.outputPath("last-page.png") });
  await button("View").click();
  await expect(page.getByRole("button", { name: /Fit height$/ })).toBeVisible();
  await closePopover(page);

  await page.reload();
  await openTestNotebook(page);
  await page.getByRole("button", { name: "Open Sideways", exact: false }).click();
  await page.locator('canvas[id^="ink-canvas-"]:visible').waitFor({ timeout: 30_000 });
  await button("View").click();
  await expect(page.getByRole("button", { name: /^\S+ Horizontal scroll$/ })).toHaveAttribute("aria-current", "true");
  await page.getByRole("button", { name: "Vertical scroll", exact: true }).click();
  await button("View").click();
  await expect(page.getByRole("button", { name: /^\S+ Vertical scroll$/ })).toHaveAttribute("aria-current", "true");
  await expect(page.getByRole("button", { name: /Fit width$/ })).toBeVisible();
});

test("Flutter renames a note with its pages, sorts the notes, and search lists the matching titles only", async ({ page }, info) => {
  test.setTimeout(150_000);
  await page.goto("?root=opfs");
  await beginTestNote(page, "Rings", "Shelf");
  await page.getByRole("button", { name: "Create", exact: true }).click();
  const canvas = page.locator('canvas[id^="ink-canvas-"]:visible');
  await canvas.waitFor({ timeout: 30_000 });
  const box = await canvas.boundingBox();
  if (!box) throw new Error("Notebook canvas has no bounds");
  const cdp = await page.context().newCDPSession(page);
  const button = (name: string) => page.getByRole("button", { name, exact: true });
  const card = (title: string) => page.getByRole("button", { name: `Open ${title}`, exact: false });
  await penStroke(cdp, line(box.x + 150, box.x + 300, box.y + 250), 0.6);
  await save(page);
  await expect(page.getByRole("status", { name: /^Notebook save/ })).toHaveAccessibleName("Notebook save Saved");
  await button("Library").click();
  await button("New note").click();
  await enterText(page.getByRole("textbox", { name: "Title", exact: true }), "Fields");
  await button("Create").click();
  // Rings stays open in a tab with its canvas, so the new tab is the sign
  // that Fields is open.
  await expect(button("Close Fields")).toBeVisible({ timeout: 30_000 });
  await button("Library").click();
  await expect(card("Fields")).toBeVisible();

  await button("Rings actions").click();
  await button("Rename").click();
  await enterText(page.getByRole("textbox", { name: "Name", exact: true }), "Modules");
  await button("Rename").click();
  await expect(card("Modules")).toBeVisible();
  await expect(card("Rings")).toHaveCount(0);
  await card("Modules").click();
  await expect(button("Close Modules")).toBeVisible();
  expect(await contrastIn(page, button("Modules")), "the active tab is legible").toBeGreaterThan(4.5);
  expect(await contrastIn(page, button("Fields")), "the other tab is legible").toBeGreaterThan(4.5);
  const saved = await savedPages(page, "Modules", "Shelf");
  expect(saved.map(({ strokes }) => strokes), "the renamed note keeps its handwriting").toEqual([1]);
  expect(await page.evaluate(async () => {
    const root = await navigator.storage.getDirectory();
    return Array.fromAsync((await root.getDirectoryHandle("Shelf")).keys());
  })).not.toContain("Rings");
  await button("Library").click();

  const left = async (title: string) => (await boxOf(card(title))).x;
  const top = async (title: string) => (await boxOf(card(title))).y;
  const sort = async (item: string) => {
    await button("Sort").click();
    // The current choice carries a check mark before its name.
    await page.getByRole("button", { name: new RegExp(`^(\\S )?${item}$`) }).click();
  };
  await sort("Name");
  await sort("Z to A");
  await expect.poll(async () => (await left("Modules")) < (await left("Fields")), { message: "Z to A puts Modules first" }).toBe(true);
  await sort("A to Z");
  await expect.poll(async () => (await left("Fields")) < (await left("Modules")), { message: "A to Z puts Fields first" }).toBe(true);
  // Modules was saved after Fields was made.
  await sort("Date modified");
  await sort("Newest first");
  await expect.poll(async () => (await left("Modules")) < (await left("Fields")), { message: "the newest note is first" }).toBe(true);
  await sort("Oldest first");
  await expect.poll(async () => (await left("Fields")) < (await left("Modules")), { message: "the oldest note is first" }).toBe(true);
  await sort("List");
  await expect.poll(async () => (await top("Fields")) < (await top("Modules")), { message: "the list puts one note on each row" }).toBe(true);
  expect(await left("Fields")).toBe(await left("Modules"));
  await page.screenshot({ path: info.outputPath("list.png") });
  await sort("Grid");
  await expect.poll(async () => (await top("Fields")) === (await top("Modules"))).toBe(true);

  await button("Back to library").click();
  await button("Search").click();
  const search = page.getByRole("textbox", { name: "Search notebooks and notes", exact: true });
  await expect(search).toBeFocused();
  await page.keyboard.type("Mod");
  await expect(search).toHaveValue("Mod");
  await expect(card("Modules")).toBeVisible();
  await expect(card("Fields")).toHaveCount(0);
  // The notebook that holds a matching note shows too.
  await expect(card("Shelf")).toBeVisible();
  await page.screenshot({ path: info.outputPath("search.png") });
  await enterText(search, "Rings");
  await expect(search).toHaveValue("Rings");
  await expect(page.getByText('Nothing matches "Rings".', { exact: true })).toBeVisible();
  await expect(card("Modules")).toHaveCount(0);
  await expect(card("Shelf")).toHaveCount(0);
  await button("Clear search").click();
  await expect(search).toHaveValue("");
  await expect(card("Shelf")).toBeVisible();
  await enterText(search, "shelf");
  await expect(card("Modules")).toHaveCount(0);
  await card("Shelf").click();
  await card("Modules").click();

  await button("Open note").click();
  const filter = page.getByRole("textbox", { name: "Search", exact: true });
  await filter.click();
  await page.keyboard.type("Fie");
  await expect(filter).toHaveValue("Fie");
  await page.screenshot({ path: info.outputPath("picker.png") });
  await expect(page.getByRole("group", { name: "Modules Shelf", exact: true })).toHaveCount(0);
  await page.getByRole("group", { name: "Fields Shelf", exact: true }).click();
  await expect(page.getByRole("heading", { name: "Fields", exact: true })).toBeVisible();
});

test("Flutter saves handwriting without a Save tap and shows it after a reload", async ({ page }) => {
  test.setTimeout(120_000);
  const { box, cdp } = await openNewNote(page, "Unattended");
  const button = (name: string) => page.getByRole("button", { name, exact: true });
  const stored = (strokes: number[], message: string) => expect(async () => {
    expect((await storedPages(page, "Unattended")).map((saved) => saved.strokes), message).toEqual(strokes);
  }).toPass({ timeout: 15_000 });
  const y = box.y + 250;
  const inked = async () => (await capture(page, { x: box.x + 225, y: y - 10, width: 1, height: 20 })).some(isInk);
  await penStroke(cdp, line(box.x + 150, box.x + 300, y), 0.6);
  await stored([1], "the stroke reaches the note file");
  await button("Undo").click();
  await stored([0], "the undo reaches the note file");
  await button("Redo").click();
  await stored([1], "the redo reaches the note file");
  await button("Pages").click();
  await button("Add page").click();
  await stored([1, 0], "the new page reaches the note file");

  await page.reload();
  await openTestNotebook(page);
  await page.getByRole("button", { name: "Open Unattended", exact: false }).click();
  await page.locator('canvas[id^="ink-canvas-"]:visible').waitFor({ timeout: 30_000 });
  await expect(page.getByText("1 / 2", { exact: true })).toBeVisible();
  await expect.poll(inked, { message: "the handwriting returns" }).toBe(true);
});

test("Flutter creates a note in each page size and orientation", async ({ page }) => {
  test.setTimeout(150_000);
  await page.goto("?root=opfs");
  await createTestNotebook(page);
  const button = (name: string) => page.getByRole("button", { name, exact: true });
  const a4 = [595.28, 841.89], letter = [612, 792];
  const papers: [string, string, number[]][] = [
    ["A4", "Portrait", a4],
    ["A4", "Landscape", a4.toReversed()],
    ["Letter", "Portrait", letter],
    ["Letter", "Landscape", letter.toReversed()],
  ];
  for (const [paper, orientation, size] of papers) {
    const title = `${paper} ${orientation}`;
    await button("New note").click();
    await enterText(page.getByRole("textbox", { name: "Title", exact: true }), title);
    await button(paper).click();
    await button(orientation).click();
    await button("Create").click();
    await expect(page.getByRole("heading", { name: title, exact: true })).toBeVisible({ timeout: 30_000 });
    expect((await savedPages(page, title)).map((saved) => saved.size), title).toEqual([size]);
    await button("Pages").click();
    await button("Add page").click();
    await expect(page.getByText("1 / 2", { exact: true })).toBeVisible();
    expect((await savedPages(page, title)).map((saved) => saved.size), `${title}, second page`).toEqual([size, size]);
    await button("Library").click();
  }
});

// Lined paper on the screen, and words written on it. `rules` holds the
// screen rows of the rules below the top of the view; `find` reads them again
// after the page scrolls.
async function linedPaper(page: Page, cdp: CDPSession, box: Box) {
  // The rules of the paper below a screen row: the middle row of each thin
  // run that is darker than the paper, in a column with no handwriting.
  const rulesBelow = async (top: number) => {
    const height = Math.floor(box.y + box.height - 10 - top);
    const column = await capture(page, { x: box.x + box.width - 100, y: top, width: 1, height });
    const paper = column.reduce((best, rgb) => (brightness(rgb) > brightness(best) ? rgb : best));
    const found: number[] = [];
    let run: number[] = [];
    column.forEach((rgb, i) => {
      if (brightness(paper) - brightness(rgb) > 20) return run.push(top + i);
      if (run.length > 0 && run.length <= 4) found.push(run[Math.floor(run.length / 2)]);
      run = [];
    });
    return found;
  };
  let rules = await rulesBelow(Math.round(box.y + 120));
  const spacing = rules[1] - rules[0];
  const middle = (band: number) => rules[band] + spacing / 2;
  // The red margin line and the right edge of the page, which fills the width.
  const row = await capture(page, { x: box.x, y: Math.round(middle(0)), width: 300, height: 1 });
  const margin = box.x + row.reduce((best, rgb, i) => (rgb[0] - rgb[2] > row[best][0] - row[best][2] ? i : best), 0);
  expect(row[margin - box.x][0] - row[margin - box.x][2], "the paper has a margin line").toBeGreaterThan(25);
  const edge = box.x + box.width;

  // A word: one zigzag stroke, 70 px wide, in the band below rule `band`.
  const word = (left: number, band: number) =>
    penStroke(cdp, Array.from({ length: 8 }, (_, i) => ({
      x: margin + left + 10 * i, y: middle(band) + (i % 2 ? 0.2 : -0.2) * spacing,
    })), 0.6);
  // The words in a band: the screen columns of each run of ink, where a gap
  // of 6 px ends a run.
  const words = async (band: number) => {
    const left = margin + 8, width = edge - left;
    const pixels = await capture(page, { x: left, y: rules[band] + 3, width, height: Math.round(spacing) - 6 });
    const inked = new Array<boolean>(width).fill(false);
    pixels.forEach((rgb, i) => { if (isInk(rgb)) inked[i % width] = true; });
    const runs: { left: number; right: number }[] = [];
    inked.forEach((ink, i) => {
      if (!ink) return;
      const last = runs.at(-1);
      if (last && left + i - last.right < 6) last.right = left + i;
      else runs.push({ left: left + i, right: left + i });
    });
    return runs;
  };
  // The band shows words that start at these distances from the margin.
  const shows = (band: number, lefts: number[], message: string) =>
    expect.poll(async () => (await words(band)).map(({ left }) =>
      lefts.find((expected) => Math.abs(left - margin - expected) <= 4) ?? left - margin), { message }).toEqual(lefts);
  return {
    get rules() { return rules; },
    find: async (top: number) => { rules = await rulesBelow(top); },
    spacing, middle, margin, edge, word, words, shows,
  };
}

const heldPen = { pointerType: "pen" as const, force: 0.6, button: "left" as const };

// The pen, which is down, moves.
async function penDrag(cdp: CDPSession, from: PenPoint, to: PenPoint): Promise<void> {
  const steps = Math.ceil(Math.hypot(to.x - from.x, to.y - from.y) / 20);
  for (let step = 1; step <= steps; ++step) {
    await cdp.send("Input.dispatchMouseEvent", {
      type: "mouseMoved", buttons: 1, ...heldPen,
      x: from.x + ((to.x - from.x) * step) / steps, y: from.y + ((to.y - from.y) * step) / steps,
    });
  }
}

// The pen goes down and moves, and stays down.
async function penHold(cdp: CDPSession, from: PenPoint, to: PenPoint): Promise<void> {
  await cdp.send("Input.dispatchMouseEvent", { type: "mousePressed", clickCount: 1, ...from, ...heldPen });
  await penDrag(cdp, from, to);
}

async function penRelease(cdp: CDPSession, at: PenPoint): Promise<void> {
  await cdp.send("Input.dispatchMouseEvent", { type: "mouseReleased", clickCount: 1, ...at, ...heldPen });
}

test("Flutter insert space moves the handwriting with the pen in each mode, and onto a new page", async ({ page }, info) => {
  test.setTimeout(240_000);
  await page.goto("?root=opfs");
  await beginTestNote(page, "Space", "Space notes");
  const button = (name: string) => page.getByRole("button", { name, exact: true });
  await button("Lined").click();
  await button("Landscape").click();
  await button("Create").click();
  const canvas = page.locator('canvas[id^="ink-canvas-"]:visible');
  await canvas.waitFor({ timeout: 30_000 });
  const box = await boxOf(canvas);
  const cdp = await page.context().newCDPSession(page);
  const paper = await linedPaper(page, cdp, pageIn(box));
  const { spacing, middle, margin, edge, word, words, shows } = paper;
  // The ink of the lone word, which the vertical and horizontal modes move off the bands.
  const lone = () => pixelBounds(page, {
    x: margin + 150, y: paper.rules[4], width: 450, height: Math.round(4 * spacing),
  }, isInk);

  const hold = (from: PenPoint, to: PenPoint) => penHold(cdp, from, to);
  const release = (at: PenPoint) => penRelease(cdp, at);
  // A tap on the selected tool opens its modes.
  const spaceMode = async (mode: string) => {
    await button("Insert space").click();
    await button(mode).click();
    await closePopover(page);
  };
  const strokes = async () => (await savedPages(page, "Space", "Space notes")).map((saved) => saved.strokes);

  await word(60, 1);
  await word(220, 1);
  await word(380, 1);
  await word(60, 2);
  await word(220, 4);
  await shows(1, [60, 220, 380], "three words on a line");
  await button("Insert space").click();

  // Reflow, the first mode: the rest of the line follows the pen.
  let from = { x: margin + 175, y: middle(1) };
  let to = { x: from.x + 120, y: from.y };
  await hold(from, to);
  await page.screenshot({ path: info.outputPath("rest-of-line.png") });
  await shows(1, [60, 340, 500], "the words after the pen follow it while it is down");
  await shows(2, [60], "the next line stays");
  const lines = { x: margin - 60, y: paper.rules[0], width: 700, height: Math.round(6 * spacing) };
  expect((await capture(page, lines)).filter(isOutline).length, "the drag shows the ink, with no selection band").toBe(0);
  await release(to);
  await shows(1, [60, 340, 500], "the release keeps the words where the drag showed them");

  // A word pushed past the end of the line goes to the start of the next
  // line, and the word of that line moves right of it.
  const [, , third] = await words(1);
  const [next] = await words(2);
  const dx = edge - third.right + 20;
  const pushed = next.left - margin + (third.right - third.left) + 1.25 * 0.3 * spacing;
  to = { x: from.x + dx, y: from.y };
  await hold(from, to);
  await page.screenshot({ path: info.outputPath("reflow.png") });
  await shows(1, [60, 340 + dx], "the last word leaves the line");
  await shows(2, [60, pushed], "the last word starts the next line and pushes its word right");
  await release(to);
  await shows(2, [60, pushed], "the release keeps the reflow");
  await button("Undo").click();
  await shows(1, [60, 340, 500], "one undo restores the line");
  await shows(2, [60], "one undo restores the next line");

  // A drag from the margin moves whole lines.
  from = { x: margin - 40, y: middle(1) };
  to = { x: from.x, y: middle(3) };
  await hold(from, to);
  await page.screenshot({ path: info.outputPath("whole-lines.png") });
  await shows(1, [], "the line leaves its band");
  await shows(3, [60, 340, 500], "the line is two lines lower");
  await shows(4, [60], "the second line is two lines lower");
  await shows(6, [220], "the last line is two lines lower");
  await release(to);
  await shows(3, [60, 340, 500], "the release keeps the lines");
  expect(await strokes()).toEqual([5]);

  // A drag up deletes the ink that it passes and closes the gap.
  from = { x: margin - 40, y: middle(6) };
  to = { x: from.x, y: middle(4) };
  await hold(from, to);
  await page.screenshot({ path: info.outputPath("erase.png") });
  await shows(4, [220], "the lower line takes the place of the line the pen passed");
  await shows(6, [], "the lower line leaves its band");
  await shows(3, [60, 340, 500], "the line above the pen stays");
  await release(to);
  expect(await strokes()).toEqual([4]);
  await button("Undo").click();
  await shows(4, [60], "one undo restores the deleted word");
  await shows(6, [220], "one undo restores the moved line");
  await button("Redo").click();
  await shows(4, [220], "the redo repeats the deletion and the move");

  // Vertical: the ink below the pen moves by the drag, off the lines.
  await spaceMode("Vertical");
  const before = await lone();
  from = { x: margin + 400, y: paper.rules[4] + 2 };
  to = { x: from.x, y: from.y + 1.5 * spacing };
  await hold(from, to);
  await page.screenshot({ path: info.outputPath("vertical.png") });
  await expect.poll(async () => Math.round((2 * ((await lone()).top - before.top)) / spacing) / 2,
    { message: "the word below the pen is one and a half lines lower" }).toBe(1.5);
  await shows(3, [60, 340, 500], "the line above the pen stays");
  await release(to);

  // Horizontal: the ink right of the pen moves sideways, on every line.
  await spaceMode("Horizontal");
  from = { x: margin + 175, y: middle(1) };
  to = { x: from.x + 100, y: from.y };
  await hold(from, to);
  await page.screenshot({ path: info.outputPath("horizontal.png") });
  await shows(3, [60, 440, 600], "the words right of the pen move with it");
  await expect.poll(async () => Math.round(((await lone()).left - before.left) / 10) * 10,
    { message: "the lower word right of the pen moves with it" }).toBe(100);
  await release(to);
  // The ink stops at the right edge of the page.
  const [, , last] = await words(3);
  const room = edge - 1 - last.right;
  to = { x: edge - 20, y: from.y };
  await hold(from, to);
  await page.screenshot({ path: info.outputPath("edge.png") });
  await shows(3, [60, 440 + room, 600 + room], "the words stop where the last word meets the page edge");
  await release(to);
  await expect(page.getByText("1 / 1", { exact: true })).toBeVisible();
  await button("Undo").click();
  await shows(3, [60, 440, 600], "one undo restores the words");

  // Vertical at the foot of the page: the ink that passes the bottom goes to
  // a new page.
  await page.mouse.move(box.x + box.width / 2, box.y + box.height / 2);
  await page.mouse.wheel(0, 4000);
  // The hint shows at the end of the notebook: the foot of the page is in view.
  await expect(page.getByText("Pull and hold to add a page", { exact: true })).toBeVisible();
  await paper.find(Math.round(box.y + 180));
  const foot = paper.rules.length - 4;
  await button("Pen").click();
  await word(220, foot);
  await shows(foot, [220], "a word near the foot of the page");
  await button("Insert space").click();
  await spaceMode("Vertical");
  from = { x: margin + 400, y: paper.rules[foot - 3] + 2 };
  to = { x: from.x, y: box.y + box.height - 6 };
  await hold(from, to);
  await page.screenshot({ path: info.outputPath("overflow.png") });
  await shows(foot, [], "the word leaves the page while the pen is down");
  await release(to);
  await expect(page.getByText(/^\d \/ 2$/)).toBeVisible();
  expect(await strokes()).toEqual([4, 1]);
  await button("Undo").click();
  await expect(page.getByText("1 / 1", { exact: true })).toBeVisible();
  expect(await strokes()).toEqual([5]);

  // The saved note reopens with the word on the new page.
  await button("Redo").click();
  expect(await strokes()).toEqual([4, 1]);
  await page.reload();
  await openTestNotebook(page, "Space notes");
  await page.getByRole("button", { name: "Open Space", exact: false }).click();
  await canvas.waitFor({ timeout: 30_000 });
  await expect(page.getByText("1 / 2", { exact: true })).toBeVisible();
  await paper.find(Math.round(pageIn(box).y + 120));
  await shows(3, [60, 440, 600], "the first page reopens with its words in place");
  await goToPage(page, 2);
  await expect(page.getByText("2 / 2", { exact: true })).toBeVisible();
  await page.screenshot({ path: info.outputPath("reopened.png") });
  // The push put the word three lines below the top of the page, below the tool bar.
  const carried = await pixelBounds(page, {
    x: Math.round(margin + 200), y: Math.round(box.y + 70), width: 120, height: Math.round(3 * spacing),
  }, isInk);
  expect(Math.round((carried.left - margin) / 10) * 10, "the word reopens on the new page in its column").toBe(220);
});

test("Flutter scrolls the page with the mouse wheel and zooms it with Ctrl and the wheel", async ({ page }, info) => {
  test.setTimeout(90_000);
  const { box, cdp } = await openNewNote(page, "Wheel");
  const written = { x: box.x + 500, y: box.y + 420 };
  await penStroke(cdp, line(written.x - 40, written.x + 40, written.y), 0.6);
  // A column through the handwriting, between two columns of paper dots.
  const column = written.x + 18;
  const top = box.y + 120;
  const bottom = box.y + box.height - 40;
  const before = await inkRow(page, column, top, bottom);
  const inkWidth = (row: number) => inkLength(page, row, written.x - 300, written.x + 300);
  const length = await inkWidth(before);
  // The handwriting is `scrolled` px above its first row, at its first size.
  const shows = (scrolled: number, message: string) => expect(async () => {
    const row = await inkRow(page, column, top, bottom);
    expect(before - row, message).toBe(scrolled);
    expect(await inkWidth(row), message).toBe(length);
  }).toPass({ timeout: 5_000 });

  await page.mouse.move(box.x + box.width / 2, box.y + box.height / 2);
  await page.mouse.wheel(0, 200);
  await shows(200, "the wheel scrolls the page down");
  await page.mouse.wheel(0, -200);
  await page.screenshot({ path: info.outputPath("scrolled-back.png") });
  await shows(0, "the wheel scrolls the page back up at the same zoom");

  // Ctrl and the wheel zoom the page about the pointer, here on the handwriting.
  await page.mouse.move(written.x, before);
  await page.keyboard.down("Control");
  await page.mouse.wheel(0, -100);
  await page.keyboard.up("Control");
  await page.screenshot({ path: info.outputPath("zoomed.png") });
  await expect(async () => {
    expect(await inkWidth(await inkRow(page, column, top, bottom))).toBeGreaterThan(1.4 * length);
  }, "Ctrl and the wheel make the handwriting larger").toPass({ timeout: 5_000 });
});

test("Flutter ruled lasso and ruled eraser take the words of the lines under the pen and show them during the drag", async ({ page }, info) => {
  test.setTimeout(240_000);
  await page.goto("?root=opfs");
  await beginTestNote(page, "Ruled", "Ruled notes");
  const button = (name: string) => page.getByRole("button", { name, exact: true });
  await button("Lined").click();
  await button("Landscape").click();
  await button("Create").click();
  const canvas = page.locator('canvas[id^="ink-canvas-"]:visible');
  await canvas.waitFor({ timeout: 30_000 });
  const box = await boxOf(canvas);
  const cdp = await page.context().newCDPSession(page);
  const { rules, spacing, middle, margin, word, shows } = await linedPaper(page, cdp, pageIn(box));
  const at = (left: number, band: number) => ({ x: margin + left, y: middle(band) });
  // A tap on the selected tool opens its modes.
  const ruledMode = async (tool: string) => {
    await button(tool).click();
    await button(tool).click();
    await button("Ruled").click();
    await closePopover(page);
  };
  const near = (value: number, expected: number, message: string) =>
    expect(Math.abs(value - expected), `${message}: ${value} is near ${expected}`).toBeLessThanOrEqual(6);

  // Two columns on lines 1 to 3, with a divider between them, and words on lines 4 to 6.
  const divider = 330;
  await word(60, 1);
  await word(220, 1);
  await word(380, 1);
  await word(60, 2);
  await word(380, 2);
  await penStroke(cdp, Array.from({ length: 13 }, (_, i) => ({
    x: margin + divider, y: rules[1] + 2 + ((3 * spacing - 4) * i) / 12,
  })), 0.6);
  await word(60, 4);
  await word(220, 4);
  await word(60, 5);
  await word(60, 6);
  await shows(1, [60, 220, divider, 380], "line 1 has three words and the divider");
  await shows(2, [60, divider, 380], "line 2 has two words and the divider");
  await ruledMode("Eraser");
  await ruledMode("Lasso");

  // The ruled lasso outlines the lines it covers while the pen is down.
  const outline = () => pixelBounds(page, {
    x: Math.ceil(box.x), y: rules[0] + 4, width: Math.floor(box.width) - 1, height: Math.round(4.5 * spacing),
  }, isOutline);
  await penHold(cdp, at(200, 1), at(300, 1));
  await page.screenshot({ path: info.outputPath("one-line.png") });
  await expect(async () => {
    const part = await outline();
    near(part.top, rules[1], "the top of the part of line 1");
    near(part.bottom, rules[2], "the bottom of the part of line 1");
    near(part.left, margin + 200, "the pen-down");
    near(part.right, margin + 300, "the pen");
  }).toPass({ timeout: 5_000 });
  // On a second line, the outline stops at the divider of the column.
  await penDrag(cdp, at(300, 1), at(150, 2));
  await page.screenshot({ path: info.outputPath("two-lines.png") });
  await expect(async () => {
    const column = await outline();
    near(column.top, rules[1], "the top of line 1");
    near(column.bottom, rules[3], "the bottom of line 2");
    near(column.right, margin + divider, "the divider");
    expect(column.left, "line 2 from the page edge").toBeLessThan(margin - 20);
  }).toPass({ timeout: 5_000 });
  await penRelease(cdp, at(150, 2));
  await button("Delete selection").click();
  await shows(1, [60, divider, 380], "the word after the pen-down in the left column is taken");
  await shows(2, [divider, 380], "the word before the pen on line 2 is taken");
  await button("Undo").click();
  await shows(1, [60, 220, divider, 380], "one undo restores line 1");
  await shows(2, [60, divider, 380], "one undo restores line 2");

  // A ruled selection moves down by whole lines.
  const wordTop = async (left: number, band: number) => (await pixelBounds(page, {
    x: Math.round(margin + left - 6), y: rules[band] + 2, width: 84, height: Math.round(spacing) - 4,
  }, isInk)).top - rules[band];
  const top = await wordTop(220, 4);
  await penHold(cdp, at(200, 4), at(300, 4));
  await penRelease(cdp, at(300, 4));
  await penStroke(cdp, [0, 0.25, 0.5, 0.75, 1].map((t) => ({
    x: margin + 255 + 200 * t, y: middle(4) + 0.7 * spacing * t,
  })), 0.6);
  await shows(4, [60], "the selected word leaves line 4");
  await shows(5, [60, 420], "the selected word is on line 5");
  // A move that followed the pen would put it 0.3 of a line higher.
  expect(Math.abs(await wordTop(420, 5) - top), "the word is one whole line lower").toBeLessThan(0.15 * spacing);

  // The ruled eraser, inside the selection: the ink goes while the pen is down.
  await button("Eraser").click();
  await penHold(cdp, at(430, 5), at(480, 5));
  await page.screenshot({ path: info.outputPath("erase-held.png") });
  await shows(5, [60], "the word under the held eraser is hidden");
  await penRelease(cdp, at(480, 5));
  // Along a line it takes the words it touches; on the next line it starts again.
  await penHold(cdp, at(200, 1), at(310, 1));
  await shows(1, [60, divider, 380], "the word under the held eraser on line 1 is hidden");
  await penDrag(cdp, at(310, 1), at(310, 2));
  await shows(2, [60, divider, 380], "line 2 stays when the eraser comes down onto it");
  await penDrag(cdp, at(310, 2), at(100, 2));
  await shows(2, [divider, 380], "the word under the held eraser on line 2 is hidden");
  await penRelease(cdp, at(100, 2));
  // In the left margin it takes each whole line that it leaves.
  await penHold(cdp, at(-30, 4), at(-30, 6));
  await shows(4, [], "line 4 is hidden");
  await shows(5, [], "line 5 is hidden");
  await shows(6, [60], "the line of the pen stays");
  await penRelease(cdp, at(-30, 6));
  const strokes = async () => (await savedPages(page, "Ruled", "Ruled notes")).map((saved) => saved.strokes);
  await expect.poll(strokes, "the divider and four words remain").toEqual([5]);
  await button("Undo").click();
  await shows(4, [60], "one undo restores line 4");
  await shows(5, [60], "one undo restores line 5");
  await button("Redo").click();
  await shows(4, [], "redo erases line 4 again");
  await expect.poll(strokes).toEqual([5]);
});

test("Flutter ruled eraser takes a word on plain paper and keeps the paper plain", async ({ page }) => {
  test.setTimeout(90_000);
  const { box, cdp } = await openNewNote(page, "Ruled plain", "Plain");
  // Two words on one row and a word four rows of Write's blank-page lines lower.
  const spots = [{ x: box.x + 235, y: box.y + 200 }, { x: box.x + 395, y: box.y + 200 }, { x: box.x + 235, y: box.y + 320 }];
  const paper: Rgb[][] = [];
  for (const spot of spots) paper.push(await screenPixels(page, spot));
  const ink: number[] = [];
  for (const [i, spot] of spots.entries()) {
    await penStroke(cdp, Array.from({ length: 8 }, (_, k) => ({ x: spot.x - 35 + 10 * k, y: spot.y + (k % 2 ? 3 : -3) })), 0.6);
    ink.push(await inkAt(page, spot, paper[i]));
  }
  const shown = () => Promise.all(spots.map(async (spot, i) => (await inkAt(page, spot, paper[i])) > 0.8 * ink[i]));
  const button = (name: string) => page.getByRole("button", { name, exact: true });
  await button("Eraser").click();
  await button("Eraser").click();
  await button("Ruled").click();
  await closePopover(page);

  const from = { x: spots[0].x - 50, y: spots[0].y };
  const to = { x: spots[0].x + 50, y: spots[0].y };
  await penHold(cdp, from, to);
  await expect.poll(shown, "the word under the held eraser is hidden").toEqual([false, true, true]);
  await penRelease(cdp, to);
  const saved = async () => (await savedPages(page, "Ruled plain", "Plain")).map(({ strokes, ruling }) => ({ strokes, ruling }));
  await expect.poll(saved).toEqual([{ strokes: 2, ruling: "blank" }]);
});

// The largest brightness step between two neighbors in a screen column.
// Handwriting that shows sharp gives the step from ink to paper.
async function sharpestStep(page: Page, x: number, top: number, bottom: number): Promise<number> {
  const column = await capture(page, { x, y: top, width: 1, height: bottom - top });
  return Math.max(...column.slice(1).map((rgb, i) => Math.abs(brightness(rgb) - brightness(column[i]))));
}

test("Flutter menus, alerts, action sheets, and sheets blur the handwriting behind them, and the alert scrim blurs the page", async ({ page }, info) => {
  test.setTimeout(120_000);
  const { box, cdp } = await openNewNote(page, "Frosted");
  const button = (name: string) => page.getByRole("button", { name, exact: true });
  // Lines 9 px apart: each surface has several of them behind it.
  for (let y = box.y + 90; y < box.y + box.height - 10; y += 9) {
    await penStroke(cdp, line(pageIn(box).x + 30, pageIn(box).x + pageIn(box).width - 30, y, 2), 0.8);
  }
  expect(await sharpestStep(page, box.x + 200, box.y + 200, box.y + 240), "the lines are sharp on the page").toBeGreaterThan(300);
  // A column of a surface with no text and no divider, across three lines or
  // more. Sharp lines behind the surfaces give steps of 21 to 65.
  const blurred = (x: number, top: number, bottom: number, surface: string) =>
    expect.poll(() => sharpestStep(page, x, top, bottom), `${surface} blurs the lines behind it`).toBeLessThan(8);

  await button("Pages").click();
  const item = await boxOf(button("Go to page"));
  await blurred(item.x + 0.7 * item.width, item.y + 4, item.y + item.height - 4, "the menu");

  await button("Go to page").click();
  // The closing menu still holds a "Go to page" label.
  const title = await boxOf(page.getByRole("alertdialog").getByText("Go to page", { exact: true }));
  await blurred(title.x - 10, title.y - 6, title.y + title.height + 6, "the alert");
  await blurred(box.x + 120, title.y - 20, title.y + 40, "the scrim beside the alert");
  expect(await capture(page, { x: title.x - 10, y: title.y + title.height / 2, width: 1, height: 1 }), "the alert is leaf").toEqual([[0xee, 0xf0, 0xea]]);
  await page.screenshot({ path: info.outputPath("alert.png") });
  await button("Cancel").click();

  await button("Pages").click();
  await button("Paper for new pages").click();
  const action = await boxOf(button("Grid paper"));
  await blurred(action.x + 0.6 * action.width, action.y + 4, action.y + action.height - 4, "the action sheet");
  const heading = await boxOf(page.getByText("Paper for new pages", { exact: true }));
  expect(await capture(page, { x: heading.x - 10, y: heading.y + heading.height / 2, width: 1, height: 1 }), "the action sheet is leaf").toEqual([[0xee, 0xf0, 0xea]]);
  await button("Done").click();

  await button("Pages").click();
  await page.getByRole("button", { name: /^Layers/ }).click();
  // The empty list below the last control of the only layer row.
  const last = await boxOf(button("Delete Ink"));
  await blurred(last.x + 10, last.y + last.height + 20, last.y + last.height + 60, "the layers sheet");
  // The page beside the sheet shows a change that the sheet makes.
  const lines = async () => (await capture(page, { x: pageIn(box).x + 100, y: box.y + 200, width: 1, height: 40 })).some(isInk);
  expect(await lines(), "the lines show beside the sheet").toBe(true);
  await button("Hide Ink").click();
  await expect.poll(lines, "the lines of the hidden layer show no more beside the sheet").toBe(false);
  await button("Done").click();
  await expect(button("Done")).toHaveCount(0);
  expect(await lines(), "the layer stays hidden on the page").toBe(false);
});

// The deployment also answers at this machine's LAN address, where Chrome
// gives no folder access: the context is not secure.
function lanAddress(deployment: string): string {
  const lan = Object.values(networkInterfaces()).flat().find((address) => address?.family === "IPv4" && !address.internal);
  if (!lan) throw new Error("This machine has no LAN address");
  const url = new URL(deployment);
  url.protocol = "http:";
  url.hostname = lan.address;
  return url.href;
}

test("Flutter at a LAN address says the address is not secure and names the localhost address", async ({ page, baseURL }, info) => {
  test.setTimeout(60_000);
  if (!baseURL) throw new Error("The Playwright configuration has no baseURL");
  await page.goto(lanAddress(baseURL));
  expect(await page.evaluate(() => window.isSecureContext), "the LAN address is not a secure context").toBe(false);
  const error = page.getByRole("button", { name: /is not a secure address/ });
  await expect(error).toBeVisible();
  await expect(error).toHaveAccessibleName(new RegExp(`Open http://localhost${new URL(baseURL).pathname} on this machine`));
  await expect(page.getByRole("button", { name: /reading 'controller'/ }), "the service worker failure is not a second error").toHaveCount(0);
  await expect(page.getByRole("button", { name: /showDirectoryPicker/ })).toHaveCount(0);
  await page.screenshot({ path: info.outputPath("lan-address.png") });
});

// One notes folder from its first launch onward: the folder choice, a
// notebook, handwriting with each tool on three pages, a restart that opens
// the saved folder, a reconnection, the library operations, and an export.
// Each step asserts the screen and the files.
test("Flutter lifetime: first launch, folder choice, three written pages, restart, reconnection, library changes, and export", async ({ page }, info) => {
  test.setTimeout(360_000);
  const shot = (name: string) => page.screenshot({ path: info.outputPath(`${name}.png`) });
  const button = (name: string) => page.getByRole("button", { name, exact: true });
  const opfs = () => page.evaluate(async () => {
    const root = await navigator.storage.getDirectory();
    const folders = await Array.fromAsync(root.keys());
    const metadata = folders.includes(".library.json")
      ? JSON.parse(await (await (await root.getFileHandle(".library.json")).getFile()).text())
      : null;
    return { folders, metadata };
  });

  // First launch: a fresh browser profile has no saved folder. Automation
  // cannot drive the native picker; here it yields the origin-private file
  // system, which the app keeps in IndexedDB as it keeps any chosen folder.
  await page.addInitScript(() => {
    Object.defineProperty(window, "showDirectoryPicker", {
      configurable: true,
      value: async () => navigator.storage.getDirectory(),
    });
  });
  await page.goto("");
  await expect(page.getByText("Your notes live in a folder on this device.", { exact: true })).toBeVisible();
  await shot("first-launch");
  await button("Choose notes folder").click();
  await expect(page.getByText("Your notebooks appear here.", { exact: true })).toBeVisible();
  expect((await opfs()).folders, "the app prepares the folder's templates and pens").toEqual(expect.arrayContaining([".templates", ".pens.json"]));
  await shot("empty-library");

  // The first notebook and its first note.
  await button("New notebook").click();
  await enterText(page.getByRole("textbox", { name: "Notebook title", exact: true }), "Analysis");
  await enterText(page.getByRole("textbox", { name: "Description", exact: true }), "Measure theory");
  await addTag(page, "measure");
  await button("Grid").click();
  await button("Create").click();
  await expect(page.getByRole("heading", { name: "Analysis", exact: true })).toBeVisible();
  await button("New note").click();
  await enterText(page.getByRole("textbox", { name: "Title", exact: true }), "Integrals");
  // A new note starts with its notebook's tags.
  await expect(button("Remove tag measure")).toBeVisible();
  await button("Create").click();
  const canvas = page.locator('canvas[id^="ink-canvas-"]:visible');
  await canvas.waitFor({ timeout: 30_000 });
  const box = await boxOf(canvas);
  const cdp = await page.context().newCDPSession(page);
  const pages = () => savedPages(page, "Integrals", "Analysis");
  const strokes = async () => (await pages()).map((saved) => saved.strokes);

  // Three rows of handwriting on page 1; each is checked on screen against
  // the paper captured before writing.
  const rows = [170, 260, 350].map((dy) => ({ x: box.x + 220, y: box.y + dy }));
  const moved = { x: rows[2].x, y: rows[2].y + 120 };
  const paper = new Map<PenPoint, Rgb[]>();
  for (const spot of [...rows, moved]) paper.set(spot, await screenPixels(page, spot));
  const write = (spot: PenPoint) => penStroke(cdp, line(spot.x - 60, spot.x + 60, spot.y), 0.6);
  await write(rows[0]);
  const stroke = await inkAt(page, rows[0], paper.get(rows[0])!);
  expect(stroke, "the first row shows ink").toBeGreaterThan(0);
  const inked = async () => {
    const spots = [];
    for (const spot of [...rows, moved]) spots.push((await inkAt(page, spot, paper.get(spot)!)) > 0.5 * stroke);
    return spots;
  };
  await write(rows[1]);
  await write(rows[2]);
  expect(await inked()).toEqual([true, true, true, false]);
  expect(await strokes()).toEqual([3]);
  await shot("page-1-written");

  // The stroke eraser takes the second row; undo and redo take it back and
  // away again, on screen and in the file.
  await button("Eraser").click();
  await button("Eraser").click();
  await button("Stroke").click();
  await closePopover(page);
  await penStroke(cdp, [-40, -20, 0, 20, 40].map((dy) => ({ x: rows[1].x, y: rows[1].y + dy })), 0.6);
  expect(await inked()).toEqual([true, false, true, false]);
  expect(await strokes()).toEqual([2]);
  await button("Undo").click();
  expect(await inked()).toEqual([true, true, true, false]);
  expect(await strokes()).toEqual([3]);
  await button("Redo").click();
  expect(await inked()).toEqual([true, false, true, false]);
  expect(await strokes()).toEqual([2]);

  // A highlight across the first row leaves the handwriting dark.
  const plainInk = await darkestPixel(page, rows[0]);
  await button("Highlighter").click();
  await penStroke(cdp, [-40, -20, 0, 20, 40].map((dy) => ({ x: rows[0].x + 30, y: rows[0].y + dy })), 0.6);
  const crossing = await darkestPixel(page, rows[0]);
  for (const channel of [0, 1, 2]) expect(Math.abs(crossing[channel] - plainInk[channel]), "the highlighted handwriting keeps its color").toBeLessThan(24);
  expect(await strokes()).toEqual([3]);

  // The lasso moves the third row down; the pen writes again afterwards.
  await button("Lasso").click();
  await penStroke(cdp, [
    { x: rows[2].x - 80, y: rows[2].y - 40 }, { x: rows[2].x + 80, y: rows[2].y - 40 },
    { x: rows[2].x + 80, y: rows[2].y + 40 }, { x: rows[2].x - 80, y: rows[2].y + 40 },
    { x: rows[2].x - 80, y: rows[2].y - 40 },
  ], 0.6);
  await penStroke(cdp, [0, 40, 80, 120].map((dy) => ({ x: rows[2].x, y: rows[2].y + dy })), 0.6);
  await button("Pen").click();
  expect(await inked()).toEqual([true, false, false, true]);
  expect(await strokes()).toEqual([3]);
  await shot("page-1-edited");

  // A typed text box. The new box is selected, as pasted content is, so a
  // pen-down elsewhere would only dismiss the selection; its menu clears it.
  await button("Text").click();
  await enterText(page.getByRole("textbox", { name: "Text", exact: true }), "Theorem 1");
  await button("Done").click();
  expect((await pages())[0].text).toContain("Theorem 1");
  await expect(button("Clear selection")).toBeVisible();
  await shot("text-box-selected");
  await button("Clear selection").click();
  await expect(button("Clear selection")).toHaveCount(0);
  await button("Pen").click();

  // Pages 2 and 3, each written; the overview returns to page 1, which
  // still shows its own ink and none of the other pages'.
  const addPage = async (number: number) => {
    await button("Pages").click();
    await button("Add page").click();
    await expect(page.getByText(`${number - 1} / ${number}`, { exact: true })).toBeVisible();
    await goToPage(page, number);
    await expect(page.getByText(`${number} / ${number}`, { exact: true })).toBeVisible();
  };
  await addPage(2);
  expect(await inked(), "a new page is blank").toEqual([false, false, false, false]);
  await write(rows[0]);
  await write(rows[1]);
  expect(await inked()).toEqual([true, true, false, false]);
  await addPage(3);
  await write(rows[2]);
  expect(await inked()).toEqual([false, false, true, false]);
  expect(await strokes()).toEqual([3, 2, 1]);
  await shot("page-3-written");
  await button("Pages").click();
  await button("Page overview").click();
  for (const number of [1, 2, 3]) await expect(button(`Page ${number}`)).toBeVisible();
  await shot("page-overview");
  await button("Page 1").click();
  await expect(page.getByText("1 / 3", { exact: true })).toBeVisible();
  expect(await inked()).toEqual([true, false, false, true]);

  // A restart: the saved folder opens without a gesture, and the note shows
  // the same ink on each page. The app finds the saved folder as a handle in
  // IndexedDB; Chromium 153 exits when it reads a stored OPFS handle back
  // (TRAPS.md), so the restart gives the app its saved folder in the host's
  // own terms instead.
  const restart = async (needsGesture: boolean) => {
    await page.addInitScript((needsGesture) => {
      Object.defineProperty(window, "mathNotes", {
        configurable: true,
        set(value) {
          Object.assign(value, {
            startRoot: async () => ({ root: await navigator.storage.getDirectory(), needsGesture }),
            requestPermission: async () => true,
          });
          Object.defineProperty(window, "mathNotes", { configurable: true, writable: true, value });
        },
      });
    }, needsGesture);
    await page.goto("");
  };
  await restart(false);
  await expect(page.getByRole("button", { name: "Open Analysis", exact: false })).toBeVisible({ timeout: 30_000 });
  await expect(page.getByText(/^1 note/)).toBeVisible();
  await shot("library-after-restart");
  await openTestNotebook(page, "Analysis");
  await page.getByRole("button", { name: "Open Integrals", exact: false }).click();
  await expect(page.getByText("1 / 3", { exact: true })).toBeVisible();
  expect(await boxOf(canvas), "the canvas keeps its place after a restart").toEqual(box);
  expect(await inked()).toEqual([true, false, false, true]);
  await goToPage(page, 2);
  await expect(page.getByText("2 / 3", { exact: true })).toBeVisible();
  expect(await inked()).toEqual([true, true, false, false]);
  await goToPage(page, 3);
  await expect(page.getByText("3 / 3", { exact: true })).toBeVisible();
  expect(await inked()).toEqual([false, false, true, false]);
  expect(await strokes()).toEqual([3, 2, 1]);

  // A restart whose folder needs a permission gesture.
  await restart(true);
  await expect(button("Reconnect folder")).toBeVisible();
  await shot("reconnect");
  await button("Reconnect folder").click();
  await openTestNotebook(page, "Analysis");
  await page.getByRole("button", { name: "Open Integrals", exact: false }).click();
  await expect(page.getByText("1 / 3", { exact: true })).toBeVisible();
  expect(await inked()).toEqual([true, false, false, true]);

  // The library over time: a second notebook and note, a move, a search, a
  // favorite, the trash, a rename, and a tag.
  await button("Library").click();
  await button("Back to library").click();
  await createTestNotebook(page, "Topology");
  await button("New note").click();
  await enterText(page.getByRole("textbox", { name: "Title", exact: true }), "Compactness");
  await button("Create").click();
  // Integrals is still open, so closing this note shows that one.
  await button("Close Compactness").click();
  await expect(page.getByRole("heading", { name: "Integrals", exact: true })).toBeVisible();
  await button("Library").click();
  await expect(page.getByRole("heading", { name: "Topology", exact: true })).toBeVisible();
  await button("Back to library").click();
  await openTestNotebook(page, "Analysis");
  await button("Integrals actions").click();
  await button("Move").click();
  await button("Topology").click();
  await expect(button("Integrals actions")).toHaveCount(0);
  await button("Back to library").click();
  await openTestNotebook(page, "Topology");
  await expect(page.getByRole("button", { name: "Open Integrals", exact: false })).toBeVisible();
  await expect(page.getByRole("button", { name: "Open Compactness", exact: false })).toBeVisible();
  await shot("moved");

  await button("Back to library").click();
  await button("Search").click();
  await enterText(page.getByRole("textbox", { name: "Search notebooks and notes", exact: true }), "Integrals");
  await expect(page.getByRole("button", { name: "Open Integrals", exact: false })).toBeVisible();
  await expect(page.getByRole("button", { name: "Open Compactness", exact: false })).toHaveCount(0);
  await button("Integrals actions").click();
  await button("Add favorite").click();
  await page.getByText("Favorites", { exact: true }).click();
  await expect(page.getByRole("button", { name: "Open Integrals", exact: false })).toBeVisible();
  await expect(page.getByRole("button", { name: "Open Compactness", exact: false })).toHaveCount(0);

  await button("Recent").click();
  await button("Compactness actions").click();
  await button("Move to trash").click();
  await button("Trash").click();
  await button("Compactness actions").click();
  await button("Restore").click();
  await button("Topology").click();
  await button("Library").click();
  await openTestNotebook(page, "Topology");
  await expect(page.getByRole("button", { name: "Open Compactness", exact: false })).toBeVisible();

  await button("Back to library").click();
  await button("Analysis notebook actions").click();
  await button("Rename").click();
  await enterText(page.getByRole("textbox", { name: "Name", exact: true }), "Real analysis");
  await button("Rename").click();
  await expect(button("Real analysis notebook actions")).toBeVisible();
  await openTestNotebook(page, "Real analysis");
  await expect(page.getByText("Measure theory", { exact: true }), "the renamed notebook keeps its description").toBeVisible();
  await expect(page.getByText("This notebook has no notes yet.", { exact: true })).toBeVisible();
  await button("Back to library").click();

  await button("New tag").click();
  await enterText(page.getByRole("textbox", { name: "Tag name", exact: true }), "geometry");
  await button("Add tag").click();
  await openTestNotebook(page, "Topology");
  await button("Integrals actions").click();
  await button("Details and tags").click();
  await addTag(page, "geometry");
  await button("Save details").click();
  await page.getByRole("button", { name: /^geometry/ }).click();
  await expect(page.getByRole("button", { name: "Open Integrals", exact: false })).toBeVisible();
  await expect(page.getByRole("button", { name: "Open Compactness", exact: false })).toHaveCount(0);
  await shot("library-final");

  const { folders, metadata } = await opfs();
  expect(folders).toEqual(expect.arrayContaining(["Real analysis", "Topology"]));
  expect(folders).not.toContain("Analysis");
  expect(metadata.folders["Real analysis"].description).toBe("Measure theory");
  expect(metadata.folders["Real analysis"].tags).toEqual(["measure"]);
  expect(metadata.folders.Analysis).toBeUndefined();
  expect(metadata.notes["Topology/Integrals"].favorite).toBe(true);
  expect(metadata.notes["Topology/Integrals"].tags).toEqual(["measure", "geometry"]);
  expect(metadata.notes["Analysis/Integrals"]).toBeUndefined();
  expect(metadata.notes[".trash/Compactness"]).toBeUndefined();
  expect(metadata.tags.map(({ name }: { name: string }) => name)).toEqual(expect.arrayContaining(["measure", "geometry"]));

  // The moved note keeps its pages, and exports them.
  const stored = await storedPages(page, "Integrals", "Topology");
  expect(stored.map((saved) => saved.strokes)).toEqual([3, 2, 1]);
  expect(stored[0].text).toContain("Theorem 1");
  await page.getByRole("button", { name: "Open Integrals", exact: false }).click();
  await expect(page.getByText("1 / 3", { exact: true })).toBeVisible();
  expect(await inked()).toEqual([true, false, false, true]);
  await button("More").click();
  await button("Export PDF").click();
  const download = page.waitForEvent("download");
  await button("Export").click();
  const pdfPath = info.outputPath("integrals.pdf");
  await (await download).saveAs(pdfPath);
  expect(execFileSync("pdfinfo", [pdfPath], { encoding: "utf8" })).toMatch(/Pages:\s+3/);
  expect(execFileSync("pdftotext", [pdfPath, "-"], { encoding: "utf8" })).toContain("Theorem 1");
});

// A saved notebook in the notes folder, by its folder path: its layers, and
// each page's layer groups in file order with their strokes, links,
// bookmarks, and the lines of each text box.
function storedNote(page: Page, path: string[]) {
  return whenSaved(() => page.evaluate(async (path) => {
    let dir = await navigator.storage.getDirectory();
    for (const name of path) dir = await dir.getDirectoryHandle(name);
    const manifest = JSON.parse(await (await (await dir.getFileHandle("notebook.json")).getFile()).text());
    const files = await dir.getDirectoryHandle("pages");
    const pages = [];
    for (const entry of manifest.pages as { file: string }[]) {
      const svg = await (await (await files.getFileHandle(entry.file.replace("pages/", ""))).getFile()).text();
      const parsed = new DOMParser().parseFromString(svg, "image/svg+xml");
      const groups = Array.from(parsed.documentElement.children).filter((g) => g.tagName === "g" && g.id !== "background");
      pages.push({
        file: entry.file,
        groups: groups.map((g) => ({
          id: g.id,
          xml: g.outerHTML,
          strokes: Array.from(g.querySelectorAll('path[id^="s-"]'), (stroke) => ({ id: stroke.id, d: stroke.getAttribute("d") })),
        })),
        links: Array.from(parsed.querySelectorAll("a"), (link) => link.getAttribute("href")),
        bookmarks: Array.from(parsed.querySelectorAll("g.mn-bookmark"), (bookmark) => bookmark.id),
        texts: Array.from(parsed.querySelectorAll("text"), (box) => Array.from(box.querySelectorAll("tspan"), (line) => line.textContent)),
      });
    }
    return { layers: manifest.layers as { id: string; name: string; hidden: boolean; locked: boolean }[], pages };
  }, path));
}

test("Flutter research session: layers, clippings, bookmarks, links between notes, split view, reload, and export", async ({ page }, info) => {
  test.setTimeout(480_000);
  const shot = (name: string) => page.screenshot({ path: info.outputPath(`${name}.png`) });
  const button = (name: string) => page.getByRole("button", { name, exact: true });
  const lecture = ["Topology", "Lecture"];
  const proofs = ["Topology", "Proofs"];
  const saved = async (path: string[]) => {
    await save(page);
    await expect(page.getByRole("status", { name: /^Notebook save/ })).toHaveAccessibleName("Notebook save Saved");
    return storedNote(page, path);
  };
  const strokeCounts = (note: Awaited<ReturnType<typeof storedNote>>, index = 0) =>
    note.pages[index].groups.map((group) => group.strokes.length);

  await page.goto("?root=opfs");
  await createTestNotebook(page, "Topology");
  await button("New note").click();
  await enterText(page.getByRole("textbox", { name: "Title", exact: true }), "Lecture");
  await button("Create").click();
  const canvas = page.locator('canvas[id^="ink-canvas-"]:visible');
  await canvas.waitFor({ timeout: 30_000 });
  const box = await boxOf(canvas);
  const cdp = await page.context().newCDPSession(page);

  // Three rows of handwriting, each checked on screen against the paper
  // captured before writing.
  const rows = [170, 260, 350].map((dy) => ({ x: box.x + 220, y: box.y + dy }));
  const paper = new Map<PenPoint, Rgb[]>();
  for (const spot of rows) paper.set(spot, await screenPixels(page, spot));
  const write = (spot: PenPoint) => penStroke(cdp, line(spot.x - 60, spot.x + 60, spot.y), 0.6);
  await write(rows[0]);
  const stroke = await inkAt(page, rows[0], paper.get(rows[0])!);
  expect(stroke, "the first row shows ink").toBeGreaterThan(0);
  const inked = async () => {
    const spots = [];
    for (const spot of rows) spots.push((await inkAt(page, spot, paper.get(spot)!)) > 0.5 * stroke);
    return spots;
  };
  const lasso = (top: number, bottom: number) => penStroke(cdp, [
    { x: rows[0].x - 80, y: top }, { x: rows[0].x + 80, y: top },
    { x: rows[0].x + 80, y: bottom }, { x: rows[0].x - 80, y: bottom },
    { x: rows[0].x - 80, y: top },
  ], 0.6);
  const layers = async (action: () => Promise<void>) => {
    await button("Pages").click();
    await button("Layers").click();
    await action();
    await button("Done").click();
    // Pen events before the sheet's barrier is gone never reach the page
    // (TRAPS.md).
    await expect(button("Library")).toBeVisible();
  };
  const addLayer = async (name: string) => {
    await button("Add").click();
    await enterText(page.getByRole("textbox", { name: "Layer name", exact: true }), name);
    await button("Save").click();
    await expect(page.getByRole("group", { name, exact: true })).toBeVisible();
  };

  // A second layer for sketches; new ink goes to the active layer.
  await layers(() => addLayer("Sketch"));
  await write(rows[1]);
  expect(await inked()).toEqual([true, true, false]);
  let note = await saved(lecture);
  expect(note.layers.map((layer) => layer.name)).toEqual(["Ink", "Sketch"]);
  const [ink, sketch] = note.layers.map((layer) => layer.id);
  expect(note.pages[0].groups.map((group) => group.id)).toEqual([ink, sketch]);
  expect(strokeCounts(note)).toEqual([1, 1]);

  // A locked layer keeps its ink under the stroke eraser and the lasso.
  await layers(() => button("Lock Ink").click());
  await button("Eraser").click();
  await button("Eraser").click();
  await button("Stroke").click();
  await closePopover(page);
  await penStroke(cdp, [130, 170, 210, 260, 300].map((y) => ({ x: rows[0].x, y: box.y + y })), 0.6);
  expect(await inked(), "the eraser takes the sketch only").toEqual([true, false, false]);
  await button("Undo").click();
  expect(await inked()).toEqual([true, true, false]);
  await button("Lasso").click();
  await lasso(box.y + 130, box.y + 300);
  await button("Delete selection").click();
  expect(await inked(), "the lasso takes the sketch only").toEqual([true, false, false]);
  await button("Undo").click();
  expect(await inked()).toEqual([true, true, false]);
  note = await saved(lecture);
  expect(note.layers.map((layer) => layer.locked)).toEqual([true, false]);
  expect(strokeCounts(note)).toEqual([1, 1]);
  await shot("locked-layer");

  // Reordering moves the layer groups in the page file and changes nothing
  // in them.
  const before = note.pages[0].groups.map((group) => group.xml);
  await layers(async () => {
    await button("Unlock Ink").click();
    await button("Down Sketch").click();
  });
  note = await saved(lecture);
  expect(note.layers.map((layer) => layer.name)).toEqual(["Sketch", "Ink"]);
  expect(note.pages[0].groups.map((group) => group.xml)).toEqual([before[1], before[0]]);

  // A hidden layer is not drawn.
  await layers(() => button("Hide Sketch").click());
  expect(await inked()).toEqual([true, false, false]);
  await layers(() => button("Show Sketch").click());
  expect(await inked()).toEqual([true, true, false]);

  // A layer for labels, merged down into the ink.
  await layers(() => addLayer("Labels"));
  await button("Pen").click();
  await write(rows[2]);
  expect(await inked()).toEqual([true, true, true]);
  await layers(() => button("Merge down Labels").click());
  note = await saved(lecture);
  expect(note.layers.map((layer) => layer.name)).toEqual(["Sketch", "Ink"]);
  expect(note.pages[0].groups.map((group) => group.id)).toEqual([sketch, ink]);
  expect(strokeCounts(note)).toEqual([1, 2]);
  expect(await inked()).toEqual([true, true, true]);

  // An export without the sketch layer leaves out its ink: a render of the
  // PDF page at the screen page's width has ink at the first and third rows
  // only.
  const exportPdf = async (name: string, exclude: string[] = []) => {
    await button("More").click();
    await button("Export PDF").click();
    for (const layer of exclude) await page.getByRole("switch", { name: layer, exact: true }).click();
    await shot(`export-${name}`);
    const download = page.waitForEvent("download");
    await button("Export").click();
    const path = info.outputPath(`${name}.pdf`);
    await (await download).saveAs(path);
    return path;
  };
  const sheet = pageIn(box);
  const width = Math.round(sheet.width);
  const withoutSketch = await exportPdf("without-sketch", ["Sketch"]);
  const render = info.outputPath("without-sketch-page-1");
  execFileSync("pdftoppm", ["-png", "-f", "1", "-l", "1", "-singlefile", "-scale-to-x", `${width}`, "-scale-to-y", "-1", withoutSketch, render]);
  const rendered = await pngPixels(page, await readFile(`${render}.png`));
  const renderedInk = (spot: PenPoint) => {
    const x = Math.round(spot.x - sheet.x);
    const y = Math.round(spot.y - sheet.y);
    let dark = 0;
    for (let dy = -4; dy <= 4; dy++) for (let dx = -4; dx <= 4; dx++) if (isInk(rendered[(y + dy) * width + x + dx])) dark++;
    return dark > 0;
  };
  expect(rows.map(renderedInk)).toEqual([true, false, true]);

  // Deleting the sketch layer removes its ink.
  await layers(async () => {
    await button("Delete Sketch").click();
    await expect(page.getByRole("alertdialog").getByText("Delete Sketch?", { exact: true })).toBeVisible();
    await page.getByRole("alertdialog").getByRole("button", { name: "Delete", exact: true }).click();
  });
  expect(await inked()).toEqual([true, false, true]);
  note = await saved(lecture);
  expect(note.layers.map((layer) => layer.name)).toEqual(["Ink"]);
  expect(strokeCounts(note)).toEqual([2]);
  const lectureStrokes = note.pages[0].groups[0].strokes;

  // The clippings panel starts with Write's four shapes; the two rows become
  // a fifth clipping, a page of the clippings notebook. The panel narrows the
  // page, so the selection comes first.
  await button("Lasso").click();
  await lasso(box.y + 130, box.y + 390);
  await button("Clippings").click();
  // The panel lists the clippings in a scroll view; one off screen has no
  // semantics node until the wheel scrolls it in.
  const clipping = async (number: number) => {
    const target = button(`Insert clipping ${number}`);
    const panel = await boxOf(button("Save selected content"));
    await expect(async () => {
      if ((await target.count()) === 0) {
        await page.mouse.move(panel.x + panel.width / 2, panel.y + 250);
        await page.mouse.wheel(0, 200);
      }
      await expect(target).toBeVisible({ timeout: 500 });
    }).toPass({ timeout: 10_000 });
  };
  for (const number of [1, 2, 3, 4]) await clipping(number);
  await button("Save selected content").click();
  await clipping(5);
  await shot("clipping-saved");
  const clippings = await storedNote(page, [".clippings"]);
  expect(clippings.pages).toHaveLength(5);
  const clipped = clippings.pages[4].groups.flatMap((group) => group.strokes);
  expect(clipped.map((s) => s.d).sort()).toEqual(lectureStrokes.map((s) => s.d).sort());
  await button("Clippings").click();
  await button("Clear selection").click();

  // Page 2: a row of handwriting and a bookmark at its line.
  await button("Pen").click();
  await button("Pages").click();
  await button("Add page").click();
  await goToPage(page, 2);
  await expect(page.getByText("2 / 2", { exact: true })).toBeVisible();
  await write(rows[0]);
  await button("Pages").click();
  await button("Add bookmark").click();
  // The banner is one semantics node, labeled with its mode and its hint.
  await expect(page.getByLabel("Add bookmark\nTap the line to mark.", { exact: true })).toBeVisible();
  await page.mouse.click(rows[0].x, rows[0].y);
  await button("Close Add bookmark").click();
  await button("Clear selection").click();
  note = await saved(lecture);
  expect(note.pages[1].bookmarks).toHaveLength(1);
  const bookmark = `${note.pages[1].file.replace("pages/", "")}#${note.pages[1].bookmarks[0]}`;

  // The first row of page 1 links to the bookmark, and following it goes
  // to page 2.
  await goToPage(page, 1);
  await expect(page.getByText("1 / 2", { exact: true })).toBeVisible();
  await button("Lasso").click();
  await lasso(box.y + 130, box.y + 210);
  await button("Link selected content").click();
  await button("Page or bookmark").click();
  await page.getByText("Bookmark on page 2", { exact: true }).click();
  note = await saved(lecture);
  expect(note.pages[0].links).toEqual([bookmark]);
  const followLinks = async (on: boolean) => {
    await button("More").click();
    await button("Settings").click();
    const toggle = page.getByRole("switch", { name: "Follow links", exact: true });
    await toggle.click();
    if (on) await expect(toggle).toBeChecked();
    else await expect(toggle).not.toBeChecked();
    await button("Done").click();
    await expect(button("Library")).toBeVisible();
  };
  await followLinks(true);
  await page.mouse.click(rows[0].x, rows[0].y);
  await expect(page.getByText("2 / 2", { exact: true })).toBeVisible();
  await followLinks(false);
  await shot("followed-bookmark");

  // A second note gets the clipping, with new stroke ids and the same
  // outlines.
  await button("Library").click();
  await expect(page.getByRole("heading", { name: "Topology", exact: true })).toBeVisible();
  await button("New note").click();
  await enterText(page.getByRole("textbox", { name: "Title", exact: true }), "Proofs");
  await button("Create").click();
  await expect(page.getByRole("heading", { name: "Proofs", exact: true })).toBeVisible();
  await button("Clippings").click();
  await button("Insert clipping 5").click();
  await button("Clippings").click();
  let other = await saved(proofs);
  const pasted = other.pages[0].groups.flatMap((group) => group.strokes);
  expect(pasted.map((s) => s.d).sort()).toEqual(lectureStrokes.map((s) => s.d).sort());
  for (const { id } of pasted) expect(lectureStrokes.map((s) => s.id)).not.toContain(id);

  // The pasted ink stays selected, and links to the bookmark in Lecture.
  const outline = await pixelBounds(page, { x: Math.round(box.x), y: Math.round(box.y), width: Math.floor(box.width), height: Math.floor(box.height) }, isOutline);
  const pastedCenter = { x: (outline.left + outline.right) / 2, y: (outline.top + outline.bottom) / 2 };
  await button("Link selected content").click();
  await button("Another notebook").click();
  await page.getByRole("group", { name: "Lecture Topology", exact: true }).click();
  await page.getByText("Bookmark on page 2", { exact: true }).click();
  other = await saved(proofs);
  const crossLink = `../../Lecture/pages/${bookmark}`;
  expect(other.pages[0].links).toEqual([crossLink]);
  await button("Clear selection").click();

  // A typed proof sketch with an explicit line break.
  await button("Text").click();
  const text = page.getByRole("textbox", { name: "Text", exact: true });
  await enterText(text, "Lemma 2");
  await text.press("Enter");
  await text.pressSequentially("Proof.");
  await button("Done").click();
  await button("Clear selection").click();
  other = await saved(proofs);
  expect(other.pages[0].texts).toContainEqual(["Lemma 2", "Proof."]);
  await shot("proofs");

  // Following the link from Proofs opens Lecture at page 2.
  await button("Pen").click();
  await followLinks(true);
  await page.mouse.click(pastedCenter.x, pastedCenter.y);
  await expect(page.getByRole("heading", { name: "Lecture", exact: true })).toBeVisible();
  await expect(page.getByText("2 / 2", { exact: true })).toBeVisible();

  // After a reload, both notes keep their content and the link still works.
  await page.goto("?root=opfs");
  await openTestNotebook(page, "Topology");
  await page.getByRole("button", { name: "Open Proofs", exact: false }).click();
  await expect(page.getByRole("heading", { name: "Proofs", exact: true })).toBeVisible();
  other = await storedNote(page, proofs);
  expect(other.pages[0].links).toEqual([crossLink]);
  expect(other.pages[0].texts).toContainEqual(["Lemma 2", "Proof."]);
  note = await storedNote(page, lecture);
  expect(note.pages.map((saved) => saved.groups.map((group) => group.strokes.length))).toEqual([[2], [1]]);
  expect(note.pages[0].links).toEqual([bookmark]);
  await followLinks(true);
  await page.mouse.click(pastedCenter.x, pastedCenter.y);
  await expect(page.getByRole("heading", { name: "Lecture", exact: true })).toBeVisible();
  await expect(page.getByText("2 / 2", { exact: true })).toBeVisible();
  await shot("followed-after-reload");

  // Split view: Lecture beside Proofs. Page 2 of Lecture is selected and
  // dragged into Proofs, which gains its row with a new id.
  await button("View").click();
  await button("Split view").click();
  await page.getByRole("button", { name: /^Reference: / }).click();
  await page.getByRole("group", { name: "Proofs Topology", exact: true }).click();
  await expect(button("Reference: Proofs")).toBeVisible();
  await expect(canvas).toHaveCount(2);
  await shot("split-view");
  await button("Pages").first().click();
  await button("Select page").click();
  const handle = page.getByLabel("Drag a copy", { exact: true });
  const from = await boxOf(handle);
  const to = await boxOf(canvas.nth(1));
  await page.mouse.move(from.x + from.width / 2, from.y + from.height / 2);
  await page.mouse.down();
  await page.waitForTimeout(800);
  await page.mouse.move(to.x + to.width / 2, to.y + to.height / 2, { steps: 20 });
  await page.waitForTimeout(400);
  await page.mouse.up();
  await shot("dragged-between-panes");
  const row = note.pages[1].groups[0].strokes.map((s) => s.id);
  await expect.poll(async () => (await storedNote(page, proofs)).pages[0].groups.flatMap((group) => group.strokes).length, { timeout: 15_000 }).toBe(3);
  other = await storedNote(page, proofs);
  for (const { id } of other.pages[0].groups.flatMap((group) => group.strokes)) expect(row).not.toContain(id);
  await button("View").first().click();
  await button("Close split view").click();
  await expect(canvas).toHaveCount(1);

  // The exported PDFs keep the links: Lecture's link goes to the named
  // destination of its bookmark, and Proofs' link names the bookmark in
  // Lecture by its path from the notebook.
  const annotations = (path: string) =>
    JSON.stringify(JSON.parse(execFileSync("qpdf", ["--json=2", path], { encoding: "utf8" })));
  const lecturePdf = annotations(await exportPdf("lecture"));
  const destination = `pages/${bookmark}`;
  expect(lecturePdf).toContain('"/Subtype":"/Link"');
  expect(lecturePdf.split(destination).length - 1, "the link and its destination name the bookmark").toBeGreaterThanOrEqual(2);
  await button("Proofs").click();
  await expect(page.getByRole("heading", { name: "Proofs", exact: true })).toBeVisible();
  const proofsPdf = annotations(await exportPdf("proofs"));
  expect(proofsPdf).toContain(`"/URI":"u:../Lecture/${destination}"`);
});

// The fill of each saved stroke on one page of a note, in file order.
function storedFills(page: Page, path: string[], file: string) {
  return whenSaved(() => page.evaluate(async ({ path, file }) => {
    let dir = await navigator.storage.getDirectory();
    for (const name of path) dir = await dir.getDirectoryHandle(name);
    const svg = await (await (await (await dir.getDirectoryHandle("pages")).getFileHandle(file)).getFile()).text();
    return [...svg.matchAll(/<path id="s-[^"]*"[^>]* fill="(#[0-9A-F]{6})"/g)].map((match) => match[1]);
  }, { path, file }));
}

test("Flutter lecture session: every core tool on one note, pages, a PDF beside it, reload, library, a sync conflict, and export", async ({ page, context }, info) => {
  test.setTimeout(600_000);
  await context.grantPermissions(["clipboard-read", "clipboard-write"]);
  const shot = (name: string) => page.screenshot({ path: info.outputPath(`${name}.png`) });
  const button = (name: string) => page.getByRole("button", { name, exact: true });
  const choose = async (menu: string, item: string) => {
    await button(menu).click();
    await button(item).click();
  };
  const notebook = "Semester";
  let title = "Lecture 1";

  await page.goto("?root=opfs");
  await createTestNotebook(page, notebook);
  await button("New note").click();
  await enterText(page.getByRole("textbox", { name: "Title", exact: true }), title);
  await button("Dot").click();
  await button("Create").click();
  const canvas = page.locator('canvas[id^="ink-canvas-"]:visible');
  await canvas.waitFor({ timeout: 30_000 });
  const box = await boxOf(canvas);
  const cdp = await page.context().newCDPSession(page);
  const pages = () => savedPages(page, title, notebook);
  const strokes = async () => (await pages()).map((saved) => saved.strokes);
  const at = (dx: number, dy: number) => ({ x: box.x + dx, y: box.y + dy });
  const drag = (from: PenPoint, dx: number, dy: number) =>
    penStroke(cdp, [0, 0.25, 0.5, 0.75, 1].map((t) => ({ x: from.x + dx * t, y: from.y + dy * t })), 0.6);
  const lassoAround = (b: Bounds) =>
    penStroke(cdp, [
      { x: b.left - 30, y: b.top - 30 }, { x: b.right + 30, y: b.top - 30 },
      { x: b.right + 30, y: b.bottom + 30 }, { x: b.left - 30, y: b.bottom + 30 },
      { x: b.left - 30, y: b.top - 30 },
    ], 0.6);

  // Page 1 of the lecture. The spots are captured as paper before writing.
  const heading = at(220, 110), light = at(220, 170), hard = at(220, 220);
  const slanted = at(220, 280), moved = at(220, 380);
  const paper = new Map<PenPoint, Rgb[]>();
  for (const spot of [heading, light, hard, slanted, moved]) paper.set(spot, await screenPixels(page, spot));

  // The heading: a thick red pen, saved for the headings of later pages.
  await pickColor(page, "#d92d39");
  await button("Pen").click();
  await button("3.6 pt").click();
  await button("Save pen").click();
  await closePopover(page);
  await penStroke(cdp, line(heading.x - 80, heading.x + 80, heading.y), 0.6);
  await pickColor(page, "#1a1a1a");
  await button("Pen").click();
  await button("0.6 pt").click();
  await closePopover(page);

  // A light line and a hard one: the pressure shows in the ink.
  await penStroke(cdp, line(light.x - 60, light.x + 60, light.y), 0.15);
  await penStroke(cdp, line(hard.x - 60, hard.x + 60, hard.y), 1);
  const hardInk = await inkAt(page, hard, paper.get(hard)!);
  expect(hardInk / (await inkAt(page, light, paper.get(light)!)), "the hard line is darker than the light one").toBeGreaterThan(1.3);

  // A slanted line written while the palm drags on the page: the page stays.
  const column = hard.x + 30;
  const before = await inkRow(page, column, hard.y - 20, hard.y + 20);
  const palm = { id: 1, x: box.x + box.width - 80, y: box.y + box.height - 60 };
  const pen = { pointerType: "pen" as const, force: 0.6 };
  await cdp.send("Input.dispatchMouseEvent", { type: "mousePressed", button: "left", clickCount: 1, x: slanted.x - 50, y: slanted.y - 20, ...pen });
  await cdp.send("Input.dispatchTouchEvent", { type: "touchStart", touchPoints: [palm] });
  for (const [step, distance] of [40, 150, 300].entries()) {
    await cdp.send("Input.dispatchTouchEvent", { type: "touchMove", touchPoints: [{ ...palm, y: palm.y - distance }] });
    await cdp.send("Input.dispatchMouseEvent", { type: "mouseMoved", button: "left", buttons: 1, x: slanted.x - 50 + 33 * (step + 1), y: slanted.y - 20 + 13 * (step + 1), ...pen });
  }
  await cdp.send("Input.dispatchTouchEvent", { type: "touchEnd", touchPoints: [] });
  await cdp.send("Input.dispatchMouseEvent", { type: "mouseReleased", button: "left", clickCount: 1, x: slanted.x + 50, y: slanted.y + 20, ...pen });
  expect(await inkRow(page, column, hard.y - 20, hard.y + 20), "the palm does not scroll the page").toBe(before);
  expect(await strokes()).toEqual([4]);
  await shot("written");

  // The partial eraser cuts the hard line in two; a two-finger tap undoes,
  // a three-finger tap redoes, and Ctrl+Z undoes again.
  await button("Eraser").click();
  await button("Eraser").click();
  await button("Partial").click();
  await closePopover(page);
  await penStroke(cdp, [-30, 0, 30].map((dy) => ({ x: hard.x, y: hard.y + dy })), 0.6);
  expect(await strokes(), "the cut leaves two pieces").toEqual([5]);
  const tap = async (fingers: number) => {
    const touchPoints = Array.from({ length: fingers }, (_, id) => ({ id, x: box.x + 500 + 60 * id, y: box.y + 300 }));
    await cdp.send("Input.dispatchTouchEvent", { type: "touchStart", touchPoints });
    await cdp.send("Input.dispatchTouchEvent", { type: "touchEnd", touchPoints: [] });
  };
  await tap(2);
  expect(await strokes(), "a two-finger tap undoes the cut").toEqual([4]);
  await tap(3);
  expect(await strokes(), "a three-finger tap redoes it").toEqual([5]);
  await page.keyboard.press("Control+z");
  expect(await strokes(), "Ctrl+Z undoes it").toEqual([4]);

  // The pen's side button erases with the eraser's mode, still Partial: it
  // cuts the light line in two. The Undo button restores the line.
  await button("Pen").click();
  const side = { pointerType: "pen" as const, force: 0.6, button: "right" as const, buttons: 2 };
  await cdp.send("Input.dispatchMouseEvent", { type: "mousePressed", clickCount: 1, x: light.x, y: light.y - 25, ...side });
  await cdp.send("Input.dispatchMouseEvent", { type: "mouseMoved", x: light.x, y: light.y, ...side });
  await cdp.send("Input.dispatchMouseEvent", { type: "mouseMoved", x: light.x, y: light.y + 25, ...side });
  await cdp.send("Input.dispatchMouseEvent", { type: "mouseReleased", clickCount: 1, x: light.x, y: light.y + 25, ...side, buttons: 0 });
  expect(await strokes(), "the side button cuts the light line in two").toEqual([5]);
  await expect.poll(() => inkAt(page, light, paper.get(light)!), { message: "the cut shows paper" }).toBeLessThan(0.1 * hardInk);
  await button("Undo").click();
  expect(await strokes()).toEqual([4]);

  // The lasso moves the slanted line down; Copy, a move of the original, and
  // Paste leave a copy where it was; the copy turns red, is duplicated, and
  // the duplicate is deleted.
  await button("Lasso").click();
  await lassoAround({ left: slanted.x - 50, right: slanted.x + 50, top: slanted.y - 20, bottom: slanted.y + 20 });
  await penStroke(cdp, [0, 25, 50, 75, 100].map((dy) => ({ x: slanted.x, y: slanted.y + dy })), 0.6);
  await button("Copy").click();
  await penStroke(cdp, [0, 25, 50, 75, 100].map((dy) => ({ x: moved.x, y: moved.y + dy })), 0.6);
  await page.mouse.click(moved.x, moved.y, { button: "right" });
  await button("Paste").click();
  await pickColor(page, "#d92d39");
  await button("Duplicate").click();
  await button("Delete selection").click();
  await expect(button("Delete selection")).toHaveCount(0);
  expect(await inkAt(page, slanted, paper.get(slanted)!), "the slanted line left its place").toBeLessThan(0.1 * hardInk);
  expect(await inkAt(page, moved, paper.get(moved)!), "the red copy is where the line was copied").toBeGreaterThan(0.3 * hardInk);
  expect(await strokes()).toEqual([5]);
  expect(await storedFills(page, [notebook, title], "0001.svg"), "the heading and the copy are red")
    .toEqual(["#D92D39", "#1A1A1A", "#1A1A1A", "#1A1A1A", "#D92D39"]);
  await pickColor(page, "#1a1a1a");
  await shot("selections");

  // A rectangle selection takes the hard line alone; undo brings it back.
  // The color choice chose the pen, so the first tap chooses the lasso and
  // the second opens its modes.
  await button("Lasso").click();
  await button("Lasso").click();
  await button("Rectangle").click();
  await closePopover(page);
  await penStroke(cdp, [0, 0.25, 0.5, 0.75, 1].map((t) => ({ x: hard.x - 90 + 180 * t, y: hard.y - 22 + 44 * t })), 0.6);
  await button("Delete selection").click();
  expect(await strokes(), "the rectangle takes one line").toEqual([4]);
  await button("Undo").click();
  expect(await strokes()).toEqual([5]);

  // The original slanted line, now 200 px below its start, doubles in size
  // by its bottom-right handle.
  await button("Lasso").click();
  await button("Freehand").click();
  await closePopover(page);
  const region = { x: Math.round(box.x) + 120, y: Math.round(box.y) + 430, width: 400, height: Math.min(200, 715 - Math.round(box.y) - 430) };
  const original = await pixelBounds(page, region, isInk);
  await lassoAround(original);
  const outline = await pixelBounds(page, region, isOutline);
  const corner = { x: outline.right - 5, y: outline.bottom - 5 };
  const pad = corner.y - original.bottom;
  await drag(corner, size(original).width + pad, size(original).height + pad);
  await button("Clear selection").click();
  const doubled = await pixelBounds(page, region, isInk);
  expect(size(doubled).width / size(original).width, "the line is twice as wide").toBeCloseTo(2, 0);
  expect(Math.abs(doubled.left - original.left), "the opposite corner stays").toBeLessThan(6);
  await shot("resized");

  // A typed definition and a figure.
  await button("Text").click();
  await enterText(page.getByRole("textbox", { name: "Text", exact: true }), "Definition 1");
  await button("Done").click();
  await button("Clear selection").click();
  const chooser = page.waitForEvent("filechooser");
  await button("Image").click();
  await (await chooser).setFiles("e2e/fixtures/figure.jpg");
  await expect(button("Delete selection")).toBeAttached();
  await button("Clear selection").click();
  await button("Pen").click();
  const first = (await pages())[0];
  expect(first.text).toContain("Definition 1");
  expect((await storedNote(page, [notebook, title])).pages[0].groups.map((group) => group.xml).join(""), "the figure is saved").toContain("<image");
  await shot("page-1");

  // Page 2 in the saved heading pen, and a lined page 3.
  await choose("Pages", "Add page");
  await expect(page.getByText("1 / 2", { exact: true })).toBeVisible();
  await goToPage(page, 2);
  await expect(page.getByText("2 / 2", { exact: true })).toBeVisible();
  await openColors(page);
  await button("Saved pen 3.6 pt #d92d39").click();
  await expect(button("Library")).toBeVisible();
  await penStroke(cdp, line(heading.x - 80, heading.x + 80, heading.y), 0.6);
  await pickColor(page, "#1a1a1a");
  await button("Pen").click();
  await button("0.6 pt").click();
  await closePopover(page);
  await penStroke(cdp, line(light.x - 60, light.x + 60, light.y), 0.6);
  // A second device later edits page 2 as it is now (the sync conflict below).
  const remotePage2 = await whenSaved(() => page.evaluate(async ({ notebook, title }) => {
    const dir = await (await (await navigator.storage.getDirectory()).getDirectoryHandle(notebook)).getDirectoryHandle(title);
    return (await (await (await dir.getDirectoryHandle("pages")).getFileHandle("0002.svg")).getFile()).text();
  }, { notebook, title }));
  await choose("Pages", "Paper for new pages");
  await button("Lined paper").click();
  await button("Done").click();
  await choose("Pages", "Add page");
  await expect(page.getByText("2 / 3", { exact: true })).toBeVisible();
  await goToPage(page, 3);
  await penStroke(cdp, line(light.x - 60, light.x + 60, light.y), 0.6);
  expect(await strokes()).toEqual([5, 2, 1]);

  // A page inserted before page 3 by mistake is deleted in the overview;
  // page 1 is duplicated and its copy dragged to the end.
  await choose("Pages", "Insert page before");
  await expect(page.getByText(/^\d \/ 4$/)).toBeVisible();
  await choose("Pages", "Page overview");
  const tile = (n: number) => button(`Page ${n}`);
  const act = async (n: number, action: string) => {
    await button(`Page ${n} actions`).click();
    await button(action).click();
  };
  await act(3, "Delete");
  await expect(tile(4)).toHaveCount(0);
  await act(1, "Duplicate");
  await expect(tile(4)).toBeVisible();
  const from = await boxOf(tile(2));
  const to = await boxOf(tile(4));
  await page.mouse.move(from.x + from.width / 2, from.y + from.height / 2);
  await page.mouse.down();
  await page.waitForTimeout(800);
  await page.mouse.move(to.x + to.width / 2, to.y + to.height / 2, { steps: 20 });
  await page.waitForTimeout(400);
  await page.mouse.up();
  await shot("overview");
  await tile(1).click();
  await expect(page.getByText("1 / 4", { exact: true })).toBeVisible();
  let saved = await pages();
  // A new page file takes the number after the highest of the note's pages
  // (NextPageFile): the copy reuses the number of the deleted page.
  expect(saved.map((p) => p.file)).toEqual(["pages/0001.svg", "pages/0002.svg", "pages/0003.svg", "pages/0004.svg"]);
  expect(saved.map((p) => p.strokes)).toEqual([5, 2, 1, 5]);
  expect(saved[2].ruling, "page 3 is lined").toBe("lined");
  expect(saved[3].ruling, "the copy keeps the paper of page 1").toBe(saved[0].ruling);

  // Delete page: the toast's Undo restores it; the second delete stands.
  await goToPage(page, 4);
  await choose("Pages", "Delete page");
  const toast = page.getByRole("status", { name: "Page 4 deleted", exact: true });
  await toast.hover();
  expect(await strokes()).toEqual([5, 2, 1]);
  await button("Undo").last().click();
  await expect(page.getByText(/^\d \/ 4$/)).toBeVisible();
  await goToPage(page, 4);
  await choose("Pages", "Delete page");
  await expect(page.getByText(/^\d \/ 3$/)).toBeVisible();
  expect(await strokes()).toEqual([5, 2, 1]);

  // A finger writes on page 2 while finger drawing is on; with it off, the
  // same finger pans and writes nothing.
  await goToPage(page, 2);
  const fingerDrawing = async () => {
    await choose("More", "Settings");
    await page.getByRole("switch", { name: "Draw with finger", exact: true }).click();
    await button("Done").click();
  };
  const fingerLine = async (y: number) => {
    const finger = (x: number) => ({ id: 1, x: box.x + x, y: box.y + y });
    await cdp.send("Input.dispatchTouchEvent", { type: "touchStart", touchPoints: [finger(160)] });
    for (const x of [200, 260, 320]) await cdp.send("Input.dispatchTouchEvent", { type: "touchMove", touchPoints: [finger(x)] });
    await cdp.send("Input.dispatchTouchEvent", { type: "touchEnd", touchPoints: [] });
  };
  await fingerDrawing();
  await fingerLine(320);
  expect(await strokes(), "the finger writes").toEqual([5, 3, 1]);
  await fingerDrawing();
  await fingerLine(400);
  expect(await strokes(), "the finger no longer writes").toEqual([5, 3, 1]);

  // The paper for the lecture, imported beside it: a highlight and a margin
  // note; then back to the lecture's tab, still on its page.
  await button("Library").click();
  const pdfChooser = page.waitForEvent("filechooser");
  await button("Import PDF").click();
  await (await pdfChooser).setFiles("e2e/fixtures/paper.pdf");
  await expect(page.getByText("1 / 2", { exact: true })).toBeVisible({ timeout: 60_000 });
  await button("Highlighter").click();
  await penStroke(cdp, line(box.x + 200, box.x + 500, box.y + 200), 0.6);
  await button("Pen").click();
  await penStroke(cdp, line(box.x + 120, box.x + 220, box.y + 350), 0.6);
  expect((await savedPages(page, "paper", notebook)).map((p) => p.strokes), "the highlight and the note are saved").toEqual([2, 0]);
  await shot("paper");
  await button(title).click();
  await expect(page.getByRole("heading", { name: title, exact: true })).toBeVisible();
  await expect(page.getByText(/^\d \/ 3$/)).toBeVisible();

  // A pinch zooms page 1; the pen writes at the zoomed place; Fit width and
  // Go to page return to the first view.
  await goToPage(page, 1);
  await expect(page.getByText("1 / 3", { exact: true })).toBeVisible();
  const touch = (type: "touchStart" | "touchMove" | "touchEnd", points: PenPoint[]) =>
    cdp.send("Input.dispatchTouchEvent", { type, touchPoints: points.map((p, id) => ({ id, ...p })) });
  const spread = (half: number) => [{ x: box.x + 600 - half, y: box.y + 450 }, { x: box.x + 600 + half, y: box.y + 450 }];
  await touch("touchStart", spread(50));
  for (let half = 60; half <= 120; half += 10) await touch("touchMove", spread(half));
  await touch("touchEnd", []);
  const zoomedSpot = at(600, 330);
  const zoomedPaper = await screenPixels(page, zoomedSpot);
  await penStroke(cdp, line(zoomedSpot.x - 60, zoomedSpot.x + 60, zoomedSpot.y), 0.6);
  expect(await inkAt(page, zoomedSpot, zoomedPaper), "the zoomed pen writes under the pen").toBeGreaterThan(0.3 * hardInk);
  expect(await strokes()).toEqual([6, 3, 1]);
  await shot("zoomed");
  await button("View").click();
  await page.getByRole("button", { name: /Fit width$/ }).click();
  await goToPage(page, 1);
  // With two notes open, the tab strip moves the canvas and its page down.
  const lowered = (await boxOf(canvas)).y - box.y;
  await expect.poll(() => inkAt(page, { x: hard.x, y: hard.y + lowered }, paper.get(hard)!), { message: "the first view returns" }).toBeGreaterThan(0.8 * hardInk);

  // A reload: the lecture opens with the same pages, ink, text, and figure.
  await page.reload();
  await openTestNotebook(page, notebook);
  await page.getByRole("button", { name: `Open ${title}`, exact: false }).click();
  await canvas.waitFor({ timeout: 30_000 });
  await expect(page.getByText(/^1 \/ 3$/)).toBeVisible();
  await expect.poll(() => inkAt(page, hard, paper.get(hard)!), { message: "the hard line returns" }).toBeGreaterThan(0.8 * hardInk);
  expect(await inkAt(page, moved, paper.get(moved)!), "the red copy returns").toBeGreaterThan(0.3 * hardInk);
  saved = await pages();
  expect(saved.map((p) => p.strokes)).toEqual([6, 3, 1]);
  expect(saved[0].text).toContain("Definition 1");
  await shot("reloaded");

  // The library: the lecture is renamed and found by title; the paper moves
  // to a new Archive notebook, goes to the trash, and is restored there.
  await button("Library").click();
  await button(`${title} actions`).click();
  await button("Rename").click();
  await enterText(page.getByRole("textbox", { name: "Name", exact: true }), "Lecture 1 Compactness");
  await button("Rename").click();
  title = "Lecture 1 Compactness";
  await expect(page.getByRole("button", { name: `Open ${title}`, exact: false })).toBeVisible();
  await button("Back to library").click();
  await button("Search").click();
  await enterText(page.getByRole("textbox", { name: "Search notebooks and notes", exact: true }), "Compact");
  await expect(page.getByRole("button", { name: `Open ${title}`, exact: false })).toBeVisible();
  await expect(page.getByRole("button", { name: "Open paper", exact: false })).toHaveCount(0);
  await button("Clear search").click();
  await createTestNotebook(page, "Archive");
  await button("Back to library").click();
  await openTestNotebook(page, notebook);
  await button("paper actions").click();
  await button("Move").click();
  await button("Archive").click();
  await expect(button("paper actions")).toHaveCount(0);
  await button("Back to library").click();
  await openTestNotebook(page, "Archive");
  await button("paper actions").click();
  await button("Move to trash").click();
  await button("Trash").click();
  await button("paper actions").click();
  await button("Restore").click();
  await button("Archive").click();
  await button("Library").click();
  await openTestNotebook(page, "Archive");
  await expect(page.getByRole("button", { name: "Open paper", exact: false })).toBeVisible();
  expect((await storedPages(page, "paper", "Archive")).map((p) => p.strokes), "the paper keeps its notes").toEqual([2, 0]);
  await shot("library");

  // A sync client leaves a conflict copy of page 2 from the second device.
  // The More menu offers the comparison only once the copy exists; Keep both
  // pages adds the copy as a page.
  await button("Back to library").click();
  await openTestNotebook(page, notebook);
  await page.getByRole("button", { name: `Open ${title}`, exact: false }).click();
  await canvas.waitFor({ timeout: 30_000 });
  await button("More").click();
  await expect(button("Save")).toBeVisible();
  await expect(button("Compare conflicting versions"), "no conflict copy, no comparison").toHaveCount(0);
  await closePopover(page);
  await page.evaluate(async ({ notebook, title, svg }) => {
    const dir = await (await (await navigator.storage.getDirectory()).getDirectoryHandle(notebook)).getDirectoryHandle(title);
    const file = await (await dir.getDirectoryHandle("pages")).getFileHandle("0002.sync-conflict-20261002-101500-MATHNOT.svg", { create: true });
    const writable = await file.createWritable();
    await writable.write(svg);
    await writable.close();
  }, { notebook, title, svg: remotePage2 });
  await choose("More", "Compare conflicting versions");
  await expect(page.getByText("Syncthing: pages/0002.svg", { exact: true })).toBeVisible();
  await shot("conflict");
  await button("Keep both pages").click();
  await expect(page.getByText(/^\d \/ 4$/)).toBeVisible({ timeout: 30_000 });
  expect((await strokes()).toSorted((a, b) => a - b), "the copy of page 2 is a page of its own").toEqual([1, 2, 3, 6]);
  await button("More").click();
  await expect(button("Save")).toBeVisible();
  await expect(button("Compare conflicting versions"), "the conflict is resolved").toHaveCount(0);
  await closePopover(page);

  // The export: four A4 pages with the typed definition and the red heading.
  await choose("More", "Export PDF");
  const download = page.waitForEvent("download");
  await button("Export").click();
  const pdfPath = info.outputPath("lecture.pdf");
  await (await download).saveAs(pdfPath);
  const pdfInfo = execFileSync("pdfinfo", [pdfPath], { encoding: "utf8" });
  expect(pdfInfo).toMatch(/Pages:\s+4/);
  expect(pdfInfo).toMatch(/\(A4\)/);
  expect(execFileSync("pdftotext", [pdfPath, "-"], { encoding: "utf8" })).toContain("Definition 1");
  const prefix = info.outputPath("lecture-1");
  execFileSync("pdftoppm", ["-r", "72", "-png", "-f", "1", "-l", "1", "-singlefile", pdfPath, prefix]);
  const exported = await pngPixels(page, await readFile(`${prefix}.png`));
  expect(exported.filter(([red, green, blue]) => red > 180 && green < 90 && blue < 100).length, "the red heading and copy are exported").toBeGreaterThan(50);
});
