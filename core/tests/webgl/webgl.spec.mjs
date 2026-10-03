// Playwright: a stroke drawn through ink_input reaches the WebGL2 canvas
// through ink_render. Served without COOP/COEP headers.
import { test, expect } from "@playwright/test";

test("ink_render draws the desk, the paper and a stroke on a WebGL2 canvas", async ({ page }) => {
  page.on("console", (message) => console.log(`[${message.type()}] ${message.text()}`));
  await page.goto("/index.html");
  await page.waitForFunction(() => window.inkReady === true);
  const result = await page.evaluate(() => {
    const canvas = document.getElementById("canvas");
    canvas.width = 700;
    canvas.height = 400;
    const drew = Module.ccall("render_stroke", "number", ["number", "number"], [700, 400]);
    const px = (x, y) => (Module.ccall("canvas_pixel", "number", ["number", "number", "number"], [x, y, 400]) >>> 0)
      .toString(16).padStart(8, "0");
    const pixels = { stroke: px(90, 50), paper: px(300, 300), desk: px(650, 50) };
    return { drew, again: Module.ccall("render_again", "number", [], []), ...pixels };
  });
  expect(result).toEqual({ drew: 1, again: 0, stroke: "1a1a1aff", paper: "fcfaf5ff", desk: "daddd5ff" });
});
