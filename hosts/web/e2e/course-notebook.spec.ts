import { expect } from "@playwright/test";
import { test, enterText, closeNote, addTag, createTestNotebook, openTestNotebook, capture, centerPixel, textIn, contrastIn, inView, boxOf, BOARD, isRibbon, openMenuAt, type Box, type Rgb } from "./support.ts";

// A user sets up the notebooks of a course in an empty library. A first New
// Notebook sheet is closed with Escape, and a second one with a typed title
// asks before it discards it. The user makes a problem-set notebook in Ochre
// cloth, saves a note template from its New Note sheet, and trashes and
// restores its first note through the card menus. A lecture notebook in
// Forest cloth with a spine is renamed. A seminar note is saved as a draft,
// resumed after a reload, saved as a template, and created from that
// template after a second reload, which also shows the renamed lecture
// notebook with every field. Each step asserts the screen and the files.
test("Flutter course notebook: set up a course notebook", async ({ page }, info) => {
  test.setTimeout(300_000);
  page.on("pageerror", error => console.error(error.stack));
  page.on("console", message => { if (message.type() === "error") console.error(message.text()); });
  const button = (name: string) => page.getByRole("button", { name, exact: true });
  const text = (content: string) => page.getByText(content, { exact: true });
  const covers: Record<string, Rgb> = {
    Navy: [0x24, 0x32, 0x4a], Oxblood: [0x5b, 0x23, 0x28], Forest: [0x2f, 0x4a, 0x3a], Ochre: [0xa8, 0x7b, 0x2c],
  };

  await page.goto("?root=opfs");

  await test.step("the user opens a New Notebook sheet and closes it unchanged with Escape", async () => {
    expect(await contrastIn(page, button("New notebook")), "New notebook is legible").toBeGreaterThan(4.5);
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
  });

  await test.step("the user types a title in a second sheet, keeps editing, and then discards it", async () => {
    const title = page.getByRole("textbox", { name: "Notebook title", exact: true });
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

  await test.step("the user makes a problem-set notebook in Ochre cloth", async () => {
    await button("New notebook").click();
    await enterText(page.getByRole("textbox", { name: "Notebook title", exact: true }), "Problem sets");
    await addTag(page, "groups");
    await expect(text("Cover color")).toBeVisible();
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
    // The preview is the cover: the title on its label, set in the chosen cloth.
    const label = await boxOf(text("Problem sets"));
    await expect(async () => {
      // The cloth shows in the 10 px gap between the page and the label.
      const [cloth] = await capture(page, { x: Math.round(label.x + label.width / 2), y: Math.round(label.y) - 9, width: 1, height: 1 });
      expect(cloth, "the preview cover is in the chosen cloth").toEqual(covers.Ochre);
    }).toPass({ timeout: 5_000 });

    const location = await textIn(page, await boxOf(button("My Notes")));
    expect(location.left, "the location control starts under its heading")
      .toBeCloseTo((await textIn(page, await boxOf(text("Location")))).left, -1);
    const later = await textIn(page, await boxOf(text("You can move this notebook later.")));
    expect(later.contrast, "the location note is legible").toBeGreaterThan(4.5);
    await page.screenshot({ path: info.outputPath("new-notebook.png") });
    expect(await contrastIn(page, button("Create")), "Create is legible").toBeGreaterThan(4.5);
    await button("Create").click();
  });

  await test.step("the user saves a note template from the notebook's New Note sheet and makes the first note", async () => {
    // A new notebook opens; its New Note sheet takes the notebook's tags.
    expect(await contrastIn(page, button("New note")), "New note is legible").toBeGreaterThan(4.5);
    await button("New note").click();
    await enterText(page.getByRole("textbox", { name: "Title", exact: true }), "Week 1");
    const change = await textIn(page, await boxOf(button("Change notebook · Problem sets")));
    expect(change.left, "the notebook control starts under its heading")
      .toBeCloseTo((await textIn(page, await boxOf(text("Notebook")))).left, -1);
    // Save as template first: its scroll into view moves the heading.
    const save = await boxOf(button("Save as template"));
    const heading = await boxOf(text("Templates"));
    for (const name of ["Save as template", "Save as draft", "Cancel", "Portrait", "Landscape"]) {
      expect(await contrastIn(page, button(name)), `${name} is legible`).toBeGreaterThan(4.5);
    }
    expect(save.y - (heading.y + heading.height), "Save as template is under the Templates heading").toBeGreaterThanOrEqual(0);
    expect(save.y - (heading.y + heading.height)).toBeLessThan(30);
    await (await inView(button("Save as template"))).click();
    await enterText(page.getByRole("textbox", { name: "Template name", exact: true }), "Problem set paper");
    await button("Save template").click();
    await expect(page.getByRole("status", { name: "Template saved", exact: true })).toBeVisible();
    await button("New note").click();
    await enterText(page.getByRole("textbox", { name: "Title", exact: true }), "Week 1");
    const template = await boxOf(page.getByRole("button", { name: "Problem set paper", exact: false }));
    const summary = await textIn(page, { ...template, y: template.y + template.height / 2, height: template.height / 2 });
    expect(summary.contrast, "the template summary is legible").toBeGreaterThan(4.5);
    await page.screenshot({ path: info.outputPath("new-note.png") });
    await button("Create").click();
    await closeNote(page);
  });

  await test.step("the user trashes the note from its card menu and checks the library chrome", async () => {
    const noteMenu = ["Pin note", "Details and tags", "Rename", "Move", "Move to trash"].map(button);
    await openMenuAt(button("Week 1 actions"), noteMenu);
    await page.screenshot({ path: info.outputPath("note-menu.png") });
    await button("Move to trash").click();
    await expect(button("Week 1 actions")).toHaveCount(0);

    await button("Back to library").click();
    const card = await boxOf(page.getByRole("button", { name: "Open Problem sets", exact: false }));
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
  });

  await test.step("the user opens the notebook menu, then restores the note from the trash", async () => {
    await openMenuAt(button("Problem sets notebook actions"), [button("Rename"), button("Move to trash")]);
    await page.screenshot({ path: info.outputPath("notebook-menu.png") });
    await button("Rename").click();
    await button("Cancel").click();

    await button("Trash").click();
    await openMenuAt(page.getByRole("button", { name: "Open Week 1", exact: false }), [button("Restore")]);
    await page.screenshot({ path: info.outputPath("trash-menu.png") });
    await button("Restore").click();
    await button("Problem sets").click();
    await button("Library").click();
    await openTestNotebook(page, "Problem sets");
    await expect(page.getByRole("button", { name: "Open Week 1", exact: false })).toBeVisible();
    await button("Back to library").click();
  });

  await test.step("the user makes a lecture notebook in Forest cloth with a spine and renames it", async () => {
    await button("New notebook").click();
    await enterText(page.getByRole("textbox", { name: "Notebook title", exact: true }), "Algebra");
    await enterText(page.getByRole("textbox", { name: "Description", exact: true }), "Lecture notes");
    await addTag(page, "groups");
    await button("Lined").click();
    await button("Spine").click();
    await button("Forest").click();
    await button("Create").click();
    await button("New note").click();
    await enterText(page.getByRole("textbox", { name: "Title", exact: true }), "Rings");
    await button("Create").click();
    await button("More").waitFor();
    await button("Library").click();
    await expect(page.getByText("Lecture notes", { exact: true })).toBeVisible();
    await page.screenshot({ path: info.outputPath("notebook-info.png") });
    await button("Algebra notebook actions").click();
    await button("Rename").click();
    await enterText(page.getByRole("textbox", { name: "Name", exact: true }), "Field theory");
    await button("Rename").click();
    await expect(button("Field theory notebook actions")).toBeVisible();
  });

  await test.step("the user starts a seminar note on lined landscape Letter paper and saves it as a draft", async () => {
    await button("Back to library").click();
    await createTestNotebook(page, "Reading seminar");
    await button("New note").click();
    await enterText(page.getByRole("textbox", { name: "Title", exact: true }), "Seminar");
    await button("Lined").click();
    await addTag(page, "analysis");
    await button("Letter").click();
    await button("Landscape").click();
    await button("Save as draft").click();
    await expect(page.getByRole("status", { name: "Draft saved", exact: true })).toBeVisible();
  });

  await test.step("the user reloads, resumes the draft, and saves its settings as a template", async () => {
    await page.reload();
    await openTestNotebook(page, "Reading seminar");
    await button("New note").click();
    await expect(page.getByRole("textbox", { name: "Title", exact: true })).toHaveValue("Seminar");
    await (await inView(button("Save as template"))).click();
    await enterText(page.getByRole("textbox", { name: "Template name", exact: true }), "Proof paper");
    await button("Save template").click();
    await expect(page.getByRole("status", { name: "Template saved", exact: true })).toBeVisible();
  });

  await test.step("the user reloads again and creates the seminar note from the template", async () => {
    await page.reload();
    await openTestNotebook(page, "Reading seminar");
    await button("New note").click();
    await button("Plain").click();
    await addTag(page, "temporary");
    await (await inView(page.getByRole("button", { name: "Proof paper", exact: false }))).click();
    await expect(page.getByRole("img", { name: "First page preview", exact: true })).toBeVisible();
    await page.screenshot({ path: info.outputPath("settings-selected.png") });
    await expect(button("Remove tag analysis")).toBeVisible();
    await expect(button("Remove tag temporary")).toHaveCount(0);
    await button("Create").click();
    await button("More").waitFor();
    const stored = await page.evaluate(async () => {
      const root = await navigator.storage.getDirectory();
      const notebook = await root.getDirectoryHandle("Reading seminar");
      const note = await notebook.getDirectoryHandle("Seminar");
      return {
        manifest: await (await (await note.getFileHandle("notebook.json")).getFile()).text(),
        metadata: await (await (await root.getFileHandle(".library.json")).getFile()).text(),
      };
    });
    expect(JSON.parse(stored.manifest).template).toBe("lined-medium");
    expect(JSON.parse(stored.manifest).pageSize).toEqual([792, 612]);
    expect(JSON.parse(stored.metadata).notes["Reading seminar/Seminar"].tags).toEqual(["analysis"]);
    expect(JSON.parse(stored.metadata).draft).toBeUndefined();
    await closeNote(page);
    await button("Back to library").click();
  });

  await test.step("after the reload, the renamed lecture notebook keeps its note and metadata in the files", async () => {
    await openTestNotebook(page, "Field theory");
    await page.getByRole("button", { name: "Open Rings", exact: false }).click();
    await button("More").waitFor();
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
    expect(metadata.folders["Field theory"]).toMatchObject({ paper: "lined-medium", coverColor: "#2F4A3A", coverStyle: "spine", tags: ["groups"] });
  });

  // After the reload every field shows. A cover's left edge is the 12 px
  // spine in a darker shade of the Forest cloth.
  const forest = covers.Forest;
  const expectCover = async (cover: Box, where: string) => {
    // The cloth shows between the spine and the inset page.
    expect(await centerPixel(page, { x: cover.x + 15, y: cover.y + 50 }), `the ${where} is in the Forest cloth`).toEqual(forest);
    const spine = await centerPixel(page, { x: cover.x + 6, y: cover.y + 50 });
    expect(spine[1], `the ${where} has a spine`).toBeLessThan(forest[1] - 10);
  };
  // A tag chip whose text lies in `area`.
  const chipIn = async (name: string, area: Box) => {
    for (const chip of await page.getByText(name, { exact: true }).all()) {
      const box = await chip.boundingBox();
      if (box && box.x >= area.x && box.x + box.width <= area.x + area.width && box.y >= area.y && box.y + box.height <= area.y + area.height) return true;
    }
    return false;
  };

  await test.step("the user sees the lecture notebook's cover and tags and adds a tag from its chips", async () => {
    await closeNote(page);
    const header = await boxOf(button("Add tag to Field theory"));
    await expect(page.getByRole("heading", { name: "Field theory", exact: true })).toBeVisible();
    await expect(page.getByText("Lecture notes", { exact: true })).toBeVisible();
    const notebookCover = await boxOf(page.getByRole("heading", { name: "Field theory", exact: true }));
    await expectCover({ x: notebookCover.x - 132, y: notebookCover.y, width: 112, height: 160 }, "notebook view cover");
    // The chips row, across the content: a new chip moves the + to the right.
    const row = { x: 0, y: header.y - 10, width: page.viewportSize()!.width, height: header.height + 20 };
    expect(await chipIn("groups", row), "the notebook view shows the tag").toBe(true);
    await page.screenshot({ path: info.outputPath("notebook-view.png") });

    // The tag chips' + adds a tag to the notebook.
    await button("Add tag to Field theory").click();
    await addTag(page, "fields");
    await button("Save details").click();
    await expect.poll(() => chipIn("fields", row), { message: "the new tag joins the chips" }).toBe(true);
    // The sidebar counts the notebook that carries the tag.
    await expect(page.getByRole("button", { name: "fields", exact: false }).first()).toHaveAccessibleName(/^fields\s*1$/);

    await button("Back to library").click();
    const opener = page.getByRole("button", { name: "Open Field theory", exact: false });
    await expectCover(await boxOf(opener), "card");
    // The card is one button; its chips are part of its name.
    await expect(opener, "the card shows the tags").toHaveAccessibleName(/ groups fields$/);
    await page.screenshot({ path: info.outputPath("library-card.png") });
  });

  // A note made after the reload starts on the notebook's paper and shows
  // the notebook's description under its title.
  await test.step("the user makes a second lecture note", async () => {
    await openTestNotebook(page, "Field theory");
    await button("New note").click();
    await enterText(page.getByRole("textbox", { name: "Title", exact: true }), "Galois");
    await button("Create").click();
    await expect(page.getByRole("heading", { name: "Galois", exact: true })).toBeVisible({ timeout: 30_000 });
    const title = await boxOf(page.getByRole("heading", { name: "Galois", exact: true }));
    const description = await boxOf(page.getByText("Lecture notes", { exact: true }).filter({ visible: true }));
    expect(description.y, "the description is under the title").toBeGreaterThanOrEqual(title.y + title.height - 2);
    await page.screenshot({ path: info.outputPath("editor-description.png") });
    const galois = await page.evaluate(async () => {
      const note = await (await (await navigator.storage.getDirectory()).getDirectoryHandle("Field theory")).getDirectoryHandle("Galois");
      return JSON.parse(await (await (await note.getFileHandle("notebook.json")).getFile()).text());
    });
    expect(galois.template, "the new note is on the notebook's paper").toBe("lined-medium");
  });
});
