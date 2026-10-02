import { expect, test as base, type CDPSession, type Locator, type Page } from "@playwright/test";
import { networkInterfaces } from "node:os";

// A failed workflow keeps the bridge's pointer log (window.mathNotesPointers):
// whether each pen event reached Flutter and the engine, for a stroke that
// left no ink (#72).
export const test = base.extend<{ pointerLog: void }>({
  pointerLog: [async ({ page }, use, info) => {
    await use();
    if (info.status === info.expectedStatus) return;
    const log = await page.evaluate(() => (window as unknown as { mathNotesPointers?: string[] }).mathNotesPointers ?? [])
      .catch(() => ["the page is gone"]);
    await info.attach("pointers.txt", { body: log.join("\n"), contentType: "text/plain" });
  }, { auto: true }],
});

// Two animation frames: Flutter has drawn and sent what the last input
// changed.
export async function frames(page: Page): Promise<void> {
  await page.evaluate(() => new Promise<void>((done) => requestAnimationFrame(() => requestAnimationFrame(() => done()))));
}

// A long press on `from`, then a drag to `to`. The frames after the hold let
// Flutter's long-press timer fire before the first move: a busy main thread
// can deliver queued input ahead of a due timer, and a move inside the hold
// cancels the drag (DelayedMultiDragGestureRecognizer). The move runs in
// steps with frames between them, as a hand moves: drop targets and
// reorderable grids track the drag per frame, and a release that arrives
// ahead of those frames drops at a stale slot.
export async function longPressDrag(page: Page, from: Box, to: Box): Promise<void> {
  const start = { x: from.x + from.width / 2, y: from.y + from.height / 2 };
  const end = { x: to.x + to.width / 2, y: to.y + to.height / 2 };
  await page.mouse.move(start.x, start.y);
  await page.mouse.down();
  await page.waitForTimeout(800);
  await frames(page);
  for (let step = 1; step <= 10; step++) {
    await page.mouse.move(start.x + ((end.x - start.x) * step) / 10, start.y + ((end.y - start.y) * step) / 10, { steps: 2 });
    await frames(page);
  }
  await page.waitForTimeout(400);
  await frames(page);
  await page.mouse.up();
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

// A read of a saved file while the app may be saving it again. `getFile()`
// snapshots the file, and Chromium can refuse the snapshot with NotReadableError
// or NotFoundError once the app's writable stream has swapped a new file in (storage/browser/
// blob/blob_reader.cc compares the modification time). The next read opens
// the new file.
export async function whenSaved<T>(read: () => Promise<T>): Promise<T> {
  const deadline = Date.now() + 3000;
  for (;;) {
    try {
      return await read();
    } catch (error) {
      if (!(error instanceof Error && /NotReadableError|NotFoundError/.test(error.message)) || Date.now() >= deadline) throw error;
      await new Promise((resolve) => setTimeout(resolve, 20));
    }
  }
}

export async function addTag(page: Page, tag: string): Promise<void> {
  await enterText(page.getByRole("textbox", { name: "Add a tag…", exact: true }), tag);
  await page.getByRole("button", { name: "Add tag", exact: true }).click();
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

export async function beginTestNote(page: Page, title: string, notebook = "Test Notebook"): Promise<void> {
  await createTestNotebook(page, notebook);
  await page.getByRole("button", { name: "New note", exact: true }).click();
  await enterText(page.getByRole("textbox", { name: "Title", exact: true }), title);
}

// A saved notebook in the notes folder, by its folder path: its layers, and
// each page's layer groups in file order with their strokes, links,
// bookmarks, and the lines of each text box.
export function storedNote(page: Page, path: string[]) {
  return whenSaved(() => page.evaluate(async (path) => {
    let dir = await navigator.storage.getDirectory();
    for (const name of path) dir = await dir.getDirectoryHandle(name);
    const manifest = JSON.parse(await (await (await dir.getFileHandle("notebook.json")).getFile()).text());
    const files = await dir.getDirectoryHandle("pages");
    const pages = [];
    for (const entry of manifest.pages as { file: string }[]) {
      const svg = await (await (await files.getFileHandle(entry.file.replace("pages/", ""))).getFile()).text();
      const parsed = new DOMParser().parseFromString(svg, "image/svg+xml");
      const groups = Array.from(parsed.documentElement.children).filter((g) => g.tagName === "g" && g.id !== "background");
      pages.push({
        file: entry.file,
        groups: groups.map((g) => ({
          id: g.id,
          xml: g.outerHTML,
          strokes: Array.from(g.querySelectorAll('path[id^="s-"]'), (stroke) => ({ id: stroke.id, d: stroke.getAttribute("d") })),
        })),
        links: Array.from(parsed.querySelectorAll("a"), (link) => link.getAttribute("href")),
        bookmarks: Array.from(parsed.querySelectorAll("g.mn-bookmark"), (bookmark) => bookmark.id),
        texts: Array.from(parsed.querySelectorAll("text"), (box) => Array.from(box.querySelectorAll("tspan"), (line) => line.textContent)),
      });
    }
    return { layers: manifest.layers as { id: string; name: string; hidden: boolean; locked: boolean }[], pages };
  }, path));
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

// Waits for the motion in a rectangle to end: two captures in a row alike.
export async function settled(page: Page, clip: Box): Promise<void> {
  await expect(async () => {
    const before = await capture(page, clip);
    expect(await capture(page, clip)).toEqual(before);
  }, "the view comes to rest").toPass({ timeout: 10_000 });
}

// The 9 × 9 square around a point.
export function screenPixels(page: Page, center: PenPoint): Promise<Rgb[]> {
  return capture(page, { x: center.x - 4, y: center.y - 4, width: 9, height: 9 });
}

export const brightness = (rgb: Rgb) => rgb[0] + rgb[1] + rgb[2];

// The ribbon outline and round handles of a selection (#9E2A2B), with their
// antialiased edges; the salmon test figure is brighter than red 215.
export const isOutline = ([red, green, blue]: Rgb) => red < 215 && red - green > 50 && red - blue > 50;

// Pen ink is near black; the paper, its dots, and its rules are much lighter.
// The ribbon marks of a selection are as dark, and are not ink.
export const isInk = (rgb: Rgb) => brightness(rgb) < 250 && !isOutline(rgb);

// The screen row of the darkest pixel in a column between two rows.
export async function inkRow(page: Page, x: number, top: number, bottom: number): Promise<number> {
  const column = await capture(page, { x, y: top, width: 1, height: bottom - top });
  const darkest = column.reduce((best, rgb, i) => (brightness(rgb) < brightness(column[best]) ? i : best), 0);
  expect(isInk(column[darkest]), "a column crosses the handwriting").toBe(true);
  return top + darkest;
}

// How many pixels of a screen row between two columns are ink.
export async function inkLength(page: Page, y: number, left: number, right: number): Promise<number> {
  return (await capture(page, { x: left, y, width: right - left, height: 1 })).filter(isInk).length;
}

export type Bounds = { left: number; right: number; top: number; bottom: number };

// The screen bounds of the pixels in a region that pass a test.
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

export const size = (bounds: Bounds) => ({ width: bounds.right - bounds.left, height: bounds.bottom - bounds.top });

export async function darkestPixel(page: Page, center: PenPoint): Promise<Rgb> {
  const pixels = await screenPixels(page, center);
  return pixels.reduce((darkest, rgb) => (brightness(rgb) < brightness(darkest) ? rgb : darkest));
}

// How much ink is on screen around a point: the total darkening of the
// square since `paper`, its capture before writing.
export async function inkAt(page: Page, center: PenPoint, paper: Rgb[]): Promise<number> {
  const pixels = await screenPixels(page, center);
  return pixels.reduce((sum, rgb, i) => sum + brightness(paper[i]) - brightness(rgb), 0);
}

export async function centerPixel(page: Page, center: PenPoint): Promise<Rgb> {
  return (await screenPixels(page, center))[40];
}

export async function openNewNote(page: Page, title: string, paper?: string): Promise<{ box: Box; cdp: CDPSession }> {
  await page.goto("?root=opfs");
  // Each paper gets its own notebook: the storage keeps earlier notebooks.
  await beginTestNote(page, title, paper);
  if (paper) await page.getByRole("button", { name: paper, exact: true }).click();
  await page.getByRole("button", { name: "Create", exact: true }).click();
  const canvas = page.locator('canvas[id^="ink-canvas-"]:visible');
  await canvas.waitFor({ timeout: 30_000 });
  const box = await canvas.boundingBox();
  if (!box) throw new Error("Notebook canvas has no bounds");
  return { box, cdp: await page.context().newCDPSession(page) };
}

// The editor leaves a desk margin around the pages at zoom 1 (deskMargin and
// deskLeft in editor_screen.dart); on the left it clears the floating rail.
// The first page's screen rectangle in a canvas.
export const DESK_MARGIN = 16;

export const DESK_LEFT = 8 + 60 + DESK_MARGIN;

export function pageIn(canvas: Box): Box {
  return { x: canvas.x + DESK_LEFT, y: canvas.y + DESK_MARGIN, width: canvas.width - DESK_LEFT - DESK_MARGIN, height: canvas.height - DESK_MARGIN };
}

// WCAG relative luminance: https://www.w3.org/TR/WCAG22/#dfn-relative-luminance
export function luminance(rgb: Rgb): number {
  const [red, green, blue] = rgb.map((channel) => {
    const value = channel / 255;
    return value <= 0.04045 ? value / 12.92 : ((value + 0.055) / 1.055) ** 2.4;
  });
  return 0.2126 * red + 0.7152 * green + 0.0722 * blue;
}

// WCAG contrast ratio; 4.5 is the minimum for legible body text:
// https://www.w3.org/TR/WCAG22/#contrast-minimum
export const contrast = (a: Rgb, b: Rgb) =>
  (Math.max(luminance(a), luminance(b)) + 0.05) / (Math.min(luminance(a), luminance(b)) + 0.05);

// The text drawn in a screen region: its left edge, and its contrast with
// the background, which is the top-left pixel of the region.
export async function textIn(page: Page, box: Box): Promise<{ left: number; contrast: number }> {
  const region = { x: Math.round(box.x), y: Math.round(box.y), width: Math.round(box.width), height: Math.round(box.height) };
  const pixels = await capture(page, region);
  const ratios = pixels.map((rgb) => contrast(rgb, pixels[0]));
  const first = ratios.reduce((left, ratio, i) => (ratio > 2 ? Math.min(left, i % region.width) : left), region.width);
  return { left: region.x + first, contrast: Math.max(...ratios) };
}

// The contrast of the text inside a control, measured from 4 px inside its
// rounded corners, where its own fill is the background.
export async function contrastIn(page: Page, locator: Locator): Promise<number> {
  const box = await boxOf(locator);
  return (await textIn(page, { x: box.x + 4, y: box.y + 4, width: box.width - 8, height: box.height - 8 })).contrast;
}

// Scrolls a control into view and waits until Flutter has drawn the scroll.
// Playwright scrolls the semantics DOM at once; Flutter scrolls its content
// in a later frame, and a click before that frame lands on the control that
// was drawn at that point (TRAPS.md).
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

// The ribbon (#9E2A2B) that marks the current selection; no cover color is
// as red with as little green and blue.
// Binder's board (#DADDD5): the desk and the chrome.
export const BOARD: Rgb = [0xda, 0xdd, 0xd5];

export const isRibbon = ([red, green, blue]: Rgb) => red > 130 && green < 80 && blue < 80;

// Taps an anchor whose pull-down menu opens at it: the items start within a
// finger's width of the anchor, and the menu is much narrower than the screen.
export async function openMenuAt(anchor: Locator, items: Locator[]): Promise<void> {
  const at = await boxOf(anchor);
  await anchor.click();
  // The menu grows from the anchor; the assertions hold when it is open.
  await expect(async () => {
    const boxes = await Promise.all(items.map(async (item) => {
      const box = await item.boundingBox();
      if (!box) throw new Error("The menu item has no bounds");
      return box;
    }));
    const left = Math.min(...boxes.map((box) => box.x));
    const right = Math.max(...boxes.map((box) => box.x + box.width));
    const top = Math.min(...boxes.map((box) => box.y));
    const bottom = Math.max(...boxes.map((box) => box.y + box.height));
    expect(right - left, "the menu is narrower than a bottom sheet").toBeLessThan(400);
    expect(right - left, "the menu is wider than its anchor's icon").toBeGreaterThan(150);
    expect(Math.max(left - (at.x + at.width), at.x - right), "the menu is beside the anchor").toBeLessThan(44);
    expect(Math.max(top - (at.y + at.height), at.y - bottom), "the menu is above or below the anchor").toBeLessThan(44);
  }).toPass({ timeout: 5_000 });
}

// The salmon square of fixtures/figure.jpg: 90 px wide, 15 px right of and
// 80 px below the top-left corner of the 230 × 200 px image.
export const isSalmon = ([red, green, blue]: Rgb) => red > 230 && Math.abs(green - 128) < 30 && Math.abs(blue - 129) < 30;

// The fill of each saved stroke on one page of a note, in file order.
export function storedFills(page: Page, path: string[], file: string) {
  return whenSaved(() => page.evaluate(async ({ path, file }) => {
    let dir = await navigator.storage.getDirectory();
    for (const name of path) dir = await dir.getDirectoryHandle(name);
    const svg = await (await (await (await dir.getDirectoryHandle("pages")).getFileHandle(file)).getFile()).text();
    return [...svg.matchAll(/<path id="s-[^"]*"[^>]* fill="(#[0-9A-F]{6})"/g)].map((match) => match[1]);
  }, { path, file }));
}

// Rows of a column through a stroke that the stroke darkens.
export async function inkThickness(page: Page, center: PenPoint): Promise<number> {
  const column = await capture(page, { x: center.x, y: center.y - 20, width: 1, height: 41 });
  return column.filter((rgb) => brightness(rgb) < 600).length;
}

// A tap outside a popover closes it. The popover's barrier takes every pointer
// event and hides the screen behind it from the accessibility tree until the
// close transition ends, so the editor's own buttons coming back is the sign
// that the next pen event reaches the page.
export async function closePopover(page: Page): Promise<void> {
  const viewport = page.viewportSize();
  if (!viewport) throw new Error("Page has no viewport");
  await page.mouse.click(viewport.width - 20, viewport.height - 20);
  await expect(page.getByRole("button", { name: "Library", exact: true })).toBeVisible();
}

// The rail's current-color dot opens the Colors popover: the swatches, the
// palette editor, and the saved pens.
// The current-color dot. Its accessible name carries the color: "Colors #1a1a1a".
export const COLORS = /^Colors #[0-9a-f]{6}$/;

export async function openColors(page: Page): Promise<void> {
  await page.getByRole("button", { name: COLORS }).click();
  await expect(page.getByRole("button", { name: "Edit colors", exact: true })).toBeVisible();
}

// A tap outside a popover that opened over the Colors popover closes only
// the top one.
export async function backToColors(page: Page): Promise<void> {
  const viewport = page.viewportSize();
  if (!viewport) throw new Error("Page has no viewport");
  await page.mouse.click(viewport.width - 20, viewport.height - 20);
  await expect(page.getByRole("button", { name: "Edit colors", exact: true })).toBeVisible();
}

// A tap on a swatch that is not the current color chooses it and closes the
// Colors popover.
export async function pickColor(page: Page, hex: string): Promise<void> {
  await openColors(page);
  await page.getByRole("button", { name: `Color ${hex}`, exact: true }).click();
  await expect(page.getByRole("button", { name: "Library", exact: true })).toBeVisible();
}

// The accessible names of the controls that Tab focuses, in order, from the
// current focus.
export async function tabOrder(page: Page, presses: number): Promise<string[]> {
  const names: string[] = [];
  for (let i = 0; i < presses; i++) {
    // Flutter creates a text field's input element after its focus moves, so
    // each press waits for the document focus to move.
    const before = await page.evaluateHandle(() => document.activeElement);
    await page.keyboard.press("Tab");
    await page.waitForFunction((element) => document.activeElement !== element, before);
    names.push(await page.evaluate(() => {
      const focused = document.activeElement;
      return (focused?.getAttribute("aria-label") ?? focused?.textContent ?? "").trim();
    }));
  }
  return names;
}

// The pages in the files of a note, in document order: the file of each page,
// its SVG size, and its stroke count.
export function storedPages(page: Page, title: string, notebook = "Test Notebook") {
  return whenSaved(() => page.evaluate(async ({ title, notebook }) => {
    const root = await navigator.storage.getDirectory();
    const dir = await (await root.getDirectoryHandle(notebook)).getDirectoryHandle(title);
    const manifest = JSON.parse(await (await (await dir.getFileHandle("notebook.json")).getFile()).text());
    const pages = await dir.getDirectoryHandle("pages");
    const saved = [];
    for (const entry of manifest.pages as { file: string }[]) {
      const svg = await (await (await pages.getFileHandle(entry.file.replace("pages/", ""))).getFile()).text();
      const parsed = new DOMParser().parseFromString(svg, "image/svg+xml");
      saved.push({
        file: entry.file,
        size: parsed.documentElement.getAttribute("viewBox")?.split(" ").slice(2).map(Number),
        strokes: svg.match(/<path id="s-/g)?.length ?? 0,
        ruling: parsed.getElementById("background")?.getAttribute("mn:ruling"),
        text: Array.from(parsed.querySelectorAll("text"), (box) => box.textContent).join("\n"),
      });
    }
    return saved;
  }, { title, notebook }));
}

export async function savedPages(page: Page, title: string, notebook = "Test Notebook") {
  await save(page);
  await expect(page.getByRole("status", { name: /^Notebook save/ })).toHaveAccessibleName("Notebook save Saved");
  return storedPages(page, title, notebook);
}

// Lined paper on the screen, and words written on it. `rules` holds the
// screen rows of the rules below the top of the view; `find` reads them again
// after the page scrolls.
export async function linedPaper(page: Page, cdp: CDPSession, box: Box) {
  // The rules of the paper below a screen row: the middle row of each thin
  // run that is darker than the paper, in a column with no handwriting.
  const rulesBelow = async (top: number) => {
    const height = Math.floor(box.y + box.height - 10 - top);
    const column = await capture(page, { x: box.x + box.width - 100, y: top, width: 1, height });
    const paper = column.reduce((best, rgb) => (brightness(rgb) > brightness(best) ? rgb : best));
    const found: number[] = [];
    let run: number[] = [];
    column.forEach((rgb, i) => {
      if (brightness(paper) - brightness(rgb) > 20) return run.push(top + i);
      if (run.length > 0 && run.length <= 4) found.push(run[Math.floor(run.length / 2)]);
      run = [];
    });
    return found;
  };
  let rules = await rulesBelow(Math.round(box.y + 120));
  const spacing = rules[1] - rules[0];
  const middle = (band: number) => rules[band] + spacing / 2;
  // The red margin line and the right edge of the page, which fills the width.
  const row = await capture(page, { x: box.x, y: Math.round(middle(0)), width: 300, height: 1 });
  const margin = box.x + row.reduce((best, rgb, i) => (rgb[0] - rgb[2] > row[best][0] - row[best][2] ? i : best), 0);
  expect(row[margin - box.x][0] - row[margin - box.x][2], "the paper has a margin line").toBeGreaterThan(25);
  const edge = box.x + box.width;

  // A word: one zigzag stroke, 70 px wide, in the band below rule `band`.
  const word = (left: number, band: number) =>
    penStroke(cdp, Array.from({ length: 8 }, (_, i) => ({
      x: margin + left + 10 * i, y: middle(band) + (i % 2 ? 0.2 : -0.2) * spacing,
    })), 0.6);
  // The words in a band: the screen columns of each run of ink, where a gap
  // of 6 px ends a run.
  const words = async (band: number) => {
    const left = margin + 8, width = edge - left;
    const pixels = await capture(page, { x: left, y: rules[band] + 3, width, height: Math.round(spacing) - 6 });
    const inked = new Array<boolean>(width).fill(false);
    pixels.forEach((rgb, i) => { if (isInk(rgb)) inked[i % width] = true; });
    const runs: { left: number; right: number }[] = [];
    inked.forEach((ink, i) => {
      if (!ink) return;
      const last = runs.at(-1);
      if (last && left + i - last.right < 6) last.right = left + i;
      else runs.push({ left: left + i, right: left + i });
    });
    return runs;
  };
  // The band shows words that start at these distances from the margin.
  const shows = (band: number, lefts: number[], message: string) =>
    expect.poll(async () => (await words(band)).map(({ left }) =>
      lefts.find((expected) => Math.abs(left - margin - expected) <= 4) ?? left - margin), { message }).toEqual(lefts);
  return {
    get rules() { return rules; },
    find: async (top: number) => { rules = await rulesBelow(top); },
    spacing, middle, margin, edge, word, words, shows,
  };
}

export const heldPen = { pointerType: "pen" as const, force: 0.6, button: "left" as const };

// The pen, which is down, moves.
export async function penDrag(cdp: CDPSession, from: PenPoint, to: PenPoint): Promise<void> {
  const steps = Math.ceil(Math.hypot(to.x - from.x, to.y - from.y) / 20);
  for (let step = 1; step <= steps; ++step) {
    await cdp.send("Input.dispatchMouseEvent", {
      type: "mouseMoved", buttons: 1, ...heldPen,
      x: from.x + ((to.x - from.x) * step) / steps, y: from.y + ((to.y - from.y) * step) / steps,
    });
  }
}

// The pen goes down and moves, and stays down.
export async function penHold(cdp: CDPSession, from: PenPoint, to: PenPoint): Promise<void> {
  await cdp.send("Input.dispatchMouseEvent", { type: "mousePressed", clickCount: 1, ...from, ...heldPen });
  await penDrag(cdp, from, to);
}

export async function penRelease(cdp: CDPSession, at: PenPoint): Promise<void> {
  await cdp.send("Input.dispatchMouseEvent", { type: "mouseReleased", clickCount: 1, ...at, ...heldPen });
}

// The largest brightness step between two neighbors in a screen column.
// Handwriting that shows sharp gives the step from ink to paper.
export async function sharpestStep(page: Page, x: number, top: number, bottom: number): Promise<number> {
  const column = await capture(page, { x, y: top, width: 1, height: bottom - top });
  return Math.max(...column.slice(1).map((rgb, i) => Math.abs(brightness(rgb) - brightness(column[i]))));
}

// The deployment also answers at this machine's LAN address, where Chrome
// gives no folder access: the context is not secure.
export function lanAddress(deployment: string): string {
  const lan = Object.values(networkInterfaces()).flat().find((address) => address?.family === "IPv4" && !address.internal);
  if (!lan) throw new Error("This machine has no LAN address");
  const url = new URL(deployment);
  url.protocol = "http:";
  url.hostname = lan.address;
  return url.href;
}
