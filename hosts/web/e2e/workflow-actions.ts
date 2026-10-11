import type { CDPSession, Locator, Page } from "@playwright/test";
import { expect } from "@playwright/test";

// Two animation frames: Flutter has drawn and sent what the last input
// changed.
export async function frames(page: Page): Promise<void> {
  await page.evaluate(() => new Promise<void>((done) => requestAnimationFrame(() => requestAnimationFrame(() => done()))));
}

// Flutter activates its text input channel after semantic focus is delivered.
// Use actual keyboard input after clicking, rather than fill's synchronous DOM
// value assignment. See Flutter web_ui semantics/text_field.dart, activate.
// The framework then sends the caret of the click to the input; a select-all
// before that arrives is undone (TRAPS.md).
export async function focusText(field: Locator): Promise<void> {
  await field.click();
  await frames(field.page());
}

export async function enterText(field: Locator, value: string): Promise<void> {
  await focusText(field);
  await field.press("ControlOrMeta+a");
  await field.pressSequentially(value);
}

export async function save(page: Page): Promise<void> {
  await page.getByRole("button", { name: "More", exact: true }).click();
  await page.getByRole("button", { name: "Save", exact: true }).click();
}

export async function goToPage(page: Page, number: number): Promise<void> {
  await page.getByRole("button", { name: "Pages", exact: true }).click();
  await page.getByRole("button", { name: "Go to page", exact: true }).click();
  await enterText(page.getByRole("textbox"), `${number}`);
  await page.getByRole("button", { name: "Go", exact: true }).click();
  // Pen events before the alert's barrier is gone never reach the page
  // (TRAPS.md). Split view shows a Library button in each pane.
  await expect(page.getByRole("button", { name: "Library", exact: true }).first()).toBeVisible();
}

export async function closeNote(page: Page): Promise<void> {
  await page.getByRole("button", { name: "More", exact: true }).click();
  await page.getByRole("button", { name: "Close note", exact: true }).click();
}

export type Box = { x: number; y: number; width: number; height: number };
export type PenPoint = { x: number; y: number };

// One CDP pen stroke through the points, at one pressure.
export async function penStroke(cdp: CDPSession, points: PenPoint[], force: number): Promise<void> {
  const pen = { pointerType: "pen" as const, force, tiltX: 20, tiltY: -10 };
  const [first, ...rest] = points;
  const last = points[points.length - 1];
  await cdp.send("Input.dispatchMouseEvent", {
    type: "mousePressed", button: "left", clickCount: 1, ...first, ...pen,
  });
  for (const point of rest) {
    await cdp.send("Input.dispatchMouseEvent", {
      type: "mouseMoved", button: "left", buttons: 1, ...point, ...pen,
    });
  }
  await cdp.send("Input.dispatchMouseEvent", {
    type: "mouseReleased", button: "left", clickCount: 1, ...last, ...pen,
  });
}

export function line(x0: number, x1: number, y: number, steps = 10): PenPoint[] {
  return Array.from({ length: steps + 1 }, (_, i) => ({ x: x0 + ((x1 - x0) * i) / steps, y }));
}

export type Rgb = [number, number, number];

// The pixels of a PNG, row by row. The page decodes the PNG and returns the
// RGBA bytes as one base64 string: an array of pixels takes seconds to cross
// the protocol.
export async function pngPixels(page: Page, png: Buffer): Promise<Rgb[]> {
  const rgba = Buffer.from(await page.evaluate(async (base64) => {
    const bytes = Uint8Array.from(atob(base64), (c) => c.charCodeAt(0));
    const bitmap = await createImageBitmap(new Blob([bytes], { type: "image/png" }));
    const context = new OffscreenCanvas(bitmap.width, bitmap.height).getContext("2d");
    if (!context) throw new Error("No 2D context");
    context.drawImage(bitmap, 0, 0);
    const data = context.getImageData(0, 0, bitmap.width, bitmap.height).data;
    let binary = "";
    for (let i = 0; i < data.length; i += 0x8000) binary += String.fromCharCode(...data.subarray(i, i + 0x8000));
    return btoa(binary);
  }, png.toString("base64")), "base64");
  return Array.from({ length: rgba.length / 4 }, (_, i): Rgb => [rgba[4 * i], rgba[4 * i + 1], rgba[4 * i + 2]]);
}

// The on-screen pixels of a rectangle, row by row, from a clipped capture: a
// full-viewport capture can show the WebGL canvas displaced (TRAPS.md).
export async function capture(page: Page, clip: Box): Promise<Rgb[]> {
  return pngPixels(page, await page.screenshot({ clip }));
}

