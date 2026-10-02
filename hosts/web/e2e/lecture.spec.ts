import { expect } from "@playwright/test";
import { execFileSync } from "node:child_process";
import { readFile } from "node:fs/promises";
import { test, longPressDrag, enterText, goToPage, whenSaved, createTestNotebook, openTestNotebook, storedNote, penStroke, line, pngPixels, screenPixels, isOutline, isInk, inkRow, pixelBounds, size, inkAt, boxOf, storedFills, closePopover, openColors, pickColor, storedPages, savedPages, type PenPoint, type Rgb, type Bounds } from "./support.ts";

test("Flutter lecture session: every core tool on one note, pages, a PDF beside it, reload, library, a sync conflict, and export", async ({ page, context }, info) => {
  test.setTimeout(600_000);
  await context.grantPermissions(["clipboard-read", "clipboard-write"]);
  const shot = (name: string) => page.screenshot({ path: info.outputPath(`${name}.png`) });
  const button = (name: string) => page.getByRole("button", { name, exact: true });
  const choose = async (menu: string, item: string | RegExp) => {
    await button(menu).click();
    await page.getByRole("button", { name: item, exact: typeof item === "string" }).click();
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
  await test.step("the left navigation opens pages, bookmarks, outlines, and layers", async () => {
    await button("Open navigation").click();
    await expect(page.getByText("Arrange pages", { exact: true })).toBeVisible();
    await page.getByText("Bookmarks", { exact: true }).click();
    await expect(page.getByText("No bookmarks", { exact: true })).toBeVisible();
    await page.getByText("Outlines", { exact: true }).click();
    await expect(page.getByText("No outlines", { exact: true })).toBeVisible();
    await page.getByText("Layers", { exact: true }).click();
    await expect(button("Hide Ink")).toBeVisible();
    await expect(button("Edit Ink")).toBeVisible();
    await button("Close navigation").click();
  });
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
  await choose("Add page", "At end");
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
  // A second device later edits page 2 as it is now (the sync conflict
  // below), once both strokes are saved.
  expect(await strokes()).toEqual([5, 2]);
  const remotePage2 = await whenSaved(() => page.evaluate(async ({ notebook, title }) => {
    const dir = await (await (await navigator.storage.getDirectory()).getDirectoryHandle(notebook)).getDirectoryHandle(title);
    return (await (await (await dir.getDirectoryHandle("pages")).getFileHandle("0002.svg")).getFile()).text();
  }, { notebook, title }));
  await choose("Pages", "Paper for new pages");
  await button("Lined paper").click();
  await button("Done").click();
  await choose("Add page", "At end");
  await expect(page.getByText("2 / 3", { exact: true })).toBeVisible();
  await goToPage(page, 3);
  await penStroke(cdp, line(light.x - 60, light.x + 60, light.y), 0.6);
  expect(await strokes()).toEqual([5, 2, 1]);

  // A page inserted before page 3 by mistake is deleted in the overview;
  // page 1 is duplicated and its copy dragged to the end.
  await choose("Add page", /^Before page/);
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
  await longPressDrag(page, from, to);
  // A new page file takes the number after the highest of the note's pages
  // (NextPageFile): the copy reuses the number of the deleted page.
  await expect.poll(async () => (await storedPages(page, title, notebook)).map((p) => p.file)).toEqual(["pages/0001.svg", "pages/0002.svg", "pages/0003.svg", "pages/0004.svg"]);
  await shot("overview");
  await tile(1).click();
  await expect(page.getByText("1 / 4", { exact: true })).toBeVisible();
  let saved = await pages();
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
  await choose("More", "Share");
  const download = page.waitForEvent("download");
  await button("Download PDF").click();
  const pdfPath = info.outputPath("lecture.pdf");
  await (await download).saveAs(pdfPath);
  const pdfInfo = execFileSync("pdfinfo", [pdfPath], { encoding: "utf8" });
  expect(pdfInfo).toMatch(/Pages:\s+4/);
  expect(pdfInfo).toMatch(/\(A4\)/);
  // The text box sets "fi" as a ligature; NFKC reads it as two letters.
  expect(execFileSync("pdftotext", [pdfPath, "-"], { encoding: "utf8" }).normalize("NFKC")).toContain("Definition 1");
  const prefix = info.outputPath("lecture-1");
  execFileSync("pdftoppm", ["-r", "72", "-png", "-f", "1", "-l", "1", "-singlefile", pdfPath, prefix]);
  const exported = await pngPixels(page, await readFile(`${prefix}.png`));
  expect(exported.filter(([red, green, blue]) => red > 180 && green < 90 && blue < 100).length, "the red heading and copy are exported").toBeGreaterThan(50);
});
