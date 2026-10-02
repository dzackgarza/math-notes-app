import { expect, type Page } from "@playwright/test";
import { test, enterText, save, whenSaved, createTestNotebook, openTestNotebook, savedPages, penStroke, line, screenPixels, inkAt, inkRow, inkLength, settled, closePopover, type Box, type PenPoint } from "./support.ts";

// A new note in the open notebook; its canvas's screen rectangle.
async function newNote(page: Page, title: string): Promise<Box> {
  await page.getByRole("button", { name: "New note", exact: true }).click();
  await enterText(page.getByRole("textbox", { name: "Title", exact: true }), title);
  await page.getByRole("button", { name: "Create", exact: true }).click();
  const canvas = page.locator('canvas[id^="ink-canvas-"]:visible');
  await canvas.waitFor({ timeout: 30_000 });
  await expect(page.getByRole("heading", { name: title, exact: true })).toBeVisible();
  const box = await canvas.boundingBox();
  if (!box) throw new Error("Notebook canvas has no bounds");
  return box;
}

async function backToNotebook(page: Page): Promise<void> {
  await page.getByRole("button", { name: "Library", exact: true }).click();
  await expect(page.getByRole("heading", { name: "Test Notebook", exact: true })).toBeVisible();
}

// A user writes by hand as on paper: light and hard pen strokes with the palm
// on the page, a finger pan and a pinch, the mouse wheel and Ctrl+wheel zoom.
// Then pages side by side in horizontal scroll, and a reload; erasing with
// the pen's side button and its eraser end, drawing with a finger, two pages
// per row with a PDF share, and a reload that keeps the finger and layout
// settings.
test("Flutter handwriting session: pen pressure, palm, finger and wheel navigation, page layouts, eraser, and finger drawing", async ({ page }, info) => {
  test.setTimeout(240_000);
  const button = (name: string) => page.getByRole("button", { name, exact: true });
  const shot = (name: string) => page.screenshot({ path: info.outputPath(`${name}.png`) });
  const canvas = page.locator('canvas[id^="ink-canvas-"]:visible');
  const touch = (type: "touchStart" | "touchMove" | "touchEnd", points: PenPoint[]) =>
    cdp.send("Input.dispatchTouchEvent", { type, touchPoints: points.map((p, id) => ({ id, ...p })) });

  await page.goto("?root=opfs");
  await createTestNotebook(page);
  let box = await newNote(page, "Pressure");
  const cdp = await page.context().newCDPSession(page);

  await test.step("write a light and a hard stroke", async () => {
    const light = { x: box.x + 240, y: box.y + 180 };
    const hard = { x: box.x + 240, y: box.y + 260 };
    const paper = [await screenPixels(page, light), await screenPixels(page, hard)];
    await penStroke(cdp, line(box.x + 140, box.x + 340, light.y), 0.15);
    await penStroke(cdp, line(box.x + 140, box.x + 340, hard.y), 1);
    await shot("pressure");
    // Ink on screen: how much each stroke darkened the paper across its width.
    const ratio = (await inkAt(page, hard, paper[1])) / (await inkAt(page, light, paper[0]));
    expect(ratio).toBeGreaterThan(1.3);
    expect(ratio).toBeLessThan(3);
  });

  await test.step("write with the palm dragging on the page", async () => {
    const pen = { pointerType: "pen" as const, force: 0.6 };
    const palm = { id: 1, x: box.x + box.width - 80, y: box.y + box.height - 60 };
    await cdp.send("Input.dispatchMouseEvent", { type: "mousePressed", button: "left", clickCount: 1, x: box.x + 160, y: box.y + 150, ...pen });
    await cdp.send("Input.dispatchTouchEvent", { type: "touchStart", touchPoints: [palm] });
    for (const distance of [40, 150, 300]) {
      await cdp.send("Input.dispatchTouchEvent", { type: "touchMove", touchPoints: [{ ...palm, y: palm.y - distance }] });
      await cdp.send("Input.dispatchMouseEvent", { type: "mouseMoved", button: "left", buttons: 1, x: box.x + 160 + distance / 4, y: box.y + 150 + distance / 8, ...pen });
    }
    await cdp.send("Input.dispatchTouchEvent", { type: "touchEnd", touchPoints: [] });
    await cdp.send("Input.dispatchMouseEvent", { type: "mouseReleased", button: "left", clickCount: 1, x: box.x + 235, y: box.y + 187, ...pen });
    await save(page);
    await expect(page.getByRole("status", { name: /^Notebook save/ })).toHaveAccessibleName("Notebook save Saved");
    // The palm stroke is the third and last trace on the page.
    const trace = await whenSaved(() => page.evaluate(async () => {
      const root = await navigator.storage.getDirectory();
      const notebook = await root.getDirectoryHandle("Test Notebook");
      const pages = await (await notebook.getDirectoryHandle("Pressure")).getDirectoryHandle("pages");
      const svg = await (await (await pages.getFileHandle("0001.svg")).getFile()).text();
      const traces = new DOMParser().parseFromString(svg, "image/svg+xml").getElementsByTagName("inkml:trace");
      if (traces.length !== 3) throw new Error(`Saved page has ${traces.length} stroke traces, not 3`);
      const text = traces[2].textContent;
      if (!text) throw new Error("Saved page has no stroke trace");
      return text.split(",").map((sample) => sample.trim().split(" ").slice(0, 2).map(Number));
    }));
    const xs = trace.map(([x]) => x);
    const ys = trace.map(([, y]) => y);
    // The pen moved 75 px right and 37 px down. A page that scrolled with the
    // palm would stretch the stroke 300 px vertically.
    expect(Math.max(...ys) - Math.min(...ys)).toBeLessThan(Math.max(...xs) - Math.min(...xs));
  });

  await test.step("pan the page with one finger and zoom it with a pinch", async () => {
    const written = { x: box.x + 500, y: box.y + 320 };
    await penStroke(cdp, line(written.x - 40, written.x + 40, written.y), 0.6);
    // A column through the handwriting, between two columns of paper dots.
    const column = written.x + 18;
    const top = box.y + 120;
    const bottom = box.y + box.height - 40;
    const before = await inkRow(page, column, top, bottom);

    // A finger drags 150 px up; the page follows it past the touch slop.
    const finger = { x: box.x + 900, y: box.y + 450 };
    await touch("touchStart", [finger]);
    for (let dy = 30; dy <= 150; dy += 30) await touch("touchMove", [{ x: finger.x, y: finger.y - dy }]);
    await touch("touchEnd", []);
    await shot("panned");
    const panned = await inkRow(page, column, top, bottom);
    expect(before - panned).toBeGreaterThan(100);
    expect(before - panned).toBeLessThanOrEqual(150);

    // Two fingers spread from 100 to 240 px apart below the handwriting.
    const length = await inkLength(page, panned, written.x - 200, written.x + 200);
    const spread = (half: number) => [{ x: written.x - half, y: panned + 60 }, { x: written.x + half, y: panned + 60 }];
    await touch("touchStart", spread(50));
    for (let half = 60; half <= 120; half += 10) await touch("touchMove", spread(half));
    await touch("touchEnd", []);
    await shot("pinched");
    const zoomed = await inkRow(page, column, top, bottom);
    expect(await inkLength(page, zoomed, written.x - 300, written.x + 300)).toBeGreaterThan(1.5 * length);
  });

  await test.step("scroll a new note with the mouse wheel and zoom it with Ctrl and the wheel", async () => {
    await backToNotebook(page);
    box = await newNote(page, "Wheel");
    const written = { x: box.x + 500, y: box.y + 420 };
    await penStroke(cdp, line(written.x - 40, written.x + 40, written.y), 0.6);
    // A column through the handwriting, between two columns of paper dots.
    const column = written.x + 18;
    const top = box.y + 120;
    const bottom = box.y + box.height - 40;
    const before = await inkRow(page, column, top, bottom);
    const inkWidth = (row: number) => inkLength(page, row, written.x - 300, written.x + 300);
    const length = await inkWidth(before);
    // The handwriting is `scrolled` px above its first row, at its first size.
    const shows = (scrolled: number, message: string) => expect(async () => {
      const row = await inkRow(page, column, top, bottom);
      expect(before - row, message).toBe(scrolled);
      expect(await inkWidth(row), message).toBe(length);
    }).toPass({ timeout: 5_000 });

    await page.mouse.move(box.x + box.width / 2, box.y + box.height / 2);
    await page.mouse.wheel(0, 200);
    await shows(200, "the wheel scrolls the page down");
    await page.mouse.wheel(0, -200);
    await shot("scrolled-back");
    await shows(0, "the wheel scrolls the page back up at the same zoom");

    // Ctrl and the wheel zoom the page about the pointer, here on the handwriting.
    await page.mouse.move(written.x, before);
    await page.keyboard.down("Control");
    await page.mouse.wheel(0, -100);
    await page.keyboard.up("Control");
    await shot("wheel-zoomed");
    await expect(async () => {
      expect(await inkWidth(await inkRow(page, column, top, bottom))).toBeGreaterThan(1.4 * length);
    }, "Ctrl and the wheel make the handwriting larger").toPass({ timeout: 5_000 });
  });

  await test.step("put five pages side by side in horizontal scroll and pan across them", async () => {
    await backToNotebook(page);
    box = await newNote(page, "Sideways");
    for (const count of [2, 3, 4, 5]) {
      await button("Add page").click();
      await button("At end").click();
      await expect(page.getByText(`1 / ${count}`, { exact: true })).toBeVisible();
    }
    await button("View").click();
    await button("Horizontal scroll").click();
    await expect(button("Library"), "the menu closes before the pen writes (TRAPS.md)").toBeVisible();
    const strokes = async () => (await savedPages(page, "Sideways")).map((saved) => saved.strokes);
    // A page fits the view height, so the view holds more than two A4 pages.
    const pageWidth = box.height * 595.28 / 841.89;
    const y = box.y + box.height / 2;
    await penStroke(cdp, line(box.x + 100, box.x + 200, y), 0.6);
    await penStroke(cdp, line(box.x + pageWidth + 100, box.x + pageWidth + 200, y), 0.6);
    expect(await strokes(), "the second page is beside the first").toEqual([1, 1, 0, 0, 0]);
    await shot("horizontal");
    const shown = await page.getByText(/^\d \/ 5$/).textContent();
    // One finger pans the pages to the left, to the end of the row.
    for (let pan = 0; pan < 2; ++pan) {
      await cdp.send("Input.dispatchTouchEvent", { type: "touchStart", touchPoints: [{ id: 1, x: 1100, y }] });
      for (const x of [1000, 800, 600, 400, 200]) {
        await cdp.send("Input.dispatchTouchEvent", { type: "touchMove", touchPoints: [{ id: 1, x, y }] });
      }
      await cdp.send("Input.dispatchTouchEvent", { type: "touchEnd", touchPoints: [] });
    }
    await expect(page.getByText(/^\d \/ 5$/), "the pan changes the shown page").not.toHaveText(shown!);
    // The pan overscrolls past the last page, and the bounce back takes a
    // moment; a pen-down beyond the page draws nothing.
    await settled(page, { x: box.x, y, width: box.width, height: 1 });
    await penStroke(cdp, line(box.x + box.width - 300, box.x + box.width - 200, y), 0.6);
    expect(await strokes(), "the last page is at the right edge after the pan").toEqual([1, 1, 0, 0, 1]);
    await shot("last-page");
    await button("View").click();
    await expect(page.getByRole("button", { name: /Fit height$/ })).toBeVisible();
    await closePopover(page);
  });

  await test.step("reload, find horizontal scroll kept, and go back to vertical scroll", async () => {
    await page.reload();
    await openTestNotebook(page);
    await page.getByRole("button", { name: "Open Sideways", exact: false }).click();
    await canvas.waitFor({ timeout: 30_000 });
    await button("View").click();
    await expect(page.getByRole("button", { name: /^\S+ Horizontal scroll$/ })).toHaveAttribute("aria-current", "true");
    await page.getByRole("button", { name: "Vertical scroll", exact: true }).click();
    await button("View").click();
    await expect(page.getByRole("button", { name: /^\S+ Vertical scroll$/ })).toHaveAttribute("aria-current", "true");
    await expect(page.getByRole("button", { name: /Fit width$/ })).toBeVisible();
    await closePopover(page);
  });

  await test.step("erase with the pen's side button and its eraser end, then draw with a finger", async () => {
    await backToNotebook(page);
    box = await newNote(page, "Fingers");
    const strokes = async () => (await savedPages(page, "Fingers"))[0].strokes;
    const buttonDrag = async (held: "left" | "right", from: [number, number], to: [number, number]) => {
      const pen = { pointerType: "pen" as const, force: 0.6, button: held, buttons: held === "left" ? 1 : 2 };
      await cdp.send("Input.dispatchMouseEvent", { type: "mousePressed", clickCount: 1, x: box.x + from[0], y: box.y + from[1], ...pen });
      await cdp.send("Input.dispatchMouseEvent", { type: "mouseMoved", x: box.x + (from[0] + to[0]) / 2, y: box.y + (from[1] + to[1]) / 2, ...pen });
      await cdp.send("Input.dispatchMouseEvent", { type: "mouseMoved", x: box.x + to[0], y: box.y + to[1], ...pen });
      await cdp.send("Input.dispatchMouseEvent", { type: "mouseReleased", clickCount: 1, x: box.x + to[0], y: box.y + to[1], ...pen, buttons: 0 });
    };
    await buttonDrag("left", [160, 150], [300, 150]);
    expect(await strokes()).toBe(1);
    await buttonDrag("right", [230, 100], [230, 200]);
    expect(await strokes()).toBe(0);
    // CDP has no button for the eraser end of a pen, so the page receives the
    // pointer events that the eraser end makes: button 5, buttons 32.
    await buttonDrag("left", [160, 150], [300, 150]);
    expect(await strokes()).toBe(1);
    await page.evaluate(async ({ x, y }) => {
      const send = async (type: string, clientY: number, button: number, buttons: number) => {
        document.elementFromPoint(x, clientY)!.dispatchEvent(new PointerEvent(type, {
          pointerId: 9, pointerType: "pen", isPrimary: true, bubbles: true, cancelable: true, composed: true,
          clientX: x, clientY, pressure: buttons ? 0.6 : 0, button, buttons,
        }));
        await new Promise((resolve) => setTimeout(resolve, 20));
      };
      await send("pointerdown", y + 100, 5, 32);
      for (const offset of [125, 150, 175, 200]) await send("pointermove", y + offset, -1, 32);
      await send("pointerup", y + 200, 5, 0);
    }, { x: box.x + 230, y: box.y });
    expect(await strokes(), "the eraser end of the pen erases").toBe(0);

    await button("More").click();
    await button("Settings").click();
    await page.getByRole("switch", { name: "Draw with finger", exact: true }).click();
    await button("Done").click();
    const finger = (id: number, x: number, y: number) => ({ id, x: box.x + x, y: box.y + y });
    await cdp.send("Input.dispatchTouchEvent", { type: "touchStart", touchPoints: [finger(1, 160, 250)] });
    for (const x of [200, 260, 320]) {
      await cdp.send("Input.dispatchTouchEvent", { type: "touchMove", touchPoints: [finger(1, x, 250)] });
    }
    await cdp.send("Input.dispatchTouchEvent", { type: "touchEnd", touchPoints: [] });
    expect(await strokes()).toBe(1);
    // A second finger turns the stroke in progress into a pan.
    await cdp.send("Input.dispatchTouchEvent", { type: "touchStart", touchPoints: [finger(1, 160, 350)] });
    await cdp.send("Input.dispatchTouchEvent", { type: "touchMove", touchPoints: [finger(1, 200, 350)] });
    await cdp.send("Input.dispatchTouchEvent", { type: "touchStart", touchPoints: [finger(1, 200, 350), finger(2, 260, 350)] });
    for (const y of [320, 290, 260]) {
      await cdp.send("Input.dispatchTouchEvent", { type: "touchMove", touchPoints: [finger(1, 200, y), finger(2, 260, y)] });
    }
    await cdp.send("Input.dispatchTouchEvent", { type: "touchEnd", touchPoints: [] });
    expect(await strokes()).toBe(1);
  });

  await test.step("write on the right page of a two-page spread and share it as a PDF", async () => {
    await backToNotebook(page);
    await newNote(page, "Spread");
    for (let added = 0; added < 2; added++) {
      await button("Add page").click();
      await button("At end").click();
    }
    await expect(page.getByText(/^\d \/ 3$/)).toBeVisible();
    await button("View").click();
    await button("Two pages").click();
    await page.waitForTimeout(500);
    const spread = await canvas.boundingBox();
    if (!spread) throw new Error("Notebook canvas has no bounds");
    box = spread;
    const pen = { pointerType: "pen" as const, force: 0.6, button: "left" as const };
    const x = box.x + box.width * 0.75;
    const y = box.y + 200;
    await cdp.send("Input.dispatchMouseEvent", { type: "mousePressed", clickCount: 1, x, y, ...pen, buttons: 1 });
    await cdp.send("Input.dispatchMouseEvent", { type: "mouseMoved", x: x + 40, y, ...pen, buttons: 1 });
    await cdp.send("Input.dispatchMouseEvent", { type: "mouseMoved", x: x + 80, y, ...pen, buttons: 1 });
    await cdp.send("Input.dispatchMouseEvent", { type: "mouseReleased", clickCount: 1, x: x + 80, y, ...pen, buttons: 0 });
    expect((await savedPages(page, "Spread")).map((saved) => saved.strokes)).toEqual([0, 1, 0]);

    await page.evaluate(() => {
      const shared: string[] = [];
      Object.assign(window, { shared });
      navigator.canShare = () => true;
      navigator.share = async (data) => {
        for (const file of data?.files ?? []) shared.push(`${file.name} ${file.type}`);
      };
    });
    await button("More").click();
    await button("Share").click();
    await button("Send to apps").click();
    await expect.poll(() => page.evaluate(() => (window as unknown as { shared: string[] }).shared)).toEqual([
      "Spread.pdf application/pdf",
    ]);
  });

  await test.step("reload, find two pages per row and finger drawing kept", async () => {
    await page.reload();
    await openTestNotebook(page);
    await page.getByRole("button", { name: "Open Spread", exact: false }).click();
    await canvas.waitFor({ timeout: 30_000 });
    await button("View").click();
    await expect(page.getByRole("button", { name: /^\S+ Two pages$/ })).toHaveAttribute("aria-current", "true");
    await closePopover(page);
    await button("More").click();
    await button("Settings").click();
    await expect(page.getByRole("switch", { name: "Draw with finger", exact: true })).toBeChecked();
  });
});
