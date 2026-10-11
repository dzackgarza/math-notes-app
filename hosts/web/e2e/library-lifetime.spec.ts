import { test, expect } from "./native-desktop.ts";
import { enterText, addTag, darkestPixel, penStroke, line, boxOf, screenPixels, inkAt, closePopover, goToPage, createTestNotebook, openTestNotebook, type PenPoint, type Rgb } from "./workflow-actions.ts";
import { savedPages, storedPages } from "./workflow-files.ts";
import { readdir, readFile } from "node:fs/promises";
import { join } from "node:path";
import { execFileSync } from "node:child_process";

test("Flutter lifetime: first launch, folder choice, three written pages, restart, reconnection, library changes, and export", async ({ desktop }, info) => {
  test.setTimeout(900_000);
  let page = desktop.page;
  const shot = (name: string) => page.screenshot({ path: info.outputPath(`${name}.png`) });
  const button = (name: string) => page.getByRole("button", { name, exact: true });
  await expect(page.getByText("Your notes live in a folder on this device.", { exact: true })).toBeVisible();
  await shot("first-launch");
  await desktop.chooseFolder();
  await expect(page.getByText("Your notebooks appear here.", { exact: true })).toBeVisible();
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
  let canvas = page.locator('canvas[id^="ink-canvas-"]:visible');
  await canvas.waitFor({ timeout: 30_000 });
  const box = await boxOf(canvas);
  const cdp = await page.context().newCDPSession(page);
  const pages = () => savedPages(page, desktop.notes, "Integrals", "Analysis");
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
  await expect(async () => expect(await inked()).toEqual([true, true, true, false])).toPass();
  expect(await strokes()).toEqual([3]);
  await shot("page-1-written");

  // The stroke eraser takes the second row; undo and redo take it back and
  // away again, on screen and in the file.
  await button("Eraser").click();
  await button("Eraser").click();
  await button("Stroke").click();
  await closePopover(page);
  await penStroke(cdp, [-40, -20, 0, 20, 40].map((dy) => ({ x: rows[1].x, y: rows[1].y + dy })), 0.6);
  await expect(async () => expect(await inked()).toEqual([true, false, true, false])).toPass();
  expect(await strokes()).toEqual([2]);
  await button("Undo").click();
  await expect(async () => expect(await inked()).toEqual([true, true, true, false])).toPass();
  expect(await strokes()).toEqual([3]);
  await button("Redo").click();
  await expect(async () => expect(await inked()).toEqual([true, false, true, false])).toPass();
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
  await expect(async () => expect(await inked()).toEqual([true, false, false, true])).toPass();
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
  await expect(async () => expect(await inked(), "a new page is blank").toEqual([false, false, false, false])).toPass();
  await write(rows[0]);
  await write(rows[1]);
  await expect(async () => expect(await inked()).toEqual([true, true, false, false])).toPass();
  await addPage(3);
  await write(rows[2]);
  await expect(async () => expect(await inked()).toEqual([false, false, true, false])).toPass();
  expect(await strokes()).toEqual([3, 2, 1]);
  await shot("page-3-written");
  await button("Pages").click();
  await button("Page overview").click();
  for (const number of [1, 2, 3]) await expect(button(`Page ${number}`)).toBeVisible();
  await shot("page-overview");
  await button("Page 1").click();
  await expect(page.getByText("1 / 3", { exact: true })).toBeVisible();
  await expect(async () => expect(await inked()).toEqual([true, false, false, true])).toPass();

  // Reload retains the real folder capability in the same browser session.
  await page.reload();
  await expect(page.getByRole("button", { name: "Open Analysis", exact: false })).toBeVisible({ timeout: 30_000 });
  await expect(page.getByText(/^1 note/)).toBeVisible();
  await shot("library-after-restart");
  await openTestNotebook(page, "Analysis");
  await page.getByRole("button", { name: "Open Integrals", exact: false }).click();
  await expect(page.getByText("1 / 3", { exact: true })).toBeVisible();
  expect(await boxOf(canvas), "the canvas keeps its place after a restart").toEqual(box);
  await expect(async () => expect(await inked()).toEqual([true, false, false, true])).toPass();
  await goToPage(page, 2);
  await expect(page.getByText("2 / 3", { exact: true })).toBeVisible();
  await expect(async () => expect(await inked()).toEqual([true, true, false, false])).toPass();
  await goToPage(page, 3);
  await expect(page.getByText("3 / 3", { exact: true })).toBeVisible();
  await expect(async () => expect(await inked()).toEqual([false, false, true, false])).toPass();
  expect(await strokes()).toEqual([3, 2, 1]);

  // A restart whose folder needs a permission gesture.
  page = await desktop.restart();
  canvas = page.locator('canvas[id^="ink-canvas-"]:visible');
  await expect(button("Reconnect folder")).toBeVisible();
  await shot("reconnect");
  await button("Reconnect folder").click();
  await desktop.allow("Allow this time");
  await openTestNotebook(page, "Analysis");
  await page.getByRole("button", { name: "Open Integrals", exact: false }).click();
  await expect(page.getByText("1 / 3", { exact: true })).toBeVisible();
  await expect(async () => expect(await inked()).toEqual([true, false, false, true])).toPass();

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

  const folders = await readdir(desktop.notes);
  const metadata = JSON.parse(await readFile(join(desktop.notes, ".library.json"), "utf8"));
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
  const stored = await storedPages(page, desktop.notes, "Integrals", "Topology");
  expect(stored.map((saved) => saved.strokes)).toEqual([3, 2, 1]);
  expect(stored[0].text).toContain("Theorem 1");
  await page.getByRole("button", { name: "Open Integrals", exact: false }).click();
  await expect(page.getByText("1 / 3", { exact: true })).toBeVisible();
  await expect(async () => expect(await inked()).toEqual([true, false, false, true])).toPass();
  await button("More").click();
  await button("Export PDF").click();
  const download = page.waitForEvent("download");
  await button("Export").click();
  const pdfPath = info.outputPath("integrals.pdf");
  await (await download).saveAs(pdfPath);
  expect(execFileSync("pdfinfo", [pdfPath], { encoding: "utf8" })).toMatch(/Pages:\s+3/);
  expect(execFileSync("pdftotext", [pdfPath, "-"], { encoding: "utf8" })).toContain("Theorem 1");
});

