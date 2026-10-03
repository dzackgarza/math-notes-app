import { expect } from "@playwright/test";
import { test, createTestNotebook, enterText, penStroke, line, savedPages } from "./support.ts";

test("Editor preferences: the last note reopens and the undo dial uses its chosen steps", async ({ page, context }, info) => {
  test.setTimeout(120_000);
  const button = (name: string) => page.getByRole("button", { name, exact: true });
  await page.goto("?root=opfs");
  await createTestNotebook(page);
  await button("New note").click();
  await enterText(page.getByRole("textbox", { name: "Title", exact: true }), "Recall");
  await button("Create").click();
  const canvas = page.locator('canvas[id^="ink-canvas-"]:visible');
  await canvas.waitFor();
  const box = await canvas.boundingBox();
  if (!box) throw new Error("Canvas has no bounds");
  const cdp = await context.newCDPSession(page);
  for (const dy of [180, 240, 300]) {
    await penStroke(cdp, line(box.x + 200, box.x + 300, box.y + dy), 0.6);
  }
  expect((await savedPages(page, "Recall")).map((item) => item.strokes)).toEqual([3]);

  await button("More").click();
  await button("Settings").click();
  await page.getByRole("switch", { name: "Open last note on launch" }).click();
  await page.getByRole("button", { name: "8", exact: true }).click();
  expect(await page.evaluate(() => localStorage.getItem("undoDialSteps"))).toBe("8");
  await button("Done").click();
  await page.reload();
  await expect(page.getByRole("heading", { name: "Recall", exact: true })).toBeVisible();
  await canvas.waitFor();
  expect((await savedPages(page, "Recall")).map((item) => item.strokes)).toEqual([3]);
  expect(await page.evaluate(() => localStorage.getItem("undoDialSteps"))).toBe("8");
  for (const dy of [360, 420]) {
    await penStroke(cdp, line(box.x + 200, box.x + 300, box.y + dy), 0.6);
  }
  expect((await savedPages(page, "Recall")).map((item) => item.strokes)).toEqual([5]);

  const undo = await button("Undo").boundingBox();
  if (!undo) throw new Error("Undo button has no bounds");
  const start = { x: undo.x + undo.width / 2, y: undo.y + undo.height / 2 };
  const center = { x: undo.x + 1.3 * undo.width + 2.5 * undo.height, y: start.y };
  const radius = 85;
  const at = (degrees: number) => ({
    x: center.x + radius * Math.cos(Math.PI + degrees * Math.PI / 180),
    y: center.y + radius * Math.sin(Math.PI + degrees * Math.PI / 180),
  });
  await page.mouse.move(start.x, start.y);
  await page.mouse.down();
  for (let degrees = -5; degrees >= -105; degrees -= 5) await page.mouse.move(at(degrees).x, at(degrees).y);
  await page.screenshot({ path: info.outputPath("dial.png") });
  await page.mouse.up();
  expect((await savedPages(page, "Recall")).map((item) => item.strokes)).toEqual([3]);
});
