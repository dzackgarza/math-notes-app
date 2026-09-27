import { expect, test } from "@playwright/test";

test("Flutter notebook retains pen input and pages after save and reopen", async ({ page }, info) => {
  await page.goto("favicon.svg");
  await page.evaluate(async () => {
    const root = await navigator.storage.getDirectory();
    for await (const name of root.keys()) await root.removeEntry(name, { recursive: true });
  });
  await page.goto("flutter/?root=opfs");
  await page.getByRole("button", { name: "New Note", exact: true }).click();
  await page.getByRole("textbox", { name: "Title" }).fill("Lecture");
  await page.getByRole("button", { name: "Create", exact: true }).click();
  const canvas = page.locator('canvas[id^="ink-canvas-"]');
  await expect(canvas).toBeVisible();
  const box = await canvas.boundingBox();
  if (!box) throw new Error("Notebook canvas has no bounds");
  const cdp = await page.context().newCDPSession(page);
  const pen = { pointerType: "pen", force: 0.6, tiltX: 20, tiltY: -10 };
  await cdp.send("Input.dispatchMouseEvent", { type: "mousePressed", button: "left", clickCount: 1, x: box.x + 160, y: box.y + 150, ...pen });
  await cdp.send("Input.dispatchMouseEvent", { type: "mouseMoved", button: "left", buttons: 1, x: box.x + 240, y: box.y + 190, ...pen });
  await cdp.send("Input.dispatchMouseEvent", { type: "mouseReleased", button: "left", clickCount: 1, x: box.x + 240, y: box.y + 190, ...pen });
  await page.getByText("Add page", { exact: true }).click();
  await page.getByRole("button", { name: "Save", exact: true }).click();
  await expect(page.getByText("Notebook save Saved", { exact: true })).toBeVisible();
  const saved = await page.evaluate(async () => {
    const root = await navigator.storage.getDirectory();
    const dir = await root.getDirectoryHandle("Lecture");
    const pages = await dir.getDirectoryHandle("pages");
    return (await (await pages.getFileHandle("0001.svg")).getFile()).text();
  });
  expect(saved).toContain('<path id="s-');
  expect(saved).toContain("inkml:trace");
  await page.screenshot({ path: info.outputPath("notebook.png") });
  await page.reload();
  await page.getByText("Lecture", { exact: true }).click();
  await expect(canvas).toBeVisible();
  await expect(page.getByText("1 / 2", { exact: true })).toBeVisible();
  await page.getByRole("button", { name: "Next", exact: true }).click();
  await expect(page.getByText("2 / 2", { exact: true })).toBeVisible();
});
