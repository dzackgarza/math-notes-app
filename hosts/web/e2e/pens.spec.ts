import { expect, type Page } from "@playwright/test";
import { test, save, whenSaved, enterText, createTestNotebook, openTestNotebook, penStroke, line, capture, brightness, textIn, boxOf, darkestPixel, centerPixel, inkThickness, closePopover, openColors, backToColors, pickColor, pageIn, BOARD, COLORS, type Box, type Rgb } from "./support.ts";

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

// The pen and marker settings in the notes folder's .pens.json.
function storedPens(page: Page) {
  return whenSaved(() => page.evaluate(async () => {
    try {
      const root = await navigator.storage.getDirectory();
      const pens = JSON.parse(await (await (await root.getFileHandle(".pens.json")).getFile()).text());
      return { pen: pens.pen, marker: pens.marker };
    } catch (error) {
      if (error instanceof DOMException && error.name === "NotFoundError") return null;
      throw error;
    }
  }));
}

// A user sets up pens and colors: looks over the tool rail and hides a tool,
// sizes the marker, highlights handwriting, changes the pen's color and
// width between strokes, opens a saved page by itself, saves a pen, tries
// the pen popover's sizes, opacity, and the marker, and edits the palette.
// After a reload the hidden tool, the palette, and the saved pen remain.
test("Flutter pens session: tool rail, pen and marker popovers, highlighter, colors, saved pens, palette, and reload", async ({ page, context }, info) => {
  test.setTimeout(240_000);
  const button = (name: string) => page.getByRole("button", { name, exact: true });
  const shot = (name: string) => page.screenshot({ path: info.outputPath(`${name}.png`) });
  const canvas = page.locator('canvas[id^="ink-canvas-"]:visible');
  const penSize = async (label: string) => {
    await button("Pen").click();
    await button(label).click();
  };
  const plainPen = async () => {
    await pickColor(page, "#1a1a1a");
    await penSize("0.6 pt");
    await closePopover(page);
  };
  const savedPen = page.getByRole("button", { name: "Saved pen 3.6 pt #d92d39", exact: true });
  const swatches = page.getByRole("button", { name: /^Color #/ });
  const swatchColor = async (index: number) => {
    const bounds = await swatches.nth(index).boundingBox();
    if (!bounds) throw new Error("A swatch has no bounds");
    return centerPixel(page, { x: bounds.x + bounds.width / 2, y: bounds.y + bounds.height / 2 });
  };
  const near = (a: Rgb, b: Rgb) => a.every((channel, i) => Math.abs(channel - b[i]) < 30);

  await page.goto("?root=opfs");
  await createTestNotebook(page);
  let box = await newNote(page, "Chrome");
  const cdp = await context.newCDPSession(page);

  await test.step("look over the tool rail beside the page, and hide Insert space", async () => {
    // The rail is a leaf panel that floats over the desk at the left edge of
    // the canvas. Each tool and history control is in it, and at zoom 1 none
    // of them covers the page.
    const pen = await boxOf(button("Pen"));
    expect(pen.x - box.x, "the rail is at the left edge of the canvas").toBeLessThan(24);
    const controls = ["Pen", "Lasso", "Insert space", "Undo", "Redo"].map((name) => [name, button(name)] as const);
    for (const [name, locator] of [...controls, ["Colors", page.getByRole("button", { name: COLORS })] as const]) {
      const control = await boxOf(locator);
      expect(control.width, `${name} is a 44 px target`).toBeGreaterThanOrEqual(44);
      expect(control.height, `${name} is a whole 44 px target`).toBeGreaterThanOrEqual(44);
      expect(control.x + control.width, `${name} does not cover the page`).toBeLessThanOrEqual(pageIn(box).x);
    }
    // The whole rail fits the 720 px window without scrolling, 8 px between targets.
    const marker = await boxOf(button("Marker"));
    expect(marker.y - (pen.y + pen.height), "8 px between targets").toBeGreaterThanOrEqual(8);
    const colors = await page.getByRole("button", { name: COLORS }).boundingBox();
    if (!colors) throw new Error("Colors has no bounds");
    expect(colors.y + colors.height, "the rail fits the window").toBeLessThanOrEqual(box.y + box.height);
    expect(pen.y, "the rail starts below the top bar").toBeGreaterThanOrEqual(box.y);
    const rail = await centerPixel(page, { x: pen.x - 4, y: pen.y + pen.height / 2 });
    expect(rail, "the rail is leaf").toEqual([0xee, 0xf0, 0xea]);
    // The rail floats: the desk, darkened only by the rail's shadow, shows in
    // the 8 px insets to its left and above it, and to its right.
    for (const at of [{ x: box.x + 4, y: pen.y + pen.height / 2 }, { x: pen.x + pen.width / 2, y: box.y + 4 }, { x: pen.x + pen.width + 14, y: pen.y + pen.height / 2 }]) {
      expect(brightness(await centerPixel(page, at)), `the desk shows around the rail at ${at.x}, ${at.y}`).toBeGreaterThan(500);
    }
    // A hovered rail button shows a tint behind its icon.
    const tint = { x: marker.x + marker.width / 2, y: marker.y + 4 };
    const idle = brightness(await centerPixel(page, tint));
    await button("Marker").hover();
    await expect.poll(async () => brightness(await centerPixel(page, tint)), "a hovered rail button is tinted").toBeLessThan(idle - 10);
    await page.mouse.move(box.x + box.width / 2, box.y + box.height / 2);
    const library = await boxOf(button("Library"));
    const topBar = await centerPixel(page, { x: 300, y: library.y + library.height / 2 });
    expect(topBar, "the top bar is board").toEqual(BOARD);
    const firstRow = await centerPixel(page, { x: box.x + 100, y: box.y + 100 });
    expect(brightness(firstRow), "the first writing row of the page is clear").toBeGreaterThan(600);
    // The page is a sheet on the desk: a desk margin shows on each side.
    for (const at of [{ x: box.x + box.width - 4, y: box.y + 200 }, { x: box.x + 200, y: box.y + 4 }]) {
      const desk = await centerPixel(page, at);
      expect(desk.every((channel, i) => Math.abs(channel - BOARD[i]) < 6), `the desk shows at ${at.x}, ${at.y}: ${desk}`).toBe(true);
    }

    await button("More").click();
    await button("Settings").click();
    await page.getByRole("switch", { name: "Insert space", exact: true }).click();
    await button("Done").click();
    await expect(button("Insert space")).toHaveCount(0);
  });

  await test.step("size the marker in its popover", async () => {
    // The first tap selects the marker; a tap on the selected marker opens its settings.
    await button("Marker").click();
    await button("Marker").click();
    await button("3.6 pt").click();
    await shot("marker-popover");
    const viewport = page.viewportSize();
    if (!viewport) throw new Error("Page has no viewport");
    await page.mouse.click(viewport.width - 20, viewport.height - 20);
    // A read during the app's write of the file throws; the next read succeeds.
    await expect(async () => expect(await storedPens(page))
      .toMatchObject({ pen: { brush: "pressure-pen", size: 1.2 }, marker: { brush: "marker", size: 3.6 } })).toPass({ timeout: 15_000 });
  });

  await test.step("highlight a line of handwriting", async () => {
    await button("Pen").click();
    const y = box.y + 200;
    await penStroke(cdp, line(box.x + 140, box.x + 340, y), 0.6);
    const plainInk = await darkestPixel(page, { x: box.x + 180, y });
    const x = box.x + 280;
    const paper = await centerPixel(page, { x, y: y - 25 });

    await button("Highlighter").click();
    await penStroke(cdp, [{ x, y: y - 40 }, { x, y: y - 20 }, { x, y }, { x, y: y + 20 }, { x, y: y + 40 }], 0.6);
    await shot("highlighted");

    // The highlight tints the bare paper, and the handwriting it crosses keeps its own color.
    const highlight = await centerPixel(page, { x, y: y - 25 });
    expect(brightness(paper) - brightness(highlight)).toBeGreaterThan(30);
    const crossing = await darkestPixel(page, { x, y });
    for (const channel of [0, 1, 2]) expect(Math.abs(crossing[channel] - plainInk[channel])).toBeLessThan(24);
  });

  await test.step("in a new note, change the pen's width and color between two strokes", async () => {
    await backToNotebook(page);
    box = await newNote(page, "Pen settings");
    // The highlighter is selected; the first tap on the pen selects it.
    await button("Pen").click();
    const draw = async (y: number) => {
      const pen = { pointerType: "pen" as const, force: 0.6, tiltX: 20, tiltY: -10 };
      await cdp.send("Input.dispatchMouseEvent", {
        type: "mousePressed", button: "left", clickCount: 1, x: box.x + 140, y, ...pen,
      });
      await cdp.send("Input.dispatchMouseEvent", {
        type: "mouseMoved", button: "left", buttons: 1, x: box.x + 240, y, ...pen,
      });
      await cdp.send("Input.dispatchMouseEvent", {
        type: "mouseReleased", button: "left", clickCount: 1, x: box.x + 240, y, ...pen,
      });
    };

    await draw(box.y + 180);
    await button("Pen").click();
    await button("3.6 pt").click();
    const viewport = page.viewportSize();
    if (!viewport) throw new Error("Page has no viewport");
    await page.mouse.click(viewport.width - 20, viewport.height - 20);
    await pickColor(page, "#d92d39");
    await expect.poll(async () => {
      const pens = await storedPens(page);
      return pens && { size: pens.pen.size, color: pens.pen.color };
    }).toEqual({ size: 3.6, color: "#D92D39" });

    await draw(box.y + 260);
    await save(page);
    await expect(page.getByRole("status", { name: /^Notebook save/ })).toHaveAccessibleName("Notebook save Saved");
    const strokes = await whenSaved(() => page.evaluate(async () => {
      const root = await navigator.storage.getDirectory();
      const notebook = await root.getDirectoryHandle("Test Notebook");
      const pages = await (await notebook.getDirectoryHandle("Pen settings")).getDirectoryHandle("pages");
      const svg = await (await (await pages.getFileHandle("0001.svg")).getFile()).text();
      const doc = new DOMParser().parseFromString(svg, "image/svg+xml");
      return [...doc.querySelectorAll('path[id^="s-"]')].map((path) => ({
        fill: path.getAttribute("fill"),
        size: Number(path.getAttribute("mn:size")),
      }));
    }));
    expect(strokes).toEqual([
      { fill: "#1A1A1A", size: 1.2 },
      { fill: "#D92D39", size: 3.6 },
    ]);
  });

  await test.step("open the saved page SVG directly in Chrome", async () => {
    const saved = await whenSaved(() => page.evaluate(async () => {
      const root = await navigator.storage.getDirectory();
      const notebook = await root.getDirectoryHandle("Test Notebook");
      const pages = await (await notebook.getDirectoryHandle("Pen settings")).getDirectoryHandle("pages");
      const file = await (await pages.getFileHandle("0001.svg")).getFile();
      const svg = await file.text();
      const doc = new DOMParser().parseFromString(svg, "image/svg+xml");
      const stroke = doc.querySelector('path[id^="s-"]');
      if (!stroke) throw new Error("Saved page has no stroke");
      return {
        url: URL.createObjectURL(file),
        type: file.type,
        stroke: {
          d: stroke.getAttribute("d"),
          fill: stroke.getAttribute("fill"),
          size: stroke.getAttribute("mn:size"),
        },
      };
    }));
    expect(saved.type).toBe("image/svg+xml");

    const standalone = await context.newPage();
    await standalone.goto(saved.url);
    const direct = await standalone.locator('path[id^="s-"]').first().evaluate((stroke) => ({
      d: stroke.getAttribute("d"),
      fill: stroke.getAttribute("fill"),
      size: stroke.getAttribute("mn:size"),
    }));
    expect(direct).toEqual(saved.stroke);
    await standalone.close();
  });

  // The saved pen's strokes, beside the strokes of the last step.
  const write = (y: number) => penStroke(cdp, line(box.x + 440, box.x + 640, y), 0.6);
  const plain = { dx: 540, dy: 180 };
  const shortcut = { dx: 540, dy: 260 };
  const reloaded = { dx: 540, dy: 340 };

  await test.step("save the red 3.6 pt pen in the color menu and write with it", async () => {
    // The pen is already red at 3.6 pt.
    await penSize("3.6 pt");
    await button("Save pen").click();
    await closePopover(page);
    await openColors(page);
    await expect(savedPen).toBeVisible();
    await closePopover(page);
    await plainPen();
    await write(box.y + plain.dy);
    await openColors(page);
    await savedPen.click();
    // The pen waits for the popover to close (TRAPS.md).
    await expect(button("Library")).toBeVisible();
    await write(box.y + shortcut.dy);
    await plainPen();
  });

  await test.step("in a new note, try the pen popover's sizes and opacity, and the marker", async () => {
    await backToNotebook(page);
    box = await newNote(page, "Tool popover");
    const tool = (name: string) => button(name);
    const sample = page.getByRole("img", { name: "Stroke sample", exact: true });
    const sampleInk = async () => {
      const bounds = await sample.boundingBox();
      if (!bounds) throw new Error("The stroke sample has no bounds");
      return (await capture(page, bounds)).filter((rgb) => brightness(rgb) < 600).length;
    };
    const at = (y: number) => ({ x: box.x + 240, y: box.y + y });
    const popoverWrite = (y: number, force = 0.6) => penStroke(cdp, line(box.x + 140, box.x + 340, box.y + y), force);

    // The pen is selected, so a tap on it opens its popover.
    await tool("Pen").click();
    expect((await textIn(page, await boxOf(page.getByText("Size", { exact: true })))).contrast, "the Size heading is legible").toBeGreaterThan(4.5);
    await tool("0.6 pt").click();
    const thinSample = await sampleInk();
    await tool("3.6 pt").click();
    await expect.poll(sampleInk, { message: "the stroke sample follows the size" }).toBeGreaterThan(2.5 * thinSample);
    await tool("0.6 pt").click();
    await closePopover(page);
    await popoverWrite(160);
    await tool("Pen").click();
    await tool("3.6 pt").click();
    await closePopover(page);
    await popoverWrite(220);

    await tool("Pen").click();
    await tool("Advanced").click();
    // Flutter web puts a slider's label on its semantics host, not on the
    // range input that has the slider role (TRAPS.md).
    const opacity = page.getByLabel("Opacity", { exact: true });
    const track = await boxOf(opacity);
    // A Cupertino slider moves by a drag of its thumb, here at 100%.
    const middle = track.y + track.height / 2;
    await page.mouse.move(track.x + track.width - 14, middle);
    await page.mouse.down();
    await page.mouse.move(track.x, middle, { steps: 10 });
    await page.mouse.up();
    await expect(page.getByText("10%", { exact: true })).toBeVisible();
    await closePopover(page);
    await popoverWrite(280);

    // The marker keeps a constant width under light and hard pressure.
    await tool("Marker").click();
    await popoverWrite(340, 0.15);
    await popoverWrite(400, 1);
    await shot("tool-popover");

    const thin = await inkThickness(page, at(160));
    expect(await inkThickness(page, at(220)), "the 3.6 pt preset writes thicker").toBeGreaterThan(2.5 * thin);
    const solid = brightness(await darkestPixel(page, at(220)));
    const faint = brightness(await darkestPixel(page, at(280)));
    expect(faint - solid, "10% opacity writes faint ink").toBeGreaterThan(300);
    expect(await inkThickness(page, at(340)), "the marker ignores pressure").toBe(await inkThickness(page, at(400)));
  });

  await test.step("set the pen's opacity back to 100%", async () => {
    // The marker is selected; the first tap selects the pen, the second opens it.
    await button("Pen").click();
    await button("Pen").click();
    await button("Advanced").click();
    const track = await boxOf(page.getByLabel("Opacity", { exact: true }));
    const middle = track.y + track.height / 2;
    await page.mouse.move(track.x + 14, middle);
    await page.mouse.down();
    await page.mouse.move(track.x + track.width, middle, { steps: 10 });
    await page.mouse.up();
    await expect(page.getByText("100%", { exact: true })).toBeVisible();
    await closePopover(page);
  });

  let edited: Rgb = [0, 0, 0];
  let added: Rgb = [0, 0, 0];
  await test.step("edit a swatch on the HSV wheel, and add and remove swatches", async () => {
    // A short drag at an offset from the wheel's center: the hue ring is the outer
    // 20 px of the 228 px wheel, and the saturation and value square is inside it.
    const wheelDrag = async (dx: number, dy: number) => {
      const bounds = await page.getByRole("img", { name: "Color wheel", exact: true }).boundingBox();
      if (!bounds) throw new Error("The color wheel has no bounds");
      const x = bounds.x + bounds.width / 2 + dx;
      const y = bounds.y + bounds.height / 2 + dy;
      await page.mouse.move(x, y);
      await page.mouse.down();
      await page.mouse.move(x + 3, y + 3, { steps: 3 });
      await page.mouse.up();
    };
    const saturation = (rgb: Rgb) => Math.max(...rgb) - Math.min(...rgb);

    await button("Pen").click();
    await button("3.6 pt").click();
    await closePopover(page);
    // A tap on the pen's current swatch opens the wheel for that swatch.
    await openColors(page);
    await swatches.first().click();
    await wheelDrag(45, -45);
    await wheelDrag(0, 104);
    await backToColors(page);
    edited = await swatchColor(0);
    await closePopover(page);
    expect(saturation(edited), "the wheel makes the gray swatch a saturated color").toBeGreaterThan(100);
    const stroke = { x: box.x + 540, y: box.y + 200 };
    await penStroke(cdp, line(box.x + 440, box.x + 640, stroke.y), 0.6);
    const ink = await darkestPixel(page, stroke);
    expect(near(ink, edited), `the pen writes the swatch color: ink ${ink}, swatch ${edited}`).toBe(true);

    await openColors(page);
    await button("Edit colors").click();
    await button("Remove color #ffcf26").click();
    await wheelDrag(0, -104);
    await button("Add color").click();
    await backToColors(page);
    await expect(button("Color #ffcf26")).toHaveCount(0);
    await expect(swatches).toHaveCount(5);
    added = await swatchColor(4);
    expect(saturation(added), "the added swatch is a saturated color").toBeGreaterThan(100);
    expect(near(added, edited), "the added swatch differs from the edited one").toBe(false);
    await closePopover(page);

    // A thin blue pen, so the saved pen must bring back its own color and width.
    await pickColor(page, "#1f4fb5");
    await penSize("0.6 pt");
    await closePopover(page);
  });

  await test.step("reload: the hidden tool, the palette, and the saved pen remain", async () => {
    await page.reload();
    await openTestNotebook(page);
    await page.getByRole("button", { name: "Open Pen settings", exact: false }).click();
    await canvas.waitFor({ timeout: 30_000 });
    const reopened = await canvas.boundingBox();
    if (!reopened) throw new Error("Notebook canvas has no bounds");
    box = reopened;
    await shot("chrome");
    await expect(button("Insert space")).toHaveCount(0);

    await openColors(page);
    await shot("palette");
    await expect(swatches).toHaveCount(5);
    expect(near(await swatchColor(0), edited), "the edited swatch persists").toBe(true);
    expect(near(await swatchColor(4), added), "the added swatch persists").toBe(true);
    await savedPen.click();
    // The pen waits for the popover to close (TRAPS.md).
    await expect(button("Library")).toBeVisible();
    await write(box.y + reloaded.dy);
    await shot("saved-pens");

    // The saved pen writes thick red strokes; the plain pen a thin gray one.
    const spot = ({ dx, dy }: { dx: number; dy: number }) => ({ x: box.x + dx, y: box.y + dy });
    const thin = await inkThickness(page, spot(plain));
    const dark = await darkestPixel(page, spot(plain));
    expect(Math.max(...dark) - Math.min(...dark), "the plain stroke is gray, not red").toBeLessThan(30);
    expect(brightness(dark), "the plain stroke is dark").toBeLessThan(450);
    for (const at of [shortcut, reloaded]) {
      const [red, green, blue] = await darkestPixel(page, spot(at));
      expect(red - Math.max(green, blue), "the saved pen stroke is red").toBeGreaterThan(100);
      expect(await inkThickness(page, spot(at)), "the saved pen stroke is thick").toBeGreaterThan(2.5 * thin);
    }
  });
});
