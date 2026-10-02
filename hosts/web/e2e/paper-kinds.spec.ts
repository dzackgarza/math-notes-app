import { expect } from "@playwright/test";
import { test, enterText, closeNote, createTestNotebook, penStroke, line, capture, screenPixels, brightness, inkAt, pageIn, boxOf, savedPages } from "./support.ts";

// A page size, an orientation, and the size of the saved page in points.
type Size = [string, string, number[]];

// One notebook that holds a note for every kind of work: each paper style,
// each page size, and each orientation. The user makes each note, finds its
// paper as chosen, writes on it, adds a second page, and closes it. Each note
// is checked on screen and in its files.
test("Flutter notes for every kind of work: each paper, page size, and orientation", async ({ page }, info) => {
  test.setTimeout(180_000);
  const button = (name: string) => page.getByRole("button", { name, exact: true });
  const notebook = "Kinds of work";
  const a4 = [595.28, 841.89], letter = [612, 792];

  // The marks in a square of the page: full rows are rules, full columns
  // are grid verticals, and marks in neither are dots. The square starts
  // 150 px into the page, right of lined paper's margin rule (48 pt).
  const pattern = async (paper: string, sheet: { x: number; y: number }) => {
    const side = 200;
    const pixels = await capture(page, { x: sheet.x + 150, y: sheet.y + 150, width: side, height: side });
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

  // A note of one paper, size, and orientation: its paper pattern, a line of
  // handwriting below the measured square, and its saved page sizes before
  // and after a second page.
  const note = async (paper: string, size: Size | null) => {
    const title = size ? `${paper} ${size[0]} ${size[1]}` : paper;
    await button("New note").click();
    await enterText(page.getByRole("textbox", { name: "Title", exact: true }), title);
    await button(paper).click();
    if (size) {
      await button(size[0]).click();
      await button(size[1]).click();
    }
    await button("Create").click();
    await expect(page.getByRole("heading", { name: title, exact: true })).toBeVisible({ timeout: 30_000 });
    const canvas = page.locator('canvas[id^="ink-canvas-"]:visible');
    await canvas.waitFor({ timeout: 30_000 });
    const sheet = pageIn(await boxOf(canvas));
    const marks = await pattern(paper, sheet);

    const spot = { x: sheet.x + 250, y: sheet.y + 420 };
    const blank = await screenPixels(page, spot);
    const cdp = await page.context().newCDPSession(page);
    await penStroke(cdp, line(spot.x - 60, spot.x + 60, spot.y), 0.6);
    await expect.poll(() => inkAt(page, spot, blank), `${title} shows the handwriting`).toBeGreaterThan(0);
    await cdp.detach();

    if (size) {
      const saved = await savedPages(page, title, notebook);
      expect(saved.map((entry) => entry.size), title).toEqual([size[2]]);
      expect(saved.map((entry) => entry.strokes), `${title} keeps the handwriting`).toEqual([1]);
      await button("Pages").click();
      await button("Add page At end").click();
      await expect(page.getByText("1 / 2", { exact: true })).toBeVisible();
      expect((await savedPages(page, title, notebook)).map((entry) => entry.size), `${title}, second page`).toEqual([size[2], size[2]]);
    }
    await closeNote(page);
    await expect(page.getByRole("heading", { name: notebook, exact: true })).toBeVisible();
    return marks;
  };

  await page.goto("?root=opfs");
  await createTestNotebook(page, notebook);

  await test.step("the user makes a lined note on A4 portrait paper and writes on it", async () => {
    const lined = await note("Lined", ["A4", "Portrait", a4]);
    expect(lined.rows, "lined paper has rules").toBeGreaterThan(0);
    expect(lined.columns, "lined paper has no verticals").toBe(0);
  });

  await test.step("the user makes grid and graph notes in A4 landscape and Letter portrait and writes on them", async () => {
    const grids: [string, Size][] = [["Grid", ["A4", "Landscape", a4.toReversed()]], ["Graph", ["Letter", "Portrait", letter]]];
    for (const [paper, size] of grids) {
      const grid = await note(paper, size);
      expect(grid.rows, `${paper} has horizontal lines`).toBeGreaterThan(0);
      expect(grid.columns, `${paper} has vertical lines`).toBeGreaterThan(0);
    }
  });

  await test.step("the user makes a dotted note in Letter landscape and writes on it", async () => {
    const dotted = await note("Dot", ["Letter", "Landscape", letter.toReversed()]);
    expect(dotted.marks, "dot paper has dots").toBeGreaterThan(0);
    expect(dotted.rows + dotted.columns, "dot paper has no lines").toBe(0);
  });

  await test.step("the user makes a plain note and writes on it", async () => {
    const blank = await note("Plain", null);
    expect(blank.marks, "plain paper is blank").toBe(0);
  });
});
