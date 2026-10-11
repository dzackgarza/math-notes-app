import { test, expect } from "./native-desktop.ts";
import { save, enterText, penStroke, line, type PenPoint, type Rgb, createTestNotebook, boxOf, screenPixels, inkAt, closePopover, pageIn, isInk, pixelBounds, isOutline, openTestNotebook, longPressDrag } from "./workflow-actions.ts";
import { storedNote } from "./workflow-files.ts";
import { execFileSync } from "node:child_process";
import { readFile } from "node:fs/promises";
import { pngPixels, goToPage } from "./workflow-actions.ts";

test("Flutter research session: layers, clippings, bookmarks, links between notes, split view, reload, and export", async ({ desktop }, info) => {
  test.setTimeout(600_000);
  const page = desktop.page;
  const shot = (name: string) => page.screenshot({ path: info.outputPath(`${name}.png`) });
  const button = (name: string) => page.getByRole("button", { name, exact: true });
  const lecture = ["Topology", "Lecture"];
  const proofs = ["Topology", "Proofs"];
  const saved = async (path: string[]) => {
    await save(page);
    await expect(page.getByRole("status", { name: /^Notebook save/ })).toHaveAccessibleName("Notebook save Saved");
    return storedNote(page, desktop.notes, path);
  };
  const strokeCounts = (note: Awaited<ReturnType<typeof storedNote>>, index = 0) =>
    note.pages[index].groups.map((group) => group.strokes.length);

  await desktop.chooseFolder();
  await expect(page.getByRole("button", { name: "New notebook", exact: true })).toBeVisible({ timeout: 90_000 });
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
  await expect(async () => expect(await inked()).toEqual([true, true, false])).toPass();
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
  await expect(async () => expect(await inked(), "the eraser takes the sketch only").toEqual([true, false, false])).toPass();
  await button("Undo").click();
  await expect(async () => expect(await inked()).toEqual([true, true, false])).toPass();
  await button("Lasso").click();
  await lasso(box.y + 130, box.y + 300);
  await button("Delete selection").click();
  await expect(async () => expect(await inked(), "the lasso takes the sketch only").toEqual([true, false, false])).toPass();
  await button("Undo").click();
  await expect(async () => expect(await inked()).toEqual([true, true, false])).toPass();
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
  await expect(async () => expect(await inked()).toEqual([true, false, false])).toPass();
  await layers(() => button("Show Sketch").click());
  await expect(async () => expect(await inked()).toEqual([true, true, false])).toPass();

  // A layer for labels, merged down into the ink.
  await layers(() => addLayer("Labels"));
  await button("Pen").click();
  await write(rows[2]);
  await expect(async () => expect(await inked()).toEqual([true, true, true])).toPass();
  await layers(() => button("Merge down Labels").click());
  note = await saved(lecture);
  expect(note.layers.map((layer) => layer.name)).toEqual(["Sketch", "Ink"]);
  expect(note.pages[0].groups.map((group) => group.id)).toEqual([sketch, ink]);
  expect(strokeCounts(note)).toEqual([1, 2]);
  await expect(async () => expect(await inked()).toEqual([true, true, true])).toPass();

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
  await expect(async () => expect(await inked()).toEqual([true, false, true])).toPass();
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
    await expect(async () => {
      if ((await target.count()) === 0) {
        // The wheel scrolls the list under the pointer: over the lowest clipping
        // the list has built, kept on screen. boundingBox does not scroll, as
        // boxOf would, back to that clipping.
        const lowest = await page.getByRole("button", { name: /^Insert clipping \d+$/ }).last().boundingBox();
        const viewport = page.viewportSize();
        if (!lowest || !viewport) throw new Error("No clipping in the panel to scroll from");
        await page.mouse.move(lowest.x + lowest.width / 2, Math.min(lowest.y + lowest.height / 2, viewport.height - 20));
        await page.mouse.wheel(0, 200);
      }
      await expect(target).toBeVisible({ timeout: 500 });
    }).toPass({ timeout: 10_000 });
  };
  for (const number of [1, 2, 3, 4]) await clipping(number);
  await button("Save selected content").click();
  await clipping(5);
  await shot("clipping-saved");
  const clippings = await storedNote(page, desktop.notes, [".clippings"]);
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
  await expect(page.getByRole("heading", { name: "Topology", exact: true })).toBeVisible({ timeout: 30_000 });
  await button("New note").click();
  await enterText(page.getByRole("textbox", { name: "Title", exact: true }), "Proofs");
  await button("Create").click();
  await expect(page.getByRole("heading", { name: "Proofs", exact: true })).toBeVisible({ timeout: 30_000 });
  await button("Clippings").click();
  await clipping(5);
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
  await expect(page.getByRole("heading", { name: "Lecture", exact: true })).toBeVisible({ timeout: 30_000 });
  await expect(page.getByText("2 / 2", { exact: true })).toBeVisible();

  // After a reload, both notes keep their content and the link still works.
  await page.reload();
  await openTestNotebook(page, "Topology");
  await page.getByRole("button", { name: "Open Proofs", exact: false }).click();
  await expect(page.getByRole("heading", { name: "Proofs", exact: true })).toBeVisible({ timeout: 30_000 });
  other = await storedNote(page, desktop.notes, proofs);
  expect(other.pages[0].links).toEqual([crossLink]);
  expect(other.pages[0].texts).toContainEqual(["Lemma 2", "Proof."]);
  note = await storedNote(page, desktop.notes, lecture);
  expect(note.pages.map((saved) => saved.groups.map((group) => group.strokes.length))).toEqual([[2], [1]]);
  expect(note.pages[0].links).toEqual([bookmark]);
  await followLinks(true);
  await page.mouse.click(pastedCenter.x, pastedCenter.y);
  await expect(page.getByRole("heading", { name: "Lecture", exact: true })).toBeVisible({ timeout: 30_000 });
  await expect(page.getByText("2 / 2", { exact: true })).toBeVisible();
  await shot("followed-after-reload");
  await followLinks(false);

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
  const handle = page.getByText("Drag a copy", { exact: true });
  const from = await boxOf(handle);
  const to = await boxOf(canvas.nth(1));
  await longPressDrag(page, from, to);
  await shot("dragged-between-panes");
  const row = note.pages[1].groups[0].strokes.map((s) => s.id);
  await expect.poll(async () => (await storedNote(page, desktop.notes, proofs)).pages[0].groups.flatMap((group) => group.strokes).length, { timeout: 15_000 }).toBe(3);
  other = await storedNote(page, desktop.notes, proofs);
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
  await expect(page.getByRole("heading", { name: "Proofs", exact: true })).toBeVisible({ timeout: 30_000 });
  const proofsPdf = annotations(await exportPdf("proofs"));
  expect(proofsPdf).toContain(`"/URI":"u:../Lecture/${destination}"`);
});
