// Helpers for specs that run in every browser engine: pen strokes as
// constructed PointerEvents (Firefox and WebKit have no CDP input), and pixels
// read from screenshots.
import type { Locator, Page } from "@playwright/test";

// A pen stroke through `points` (page coordinates), dispatched on `target`
// as the pen digitizer delivers it.
export async function penStroke(target: Locator, points: { x: number; y: number }[]): Promise<void> {
  await target.evaluate((element, points) => {
    const send = (type: string, p: { x: number; y: number }, buttons: number) =>
      element.dispatchEvent(
        new PointerEvent(type, {
          bubbles: true, pointerId: 1, pointerType: "pen", isPrimary: true, button: type === "pointermove" ? -1 : 0,
          buttons, pressure: buttons ? 0.6 : 0, tiltX: 20, tiltY: -10, clientX: p.x, clientY: p.y,
        }),
      );
    send("pointerdown", points[0], 1);
    for (const p of points.slice(1)) send("pointermove", p, 1);
    send("pointerup", points[points.length - 1], 0);
  }, points);
}

// RGBA of page pixel (x, y), read from a screenshot.
export async function pixel(page: Page, x: number, y: number): Promise<number[]> {
  const png = (await page.screenshot({ clip: { x, y, width: 1, height: 1 } })).toString("base64");
  return page.evaluate(async (data) => {
    const image = new Image();
    image.src = `data:image/png;base64,${data}`;
    await image.decode();
    const context = new OffscreenCanvas(1, 1).getContext("2d")!;
    context.drawImage(image, 0, 0);
    return Array.from(context.getImageData(0, 0, 1, 1).data);
  }, png);
}
