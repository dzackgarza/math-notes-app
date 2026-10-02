import { expect } from "@playwright/test";
import { execFileSync } from "node:child_process";
import { test, enterText, goToPage, addTag, createTestNotebook, openTestNotebook, penStroke, line, screenPixels, darkestPixel, inkAt, boxOf, closePopover, storedPages, savedPages, lanAddress, type PenPoint, type Rgb } from "./support.ts";

// One notes folder over its first year. The user first opens the app at the
// machine's LAN address and is sent to localhost, then chooses an empty
// folder, makes a notebook, and writes on three pages with each tool; the app
// saves the edits without a Save tap. A restart opens the saved folder, a
// second restart asks for a reconnection, and then the library changes: a
// second notebook, a move, a search, a favorite, the trash, a rename, a tag,
// and an export. Each step asserts the screen and the files.
test("Flutter lifetime: first year with one notes folder", async ({ page, baseURL }, info) => {
  test.setTimeout(180_000);
  if (!baseURL) throw new Error("The Playwright configuration has no baseURL");
  const shot = (name: string) => page.screenshot({ path: info.outputPath(`${name}.png`) });
  const button = (name: string) => page.getByRole("button", { name, exact: true });
  const opfs = () => page.evaluate(async () => {
    const root = await navigator.storage.getDirectory();
    const folders = await Array.fromAsync(root.keys());
    const metadata = folders.includes(".library.json")
      ? JSON.parse(await (await (await root.getFileHandle(".library.json")).getFile()).text())
      : null;
    return { folders, metadata };
  });

  await test.step("the user opens the app at the machine's LAN address", async () => {
    await page.goto(lanAddress(baseURL));
    expect(await page.evaluate(() => window.isSecureContext), "the LAN address is not a secure context").toBe(false);
    // The error toast is one semantics node, labeled with its title and message.
    const error = page.getByLabel(/is not a secure address/);
    await expect(error).toBeVisible();
    await expect(error).toHaveAccessibleName(new RegExp(`Open http://localhost${new URL(baseURL).pathname} on this machine`));
    // The title names the error; the message does not repeat it. The
    // accessible name folds the line break into a space.
    await expect(error).toHaveAccessibleName(/^Error http:/);
    await expect(page.getByLabel(/reading 'controller'/), "the service worker failure is not a second error").toHaveCount(0);
    await expect(page.getByLabel(/showDirectoryPicker/)).toHaveCount(0);
    await shot("lan-address");
  });

  // First launch: a fresh browser profile has no saved folder. Automation
  // cannot drive the native picker; here it yields the origin-private file
  // system, which the app keeps in IndexedDB as it keeps any chosen folder.
  await test.step("the user opens localhost and chooses an empty notes folder", async () => {
    await page.addInitScript(() => {
      Object.defineProperty(window, "showDirectoryPicker", {
        configurable: true,
        value: async () => navigator.storage.getDirectory(),
      });
    });
    await page.goto("");
    await expect(page.getByText("Your notes live in a folder on this device.", { exact: true })).toBeVisible();
    await shot("first-launch");
    expect((await opfs()).folders, "the chosen folder is empty").toEqual([]);
    const choose = button("Choose notes folder");
    await expect(choose).toBeVisible();
    await choose.click();
    await expect(button("New notebook")).toBeVisible();
    await expect(page.getByText("Your notebooks appear here.", { exact: true })).toBeVisible();
    expect((await opfs()).folders, "the app prepares the folder's templates and pens").toEqual(expect.arrayContaining([".templates", ".pens.json"]));
    await shot("empty-library");
  });

  await test.step("the user makes the first notebook and its first note", async () => {
    await button("New notebook").click();
    await enterText(page.getByRole("textbox", { name: "Notebook title", exact: true }), "Analysis");
    await enterText(page.getByRole("textbox", { name: "Description", exact: true }), "Measure theory");
    await addTag(page, "measure");
    await button("Grid").click();
    await button("Create").click();
    await expect(page.getByRole("heading", { name: "Analysis", exact: true })).toBeVisible();
    await button("New note").click();
    await enterText(page.getByRole("textbox", { name: "Title", exact: true }), "Integrals");
    // A new note starts with its notebook's tags.
    await expect(button("Remove tag measure")).toBeVisible();
    await button("Create").click();
  });
  const canvas = page.locator('canvas[id^="ink-canvas-"]:visible');
  await canvas.waitFor({ timeout: 30_000 });
  const box = await boxOf(canvas);
  const cdp = await page.context().newCDPSession(page);
  const pages = () => savedPages(page, "Integrals", "Analysis");
  const strokes = async () => (await pages()).map((saved) => saved.strokes);
  // The stroke counts that reach the note file with no Save tap.
  const autosaved = (counts: number[], message: string) => expect(async () => {
    expect((await storedPages(page, "Integrals", "Analysis")).map((saved) => saved.strokes), message).toEqual(counts);
  }).toPass({ timeout: 15_000 });

  // Three rows of handwriting on page 1; each is checked on screen against
  // the paper captured before writing.
  const rows = [170, 260, 350].map((dy) => ({ x: box.x + 220, y: box.y + dy }));
  const moved = { x: rows[2].x, y: rows[2].y + 120 };
  const paper = new Map<PenPoint, Rgb[]>();
  for (const spot of [...rows, moved]) paper.set(spot, await screenPixels(page, spot));
  const write = (spot: PenPoint) => penStroke(cdp, line(spot.x - 60, spot.x + 60, spot.y), 0.6);
  let stroke = 0;
  const inked = async () => {
    const spots = [];
    for (const spot of [...rows, moved]) spots.push((await inkAt(page, spot, paper.get(spot)!)) > 0.5 * stroke);
    return spots;
  };

  await test.step("the user writes the first row, undoes and redoes it, and the file follows without a Save tap", async () => {
    await write(rows[0]);
    stroke = await inkAt(page, rows[0], paper.get(rows[0])!);
    expect(stroke, "the first row shows ink").toBeGreaterThan(0);
    await autosaved([1], "the stroke reaches the note file");
    await button("Undo").click();
    await autosaved([0], "the undo reaches the note file");
    await button("Redo").click();
    await autosaved([1], "the redo reaches the note file");
  });

  await test.step("the user writes two more rows on page 1", async () => {
    await write(rows[1]);
    await write(rows[2]);
    expect(await inked()).toEqual([true, true, true, false]);
    expect(await strokes()).toEqual([3]);
    await shot("page-1-written");
  });

  // The stroke eraser takes the second row; undo and redo take it back and
  // away again, on screen and in the file.
  await test.step("the user erases the second row and undoes and redoes the erase", async () => {
    await button("Eraser").click();
    await button("Eraser").click();
    await button("Stroke").click();
    await closePopover(page);
    await penStroke(cdp, [-40, -20, 0, 20, 40].map((dy) => ({ x: rows[1].x, y: rows[1].y + dy })), 0.6);
    expect(await inked()).toEqual([true, false, true, false]);
    expect(await strokes()).toEqual([2]);
    await button("Undo").click();
    expect(await inked()).toEqual([true, true, true, false]);
    expect(await strokes()).toEqual([3]);
    await button("Redo").click();
    expect(await inked()).toEqual([true, false, true, false]);
    expect(await strokes()).toEqual([2]);
  });

  await test.step("the user highlights the first row", async () => {
    // A highlight across the first row leaves the handwriting dark.
    const plainInk = await darkestPixel(page, rows[0]);
    await button("Highlighter").click();
    await penStroke(cdp, [-40, -20, 0, 20, 40].map((dy) => ({ x: rows[0].x + 30, y: rows[0].y + dy })), 0.6);
    const crossing = await darkestPixel(page, rows[0]);
    for (const channel of [0, 1, 2]) expect(Math.abs(crossing[channel] - plainInk[channel]), "the highlighted handwriting keeps its color").toBeLessThan(24);
    expect(await strokes()).toEqual([3]);
  });

  await test.step("the user lassos the third row down", async () => {
    // The lasso moves the third row down; the pen writes again afterwards.
    await button("Lasso").click();
    await penStroke(cdp, [
      { x: rows[2].x - 80, y: rows[2].y - 40 }, { x: rows[2].x + 80, y: rows[2].y - 40 },
      { x: rows[2].x + 80, y: rows[2].y + 40 }, { x: rows[2].x - 80, y: rows[2].y + 40 },
      { x: rows[2].x - 80, y: rows[2].y - 40 },
    ], 0.6);
    await penStroke(cdp, [0, 40, 80, 120].map((dy) => ({ x: rows[2].x, y: rows[2].y + dy })), 0.6);
    await button("Pen").click();
    expect(await inked()).toEqual([true, false, false, true]);
    expect(await strokes()).toEqual([3]);
    await shot("page-1-edited");
  });

  // A typed text box. The new box is selected, as pasted content is, so a
  // pen-down elsewhere would only dismiss the selection; its menu clears it.
  await test.step("the user types a text box", async () => {
    await button("Text").click();
    await enterText(page.getByRole("textbox", { name: "Text", exact: true }), "Theorem 1");
    await button("Done").click();
    expect((await pages())[0].text).toContain("Theorem 1");
    await expect(button("Clear selection")).toBeVisible();
    await shot("text-box-selected");
    await button("Clear selection").click();
    await expect(button("Clear selection")).toHaveCount(0);
    await button("Pen").click();
  });

  // Pages 2 and 3, each written with no Save tap; the overview returns to
  // page 1, which still shows its own ink and none of the other pages'.
  const addPage = async (number: number) => {
    await button("Pages").click();
    await button("Add page At end").click();
    await expect(page.getByText(`${number - 1} / ${number}`, { exact: true })).toBeVisible();
    await goToPage(page, number);
    await expect(page.getByText(`${number} / ${number}`, { exact: true })).toBeVisible();
  };
  await test.step("the user adds and writes pages 2 and 3 and returns to page 1 from the overview", async () => {
    await addPage(2);
    await autosaved([3, 0], "the new page reaches the note file");
    expect(await inked(), "a new page is blank").toEqual([false, false, false, false]);
    await write(rows[0]);
    await write(rows[1]);
    expect(await inked()).toEqual([true, true, false, false]);
    await addPage(3);
    await write(rows[2]);
    expect(await inked()).toEqual([false, false, true, false]);
    await autosaved([3, 2, 1], "the handwriting of pages 2 and 3 reaches the note file");
    await shot("page-3-written");
    await button("Pages").click();
    await button("Page overview").click();
    for (const number of [1, 2, 3]) await expect(button(`Page ${number}`)).toBeVisible();
    await shot("page-overview");
    await button("Page 1").click();
    await expect(page.getByText("1 / 3", { exact: true })).toBeVisible();
    expect(await inked()).toEqual([true, false, false, true]);
  });

  // A restart: the saved folder opens without a gesture, and the note shows
  // the same ink on each page; pages 2 and 3 were saved without a Save tap.
  // The app finds the saved folder as a handle in IndexedDB; Chromium 153
  // exits when it reads a stored OPFS handle back (TRAPS.md), so the restart
  // gives the app its saved folder in the host's own terms instead.
  const restart = async (needsGesture: boolean) => {
    await page.addInitScript((needsGesture) => {
      Object.defineProperty(window, "mathNotes", {
        configurable: true,
        set(value) {
          Object.assign(value, {
            startRoot: async () => ({ root: await navigator.storage.getDirectory(), needsGesture }),
            requestPermission: async () => true,
          });
          Object.defineProperty(window, "mathNotes", { configurable: true, writable: true, value });
        },
      });
    }, needsGesture);
    await page.goto("");
  };
  await test.step("the user restarts the app and finds every page as written", async () => {
    await restart(false);
    await expect(page.getByRole("button", { name: "Open Analysis", exact: false })).toBeVisible({ timeout: 30_000 });
    await expect(page.getByText(/^1 note/)).toBeVisible();
    await shot("library-after-restart");
    await openTestNotebook(page, "Analysis");
    await page.getByRole("button", { name: "Open Integrals", exact: false }).click();
    await canvas.waitFor({ timeout: 30_000 });
    await expect(page.getByText("1 / 3", { exact: true })).toBeVisible();
    expect(await boxOf(canvas), "the canvas keeps its place after a restart").toEqual(box);
    expect(await inked()).toEqual([true, false, false, true]);
    await goToPage(page, 2);
    await expect(page.getByText("2 / 3", { exact: true })).toBeVisible();
    expect(await inked()).toEqual([true, true, false, false]);
    await goToPage(page, 3);
    await expect(page.getByText("3 / 3", { exact: true })).toBeVisible();
    expect(await inked(), "the handwriting saved without a Save tap returns").toEqual([false, false, true, false]);
    expect(await strokes()).toEqual([3, 2, 1]);
  });

  await test.step("the user restarts into a folder that needs a permission gesture and reconnects it", async () => {
    await restart(true);
    await expect(button("Reconnect folder")).toBeVisible();
    await shot("reconnect");
    await button("Reconnect folder").click();
    await openTestNotebook(page, "Analysis");
    await page.getByRole("button", { name: "Open Integrals", exact: false }).click();
    await expect(page.getByText("1 / 3", { exact: true })).toBeVisible();
    expect(await inked()).toEqual([true, false, false, true]);
    expect((await storedPages(page, "Integrals", "Analysis")).map((saved) => saved.strokes), "every page keeps its edits after the reconnection").toEqual([3, 2, 1]);
  });

  await test.step("the user adds a second notebook and moves the note into it", async () => {
    await button("Library").click();
    await button("Back to library").click();
    await createTestNotebook(page, "Topology");
    await button("New note").click();
    await enterText(page.getByRole("textbox", { name: "Title", exact: true }), "Compactness");
    await button("Create").click();
    // Integrals is still open, so closing this note shows that one.
    await button("Close Compactness").click();
    await expect(page.getByRole("heading", { name: "Integrals", exact: true })).toBeVisible();
    await button("Library").click();
    await expect(page.getByRole("heading", { name: "Topology", exact: true })).toBeVisible();
    await button("Back to library").click();
    await openTestNotebook(page, "Analysis");
    await button("Integrals actions").click();
    await button("Move").click();
    await button("Topology").click();
    await expect(button("Integrals actions")).toHaveCount(0);
    await button("Back to library").click();
    await openTestNotebook(page, "Topology");
    await expect(page.getByRole("button", { name: "Open Integrals", exact: false })).toBeVisible();
    await expect(page.getByRole("button", { name: "Open Compactness", exact: false })).toBeVisible();
    await shot("moved");
  });

  await test.step("the user searches for the note and makes it a favorite", async () => {
    await button("Back to library").click();
    await enterText(page.getByRole("textbox", { name: "Search notebooks and notes", exact: true }), "Integrals");
    await expect(page.getByRole("button", { name: "Open Integrals", exact: false })).toBeVisible();
    await expect(page.getByRole("button", { name: "Open Compactness", exact: false })).toHaveCount(0);
    await button("Integrals actions").click();
    await button("Pin note").click();
    await page.getByText("Pinned", { exact: true }).click();
    await expect(page.getByRole("button", { name: "Open Integrals", exact: false })).toBeVisible();
    await expect(page.getByRole("button", { name: "Open Compactness", exact: false })).toHaveCount(0);
  });

  await test.step("the user trashes a note and restores it", async () => {
    await button("Recent").click();
    await button("Compactness actions").click();
    await button("Move to trash").click();
    await button("Trash").click();
    await button("Compactness actions").click();
    await button("Restore").click();
    await button("Topology").click();
    await button("Library").click();
    await openTestNotebook(page, "Topology");
    await expect(page.getByRole("button", { name: "Open Compactness", exact: false })).toBeVisible();
  });

  await test.step("the user renames the first notebook", async () => {
    await button("Back to library").click();
    await button("Analysis notebook actions").click();
    await button("Rename").click();
    await enterText(page.getByRole("textbox", { name: "Name", exact: true }), "Real analysis");
    await button("Rename").click();
    await expect(button("Real analysis notebook actions")).toBeVisible();
    await openTestNotebook(page, "Real analysis");
    await expect(page.getByText("Measure theory", { exact: true }), "the renamed notebook keeps its description").toBeVisible();
    await expect(page.getByText("This notebook has no notes yet.", { exact: true })).toBeVisible();
    await button("Back to library").click();
  });

  await test.step("the user makes a tag and gives it to the note", async () => {
    await button("New tag").click();
    await enterText(page.getByRole("textbox", { name: "Tag name", exact: true }), "geometry");
    await button("Add tag").click();
    await openTestNotebook(page, "Topology");
    await button("Integrals actions").click();
    await button("Details and tags").click();
    await addTag(page, "geometry");
    await button("Save details").click();
    await page.getByRole("button", { name: /^geometry/ }).click();
    await expect(page.getByRole("button", { name: "Open Integrals", exact: false })).toBeVisible();
    await expect(page.getByRole("button", { name: "Open Compactness", exact: false })).toHaveCount(0);
    await shot("library-final");

    const { folders, metadata } = await opfs();
    expect(folders).toEqual(expect.arrayContaining(["Real analysis", "Topology"]));
    expect(folders).not.toContain("Analysis");
    expect(metadata.folders["Real analysis"].description).toBe("Measure theory");
    expect(metadata.folders["Real analysis"].tags).toEqual(["measure"]);
    expect(metadata.folders.Analysis).toBeUndefined();
    expect(metadata.notes["Topology/Integrals"].favorite).toBe(true);
    expect(metadata.notes["Topology/Integrals"].tags).toEqual(["measure", "geometry"]);
    expect(metadata.notes["Analysis/Integrals"]).toBeUndefined();
    expect(metadata.notes[".trash/Compactness"]).toBeUndefined();
    expect(metadata.tags.map(({ name }: { name: string }) => name)).toEqual(expect.arrayContaining(["measure", "geometry"]));
  });

  await test.step("the user opens the moved note and exports it as a PDF", async () => {
    // The moved note keeps its pages, and exports them.
    const stored = await storedPages(page, "Integrals", "Topology");
    expect(stored.map((saved) => saved.strokes)).toEqual([3, 2, 1]);
    expect(stored[0].text).toContain("Theorem 1");
    await page.getByRole("button", { name: "Open Integrals", exact: false }).click();
    await expect(page.getByText("1 / 3", { exact: true })).toBeVisible();
    expect(await inked()).toEqual([true, false, false, true]);
    await button("More").click();
    await button("Export PDF").click();
    const download = page.waitForEvent("download");
    await button("Export").click();
    const pdfPath = info.outputPath("integrals.pdf");
    await (await download).saveAs(pdfPath);
    expect(execFileSync("pdfinfo", [pdfPath], { encoding: "utf8" })).toMatch(/Pages:\s+3/);
    expect(execFileSync("pdftotext", [pdfPath, "-"], { encoding: "utf8" })).toContain("Theorem 1");
  });
});
