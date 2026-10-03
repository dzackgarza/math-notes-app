import { expect, type CDPSession, type Page } from "@playwright/test";
import { execFileSync } from "node:child_process";
import { readFile } from "node:fs/promises";
import { test, createTestNotebook, enterText, save, pngPixels, isInk } from "./support.ts";

type Point = { x: number; y: number };

async function draw(cdp: CDPSession, points: Point[], hold: boolean): Promise<void> {
  const pen = { pointerType: "pen" as const, force: 0.6 };
  await cdp.send("Input.dispatchMouseEvent", {
    type: "mousePressed", button: "left", clickCount: 1, ...points[0], ...pen,
  });
  for (const point of points.slice(1))
    await cdp.send("Input.dispatchMouseEvent", {
      type: "mouseMoved", button: "left", buttons: 1, ...point, ...pen,
    });
  if (hold) await new Promise((resolve) => setTimeout(resolve, 550));
  await cdp.send("Input.dispatchMouseEvent", {
    type: "mouseReleased", button: "left", clickCount: 1, ...points.at(-1)!, ...pen,
  });
}

async function paths(page: Page): Promise<{ raw: number[][]; geometry: number[][] }[]> {
  await save(page);
  await expect(page.getByRole("status", { name: /^Notebook save/ })).toHaveAccessibleName("Notebook save Saved");
  return page.evaluate(async () => {
    const root = await navigator.storage.getDirectory();
    const dir = await (await root.getDirectoryHandle("Test Notebook")).getDirectoryHandle("Shapes");
    const svg = await (await (await (await dir.getDirectoryHandle("pages")).getFileHandle("0001.svg")).getFile()).text();
    const doc = new DOMParser().parseFromString(svg, "image/svg+xml");
    return Array.from(doc.querySelectorAll('path[id^="s-"]'), (path) => {
      const traces = Array.from(path.getElementsByTagName("inkml:trace"), (trace) =>
        (trace.textContent ?? "").split(",").map((sample) => sample.trim().split(/\s+/).slice(0, 2).map(Number)));
      return { raw: traces.length == 2 ? traces[0] : [], geometry: traces.at(-1)! };
    });
  });
}

