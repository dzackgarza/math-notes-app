import fc from "fast-check";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { join } from "node:path";
import type { Locator, Page } from "@playwright/test";
import { test, expect } from "./native-desktop.ts";
import { boxOf, capture, closePopover, enterText, line, openColors, penStroke, save } from "./workflow-actions.ts";
import { storedPages } from "./workflow-files.ts";

test.use({ trace: "on" });

// fast-check owns data generation, replay and shrinking. These inputs drive
// production controls; the observations are pixels and files outside the app.
const editing = fc.record({
  colorIndex: fc.nat({ max: 20 }),
  widthIndex: fc.nat({ max: 20 }),
  pressure: fc.integer({ min: 2, max: 8 }),
  x: fc.integer({ min: 180, max: 360 }),
  dy: fc.integer({ min: 0, max: 5 }),
  length: fc.integer({ min: 60, max: 140 }),
  history: fc.constantFrom("retain", "undo-redo", "branch"),
});

type PenSetting = { color: string; width: number };

// Flutter can expose a button's name through semantic text descendants.
// Read Playwright's computed accessibility tree, not one possible HTML
// encoding such as aria-label. These public setting names contain no quotes.
async function buttonName(button: Locator): Promise<string> {
  const snapshot = await button.ariaSnapshot();
  const name = /^- '?button "([^"]+)"/m.exec(snapshot);
  expect(name, `setting button has an accessible name: ${snapshot}`).not.toBeNull();
  return name![1];
}

// Read the authored file, then let the browser's SVG renderer measure its
// outline in document points. No Math Notes decoder or pen state is used.
async function checkInk(page: Page, svg: string, settings: PenSetting[]) {
  const strokes = await page.evaluate(source => {
    const parsed = new DOMParser().parseFromString(source, "image/svg+xml");
    if (parsed.querySelector("parsererror")) throw new Error("Invalid authored SVG");
    const image = document.importNode(parsed.documentElement, true);
    image.setAttribute("style", "position:fixed;left:-10000px;top:0;visibility:hidden;pointer-events:none");
    document.body.append(image);
    try {
      return Array.from(image.querySelectorAll<SVGPathElement>('path[id^="s-"]'), path => ({
        color: path.getAttribute("fill")?.toLowerCase(),
        width: Number(path.getAttribute("mn:size")),
        brush: path.getAttribute("mn:brush"),
        thickness: path.getBBox().height,
      }));
    } finally {
      image.remove();
    }
  }, svg);
  expect(strokes).toHaveLength(settings.length);
  for (const [index, setting] of settings.entries()) {
    const stroke = strokes[index];
    expect(stroke.color, `stroke ${index + 1} uses the chosen color`).toBe(setting.color);
    expect(stroke.width, `stroke ${index + 1} records the chosen size`).toBe(setting.width);
    expect(stroke.brush).toBe("pressure-pen");
    // PressurePen V1: a horizontal line has no direction or lateral-
    // acceleration enlargement, and pressure <= .8 has multiplier 1.
    // Measure the full outline: only the final three brush sizes taper.
    // https://github.com/google/ink/blob/1b220eee5a05e9b67be9f20f49ae2d574c8667a7/ink/brush/stock_brushes.cc#L91-L169
    // Two edges each allow the 0.01 pt mesh epsilon and 0.001 pt SVG rounding.
    expect(Math.abs(stroke.thickness - setting.width), `stroke ${index + 1} has the chosen physical thickness`).toBeLessThanOrEqual(0.022);
  }
}

