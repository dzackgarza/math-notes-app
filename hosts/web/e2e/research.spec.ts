import { expect } from "@playwright/test";
import { execFileSync } from "node:child_process";
import { readFile } from "node:fs/promises";
import { test, longPressDrag, enterText, save, goToPage, createTestNotebook, openTestNotebook, storedNote, penStroke, line, pngPixels, screenPixels, isOutline, isInk, pixelBounds, inkAt, pageIn, boxOf, closePopover, type PenPoint, type Rgb } from "./support.ts";

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
    await button("Share").click();
    for (const layer of exclude) await page.getByRole("switch", { name: layer, exact: true }).click();
    await shot(`export-${name}`);
    const download = page.waitForEvent("download");
    await button("Download PDF").click();
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
  // The panel lists the clippings in a scroll view; one off screen is hidden
  // or has no semantics node until the wheel scrolls it in.
  const clipping = async (number: number) => {
    const target = button(`Insert clipping ${number}`);
    await expect(async () => {
      if (!(await target.isVisible())) {
        // Wheel toward the number: up while it is below the first one shown.
        // None shows while the panel slides in.
        let first = 1;
        while (first < 10 && !(await button(`Insert clipping ${first}`).isVisible())) first++;
        if (first < 10) {
          const anchor = await boxOf(button(`Insert clipping ${first}`));
          await page.mouse.move(anchor.x + anchor.width / 2, anchor.y + anchor.height / 2);
          await page.mouse.wheel(0, number < first ? -200 : 200);
        }
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
  await button("Add page").click();
  await button("At end").click();
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
  await clipping(5);
  await button("Insert clipping 5").click();
  await button("Clippings").click();
  let other = await saved(proofs);
  const pasted = other.pages[0].groups.flatMap((group) => group.strokes);
  expect(pasted.map((s) => s.d).sort()).toEqual(lectureStrokes.map((s) => s.d).sort());
  for (const { id } of pasted) expect(lectureStrokes.map((s) => s.id)).not.toContain(id);

  // The pasted ink stays selected, and links to the bookmark in Lecture. The
  // region is the page, clear of the rail and its selected tool.
  const outline = await pixelBounds(page, {
    x: Math.ceil(sheet.x), y: Math.round(sheet.y), width: Math.floor(sheet.width) - 1, height: Math.floor(Math.min(sheet.height, 720 - sheet.y)),
  }, isOutline);
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
  const handle = page.getByText("Drag a copy", { exact: true });
  const from = await boxOf(handle);
  const to = await boxOf(canvas.nth(1));
  await longPressDrag(page, from, to);
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
