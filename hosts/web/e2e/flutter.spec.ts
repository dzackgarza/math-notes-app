import { expect } from "@playwright/test";
import { execFileSync } from "node:child_process";
import { readFile } from "node:fs/promises";
import { test, focusText, enterText, save, goToPage, createTestNotebook, openTestNotebook, beginTestNote, penStroke, line, pngPixels, capture, screenPixels, brightness, isOutline, isInk, inkLength, pixelBounds, size, inkAt, centerPixel, openNewNote, pageIn, boxOf, isSalmon, closePopover, pickColor, savedPages, linedPaper, penDrag, penHold, penRelease, type PenPoint, type Rgb, type Bounds } from "./support.ts";

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
  // The page below the toolbar, split at the middle: the wrapped box is in
  // the left half and the one-word box in the right half. The left half
  // starts on the page, right of the rail.
  const top = Math.round(box.y) + 120;
  const sheetLeft = Math.round(pageIn(box).x) + 4;
  const left = { x: sheetLeft, y: top, width: 610 - sheetLeft, height: 460 };
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

  // The ruled lasso outlines the lines it covers while the pen is down. The
  // region is the page, clear of the rail and its selected tool.
  const sheet = pageIn(box);
  const outline = () => pixelBounds(page, {
    x: Math.ceil(sheet.x), y: rules[0] + 4, width: Math.floor(sheet.width) - 1, height: Math.round(4.5 * spacing),
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
