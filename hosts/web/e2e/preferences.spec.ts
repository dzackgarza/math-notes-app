import { expect } from "@playwright/test";
import { test, centerPixel, createTestNotebook, enterText, openTestNotebook, penStroke, line, savedPages, storedNote, brightness, frames, isInk, pixelBounds, closePopover } from "./support.ts";

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
  await page.getByRole("button", { name: "Dark", exact: true }).click();
  await button("Done").click();
  await expect(page.getByRole("dialog", { name: "Settings" })).toHaveCount(0);
  await page.screenshot({ path: info.outputPath("dark-editor.png") });
  expect(await centerPixel(page, { x: 300, y: 24 })).toEqual([0x26, 0x30, 0x2c]);
  expect(brightness(await centerPixel(page, { x: 500, y: 400 }))).toBeGreaterThan(730);
  await button("Open navigation").click();
  await button("Navigation Layers").click();
  await page.screenshot({ path: info.outputPath("dark-navigation.png") });
  await button("Close navigation").click();
  await button("Pages").click();
  await page.screenshot({ path: info.outputPath("dark-pages-menu.png") });
  await closePopover(page);
  await button("Pen").click();
  await button("Save pen").waitFor();
  await page.screenshot({ path: info.outputPath("dark-pen-menu.png") });
  await closePopover(page);
  await page.reload();
  await expect(page.getByRole("heading", { name: "Recall", exact: true })).toBeVisible();
  await canvas.waitFor();
  expect(await centerPixel(page, { x: 300, y: 24 })).toEqual([0x26, 0x30, 0x2c]);
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
  await button("More").click();
  await button("Settings").click();
  await button("3 ←").first().click();
  await button("3 →").last().click();
  await frames(page);
  await page.screenshot({ path: info.outputPath("dark-settings.png") });
  await button("Done").click();
  await expect(page.getByRole("dialog", { name: "Settings" })).toHaveCount(0);
  expect(await page.evaluate(() => [localStorage.getItem("undoGesture"), localStorage.getItem("redoGesture")]))
    .toEqual(["threeFingerSwipeLeft", "threeFingerSwipeRight"]);
  await penStroke(cdp, line(box.x + 200, box.x + 300, box.y + 480), 0.6);
  expect((await savedPages(page, "Recall")).map((item) => item.strokes)).toEqual([4]);
  const inkRegion = { x: 90, y: 140, width: 600, height: 400 };
  const beforeSwipes = await pixelBounds(page, inkRegion, isInk);
  const swipe = async (direction: -1 | 1) => {
    const origin = Array.from({ length: 3 }, (_, id) => ({ id, x: box.x + 440 + id * 42, y: box.y + 240 }));
    await cdp.send("Input.dispatchTouchEvent", { type: "touchStart", touchPoints: origin });
    for (const distance of [20, 40, 60, 80]) {
      await cdp.send("Input.dispatchTouchEvent", {
        type: "touchMove", touchPoints: origin.map((point) => ({ ...point, x: point.x + direction * distance })),
      });
    }
    await cdp.send("Input.dispatchTouchEvent", { type: "touchEnd", touchPoints: [] });
  };
  await swipe(-1);
  await expect.poll(async () => (await savedPages(page, "Recall")).map((item) => item.strokes)).toEqual([3]);
  await swipe(1);
  await expect.poll(async () => (await savedPages(page, "Recall")).map((item) => item.strokes)).toEqual([4]);
  const afterSwipes = await pixelBounds(page, inkRegion, isInk);
  for (const edge of ["left", "right", "top", "bottom"] as const) {
    expect(Math.abs(afterSwipes[edge] - beforeSwipes[edge]), `the ${edge} edge stays in place`).toBeLessThanOrEqual(2);
  }
  const doubleTap = async () => {
    const point = [{ id: 0, x: box.x + 450, y: box.y + 260 }];
    for (let tap = 0; tap < 2; tap++) {
      await cdp.send("Input.dispatchTouchEvent", { type: "touchStart", touchPoints: point });
      await cdp.send("Input.dispatchTouchEvent", { type: "touchEnd", touchPoints: [] });
    }
  };
  const inkWidth = async () => {
    const bounds = await pixelBounds(page, inkRegion, isInk);
    return bounds.right - bounds.left;
  };
  const fittedWidth = await inkWidth();
  await cdp.send("Input.synthesizePinchGesture", { x: box.x + 450, y: box.y + 260, scaleFactor: 1.5, relativeSpeed: 500 });
  await frames(page);
  await expect.poll(inkWidth).toBeGreaterThan(fittedWidth * 1.2);
  await doubleTap();
  await frames(page);
  await expect.poll(async () => Math.abs((await inkWidth()) - fittedWidth)).toBeLessThanOrEqual(2);
  expect((await savedPages(page, "Recall")).map((item) => item.strokes)).toEqual([4]);
  await button("Pages").click();
  await button("Add bookmark").click();
  await expect(page.getByLabel("Add bookmark\nTap the line to mark.", { exact: true })).toBeVisible();
  await cdp.send("Input.synthesizePinchGesture", { x: box.x + 450, y: box.y + 260, scaleFactor: 1.5, relativeSpeed: 500 });
  await expect.poll(inkWidth).toBeGreaterThan(fittedWidth * 1.2);
  await doubleTap();
  await expect.poll(async () => Math.abs((await inkWidth()) - fittedWidth)).toBeLessThanOrEqual(2);
  const single = [{ id: 0, x: box.x + 450, y: box.y + 260 }];
  await cdp.send("Input.dispatchTouchEvent", { type: "touchStart", touchPoints: single });
  await cdp.send("Input.dispatchTouchEvent", { type: "touchEnd", touchPoints: [] });
  await expect.poll(async () => (await storedNote(page, ["Test Notebook", "Recall"])).pages[0].bookmarks.length).toBe(1);
  await button("Close Add bookmark").click();
  await button("Library").click();
  await page.screenshot({ path: info.outputPath("dark-library.png") });
  await openTestNotebook(page);
  await button("New note").click();
  await page.getByRole("textbox", { name: "Title", exact: true }).waitFor();
  await page.getByLabel("First page preview").waitFor();
  await page.screenshot({ path: info.outputPath("dark-new-note.png") });
  await button("Cancel").click();
  await button("Recall actions").click();
  await button("Move to trash").click();
  await expect(button("Recall actions")).toHaveCount(0);
  await expect.poll(() => page.evaluate(async () => {
    const root = await navigator.storage.getDirectory();
    const notebook = await root.getDirectoryHandle("Test Notebook");
    for await (const name of notebook.keys()) if (name === "Recall") return true;
    return false;
  })).toBe(false);
  await page.reload();
  await expect(page.getByRole("group", { name: /The last note is unavailable/ })).toBeVisible();
});
