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


export async function createTestNotebook(page: Page, name = "Test Notebook"): Promise<void> {
  await page.getByRole("button", { name: "New notebook", exact: true }).click();
  await enterText(page.getByRole("textbox", { name: "Notebook title", exact: true }), name);
  await page.getByRole("button", { name: "Create", exact: true }).click();
}

export async function openTestNotebook(page: Page, name = "Test Notebook"): Promise<void> {
  await page.getByRole("button", { name: `Open ${name}`, exact: false }).click();
  await expect(page.getByRole("heading", { name, exact: true })).toBeVisible();
}

export async function settled(page: Page, clip: Box): Promise<void> {
  await expect(async () => {
    const before = await capture(page, clip);
    expect(await capture(page, clip)).toEqual(before);
  }, "the view comes to rest").toPass({ timeout: 10_000 });
}

export function screenPixels(page: Page, center: PenPoint): Promise<Rgb[]> {
  return capture(page, { x: center.x - 4, y: center.y - 4, width: 9, height: 9 });
}

export const brightness = (rgb: Rgb) => rgb[0] + rgb[1] + rgb[2];

export const isInk = (rgb: Rgb) => brightness(rgb) < 250;

export type Bounds = { left: number; right: number; top: number; bottom: number };

export async function pixelBounds(page: Page, region: Box, test: (rgb: Rgb) => boolean): Promise<Bounds> {
  const pixels = await capture(page, region);
  const bounds = { left: Infinity, right: -Infinity, top: Infinity, bottom: -Infinity };
  pixels.forEach((rgb, i) => {
    if (!test(rgb)) return;
    const x = region.x + (i % region.width);
    const y = region.y + Math.floor(i / region.width);
    bounds.left = Math.min(bounds.left, x);
    bounds.right = Math.max(bounds.right, x);
    bounds.top = Math.min(bounds.top, y);
    bounds.bottom = Math.max(bounds.bottom, y);
  });
  expect(bounds.left, "the region shows the pixels").toBeLessThanOrEqual(bounds.right);
  return bounds;
}

export const isOutline = ([red, , blue]: Rgb) => blue - red > 60;

export async function inkAt(page: Page, center: PenPoint, paper: Rgb[]): Promise<number> {
  const pixels = await screenPixels(page, center);
  return pixels.reduce((sum, rgb, i) => sum + brightness(paper[i]) - brightness(rgb), 0);
}

export const DESK_MARGIN = 16;

export const DESK_LEFT = 8 + 60 + DESK_MARGIN;

export function pageIn(canvas: Box): Box {
  return { x: canvas.x + DESK_LEFT, y: canvas.y + DESK_MARGIN, width: canvas.width - DESK_LEFT - DESK_MARGIN, height: canvas.height - DESK_MARGIN };
}

export async function inView(locator: Locator): Promise<Locator> {
  await locator.scrollIntoViewIfNeeded();
  await frames(locator.page());
  return locator;
}

export async function boxOf(locator: Locator): Promise<Box> {
  await inView(locator);
  const box = await locator.boundingBox();
  if (!box) throw new Error("The element has no bounds");
  return box;
}

export async function longPressDrag(page: Page, from: Box, to: Box): Promise<void> {
  const x = from.x + from.width / 2;
  const y = from.y + from.height / 2;
  await page.mouse.move(x, y);
  await settled(page, from);
  await page.mouse.down();
  // This is the held input gesture, not a readiness wait. Flutter's
  // kLongPressTimeout is 500 ms (gestures/constants.dart); pressed-state
  // pixels can change earlier and do not establish a recognized long press.
  await new Promise(resolve => setTimeout(resolve, 600));
  await page.mouse.move(to.x + to.width / 2, to.y + to.height / 2, { steps: 20 });
  // The drop takes the slot the dragged item has settled into: release once
  // the items between start and target stop moving.
  const left = Math.min(from.x, to.x);
  const top = Math.min(from.y, to.y);
  await settled(page, {
    x: left, y: top,
    width: Math.max(from.x + from.width, to.x + to.width) - left,
    height: Math.max(from.y + from.height, to.y + to.height) - top,
  });
  await page.mouse.up();
}

export async function touchLongPressDrag(page: Page, from: Box, to: Box): Promise<void> {
  const start = { x: from.x + from.width / 2, y: from.y + from.height / 2, id: 1 };
  const end = { x: to.x + to.width / 2, y: to.y + to.height / 2, id: 1 };
  const cdp = await page.context().newCDPSession(page);
  await settled(page, from);
  await cdp.send("Input.dispatchTouchEvent", { type: "touchStart", touchPoints: [start] });
  await new Promise(resolve => setTimeout(resolve, 600));
  for (let step = 1; step <= 20; step++) {
    await cdp.send("Input.dispatchTouchEvent", {
      type: "touchMove",
      touchPoints: [{ x: start.x + (end.x - start.x) * step / 20, y: start.y + (end.y - start.y) * step / 20, id: 1 }],
    });
  }
  await new Promise(resolve => setTimeout(resolve, 300));
  await cdp.send("Input.dispatchTouchEvent", { type: "touchEnd", touchPoints: [] });
}

export async function closePopover(page: Page): Promise<void> {
  const viewport = page.viewportSize();
  if (!viewport) throw new Error("Page has no viewport");
  await page.mouse.click(viewport.width - 20, viewport.height - 20);
  await expect(page.getByRole("button", { name: "Library", exact: true })).toBeVisible();
}

export async function inkRow(page: Page, x: number, top: number, bottom: number): Promise<number> {
  const column = await capture(page, { x, y: top, width: 1, height: bottom - top });
  const darkest = column.reduce((best, rgb, i) => (brightness(rgb) < brightness(column[best]) ? i : best), 0);
  expect(isInk(column[darkest]), "a column crosses the handwriting").toBe(true);
  return top + darkest;
}

export const size = (bounds: Bounds) => ({ width: bounds.right - bounds.left, height: bounds.bottom - bounds.top });

export const COLORS = /^Colors #[0-9a-f]{6}$/;

export async function openColors(page: Page): Promise<void> {
  await page.getByRole("button", { name: COLORS }).click();
  await expect(page.getByRole("button", { name: "Edit colors", exact: true })).toBeVisible();
}

export async function pickColor(page: Page, hex: string): Promise<void> {
  await openColors(page);
  await page.getByRole("button", { name: `Color ${hex}`, exact: true }).click();
  await expect(page.getByRole("button", { name: "Library", exact: true })).toBeVisible();
}

export async function addTag(page: Page, tag: string): Promise<void> {
  await enterText(page.getByRole("textbox", { name: "Add a tag…", exact: true }), tag);
  await page.getByRole("button", { name: "Add tag", exact: true }).click();
}

export async function darkestPixel(page: Page, center: PenPoint): Promise<Rgb> {
  const pixels = await screenPixels(page, center);
  return pixels.reduce((darkest, rgb) => (brightness(rgb) < brightness(darkest) ? rgb : darkest));
}
