import { expect } from "@playwright/test";
import { execFileSync } from "node:child_process";
import { readFile } from "node:fs/promises";
import { test, focusText, enterText, save, goToPage, createTestNotebook, openTestNotebook, penStroke, line, pngPixels, capture, brightness, isOutline, isInk, inkLength, pixelBounds, size, centerPixel, pageIn, boxOf, isSalmon, closePopover, type PenPoint, type Rgb, type Bounds } from "./support.ts";

// A teacher prepares a handout in one notebook: a JPEG figure on page 1,
// typed text boxes on page 2, blank pages up to ten, and a ten-page export.
// A paper imported as a PDF gets margin notes and a highlight and is
// exported with them. After a reload, the figure, the text, and the
// annotated paper return unchanged. Each step asserts the screen and the
// files.
test("Flutter handout session: a figure, typed text, ten pages, an annotated PDF, reload, and export", async ({ page }, info) => {
  test.setTimeout(300_000);
  const shot = (name: string) => page.screenshot({ path: info.outputPath(`${name}.png`) });
  const button = (name: string) => page.getByRole("button", { name, exact: true });
  const notebook = "Handouts";
  const saved = async () => {
    await save(page);
    await expect(page.getByRole("status", { name: /^Notebook save/ })).toHaveAccessibleName("Notebook save Saved");
  };

  await page.goto("?root=opfs");
  await createTestNotebook(page, notebook);
  await button("New note").click();
  await enterText(page.getByRole("textbox", { name: "Title", exact: true }), "Handout");
  await button("Plain").click();
  await button("Create").click();
  const canvas = page.locator('canvas[id^="ink-canvas-"]:visible');
  await canvas.waitFor({ timeout: 30_000 });
  const box = await boxOf(canvas);
  const cdp = await page.context().newCDPSession(page);
  // Screen pixels for each point of the A4 page.
  const scale = pageIn(box).width / 595;

  // Page 1: the figure.
  const region = { x: Math.round(box.x) + 100, y: Math.round(box.y) + 80, width: 900, height: 520 };
  const square = () => pixelBounds(page, region, isSalmon);
  let halved: Bounds = { left: 0, right: 0, top: 0, bottom: 0 };
  await test.step("insert a JPEG figure, move it, resize it, delete it, and undo the delete", async () => {
    const drag = (from: PenPoint, dx: number, dy: number) =>
      penStroke(cdp, [0, 0.25, 0.5, 0.75, 1].map((t) => ({ x: from.x + dx * t, y: from.y + dy * t })), 0.6);
    // The left, right, and bottom of the selection rectangle: its outline is
    // 5 px inside the edges of its corner handles.
    const selectionRect = async () => {
      const outline = await pixelBounds(page, region, isOutline);
      return { left: outline.left + 5, right: outline.right - 5, bottom: outline.bottom - 5 };
    };

    // The image arrives selected, one point for each of its pixels.
    const chooser = page.waitForEvent("filechooser");
    await button("Image").click();
    await (await chooser).setFiles("e2e/fixtures/figure.jpg");
    await expect(button("Delete selection")).toBeAttached();
    await shot("figure-inserted");
    const inserted = await square();
    const frame = await selectionRect();
    expect(Math.abs(size(inserted).width - 90 * scale), "the square is 90 pt wide").toBeLessThan(4);
    expect(Math.abs(size(inserted).height - 90 * scale), "the square is 90 pt high").toBeLessThan(4);
    expect(Math.abs(frame.right - frame.left - 230 * scale), "the image is 230 pt wide").toBeLessThan(4);
    expect(Math.abs(inserted.left - frame.left - 15 * scale), "the square is 15 pt from the image's left edge").toBeLessThan(4);

    // A drag inside the selection moves the image.
    await drag({ x: (inserted.left + inserted.right) / 2, y: (inserted.top + inserted.bottom) / 2 }, -180, -20);
    await shot("figure-moved");
    const moved = await square();
    expect(moved).toEqual({ left: inserted.left - 180, right: inserted.right - 180, top: inserted.top - 20, bottom: inserted.bottom - 20 });

    // The bottom-right handle, dragged halfway to the opposite corner, halves the image.
    const held = await selectionRect();
    const width = held.right - held.left;
    await drag({ x: held.right, y: held.bottom }, -width / 2, (-width / 2) * (200 / 230));
    await shot("figure-halved");
    halved = await square();
    expect(Math.abs(size(halved).width - 45 * scale), "the square is 45 pt wide").toBeLessThan(4);
    expect(Math.abs(size(halved).height - 45 * scale), "the square is 45 pt high").toBeLessThan(4);
    expect(Math.abs(halved.left - held.left - 7.5 * scale), "the image's left edge stays in place").toBeLessThan(4);

    const salmon = async () => (await capture(page, region)).filter(isSalmon).length;
    await button("Delete selection").click();
    expect(await salmon(), "the image is deleted").toBe(0);
    await button("Undo").click();
    expect(await square(), "undo restores the image").toEqual(halved);
  });

  await test.step("save the figure as a copy of the JPEG", async () => {
    await saved();
    const asset = await page.evaluate(async (notebook) => {
      const root = await navigator.storage.getDirectory();
      const dir = await (await root.getDirectoryHandle(notebook)).getDirectoryHandle("Handout");
      const pages = await dir.getDirectoryHandle("pages");
      const svg = await (await (await pages.getFileHandle("0001.svg")).getFile()).text();
      const name = svg.match(/href="\.\.\/assets\/([0-9a-f]+\.jpg)"/)?.[1];
      if (!name) throw new Error("Saved image has no JPEG asset reference");
      const assets = await dir.getDirectoryHandle("assets");
      const file = await (await assets.getFileHandle(name)).getFile();
      return btoa(String.fromCharCode(...new Uint8Array(await file.arrayBuffer())));
    }, notebook);
    expect(Buffer.from(asset, "base64")).toEqual(await readFile("e2e/fixtures/figure.jpg"));
  });

  // Page 2: the typed text. The page below the toolbar, split at the
  // middle: the wrapped box is in the left half and the one-word box in the
  // right half. The left half starts on the page, right of the rail.
  const top = Math.round(box.y) + 120;
  const sheetLeft = Math.round(pageIn(box).x) + 4;
  const left = { x: sheetLeft, y: top, width: 610 - sheetLeft, height: 460 };
  const right = { x: 630, y: top, width: 610, height: 460 };
  const text = page.getByRole("textbox", { name: "Text", exact: true });
  const boxWidth = page.getByRole("textbox", { name: "Width (pt)", exact: true });
  const done = () => button("Done").click();
  const clear = () => button("Clear selection").click();
  const sentence = "Every vector space has a basis.";
  const tap = { x: 120, y: top + 30 };
  const boxRight = tap.x + 100 * scale;
  // The last of the wrapped lines: the rows 30 px above the box's bottom.
  const lastLine = (b: Bounds) => pixelBounds(page, { x: left.x, y: b.bottom - 30, width: left.width, height: 30 }, isInk);
  // A tap on a box edits it.
  const edit = async (at: PenPoint, content: string, width: string) => {
    await page.mouse.click(at.x, at.y);
    await expect(page.getByText("Edit text", { exact: true })).toBeVisible();
    await expect(text).toHaveValue(content);
    await boxWidth.click();
    await expect(boxWidth).toHaveValue(width);
  };
  const inside = { x: tap.x + 30, y: tap.y + 30 };
  let lemma: Bounds = { left: 0, right: 0, top: 0, bottom: 0 };
  let word = { x: 0, y: 0, width: 0, height: 0 };
  let rightToLeft: Bounds = { left: 0, right: 0, top: 0, bottom: 0 };

  await test.step("add page 2 and type a word and a sentence wrapped at 100 pt", async () => {
    await button("Pages").click();
    await button("Add page At end").click();
    await goToPage(page, 2);
    await expect(page.getByText("2 / 2", { exact: true })).toBeVisible();
    await button("Text").click();
    await expect(page.getByText("Insert text", { exact: true })).toBeVisible();
    await enterText(text, "Lemma");
    await done();
    await clear();
    await shot("text-inserted");
    lemma = await pixelBounds(page, right, isInk);
    word = { x: lemma.left - 10, y: lemma.top - 10, width: size(lemma).width + 20, height: size(lemma).height + 20 };
    await page.mouse.click(tap.x, tap.y);
    await expect(page.getByText("Insert text", { exact: true })).toBeVisible();
    await boxWidth.click();
    await expect(boxWidth).toHaveValue("300");
    await enterText(text, sentence);
    await enterText(boxWidth, "100");
    await done();
    await clear();
    await shot("text-wrapped");
  });

  await test.step("put the sentence on one line, reject a negative width, and delete and restore the word", async () => {
    const wrapped = await pixelBounds(page, left, isInk);
    // The "E" that starts the sentence.
    const firstLetter = () => pixelBounds(page, { x: tap.x - 5, y: tap.y, width: 25, height: 50 }, isInk);
    const letter = await firstLetter();
    expect(Math.abs(wrapped.left - tap.x), "the box starts at the tap").toBeLessThan(6);
    expect(wrapped.top - tap.y, "the box starts at the tap").toBeGreaterThanOrEqual(0);
    expect(wrapped.top - tap.y, "the box starts at the tap").toBeLessThan(25);
    expect(wrapped.right, "the lines end inside the box's width").toBeLessThan(boxRight + 2);
    expect(Math.abs((await lastLine(wrapped)).left - tap.x), "the last line starts at the box's left edge").toBeLessThan(6);

    // Width 0 puts the sentence on one line.
    await edit(inside, sentence, "100");
    await enterText(boxWidth, "0");
    await done();
    await clear();
    await shot("text-one-line");
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
    await shot("text-width-rejected");
    await button("Cancel").click();
    await clear();
    expect(await pixelBounds(page, firstRows, isInk)).toEqual(oneLine);

    // A box with no text is deleted; undo restores it.
    await edit({ x: lemma.left + 30, y: lemma.top + 10 }, "Lemma", "300");
    await focusText(text);
    await text.press("ControlOrMeta+a");
    await text.press("Backspace");
    await done();
    await shot("text-deleted");
    expect((await capture(page, word)).filter(isInk).length, "the empty box is deleted").toBe(0);
    await button("Undo").click();
    expect(await pixelBounds(page, word, isInk), "undo restores the box").toEqual(lemma);
  });

  await test.step("set the sentence right to left at 100 pt", async () => {
    await edit(inside, sentence, "0");
    await enterText(boxWidth, "100");
    await page.getByRole("switch").click();
    await done();
    await clear();
    await shot("text-right-to-left");
    rightToLeft = await pixelBounds(page, left, isInk);
    const lastRtlLine = await lastLine(rightToLeft);
    expect(Math.abs(lastRtlLine.right - boxRight), "the last line ends at the box's right edge").toBeLessThan(8);
    expect(lastRtlLine.left, "the last line starts away from the left edge").toBeGreaterThan(tap.x + 50);
    await saved();
  });

  await test.step("add pages up to ten and export a ten-page A4 PDF", async () => {
    for (let pageNumber = 3; pageNumber <= 10; pageNumber++) {
      await button("Pages").click();
      await button("Add page At end").click();
    }
    await expect(page.getByText(/^[0-9]+ \/ 10$/)).toBeVisible();
    await button("More").click();
    await button("Share").click();
    const download = page.waitForEvent("download");
    await button("Download PDF").click();
    const pdfPath = info.outputPath("handout.pdf");
    await (await download).saveAs(pdfPath);
    expect(execFileSync("qpdf", ["--check", pdfPath], { encoding: "utf8" })).toContain("No syntax or stream encoding errors found");
    const infoText = execFileSync("pdfinfo", [pdfPath], { encoding: "utf8" });
    expect(infoText).toMatch(/Pages:\s+10/);
    expect(infoText).toMatch(/Page size:\s+595 x 842 pts \(A4\)/);
  });

  // The imported paper, a Letter PDF of two pages.
  let paperBox = { x: 0, y: 0, width: 0, height: 0 };
  let paperScale = 1;
  // The black bar at the top of a fixture page (paper.tex), 1 cm tall: the
  // first tall dark run in a column through it, and the bar's length along
  // the middle row of that run. The glyphs of the text are shorter runs.
  const bar = async () => {
    const dark = (await capture(page, { x: Math.round(paperBox.x + 0.3 * paperBox.width), y: paperBox.y, width: 1, height: paperBox.height })).map(isInk);
    const top = dark.findIndex((_, row) => row + 40 <= dark.length && dark.slice(row, row + 40).every(Boolean));
    if (top < 0) throw new Error("No bar crosses the column");
    const bottom = dark.indexOf(false, top);
    const y = paperBox.y + (top + bottom) / 2;
    return { y, height: bottom - top, length: await inkLength(page, y, Math.round(paperBox.x), Math.round(paperBox.x + paperBox.width)) };
  };
  // The ink in the left margin of the page around a row. The fixture's margin is blank.
  const marginInk = async (y: number) =>
    (await capture(page, { x: Math.round(paperBox.x) + 10, y: y - 10, width: 140, height: 20 })).filter(isInk).length;
  let first = { y: 0, height: 0, length: 0 };
  let second = first;
  let note = 0;
  let secondNote = 0;
  const x = 400;

  await test.step("import a PDF into the notebook", async () => {
    await button("Library").click();
    await expect(page.getByRole("heading", { name: notebook, exact: true })).toBeVisible();
    const chooser = page.waitForEvent("filechooser");
    await button("Import PDF").click();
    await (await chooser).setFiles("e2e/fixtures/paper.pdf");
    await canvas.waitFor({ timeout: 60_000 });
    await expect(page.getByText("1 / 2", { exact: true })).toBeVisible();
    paperBox = pageIn(await boxOf(canvas));
    // Screen pixels for each point of the Letter page.
    paperScale = paperBox.width / 612;
    first = await bar();
    await expect(async () => {
      first = await bar();
      expect(first.length / paperBox.width, "the bar of page 1 spans half the page width").toBeCloseTo(0.5, 2);
    }).toPass({ timeout: 15_000 });
    expect(first.height / first.length, "the page keeps its proportions").toBeCloseTo(28.35 / 306, 2);
    await shot("pdf-imported");
  });

  await test.step("write in the margin, highlight the bar, and erase only the handwriting", async () => {
    note = first.y + 150;
    expect(await marginInk(note)).toBe(0);
    await button("Pen").click();
    await penStroke(cdp, line(paperBox.x + 20, paperBox.x + 120, note), 0.6);
    expect(await marginInk(note), "the pen writes in the margin").toBeGreaterThan(80);

    const above = { x, y: first.y - 45 };
    const paper = await centerPixel(page, above);
    await button("Highlighter").click();
    await penStroke(cdp, [-60, -30, 0, 30, 60].map((dy) => ({ x, y: first.y + dy })), 0.6);
    const tint = await centerPixel(page, above);
    expect(brightness(paper) - brightness(tint), "the highlighter tints the page").toBeGreaterThan(30);
    expect(isInk(tint)).toBe(false);
    expect(isInk(await centerPixel(page, { x, y: first.y })), "the highlighted bar stays dark").toBe(true);
    await shot("pdf-annotated");

    // The stroke eraser removes handwriting and leaves the imported page.
    await button("Eraser").click();
    await button("Eraser").click();
    await button("Stroke").click();
    await closePopover(page);
    await penStroke(cdp, [-40, 0, 40].map((dy) => ({ x: paperBox.x + 70, y: note + dy })), 0.6);
    expect(await marginInk(note), "the eraser removes the pen stroke").toBe(0);
    await penStroke(cdp, [-50, 0, 50].map((dy) => ({ x: 300, y: first.y + dy })), 0.6);
    expect(await bar(), "the eraser leaves the imported page").toEqual(first);
    await button("Undo").click();
    await expect.poll(() => marginInk(note), { message: "undo restores the pen stroke" }).toBeGreaterThan(80);
  });

  await test.step("write in the margin of page 2 and save", async () => {
    await goToPage(page, 2);
    await expect(page.getByText("2 / 2", { exact: true })).toBeVisible();
    await expect(async () => {
      second = await bar();
      expect(second.length / paperBox.width, "the bar of page 2 spans a quarter of the page width").toBeCloseTo(0.25, 2);
    }).toPass({ timeout: 15_000 });
    await button("Pen").click();
    secondNote = second.y + 150;
    await penStroke(cdp, line(paperBox.x + 20, paperBox.x + 120, secondNote), 0.6);
    expect(await marginInk(secondNote), "the pen writes on page 2").toBeGreaterThan(80);
    await shot("pdf-second-page");
    await saved();
  });

  await test.step("export the annotated paper", async () => {
    await button("More").click();
    await button("Share").click();
    const download = page.waitForEvent("download");
    await button("Download PDF").click();
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
      const row = 109 + Math.round(150 / paperScale);
      const margin = pixels.slice(612 * (row - 5), 612 * (row + 6))
        .filter((rgb, i) => i % 612 >= 20 && i % 612 < 86 && brightness(rgb) < 600).length;
      expect(margin, `the pen stroke of exported page ${pageNumber}`).toBeGreaterThan(30);
    }
    const highlighted = (await exported(1))[612 * (109 - Math.round(45 / paperScale)) + Math.round((x - paperBox.x) / paperScale)];
    expect(isInk(highlighted)).toBe(false);
    expect(brightness(highlighted), "the exported highlight").toBeLessThan(735);
  });

  await test.step("reload and find the figure and the text boxes unchanged", async () => {
    await page.reload();
    await openTestNotebook(page, notebook);
    await page.getByRole("button", { name: "Open Handout", exact: false }).click();
    await canvas.waitFor({ timeout: 30_000 });
    await button("More").waitFor();
    await shot("figure-reopened");
    expect(await square(), "the image reopens at the same place and size").toEqual(halved);
    await goToPage(page, 2);
    await expect.poll(() => pixelBounds(page, left, isInk), "the wrapped box reopens unchanged").toEqual(rightToLeft);
    await shot("text-reopened");
    expect(await pixelBounds(page, word, isInk), "the one-word box reopens unchanged").toEqual(lemma);
  });

  await test.step("open the paper and find both annotated pages unchanged", async () => {
    await button("Library").click();
    await expect(page.getByRole("heading", { name: notebook, exact: true })).toBeVisible();
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
});