test("fresh generated pen settings and history branches survive real folder restart", async ({ desktop }, info) => {
  test.setTimeout(1_200_000);
  let attempt = 0;
  const parameters = {
    numRuns: Number(process.env.FC_RUNS ?? 1),
    verbose: 2 as const,
    ...(process.env.FC_SEED === undefined ? {} : { seed: Number(process.env.FC_SEED) }),
    ...(process.env.FC_PATH === undefined ? {} : { path: process.env.FC_PATH }),
  };
  const result = await fc.check(fc.asyncProperty(fc.array(editing, { minLength: 12, maxLength: 24 }), async actions => {
    const id = attempt++;
    const root = info.outputPath(`attempt-${id}`, "notes");
    await mkdir(root, { recursive: true });
    let page = id === 0 ? desktop.page : await desktop.freshProfile();
    const button = (name: string) => page.getByRole("button", { name, exact: true });
    const observations: { action: unknown; surface: string; result?: string }[] = [];
    const discover = async (action: unknown, result?: string) => {
      observations.push({ action, surface: await page.locator("body").ariaSnapshot(), result });
      await writeFile(info.outputPath(`attempt-${id}`, "actions.json"), JSON.stringify(observations, null, 2));
    };
    try {
      await desktop.chooseFolder(root);
      await button("New notebook").click();
      await enterText(page.getByRole("textbox", { name: "Notebook title", exact: true }), "Exploration");
      await button("Create").click();
      await button("New note").click();
      await enterText(page.getByRole("textbox", { name: "Title", exact: true }), "Working calculation");
      await button("Plain").click();
      await button("A4").click();
      await button("Create").click();
      let canvas = page.locator('canvas[id^="ink-canvas-"]:visible');
      await canvas.waitFor();
      const box = await boxOf(canvas);
      const region = { x: box.x + 140, y: box.y + 100, width: 460, height: 420 };
      const cdp = await page.context().newCDPSession(page);
      const settings: PenSetting[] = [];
      const persisted = async () => {
        await save(page);
        await expect(page.getByRole("status", { name: /^Notebook save/ })).toHaveAccessibleName("Notebook save Saved", { timeout: 30_000 });
        return readFile(join(root, "Exploration", "Working calculation", "pages", "0001.svg"), "utf8");
      };
      await discover("created note");
      for (const [index, action] of actions.entries()) {
        await discover({ attempted: action });
        await button("Pen").click();
        const widths = page.getByRole("button", { name: /^\d+(\.\d+)? pt$/ });
        await expect(widths.first()).toBeVisible();
        const widthCount = await widths.count();
        expect(widthCount).toBeGreaterThanOrEqual(2);
        // Every generated run must distinguish fixed-width implementations,
        // including when fast-check shrinks all generated indices to zero.
        const width = widths.nth(index === 0 ? 0 : index === 1 ? widthCount - 1 : action.widthIndex % widthCount);
        const widthName = await buttonName(width);
        expect(widthName).toMatch(/^\d+(\.\d+)? pt$/);
        const expectedWidth = Number(widthName.split(" ")[0]);
        await width.click();
        await closePopover(page);
        const currentColor = await buttonName(page.getByRole("button", { name: /^Colors #[0-9a-f]{6}$/ }));
        expect(currentColor).toMatch(/^Colors #[0-9a-f]{6}$/);
        await openColors(page);
        const colors = page.getByRole("button", { name: /^Color #[0-9a-f]{6}$/ });
        await expect(colors.first()).toBeVisible();
        const names = await Promise.all((await colors.all()).map(buttonName));
        expect(names.length).toBeGreaterThanOrEqual(2);
        for (const name of names) expect(name).toMatch(/^Color #[0-9a-f]{6}$/);
        // Clicking the current swatch edits it. Choose another public swatch,
        // also guaranteeing that a fixed color cannot pass this workflow.
        const choices = names.filter(name => name !== currentColor.replace("Colors ", "Color "));
        const chosenColor = choices[action.colorIndex % choices.length]!;
        const setting = { color: chosenColor.split(" ")[1], width: expectedWidth };
        await discover({ chosenWidthAndColor: setting });
        await button(chosenColor).click();
        await expect(button("Library")).toBeVisible();
        const before = await persisted();
        const pixels = await capture(page, region);
        const y = box.y + 125 + index * 14 + action.dy;
        await penStroke(cdp, line(box.x + action.x, box.x + action.x + action.length, y), action.pressure / 10);
        await expect.poll(() => capture(page, region)).not.toEqual(pixels);
        const drawn = await persisted();
        await checkInk(page, drawn, [...settings, setting]);
        if (action.history !== "retain") {
          await button("Undo").click();
          expect(await persisted(), "undo restores the actual previous SVG").toBe(before);
          await checkInk(page, before, settings);
          if (action.history === "undo-redo") {
            await button("Redo").click();
            expect(await persisted(), "redo restores the completed stroke").toBe(drawn);
            await checkInk(page, drawn, [...settings, setting]);
          } else {
            await penStroke(cdp, line(box.x + action.x + 20, box.x + action.x + action.length + 20, y), action.pressure / 10);
            const branched = await persisted();
            expect(branched, "the new history branch retains different ink").not.toBe(drawn);
            await checkInk(page, branched, [...settings, setting]);
            await button("Redo").click();
            expect(await persisted(), "redo cannot revive the discarded history branch").toBe(branched);
            await checkInk(page, branched, [...settings, setting]);
          }
        }
        settings.push(setting);
        await discover({ executed: action }, `stroke ${index + 1} persisted`);
      }
      const original = await persisted();
      await writeFile(info.outputPath(`attempt-${id}`, "before-restart.svg"), original);
      const visible = await capture(page, region);
      await page.screenshot({ path: info.outputPath(`attempt-${id}`, "ink-before-restart.png"), clip: region });
      const pages = await storedPages(page, root, "Working calculation", "Exploration");
      expect(pages[0].strokes).toBe(actions.length);
      await page.screenshot({ path: info.outputPath(`attempt-${id}`, "before-restart.png") });
      page = await desktop.restart();
      await button("Reconnect folder").click();
      await desktop.allow("Allow this time");
      await page.getByRole("button", { name: /^Open Exploration/ }).click();
      await page.getByRole("button", { name: /^Open Working calculation/ }).click();
      canvas = page.locator('canvas[id^="ink-canvas-"]:visible');
      await canvas.waitFor();
      expect(await boxOf(canvas)).toEqual(box);
      const reopened = await readFile(join(root, "Exploration", "Working calculation", "pages", "0001.svg"), "utf8");
      await writeFile(info.outputPath(`attempt-${id}`, "reopened.svg"), reopened);
      expect(reopened).toBe(original);
      await checkInk(page, reopened, settings);
      await page.screenshot({ path: info.outputPath(`attempt-${id}`, "ink-reopened.png"), clip: region });
      await expect.poll(async () => {
        const pixels = await capture(page, region);
        return pixels.filter((pixel, index) => pixel.some((channel, c) => channel !== visible[index][c])).length;
      }, { message: "reopening preserves every observed ink pixel" }).toBe(0);
      await discover("reopened", "pixels and authored SVG unchanged");
      await page.screenshot({ path: info.outputPath(`attempt-${id}`, "reopened.png") });
    } catch (error) {
      await discover("failure", error instanceof Error ? error.stack : String(error));
      await page.screenshot({ path: info.outputPath(`attempt-${id}`, "failure.png") });
      throw error;
    }
  }), parameters);
  await writeFile(info.outputPath("fast-check.json"), JSON.stringify(result, null, 2));
  expect(result.failed, `Replay with FC_SEED=${result.seed} FC_PATH=${result.counterexamplePath}: ${result.errorInstance}`).toBe(false);
});
