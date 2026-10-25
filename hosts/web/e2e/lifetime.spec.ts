import { test, expect } from "./native-desktop.ts";
import { enterText, goToPage, penStroke, pngPixels, save, type Box, type Rgb } from "./workflow-actions.ts";
import { execFileSync } from "node:child_process";
import { readFile } from "node:fs/promises";
import type { Page } from "@playwright/test";

test.use({ trace: "on" });

// Compare the visible ink, independently rasterized by Chrome and Poppler.
// Normalizing its bounds allows PDF points and screen pixels to differ while
// retaining the relative positions of every mark.
async function inkMask(page: Page, png: Buffer): Promise<Set<number>> {
  const width = png.readUInt32BE(16);
  const pixels = await pngPixels(page, png);
  const dark = (rgb: Rgb) => rgb[0] + rgb[1] + rgb[2] < 350;
  const ink = pixels.flatMap((rgb, index) => dark(rgb) ? [index] : []);
  expect(ink.length, "the page contains visible handwriting").toBeGreaterThan(100);
  let left = width, top = pixels.length / width, right = 0, bottom = 0;
  for (const index of ink) {
    left = Math.min(left, index % width); right = Math.max(right, index % width);
    top = Math.min(top, Math.floor(index / width)); bottom = Math.max(bottom, Math.floor(index / width));
  }
  return new Set(ink.map(index =>
    Math.round(126 * (index % width - left) / (right - left)) +
    128 * Math.round(126 * (Math.floor(index / width) - top) / (bottom - top))));
}

function mismatch(left: Set<number>, right: Set<number>): number {
  const absent = (from: Set<number>, to: Set<number>) => [...from].filter(value => {
    for (let dy = -1; dy <= 1; dy++) for (let dx = -1; dx <= 1; dx++) {
      if (to.has(value + dx + 128 * dy)) return false;
    }
    return true;
  }).length / from.size;
  return Math.max(absent(left, right), absent(right, left));
}

