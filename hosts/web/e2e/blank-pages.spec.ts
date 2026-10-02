import { expect } from "@playwright/test";
import { test, boxOf, createTestNotebook, enterText, goToPage, line, penStroke, savedPages } from "./support.ts";

test("a note removes blank pages together and one undo restores them", async ({ page }) => {
  const button = (name: string) => page.getByRole("button", { name, exact: true });
  await page.goto("?root=opfs");
  await createTestNotebook(page, "Cleanup");
  await button("New note").click();
  await enterText(page.getByRole("textbox", { name: "Title", exact: true }), "Scratch");
  await button("Create").click();
  const canvas = page.locator('canvas[id^="ink-canvas-"]:visible');
  const box = await boxOf(canvas);
  const cdp = await page.context().newCDPSession(page);
  await penStroke(cdp, line(box.x + 150, box.x + 250, box.y + 170), 0.6);

  for (let number = 2; number <= 4; number++) {
    await button("Add page").click();
    await button("At end").click();
    await expect(page.getByText(`1 / ${number}`, { exact: true })).toBeVisible();
  }
  await goToPage(page, 3);
  await button("Text").click();
  await enterText(page.getByRole("textbox", { name: "Text", exact: true }), "Keep this page");
  await button("Done").click();
  await button("Clear selection").click();
  const before = await savedPages(page, "Scratch", "Cleanup");
  expect(before.map(({ strokes }) => strokes)).toEqual([1, 0, 0, 0]);
  expect(before[2].text).toContain("Keep this page");

  await button("Open navigation").click();
  await button("Delete all blank pages").click();
  await expect(page.getByRole("status", { name: "2 blank pages deleted" })).toBeVisible();
  const kept = await savedPages(page, "Scratch", "Cleanup");
  expect(kept).toHaveLength(2);
  expect(kept[0].strokes).toBe(1);
  expect(kept[1].text).toContain("Keep this page");

  await button("Undo").last().click();
  const restored = await savedPages(page, "Scratch", "Cleanup");
  expect(restored.map(({ file }) => file)).toEqual(before.map(({ file }) => file));
  expect(restored[2].text).toContain("Keep this page");
});
