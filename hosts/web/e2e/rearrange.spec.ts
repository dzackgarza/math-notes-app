import { expect } from "@playwright/test";
import { test, enterText, goToPage, createTestNotebook, openTestNotebook, penStroke, line, capture, settled, screenPixels, isOutline, isInk, pixelBounds, size, inkAt, pageIn, boxOf, storedFills, closePopover, pickColor, savedPages, linedPaper, penDrag, penHold, penRelease, type PenPoint, type Rgb, type Bounds } from "./support.ts";

// A student rearranges a derivation. On a dotted sheet they recolor a line,
// move, cut, paste, copy, and delete a line with the lasso, take lines with
// the rectangle and the oval, and scroll down to resize and duplicate a
// figure. On a lined sheet with two columns, the ruled lasso and the ruled
// eraser take whole words of the lines under the pen. On a second lined
// sheet, insert space makes room in each mode and pushes a word onto a new
// page, which a reload keeps.
test("Flutter rearrange session: recolor, lasso edits, shape selections, resize and duplicate, ruled selections, and insert space", async ({ page, context }, info) => {
  test.setTimeout(300_000);
  await context.grantPermissions(["clipboard-read", "clipboard-write"]);
  const button = (name: string) => page.getByRole("button", { name, exact: true });
  const notebook = "Derivations";
  const canvas = page.locator('canvas[id^="ink-canvas-"]:visible');
  const newNote = async (title: string, ...paper: string[]) => {
    await button("New note").click();
    await enterText(page.getByRole("textbox", { name: "Title", exact: true }), title);
    for (const choice of paper) await button(choice).click();
    await button("Create").click();
    await expect(page.getByRole("heading", { name: title, exact: true })).toBeVisible();
    await canvas.waitFor({ timeout: 30_000 });
  };
  const toLibrary = async () => {
    await button("Library").click();
    await expect(page.getByRole("heading", { name: notebook, exact: true })).toBeVisible();
  };

  await page.goto("?root=opfs");
  await createTestNotebook(page, notebook);
  await newNote("Derivation");
  const box = await boxOf(canvas);
  const cdp = await page.context().newCDPSession(page);

  await test.step("a lasso selection takes a palette color, and the pen keeps its own", async () => {
    const gesture = (points: [number, number][]) =>
      penStroke(cdp, points.map(([x, y]) => ({ x: box.x + x, y: box.y + y })), 0.6);
    await gesture([[160, 150], [200, 170], [240, 190]]);
    await button("Lasso").click();
    await gesture([[130, 120], [200, 115], [270, 120], [275, 170], [270, 220], [200, 225], [130, 220], [125, 170], [130, 120]]);
    await expect(button("Delete selection")).toBeAttached();
    await pickColor(page, "#d92d39");
    await button("Pen").click();
    // A pen-down away from a selection only clears it (Write, clearSelOnly).
    await gesture([[600, 500], [600, 500]]);
    await expect(button("Delete selection")).toHaveCount(0);
    await gesture([[160, 350], [200, 370], [240, 390]]);
    await savedPages(page, "Derivation", notebook);
    expect(await storedFills(page, [notebook, "Derivation"], "0001.svg")).toEqual(["#D92D39", "#1A1A1A"]);
  });

  await test.step("the lasso moves, cuts, pastes, copies, and deletes a line", async () => {
    const written = { x: box.x + 420, y: box.y + 170 };
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
    await button("Lasso").click();
    await penStroke(cdp, [
      { x: written.x - 70, y: written.y - 40 }, { x: written.x + 70, y: written.y - 40 },
      { x: written.x + 70, y: written.y + 40 }, { x: written.x - 70, y: written.y + 40 },
      { x: written.x - 70, y: written.y - 40 },
    ], 0.6);
    await dragDown(written);
    await shot("moved");
    expect(await inked()).toEqual([false, true, false]);

    await button("Cut").click();
    await shot("cut");
    expect(await inked()).toEqual([false, false, false]);
    const paste = async () => {
      await page.mouse.click(written.x, written.y, { button: "right" });
      await button("Paste").click();
    };
    await paste();
    expect(await inked()).toEqual([false, true, false]);

    // Copy leaves the selected handwriting in place; it then moves away, and
    // a paste puts the copy where the handwriting was copied from.
    await button("Copy").click();
    await dragDown(moved);
    expect(await inked()).toEqual([false, false, true]);
    await paste();
    await shot("copied");
    expect(await inked()).toEqual([false, true, true]);

    await button("Delete selection").click();
    await shot("deleted");
    expect(await inked()).toEqual([false, false, true]);
  });

  await test.step("rectangle and oval selections take the handwriting inside their shapes", async () => {
    await button("Pen").click();
    const left = { x: box.x + 660, y: box.y + 180 };
    const right = { x: box.x + 900, y: box.y + 180 };
    const below = { x: box.x + 660, y: box.y + 330 };
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
      await button("Lasso").click();
      await button(mode).click();
      await closePopover(page);
    };
    // A drag from corner to corner of the shape's bounding box.
    const dragBox = (center: PenPoint) =>
      penStroke(cdp, [0, 0.25, 0.5, 0.75, 1].map((t) => ({ x: center.x - 60 + 120 * t, y: center.y - 30 + 60 * t })), 0.6);
    const remove = () => button("Delete selection").click();

    await button("Lasso").click();
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

  await test.step("lower on the page, a figure is resized by its corner handles and duplicated", async () => {
    const region = { x: Math.round(box.x) + 150, y: Math.round(box.y) + 130, width: 600, height: 450 };
    // The wheel brings clear paper below the earlier lines into the region.
    await page.mouse.move(box.x + box.width / 2, box.y + box.height / 2);
    await page.mouse.wheel(0, 600);
    await settled(page, region);
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
    const clear = () => button("Clear selection").click();

    // A slanted stroke, 80 px wide and 60 px high.
    await button("Pen").click();
    await drag({ x: box.x + 260, y: box.y + 230 }, 80, 60);
    const written = await ink();
    // The lasso is back to freehand after the shapes.
    await button("Lasso").click();
    await button("Lasso").click();
    await button("Freehand").click();
    await closePopover(page);

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

    await button("Undo").click();
    expect(await ink(), "undo restores the size before the drag").toEqual(doubled);

    // The copy appears selected, the same distance right of and below the
    // original. A drag moves it 150 px farther down.
    await lassoAround(doubled);
    await button("Duplicate").click();
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

  await test.step("on a lined sheet, the ruled lasso and the ruled eraser take the words of the lines under the pen", async () => {
    await toLibrary();
    await newNote("Ruled", "Lined", "Landscape");
    await button("Pen").click();
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
    const strokes = async () => (await savedPages(page, "Ruled", notebook)).map((saved) => saved.strokes);
    await expect.poll(strokes, "the divider and four words remain").toEqual([5]);
    await button("Undo").click();
    await shows(4, [60], "one undo restores line 4");
    await shows(5, [60], "one undo restores line 5");
    await button("Redo").click();
    await shows(4, [], "redo erases line 4 again");
    await expect.poll(strokes).toEqual([5]);
  });

  await test.step("on a second lined sheet, insert space makes room in each mode, pushes a word onto a new page, and a reload keeps it", async () => {
    await toLibrary();
    await newNote("Space", "Lined", "Landscape");
    await button("Pen").click();
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
    const strokes = async () => (await savedPages(page, "Space", notebook)).map((saved) => saved.strokes);

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
    await openTestNotebook(page, notebook);
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
});
