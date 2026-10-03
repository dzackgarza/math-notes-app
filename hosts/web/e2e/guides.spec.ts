import { expect, type Page } from "@playwright/test";
import { test, createTestNotebook, enterText, penStroke, save } from "./support.ts";

async function traces(page: Page): Promise<{ raw: number[][]; geometry: number[][] }[]> {
  await save(page);
  await expect(page.getByRole("status", { name: /^Notebook save/ })).toHaveAccessibleName("Notebook save Saved");
  return page.evaluate(async () => {
    const root = await navigator.storage.getDirectory();
    const dir = await (await root.getDirectoryHandle("Test Notebook")).getDirectoryHandle("Guides");
    const svg = await (await (await (await dir.getDirectoryHandle("pages")).getFileHandle("0001.svg")).getFile()).text();
    const doc = new DOMParser().parseFromString(svg, "image/svg+xml");
    return Array.from(doc.querySelectorAll('path[id^="s-"]'), (path) => {
      const points = Array.from(path.getElementsByTagName("inkml:trace"), (trace) =>
        (trace.textContent ?? "").split(",").map((sample) => sample.trim().split(/\s+/).slice(0, 2).map(Number)));
      return { raw: points[0], geometry: points[1] };
    });
  });
}

test("A straight ruler and French curve guide constrain ink without entering the note", async ({ page, context }) => {
  test.setTimeout(90_000);
  const button = (name: string) => page.getByRole("button", { name, exact: true });
  await page.goto("?root=opfs");
  await createTestNotebook(page);
  await button("New note").click();
  await enterText(page.getByRole("textbox", { name: "Title", exact: true }), "Guides");
  await button("Create").click();
  const canvas = page.locator('canvas[id^="ink-canvas-"]:visible');
  await canvas.waitFor();
  const cdp = await context.newCDPSession(page);

  await button("Ruler").click();
  await button("Straight ruler").click();
  const move = button("Move ruler");
  const handle = await move.boundingBox();
  if (!handle) throw new Error("Ruler has no move handle");
  const cx = handle.x + handle.width / 2;
  const cy = handle.y + handle.height / 2;
  expect(await traces(page), "the guide is transient").toEqual([]);
  await penStroke(cdp, [
    { x: cx - 150, y: cy + 5 },
    { x: cx - 70, y: cy + 22 },
    { x: cx + 30, y: cy - 16 },
    { x: cx + 150, y: cy + 14 },
  ], 0.6);
  const straight = await traces(page);
  expect(straight).toHaveLength(1);
  const rawHeight = Math.max(...straight[0].raw.map((point) => point[1])) - Math.min(...straight[0].raw.map((point) => point[1]));
  const guidedHeight = Math.max(...straight[0].geometry.map((point) => point[1])) - Math.min(...straight[0].geometry.map((point) => point[1]));
  expect(rawHeight).toBeGreaterThan(guidedHeight + 10);
  expect(guidedHeight).toBeLessThan(0.5);

  await page.mouse.move(cx, cy);
  await page.mouse.down();
  await page.mouse.move(cx, cy + 55, { steps: 8 });
  await page.mouse.up();
  const moved = await move.boundingBox();
  if (!moved) throw new Error("Ruler move handle disappeared");
  const my = moved.y + moved.height / 2;
  await penStroke(cdp, [
    { x: cx - 140, y: my + 4 },
    { x: cx - 30, y: my - 18 },
    { x: cx + 130, y: my + 11 },
  ], 0.6);
  const second = await traces(page);
  expect(second).toHaveLength(2);
  expect(Math.abs(second[1].geometry[0][1] - straight[0].geometry[0][1])).toBeGreaterThan(20);

  await button("Ruler").click();
  await button("French curve").click();
  const curve = await move.boundingBox();
  if (!curve) throw new Error("French curve has no move handle");
  const fx = curve.x + curve.width / 2;
  const fy = curve.y + curve.height / 2;
  await penStroke(cdp, [
    { x: fx + 40, y: fy - 38 },
    { x: fx + 80, y: fy - 45 },
    { x: fx + 120, y: fy - 59 },
    { x: fx + 160, y: fy - 38 },
  ], 0.6);
  const third = await traces(page);
  expect(third).toHaveLength(3);
  const curveHeight = Math.max(...third[2].geometry.map((point) => point[1])) - Math.min(...third[2].geometry.map((point) => point[1]));
  expect(curveHeight).toBeGreaterThan(guidedHeight + 5);
  expect(third[2].geometry).not.toEqual(third[2].raw);
  await button("Ruler").click();
  await button("Hide ruler").click();
  expect(await traces(page)).toEqual(third);
});
