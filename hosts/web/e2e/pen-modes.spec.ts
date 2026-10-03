import { expect } from "@playwright/test";
import { test, closePopover, createTestNotebook, enterText, openTestNotebook, penStroke, save } from "./support.ts";

type SavedStroke = { modes: string | null; smoothing: string | null; traces: string[] };

async function strokes(page: import("@playwright/test").Page): Promise<SavedStroke[]> {
  await save(page);
  return page.evaluate(async () => {
    const root = await navigator.storage.getDirectory();
    const dir = await (await root.getDirectoryHandle("Test Notebook")).getDirectoryHandle("Modes");
    const svg = await (await (await (await dir.getDirectoryHandle("pages")).getFileHandle("0001.svg")).getFile()).text();
    const parsed = new DOMParser().parseFromString(svg, "image/svg+xml");
    return Array.from(parsed.querySelectorAll('path[id^="s-"]'), (path) => ({
      modes: path.getAttribute("mn:modes"),
      smoothing: path.getAttribute("mn:smoothing-ms"),
      traces: Array.from(path.getElementsByTagName("inkml:trace"), (trace) => trace.textContent ?? ""),
    }));
  });
}

test("Pen modes: snapped lines, temporary ink, smoothing, history, and reload", async ({ page, context }) => {
  test.setTimeout(180_000);
  const button = (name: string) => page.getByRole("button", { name, exact: true });
  await page.goto("?root=opfs");
  await createTestNotebook(page);
  await button("New note").click();
  await enterText(page.getByRole("textbox", { name: "Title", exact: true }), "Modes");
  await button("Grid").click();
  await button("Create").click();
  const canvas = page.locator('canvas[id^="ink-canvas-"]:visible');
  await canvas.waitFor();
  const box = await canvas.boundingBox();
  if (!box) throw new Error("Canvas has no bounds");
  const cdp = await context.newCDPSession(page);
  const draw = (y: number) => penStroke(cdp, [
    { x: box.x + 180, y: box.y + y },
    { x: box.x + 205, y: box.y + y + 31 },
    { x: box.x + 245, y: box.y + y - 23 },
    { x: box.x + 300, y: box.y + y + 12 },
  ], 0.6);
  const advanced = async () => {
    await button("Pen").click();
    await button("Advanced").click();
  };
  const toggle = (name: string) => page.getByRole("switch", { name }).click();

  await test.step("combine grid snapping and straight lines", async () => {
    await advanced();
    await toggle("Snap to grid");
    await toggle("Draw lines");
    await closePopover(page);
    await draw(220);
    const saved = await strokes(page);
    expect(saved).toHaveLength(1);
    expect(saved[0].modes).toBe("3");
    expect(saved[0].traces).toHaveLength(2);
    expect(saved[0].traces[0]).not.toBe(saved[0].traces[1]);
    const points = saved[0].traces[1].split(",").map((sample) => sample.trim().split(/\s+/).slice(0, 2).map(Number));
    expect(points.length).toBeGreaterThan(2);
    const [start, end] = [points[0], points.at(-1)!];
    for (const point of points) {
      const area = (point[0] - start[0]) * (end[1] - start[1]) -
        (point[1] - start[1]) * (end[0] - start[0]);
      expect(Math.abs(area), "the saved geometry is a straight line").toBeLessThan(0.2);
    }
  });

  await test.step("temporary ink leaves the note and history unchanged", async () => {
    await advanced();
    await toggle("Temporary ink");
    await closePopover(page);
    await draw(330);
    expect(await strokes(page)).toHaveLength(1);
    await button("Undo").click();
    expect(await strokes(page)).toHaveLength(0);
    await button("Redo").click();
    expect(await strokes(page)).toHaveLength(1);
  });

  await test.step("smoothing is saved with the next permanent stroke and survives reload", async () => {
    await advanced();
    await toggle("Temporary ink");
    const slider = page.getByRole("slider", { name: "Smoothing" });
    const sliderBox = await slider.boundingBox();
    if (!sliderBox) throw new Error("Smoothing slider has no bounds");
    await slider.click({ position: { x: sliderBox.width * 0.8, y: sliderBox.height / 2 } });
    await closePopover(page);
    await draw(390);
    const before = await strokes(page);
    expect(before).toHaveLength(2);
    expect(Number(before[1].smoothing)).toBeGreaterThan(20);
    await page.reload();
    await openTestNotebook(page);
    await page.getByRole("button", { name: "Open Modes", exact: false }).click();
    expect(await strokes(page)).toEqual(before);
  });
});
