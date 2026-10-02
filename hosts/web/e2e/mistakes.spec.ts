import { expect, type CDPSession, type Page } from "@playwright/test";
import { test, enterText, createTestNotebook, whenSaved, penStroke, line, capture, screenPixels, isInk, inkAt, pageIn, boxOf, closePopover, savedPages, penHold, penRelease, sharpestStep, type Box, type Rgb } from "./support.ts";

// The stroke count of the first page of a note, from the files that the
// app saves on its own, or -1 before the page file exists.
function autosavedStrokes(page: Page, notebook: string, title: string): Promise<number> {
  return whenSaved(() => page.evaluate(async ({ notebook, title }) => {
    try {
      const root = await navigator.storage.getDirectory();
      const pages = await (await (await root.getDirectoryHandle(notebook)).getDirectoryHandle(title)).getDirectoryHandle("pages");
      const svg = await (await (await pages.getFileHandle("0001.svg")).getFile()).text();
      return svg.match(/<path id="s-/g)?.length ?? 0;
    } catch (error) {
      if (error instanceof DOMException && error.name === "NotFoundError") return -1;
      throw error;
    }
  }, { notebook, title }));
}

// Two or three fingers tap the page together.
async function fingerTap(cdp: CDPSession, box: Box, fingers: number): Promise<void> {
  const touchPoints = Array.from({ length: fingers }, (_, id) => ({ id, x: box.x + 400 + 60 * id, y: box.y + 300 }));
  await cdp.send("Input.dispatchTouchEvent", { type: "touchStart", touchPoints });
  await cdp.send("Input.dispatchTouchEvent", { type: "touchEnd", touchPoints: [] });
}

// A student works a problem set and recovers from each kind of slip: a
// stroke started while a dialog is open, a stroke the browser cancels, finger
// taps that undo and redo, erases taken back, a run of strokes rewound with
// Ctrl+Z and the undo dial, and a ruled erase on a plain sheet. On that
// sheet, filled with lines, every menu, alert, action sheet, and sheet blurs
// the handwriting behind it.
test("Flutter mistakes session: blocked and cancelled strokes, finger-tap undo, erase history, the undo dial, a ruled erase on plain paper, and blurred surfaces", async ({ page }, info) => {
  test.setTimeout(300_000);
  const button = (name: string) => page.getByRole("button", { name, exact: true });
  const notebook = "Problem set";
  const scratch = "Scratch work";
  const plain = "Ruled plain";

  await page.goto("?root=opfs");
  await createTestNotebook(page, notebook);
  await button("New note").click();
  await enterText(page.getByRole("textbox", { name: "Title", exact: true }), scratch);
  await button("Create").click();
  const canvas = page.locator('canvas[id^="ink-canvas-"]:visible');
  await canvas.waitFor({ timeout: 30_000 });
  const box = await boxOf(canvas);
  const cdp = await page.context().newCDPSession(page);
  const strokes = async () => (await savedPages(page, scratch, notebook))[0].strokes;

  await test.step("a stroke under the Go to page alert and a stroke the browser cancels leave no ink", async () => {
    await button("Pages").click();
    await button("Go to page").click();
    await expect(page.getByText("Go to page", { exact: true })).toBeVisible();
    const pen = { pointerType: "pen" as const, force: 0.6, tiltX: 20, tiltY: -10 };
    await cdp.send("Input.dispatchMouseEvent", {
      type: "mousePressed", button: "left", clickCount: 1,
      x: box.x + 150, y: box.y + 180, ...pen,
    });
    await cdp.send("Input.dispatchMouseEvent", {
      type: "mouseMoved", button: "left", buttons: 1,
      x: box.x + 250, y: box.y + 220, ...pen,
    });
    await cdp.send("Input.dispatchMouseEvent", {
      type: "mouseReleased", button: "left", clickCount: 1,
      x: box.x + 250, y: box.y + 220, ...pen,
    });
    await button("Cancel").click();
    expect(await strokes(), "the dialog blocks the ink").toBe(0);

    // The browser cancels a pen stroke (a palm gesture, a lost pen): the page
    // receives pointercancel, as CDP cannot send it.
    await page.evaluate(async ({ x, y }) => {
      const send = async (type: string, clientX: number, buttons: number) => {
        document.elementFromPoint(clientX, y)!.dispatchEvent(new PointerEvent(type, {
          pointerId: 7, pointerType: "pen", isPrimary: true, bubbles: true, cancelable: true, composed: true,
          clientX, clientY: y, pressure: buttons ? 0.6 : 0, button: buttons ? 0 : -1, buttons,
        }));
        await new Promise((resolve) => setTimeout(resolve, 20));
      };
      await send("pointerdown", x, 1);
      for (const offset of [40, 80, 120, 160]) await send("pointermove", x + offset, 1);
      await send("pointercancel", x + 160, 0);
    }, { x: box.x + 150, y: box.y + 300 });
    expect(await strokes(), "the cancelled stroke leaves no ink").toBe(0);
    await penStroke(cdp, line(box.x + 150, box.x + 310, box.y + 360, 4), 0.6);
    expect(await strokes(), "the next stroke draws").toBe(1);
  });

  await test.step("a two-finger tap undoes the stroke and a three-finger tap redoes it", async () => {
    await fingerTap(cdp, box, 2);
    expect(await strokes()).toBe(0);
    await fingerTap(cdp, box, 3);
    expect(await strokes()).toBe(1);
  });

  await test.step("a partial erase and a whole-stroke erase each undo and redo", async () => {
    // The stroke from the first step stays on the page: each count is one more.
    const expectStrokes = async (count: number) => {
      await expect.poll(() => autosavedStrokes(page, notebook, scratch), { timeout: 8_000 }).toBe(count);
    };
    const drag = (from: [number, number], to: [number, number]) => penStroke(cdp, [
      { x: box.x + from[0], y: box.y + from[1] },
      { x: box.x + (from[0] + to[0]) / 2, y: box.y + (from[1] + to[1]) / 2 },
      { x: box.x + to[0], y: box.y + to[1] },
    ], 0.6);

    await drag([150, 480], [350, 480]);
    await expectStrokes(2);
    await button("Eraser").click();
    await button("Eraser").click();
    await button("Partial").click();
    await closePopover(page);
    await drag([250, 430], [250, 530]);
    await expectStrokes(3);
    await button("Undo").click();
    await expectStrokes(2);
    await button("Redo").click();
    await expectStrokes(3);
    await button("Undo").click();
    await expectStrokes(2);

    await button("Eraser").click();
    await button("Stroke").click();
    await closePopover(page);
    await drag([250, 430], [250, 530]);
    await expectStrokes(1);
    await button("Undo").click();
    await expectStrokes(2);
    await button("Redo").click();
    await expectStrokes(1);
  });

  await test.step("three lines are rewound with Ctrl+Z and the undo dial", async () => {
    await button("Pen").click();
    const spots = [180, 260, 340].map((dy) => ({ x: box.x + 620, y: box.y + dy }));
    const paper: Rgb[][] = [];
    for (const spot of spots) paper.push(await screenPixels(page, spot));
    const ink: number[] = [];
    for (const [i, spot] of spots.entries()) {
      await penStroke(cdp, line(spot.x - 40, spot.x + 40, spot.y), 0.6);
      ink.push(await inkAt(page, spot, paper[i]));
    }
    // Which of the three lines of handwriting show: each is whole or gone.
    const shown = async () => {
      const lines = [];
      for (const [i, spot] of spots.entries()) {
        const now = await inkAt(page, spot, paper[i]);
        expect(now < 0.1 * ink[i] || now > 0.8 * ink[i], `ink ${now} of ${ink[i]}`).toBe(true);
        lines.push(now > 0.8 * ink[i]);
      }
      return lines;
    };
    // A frame shows each undo or redo after the input that caused it.
    const showsLines = (lines: boolean[]) =>
      expect(async () => expect(await shown()).toEqual(lines)).toPass({ timeout: 5_000 });
    await showsLines([true, true, true]);

    await page.keyboard.press("Control+z");
    await showsLines([true, true, false]);
    await page.keyboard.press("Control+Shift+z");
    await showsLines([true, true, true]);

    // A drag from the undo button turns the dial to the right of it, over the
    // page (undo_dial.dart): each 1/32 turn counterclockwise undoes a step,
    // clockwise redoes one.
    const undo = await boxOf(button("Undo"));
    const start = { x: undo.x + undo.width / 2, y: undo.y + undo.height / 2 };
    const center = { x: undo.x + 1.3 * undo.width + 2.5 * undo.height, y: start.y };
    const radius = center.x - start.x;
    const at = (degrees: number) => {
      const angle = Math.PI + (degrees * Math.PI) / 180;
      return { x: center.x + radius * Math.cos(angle), y: center.y + radius * Math.sin(angle) };
    };
    await page.mouse.move(start.x, start.y);
    await page.mouse.down();
    for (let degrees = -4; degrees >= -28; degrees -= 4) await page.mouse.move(at(degrees).x, at(degrees).y);
    await page.screenshot({ path: info.outputPath("dial-rewound.png") });
    await showsLines([true, false, false]);
    for (let degrees = -24; degrees <= -8; degrees += 4) await page.mouse.move(at(degrees).x, at(degrees).y);
    await page.mouse.up();
    await showsLines([true, true, false]);
  });

  await test.step("on a new plain sheet, the ruled eraser takes one word and keeps the paper plain", async () => {
    await button("Library").click();
    await expect(page.getByRole("heading", { name: notebook, exact: true })).toBeVisible();
    await button("New note").click();
    await enterText(page.getByRole("textbox", { name: "Title", exact: true }), plain);
    await button("Plain").click();
    await button("Create").click();
    await expect(page.getByRole("heading", { name: plain, exact: true })).toBeVisible();
    await canvas.waitFor({ timeout: 30_000 });
    // Two words on one row and a word four rows of Write's blank-page lines lower.
    const spots = [{ x: box.x + 235, y: box.y + 200 }, { x: box.x + 395, y: box.y + 200 }, { x: box.x + 235, y: box.y + 320 }];
    const paper: Rgb[][] = [];
    for (const spot of spots) paper.push(await screenPixels(page, spot));
    const ink: number[] = [];
    for (const [i, spot] of spots.entries()) {
      await penStroke(cdp, Array.from({ length: 8 }, (_, k) => ({ x: spot.x - 35 + 10 * k, y: spot.y + (k % 2 ? 3 : -3) })), 0.6);
      ink.push(await inkAt(page, spot, paper[i]));
    }
    const shown = () => Promise.all(spots.map(async (spot, i) => (await inkAt(page, spot, paper[i])) > 0.8 * ink[i]));
    await button("Eraser").click();
    await button("Eraser").click();
    await button("Ruled").click();
    await closePopover(page);

    const from = { x: spots[0].x - 50, y: spots[0].y };
    const to = { x: spots[0].x + 50, y: spots[0].y };
    await penHold(cdp, from, to);
    await expect.poll(shown, "the word under the held eraser is hidden").toEqual([false, true, true]);
    await penRelease(cdp, to);
    const saved = async () => (await savedPages(page, plain, notebook)).map(({ strokes, ruling }) => ({ strokes, ruling }));
    await expect.poll(saved).toEqual([{ strokes: 2, ruling: "blank" }]);
  });

  await test.step("the sheet fills with lines, and each menu, alert, action sheet, and sheet blurs them", async () => {
    await button("Pen").click();
    // Lines 9 px apart: each surface has several of them behind it.
    for (let y = box.y + 90; y < box.y + box.height - 10; y += 9) {
      await penStroke(cdp, line(pageIn(box).x + 30, pageIn(box).x + pageIn(box).width - 30, y, 2), 0.8);
    }
    expect(await sharpestStep(page, box.x + 200, box.y + 200, box.y + 240), "the lines are sharp on the page").toBeGreaterThan(300);
    // A column of a surface with no text and no divider, across three lines or
    // more. Sharp lines behind the surfaces give steps of 21 to 65.
    const blurred = (x: number, top: number, bottom: number, surface: string) =>
      expect.poll(() => sharpestStep(page, x, top, bottom), `${surface} blurs the lines behind it`).toBeLessThan(8);

    await button("Pages").click();
    const item = await boxOf(button("Go to page"));
    await blurred(item.x + 0.7 * item.width, item.y + 4, item.y + item.height - 4, "the menu");

    await button("Go to page").click();
    // The closing menu still holds a "Go to page" label.
    const title = await boxOf(page.getByRole("alertdialog").getByText("Go to page", { exact: true }));
    await blurred(title.x - 10, title.y - 6, title.y + title.height + 6, "the alert");
    await blurred(box.x + 120, title.y - 20, title.y + 40, "the scrim beside the alert");
    expect(await capture(page, { x: title.x - 10, y: title.y + title.height / 2, width: 1, height: 1 }), "the alert is leaf").toEqual([[0xee, 0xf0, 0xea]]);
    await page.screenshot({ path: info.outputPath("alert.png") });
    await button("Cancel").click();

    await button("Pages").click();
    await button("Paper for new pages").click();
    const action = await boxOf(button("Grid paper"));
    await blurred(action.x + 0.6 * action.width, action.y + 4, action.y + action.height - 4, "the action sheet");
    const heading = await boxOf(page.getByText("Paper for new pages", { exact: true }));
    expect(await capture(page, { x: heading.x - 10, y: heading.y + heading.height / 2, width: 1, height: 1 }), "the action sheet is leaf").toEqual([[0xee, 0xf0, 0xea]]);
    await button("Done").click();

    await button("Open navigation").click();
    await page.getByText("Layers", { exact: true }).click();
    await button("Edit Ink").click();
    // The empty list below the last control of the only layer row.
    const last = await boxOf(button("Delete Ink"));
    await blurred(last.x + 10, last.y + last.height + 20, last.y + last.height + 60, "the layers sheet");
    // The page beside the sheet shows a change that the sheet makes.
    const lines = async () => (await capture(page, { x: pageIn(box).x + 100, y: box.y + 200, width: 1, height: 40 })).some(isInk);
    expect(await lines(), "the lines show beside the sheet").toBe(true);
    await button("Hide Ink").click();
    await expect.poll(lines, "the lines of the hidden layer show no more beside the sheet").toBe(false);
    await button("Done").click();
    await expect(button("Done")).toHaveCount(0);
    expect(await lines(), "the layer stays hidden on the page").toBe(false);
  });
});