test("A held stroke resolves only fitting shapes; a scribble erases crossed ink in one step", async ({ page, context }, info) => {
  test.setTimeout(180_000);
  const button = (name: string) => page.getByRole("button", { name, exact: true });
  await page.goto("?root=opfs");
  await createTestNotebook(page);
  await button("New note").click();
  await enterText(page.getByRole("textbox", { name: "Title", exact: true }), "Shapes");
  await button("Create").click();
  const canvas = page.locator('canvas[id^="ink-canvas-"]:visible');
  await canvas.waitFor();
  const box = await canvas.boundingBox();
  if (!box) throw new Error("Canvas has no bounds");
  const cdp = await context.newCDPSession(page);
  const at = (x: number, y: number) => ({ x: box.x + x, y: box.y + y });

  await draw(cdp, [at(170, 130), at(205, 138), at(240, 127), at(275, 136)], true);
  const line = await paths(page);
  expect(line).toHaveLength(1);
  expect(line[0].raw.length).toBeGreaterThan(line[0].geometry.length);
  expect(line[0].geometry).toHaveLength(2);

  const circle = Array.from({ length: 17 }, (_, i) => {
    const angle = 2 * Math.PI * i / 16;
    return at(310 + 38 * Math.cos(angle), 270 + 38 * Math.sin(angle));
  });
  await draw(cdp, circle, true);
  const afterCircle = await paths(page);
  expect(afterCircle).toHaveLength(2);
  expect(afterCircle[1].raw.length).toBeGreaterThan(10);
  expect(afterCircle[1].geometry.length).toBeGreaterThan(32);

  const ellipse = Array.from({ length: 17 }, (_, i) => {
    const angle = 2 * Math.PI * i / 16;
    const along = 55 * Math.cos(angle);
    const across = 25 * Math.sin(angle);
    const rotation = Math.PI / 5;
    return at(180 + along * Math.cos(rotation) - across * Math.sin(rotation),
      420 + along * Math.sin(rotation) + across * Math.cos(rotation));
  });
  await draw(cdp, ellipse, true);
  const afterEllipse = await paths(page);
  expect(afterEllipse).toHaveLength(3);
  expect(afterEllipse[2].geometry.length).toBeGreaterThan(32);
  const fitted = afterEllipse[2].geometry;
  const meanX = fitted.reduce((sum, point) => sum + point[0], 0) / fitted.length;
  const meanY = fitted.reduce((sum, point) => sum + point[1], 0) / fitted.length;
  const covariance = fitted.reduce((sum, point) => sum + (point[0] - meanX) * (point[1] - meanY), 0);
  const varianceX = fitted.reduce((sum, point) => sum + (point[0] - meanX) ** 2, 0);
  const varianceY = fitted.reduce((sum, point) => sum + (point[1] - meanY) ** 2, 0);
  expect(covariance / Math.sqrt(varianceX * varianceY), "the fitted ellipse keeps its drawn angle").toBeGreaterThan(0.25);

  await draw(cdp, [at(300, 395), at(345, 400), at(350, 445), at(305, 440), at(300, 395)], true);
  const afterPolygon = await paths(page);
  expect(afterPolygon).toHaveLength(4);
  expect(afterPolygon[3].raw).toHaveLength(6);
  expect(afterPolygon[3].geometry).toHaveLength(5);

  const arc = Array.from({ length: 9 }, (_, i) => {
    const t = i / 8;
    return at(135 + 140 * t, 550 - 200 * t * (1 - t));
  });
  await draw(cdp, arc, true);
  const afterArc = await paths(page);
  expect(afterArc).toHaveLength(5);
  expect(afterArc[4].geometry.length).toBeGreaterThan(16);

  await draw(cdp, [at(155, 320), at(195, 305), at(230, 330), at(255, 292)], true);
  const unmatched = await paths(page);
  expect(unmatched).toHaveLength(6);
  expect(unmatched[5].raw).toEqual([]);

  await button("Lasso").click();
  await draw(cdp, [at(260, 215), at(360, 215), at(360, 325), at(260, 325), at(260, 215)], false);
  await expect(button("Delete selection")).toBeAttached();
  await button("Clear selection").click();
  await button("Eraser").click();
  await draw(cdp, [at(340, 270), at(355, 270)], false);
  expect(await paths(page)).not.toEqual(unmatched);
  await button("Undo").click();
  expect(await paths(page)).toEqual(unmatched);
  await button("Pen").click();

  await draw(cdp, [at(170, 130), at(230, 130), at(170, 135), at(230, 135), at(170, 130), at(230, 130)], false);
  const erased = await paths(page);
  expect(erased).not.toEqual(unmatched);
  await button("Undo").click();
  expect(await paths(page)).toEqual(unmatched);

  await page.reload();
  await page.getByRole("button", { name: "Open Test Notebook", exact: false }).click();
  await page.getByRole("button", { name: "Open Shapes", exact: false }).click();
  expect(await paths(page)).toEqual(unmatched);

  await button("More").click();
  await button("Share").click();
  const download = page.waitForEvent("download");
  await button("Download PDF").click();
  const pdf = info.outputPath("recognized-shapes.pdf");
  await (await download).saveAs(pdf);
  expect(execFileSync("pdfinfo", [pdf], { encoding: "utf8" })).toMatch(/Pages:\s+1/);
  const rendered = info.outputPath("recognized-shapes");
  execFileSync("pdftoppm", ["-r", "72", "-png", "-f", "1", "-l", "1", "-singlefile", pdf, rendered]);
  expect((await pngPixels(page, await readFile(`${rendered}.png`))).filter(isInk).length).toBeGreaterThan(100);
});
