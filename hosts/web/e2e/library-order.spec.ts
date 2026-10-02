import { expect, type CDPSession, type Page } from "@playwright/test";
import { readFile } from "node:fs/promises";
import { test, enterText, focusText, save, goToPage, closeNote, addTag, createTestNotebook, openTestNotebook, penStroke, line, brightness, centerPixel, contrastIn, boxOf, COLORS, tabOrder, savedPages } from "./support.ts";

// The notes folder's library file, as the app saved it.
async function libraryMetadata(page: Page) {
  return JSON.parse(await page.evaluate(async () => {
    const root = await navigator.storage.getDirectory();
    return (await (await root.getFileHandle(".library.json")).getFile()).text();
  }));
}

// A short diagonal pen stroke from one canvas offset to another.
async function penDiagonal(cdp: CDPSession, from: { x: number; y: number }, to: { x: number; y: number }): Promise<void> {
  const pen = { pointerType: "pen" as const, force: 0.6 };
  await cdp.send("Input.dispatchMouseEvent", { type: "mousePressed", button: "left", clickCount: 1, ...from, ...pen });
  await cdp.send("Input.dispatchMouseEvent", { type: "mouseMoved", button: "left", buttons: 1, ...to, ...pen });
  await cdp.send("Input.dispatchMouseEvent", { type: "mouseReleased", button: "left", clickCount: 1, ...to, ...pen });
}

