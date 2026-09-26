// A notebook on a static web server, opened read-only by the URL of its
// notebook.json (#27). nginx serves e2e/fixtures/published at
// /math-notes-fixtures/published/ (e2e/nginx-fixtures.conf): three pages, a
// red and a blue ink block, and a green image loaded from ../assets/.
import { expect, test } from "@playwright/test";

import { penStroke, pixel } from "./input.ts";

const RED = [0xb5, 0x1f, 0x1f], BLUE = [0x1f, 0x4f, 0xb5], GREEN = [0x3f, 0xa3, 0x5b];
const near = (actual: number[], expected: number[]) => expected.every((c, i) => Math.abs(actual[i] - c) <= 8);

test("the read-only URL renders every page and turns pen input into no ink", async ({ page, baseURL }) => {
  const url = new URL("/math-notes-fixtures/published/notebook.json", baseURL).href;
  await page.goto(`?open=${encodeURIComponent(url)}`);
  const canvas = page.locator("#ink-canvas");
  await expect(canvas).toBeVisible();
  const box = (await canvas.boundingBox())!;
  const center = { x: box.x + box.width / 2, y: box.y + box.height / 2 };

  // Each page's block fills the middle of the view when the page is at the top.
  for (const [i, color] of [RED, BLUE, GREEN].entries()) {
    if (i > 0) await page.getByRole("button", { name: "Next page" }).click();
    await expect.poll(async () => near(await pixel(page, center.x, center.y), color), { message: `page ${i + 1}` }).toBe(true);
  }

  // A pen stroke across the paper left of the block leaves the paper white.
  await page.getByRole("button", { name: "Previous page" }).click();
  await page.getByRole("button", { name: "Previous page" }).click();
  await expect.poll(async () => near(await pixel(page, center.x, center.y), RED)).toBe(true);
  const x = box.x + box.width * 0.1;
  await penStroke(canvas, Array.from({ length: 20 }, (_, i) => ({ x, y: center.y - 100 + i * 10 })));
  await page.getByRole("button", { name: "Next page" }).click();
  await page.getByRole("button", { name: "Previous page" }).click();
  await expect.poll(async () => near(await pixel(page, center.x, center.y), RED)).toBe(true);
  expect(Math.min(...(await pixel(page, x, center.y)).slice(0, 3))).toBeGreaterThan(240);
});