test("writes and revises ten A4 pages, reconnects the real folder, and independently renders the exported PDF", async ({ desktop }, info) => {
  test.setTimeout(720_000);
  let page = desktop.page;
  const button = (name: string) => page.getByRole("button", { name, exact: true });
  await desktop.chooseFolder();
  await button("New notebook").click({ timeout: 90_000 });
  await enterText(page.getByRole("textbox", { name: "Notebook title", exact: true }), "Research");
  await button("Create").click();
  await button("New note").click();
  await enterText(page.getByRole("textbox", { name: "Title", exact: true }), "Ten-page calculation");
  await button("Plain").click();
  await button("A4").click();
  await button("Create").click();
  const canvas = () => page.locator('canvas[id^="ink-canvas-"]:visible');
  await canvas().waitFor();
  const box = (await canvas().boundingBox())!;
  const region: Box = { x: box.x + 120, y: box.y + 120, width: 460, height: 420 };
  let cdp = await page.context().newCDPSession(page);
  const stroke = (points: number[][]) => penStroke(cdp, points.map(([x, y]) => ({ x: box.x + x, y: box.y + y })), .8);
  const digits = [
    [[0, 0], [18, 0], [18, 30], [0, 30], [0, 0]],
    [[4, 7], [10, 0], [10, 30]],
    [[0, 0], [18, 0], [18, 14], [0, 30], [18, 30]],
    [[0, 0], [18, 0], [18, 15], [4, 15], [18, 15], [18, 30], [0, 30]],
    [[0, 0], [0, 15], [18, 15], [18, 0], [18, 30]],
    [[18, 0], [0, 0], [0, 15], [18, 15], [18, 30], [0, 30]],
    [[18, 0], [0, 0], [0, 30], [18, 30], [18, 15], [0, 15]],
    [[0, 0], [18, 0], [4, 30]],
    [[0, 15], [0, 0], [18, 0], [18, 30], [0, 30], [0, 15], [18, 15]],
    [[18, 15], [0, 15], [0, 0], [18, 0], [18, 30]],
  ];
  const saved = new Map<number, Set<number>>();
  for (let n = 1; n <= 10; n++) {
    if (n > 1) { await button("Pages").click(); await button("Add page").click(); }
    await goToPage(page, n);
    // Handwritten x^2 + n = y. These are ordinary pen paths, never recognized
    // or converted to typeset text by the application.
    for (const path of [
      [[150, 190], [174, 218]], [[174, 190], [150, 218]],
      [[176, 167], [188, 167], [188, 177], [176, 187], [188, 187]],
      [[207, 204], [231, 204]], [[219, 192], [219, 216]],
      [[310, 198], [334, 198]], [[310, 210], [334, 210]],
      [[356, 188], [367, 205], [378, 188]], [[367, 205], [357, 232]],
    ]) await stroke(path);
    for (const [i, digit] of String(n).split("").entries()) {
      await stroke(digits[Number(digit)].map(([x, y]) => [252 + 24 * i + x, 186 + y]));
    }
    await expect(page.getByText(`${n} / ${n}`, { exact: true })).toBeVisible();
    const image = await page.screenshot({ clip: region, path: info.outputPath(`written-${n}.png`) });
    saved.set(n, await inkMask(page, image));
  }

  for (const n of [1, 10]) {
    await goToPage(page, n);
    await button("Lasso").click();
    await stroke([[342, 177], [390, 177], [390, 246], [342, 246], [342, 177]]);
    await expect(button("Clear selection")).toBeVisible();
    await stroke([[367, 205], [367, 220], [367, 235], [367, 250]]);
    await button("Clear selection").click();
    const moved = await inkMask(page, await page.screenshot({ clip: region }));
    expect(mismatch(saved.get(n)!, moved), "moving y changes the actual page").toBeGreaterThan(.04);
    await button("Undo").click();
    await expect.poll(async () => mismatch(saved.get(n)!, await inkMask(page, await page.screenshot({ clip: region })))).toBeLessThan(.02);
    await button("Redo").click();
    await expect.poll(async () => mismatch(moved, await inkMask(page, await page.screenshot({ clip: region })))).toBeLessThan(.02);
    saved.set(n, moved);
    await button("Pen").click();
  }
  await save(page);
  await expect(page.getByRole("status", { name: /^Notebook save/ })).toHaveAccessibleName("Notebook save Saved");
  page = await desktop.restart();
  await button("Reconnect folder").click();
  await desktop.allow("Allow this time");
  await page.getByRole("button", { name: /^Open Research/ }).click({ timeout: 90_000 });
  await page.getByRole("button", { name: /^Open Ten-page calculation/ }).click();
  await canvas().waitFor();
  cdp = await page.context().newCDPSession(page);
  for (let n = 1; n <= 10; n++) {
    await goToPage(page, n);
    await expect.poll(async () => mismatch(saved.get(n)!, await inkMask(page, await page.screenshot({ clip: region })))).toBeLessThan(.02);
    await page.screenshot({ path: info.outputPath(`reopened-${n}.png`) });
  }
  await button("More").click();
  await button("Export PDF").click();
  const download = page.waitForEvent("download");
  await button("Export").click();
  const pdf = info.outputPath("ten-page-calculation.pdf");
  await (await download).saveAs(pdf);
  expect(execFileSync("pdfinfo", [pdf], { encoding: "utf8" })).toMatch(/Pages:\s+10/);
  expect(execFileSync("pdfinfo", ["-f", "1", "-l", "10", pdf], { encoding: "utf8" }).match(/size:\s+595 x 842 pts \(A4\)/g)).toHaveLength(10);
  for (let n = 1; n <= 10; n++) {
    const prefix = info.outputPath(`pdf-page-${n}`);
    execFileSync("pdftoppm", ["-r", "144", "-png", "-f", String(n), "-l", String(n), "-singlefile", pdf, prefix]);
    const observed = await inkMask(page, await readFile(`${prefix}.png`));
    expect(mismatch(saved.get(n)!, observed), `PDF page ${n} reproduces its revised handwriting`).toBeLessThan(.08);
  }
});