// One notes folder kept in order over a session. The user walks the empty
// library and the editor by keyboard, files a tagged image note and finds it
// again after a reload by its tag and its page thumbnail, works on two notes
// in tabs, reopens a note from the library on the first tap, moves a note
// between notebooks, trashes and restores it with its tags and description,
// renames a written note, sorts a notebook, and searches the library and the
// Open note picker. Each step asserts the screen and the files.
test("Flutter keeps a library in order: keyboard, tags, tabs, moves, trash, rename, sort, and search", async ({ page }, info) => {
  test.setTimeout(240_000);
  const button = (name: string) => page.getByRole("button", { name, exact: true });
  const card = (title: string) => page.getByRole("button", { name: `Open ${title}`, exact: false });
  const canvas = page.locator('canvas[id^="ink-canvas-"]:visible');
  const newNote = async (title: string) => {
    await button("New note").click();
    await enterText(page.getByRole("textbox", { name: "Title", exact: true }), title);
  };

  await page.goto("?root=opfs");
  const cdp = await page.context().newCDPSession(page);

  await test.step("the user walks the library and a new note's editor with Tab", async () => {
    await createTestNotebook(page);
    await button("Back to library").click();
    await button("Library").click();
    const library = await tabOrder(page, 16);
    const sidebar = library.indexOf("Recent"), search = library.indexOf("Search notebooks and notes");
    expect(sidebar, `the sidebar is in the Tab order: ${library}`).toBeGreaterThanOrEqual(0);
    expect(search, `the toolbar is in the Tab order: ${library}`).toBeGreaterThan(sidebar);
    expect(library.slice(sidebar, search), "Tab finishes the sidebar before the toolbar").toContain("Settings");
    // A hovered sidebar row shows a tint.
    const recent = await boxOf(button("Recent"));
    const tint = { x: recent.x + recent.width - 6, y: recent.y + recent.height / 2 };
    const idle = brightness(await centerPixel(page, tint));
    await button("Recent").hover();
    await expect.poll(async () => brightness(await centerPixel(page, tint)), "a hovered sidebar row is tinted").toBeLessThan(idle - 10);

    await openTestNotebook(page);
    await newNote("Diagram");
    await addTag(page, "topology");
    await button("Create").click();
    await canvas.waitFor({ timeout: 30_000 });
    const editor = await tabOrder(page, 30);
    for (const name of ["Library", "Open note", "Pages", "View", "More", "Pen", "Lasso", "Insert space", "Undo", "Redo"]) {
      expect(editor, `Tab reaches ${name}`).toContain(name);
    }
    expect(editor.some((name) => COLORS.test(name)), `Tab reaches Colors: ${editor}`).toBe(true);
    expect(editor.indexOf("More"), "Tab finishes the top bar before the rail").toBeLessThan(editor.indexOf("Pen"));
  });

  await test.step("the user puts an image in the tagged note and finds it by its tag and thumbnail after a reload", async () => {
    const chooser = page.waitForEvent("filechooser");
    await button("Image").click();
    await (await chooser).setFiles("../../core/tests/fixtures/render/full/0001.png");
    await expect(button("Delete selection")).toBeAttached();
    await save(page);
    await expect(page.getByRole("status", { name: /^Notebook save/ })).toHaveAccessibleName("Notebook save Saved");
    await button("Library").click();
    await page.reload();
    await page.getByRole("button", { name: /^topology/ }).click();
    await expect(page.getByRole("img", { name: "Diagram first page", exact: true })).toBeVisible();
    await page.screenshot({ path: info.outputPath("tagged-image-card.png") });
    await card("Diagram").click();
    await button("More").waitFor();
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
      return btoa(String.fromCharCode(...new Uint8Array(await file.arrayBuffer())));
    });
    expect(Buffer.from(saved, "base64")).toEqual(await readFile("../../core/tests/fixtures/render/full/0001.png"));
    expect((await libraryMetadata(page)).tags).toContainEqual({ name: "topology", color: "#2F6FEB" });
    await page.screenshot({ path: info.outputPath("image-note-reopened.png") });
    await closeNote(page);
  });

  await test.step("the user works on two notes in tabs, switching through the Open note button", async () => {
    await button("Library").click();
    await openTestNotebook(page);
    await newNote("Second");
    await button("Create").click();
    await closeNote(page);
    await expect(page.getByRole("heading", { name: "Test Notebook", exact: true })).toBeVisible();
    await newNote("First");
    await button("Create").click();
    await expect(page.getByRole("heading", { name: "First", exact: true })).toBeVisible();
    await canvas.waitFor({ timeout: 30_000 });
    let box = await boxOf(canvas);
    await penDiagonal(cdp, { x: box.x + 160, y: box.y + 150 }, { x: box.x + 240, y: box.y + 190 });
    await button("Add page").click();
    await button("At end").click();
    await goToPage(page, 2);
    await expect(page.getByText("2 / 2", { exact: true })).toBeVisible();

    await button("Open note").click();
    await page.getByRole("group", { name: "Second Test Notebook", exact: true }).click();
    await expect(page.getByRole("heading", { name: "Second", exact: true })).toBeVisible();
    await canvas.waitFor({ timeout: 30_000 });
    box = await boxOf(canvas);
    await penDiagonal(cdp, { x: box.x + 180, y: box.y + 220 }, { x: box.x + 260, y: box.y + 260 });
    await expect(page.getByText("1 / 1", { exact: true })).toBeVisible();
    await button("First").click();
    await expect(page.getByText("2 / 2", { exact: true })).toBeVisible();
    await save(page);
    await button("Second").click();
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
    // Closing a tab shows another open note; closing the last shows the library.
    await closeNote(page);
    await closeNote(page);
    await expect(page.getByRole("heading", { name: "Test Notebook", exact: true })).toBeVisible();
  });

  await test.step("the user opens a library note on the first tap, three times", async () => {
    await button("Back to library").click();
    await createTestNotebook(page, "Open timing");
    await newNote("Immediate");
    await button("Create").click();
    await closeNote(page);
    for (let attempt = 0; attempt < 3; attempt++) {
      const box = await card("Immediate").boundingBox();
      if (!box) throw new Error("Immediate note card has no bounds");
      const started = Date.now();
      await page.mouse.click(box.x + box.width / 2, box.y + box.height / 2);
      await expect(page.getByRole("heading", { name: "Immediate", exact: true })).toBeVisible({ timeout: 2_000 });
      await expect(canvas).toBeVisible({ timeout: 2_000 });
      expect(Date.now() - started).toBeLessThan(2_000);
      await closeNote(page);
      await expect(page.getByRole("heading", { name: "Open timing", exact: true })).toBeVisible();
    }
  });

  await test.step("the user moves a tagged note to another notebook and finds it by search and in Recent", async () => {
    await button("Back to library").click();
    await createTestNotebook(page, "Inbox");
    await newNote("Movable");
    await addTag(page, "algebra");
    await button("Create").click();
    await closeNote(page);
    await expect(page.getByRole("heading", { name: "Inbox", exact: true })).toBeVisible();

    await button("Back to library").click();
    await createTestNotebook(page, "Archive");
    await button("Back to library").click();
    await openTestNotebook(page, "Inbox");

    await button("Movable actions").click();
    await button("Move").click();
    await button("Archive").click();
    await expect(button("Movable actions")).toHaveCount(0);

    await button("Back to library").click();
    await openTestNotebook(page, "Archive");
    await expect(card("Movable")).toBeVisible();

    await button("Back to library").click();
    await enterText(page.getByRole("textbox", { name: "Search notebooks and notes", exact: true }), "Movable");
    await expect(card("Movable")).toBeVisible();

    await button("Recent").click();
    await expect(card("Movable")).toBeVisible();
  });

  await test.step("the user trashes and restores the note, then describes and tags it", async () => {
    await button("Movable actions").click();
    await button("Move to trash").click();

    await button("Trash").click();
    await expect(button("Movable actions")).toBeVisible();
    await button("Movable actions").click();
    await button("Restore").click();
    await button("Archive").click();

    await button("Library").click();
    await openTestNotebook(page, "Archive");
    await expect(card("Movable")).toBeVisible();

    // A tag made from the sidebar, then given to the note with its description
    // from the card menu; the sidebar tag lists the note.
    await button("New tag").click();
    await enterText(page.getByRole("textbox", { name: "Tag name", exact: true }), "geometry");
    await button("Add tag").click();
    await expect(page.getByRole("button", { name: /^geometry/ })).toBeVisible();
    await button("Movable actions").click();
    await button("Details and tags").click();
    await enterText(page.getByRole("textbox", { name: "Description", exact: true }), "Moved from Inbox");
    await addTag(page, "geometry");
    await button("Save details").click();
    await page.getByRole("button", { name: /^geometry/ }).click();
    await expect(card("Movable")).toBeVisible();

    const metadata = await libraryMetadata(page);
    expect(metadata.notes["Archive/Movable"].tags).toEqual(["algebra", "geometry"]);
    expect(metadata.notes["Archive/Movable"].description).toBe("Moved from Inbox");
    expect(metadata.tags.map(({ name }: { name: string }) => name)).toContain("geometry");
    expect(metadata.notes["Inbox/Movable"]).toBeUndefined();
    expect(metadata.notes[".trash/Movable"]).toBeUndefined();
  });

  await test.step("the user renames a written note, and its tab and pages follow", async () => {
    await button("Library").click();
    await createTestNotebook(page, "Shelf");
    await newNote("Rings");
    await button("Create").click();
    await canvas.waitFor({ timeout: 30_000 });
    const box = await boxOf(canvas);
    await penStroke(cdp, line(box.x + 150, box.x + 300, box.y + 250), 0.6);
    await save(page);
    await expect(page.getByRole("status", { name: /^Notebook save/ })).toHaveAccessibleName("Notebook save Saved");
    await button("Library").click();
    await newNote("Fields");
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
  });

  await test.step("the user sorts the notebook by name and date, and shows it as a list and a grid", async () => {
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
  });

  await test.step("the user searches the library and the Open note picker, which list the matching titles only", async () => {
    await button("Back to library").click();
    const search = page.getByRole("textbox", { name: "Search notebooks and notes", exact: true });
    await focusText(search);
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
});
