import { expect } from "@playwright/test";
import { execFileSync } from "node:child_process";
import { test, longPressDrag, enterText, save, goToPage, whenSaved, createTestNotebook, openTestNotebook, penStroke, line, textIn, contrastIn, boxOf, savedPages, type Box } from "./support.ts";

// A student works through a long problem set in one notebook: a problem on
// each of three pages, a typed lemma, an export, a page pulled in at the end,
// and a reorder in the page overview. After a reload, the next problem set
// gets pages inserted, resized, deleted, and restored beside the first one,
// which keeps its page in its tab and becomes a favorite. Offline, the first
// set still opens, takes a page, and saves it. Each step asserts the screen
// and the files.
test("Flutter problem set session: pages written, pulled in, reordered, inserted, and deleted, with reload, favorites, and offline work", async ({ page }, info) => {
  test.setTimeout(300_000);
  const shot = (name: string) => page.screenshot({ path: info.outputPath(`${name}.png`) });
  const button = (name: string) => page.getByRole("button", { name, exact: true });
  const choose = async (menu: string, item: string | RegExp) => {
    await button(menu).click();
    await page.getByRole("button", { name: item, exact: typeof item === "string" }).click();
  };
  const notebook = "Homework";
  const first = "Problem Set 3";
  const next = "Problem Set 4";
  const saved = async () => {
    await save(page);
    await expect(page.getByRole("status", { name: /^Notebook save/ })).toHaveAccessibleName("Notebook save Saved");
  };
  const manifest = (title: string) => whenSaved(() => page.evaluate(async ({ notebook, title }) => {
    const root = await navigator.storage.getDirectory();
    const dir = await (await root.getDirectoryHandle(notebook)).getDirectoryHandle(title);
    return JSON.parse(await (await (await dir.getFileHandle("notebook.json")).getFile()).text()) as { pages: { file: string }[] };
  }, { notebook, title }));
  const firstPageSvg = () => whenSaved(() => page.evaluate(async ({ notebook, title }) => {
    const root = await navigator.storage.getDirectory();
    const pages = await (await (await root.getDirectoryHandle(notebook)).getDirectoryHandle(title)).getDirectoryHandle("pages");
    return (await (await pages.getFileHandle("0001.svg")).getFile()).text();
  }, { notebook, title: first }));
  const openNote = async (title: string) => {
    await openTestNotebook(page, notebook);
    await page.getByRole("button", { name: `Open ${title}`, exact: false }).click();
  };

  await page.goto("?root=opfs");
  await createTestNotebook(page, notebook);
  await button("New note").click();
  await enterText(page.getByRole("textbox", { name: "Title", exact: true }), first);
  await button("Create").click();
  const canvas = page.locator('canvas[id^="ink-canvas-"]:visible');
  await canvas.waitFor({ timeout: 30_000 });
  let box: Box = await boxOf(canvas);
  const cdp = await page.context().newCDPSession(page);

  await test.step("write a problem on each of three pages and return to page one", async () => {
    const draw = async (offset: number) => {
      const pen = { pointerType: "pen" as const, force: 0.6 };
      const y = box.y + 180 + offset;
      await cdp.send("Input.dispatchMouseEvent", { type: "mousePressed", button: "left", clickCount: 1, x: box.x + 150, y, ...pen });
      await cdp.send("Input.dispatchMouseEvent", { type: "mouseMoved", button: "left", buttons: 1, x: box.x + 230, y, ...pen });
      await cdp.send("Input.dispatchMouseEvent", { type: "mouseReleased", button: "left", clickCount: 1, x: box.x + 230, y, ...pen });
    };
    await draw(0);
    for (let pageNumber = 2; pageNumber <= 3; pageNumber++) {
      await choose("Pages", "Add page At end");
      await expect(page.getByText(`${pageNumber - 1} / ${pageNumber}`, { exact: true })).toBeVisible();
      await goToPage(page, pageNumber);
      await expect(page.getByText(`${pageNumber} / ${pageNumber}`, { exact: true })).toBeVisible();
      await draw((pageNumber - 1) * 30);
    }
    await choose("Pages", "Page overview");
    await button("Page 1").click();
    await expect(page.getByText("1 / 3", { exact: true })).toBeVisible();
    expect((await savedPages(page, first, notebook)).map(({ strokes }) => strokes)).toEqual([1, 1, 1]);
    const svg = await firstPageSvg();
    expect(svg).toContain('<path id="s-');
    expect(svg).toContain("inkml:trace");
  });

  await test.step("type a lemma on page one and export the set", async () => {
    await button("Text").click();
    await enterText(page.getByRole("textbox", { name: "Text", exact: true }), "Lemma\nEvery basis spans the space.");
    await button("Done").click();
    await button("Clear selection").click();
    await save(page);
    await expect.poll(firstPageSvg).toContain("Every basis spans the space.");
    await button("More").click();
    await button("Export PDF").click();
    const exported = page.waitForEvent("download");
    await button("Export").click();
    const pdfPath = info.outputPath("problem-set.pdf");
    await (await exported).saveAs(pdfPath);
    expect(execFileSync("pdfinfo", [pdfPath], { encoding: "utf8" })).toMatch(/Pages:\s+3/);
    expect(execFileSync("pdftotext", [pdfPath, "-"], { encoding: "utf8" })).toContain("Every basis spans the space.");
    await shot("notebook");
  });

  await test.step("pull a page in at the end, undo and redo it from the keyboard, and save", async () => {
    await goToPage(page, 3);
    const hint = page.getByText("Pull and hold to add a page", { exact: true });
    await page.mouse.move(box.x + box.width / 2, box.y + box.height / 2);
    await page.mouse.wheel(0, 4000);
    await expect(hint).toBeVisible();
    expect((await textIn(page, await boxOf(hint))).contrast, "the hint is legible over the paper").toBeGreaterThan(4.5);
    const x = box.x + box.width / 2;
    const y = box.y + box.height - 40;
    for (const held of [false, true]) {
      await cdp.send("Input.dispatchTouchEvent", { type: "touchStart", touchPoints: [{ id: 1, x, y }] });
      for (const distance of [20, 360]) {
        await cdp.send("Input.dispatchTouchEvent", { type: "touchMove", touchPoints: [{ id: 1, x, y: y - distance }] });
      }
      if (held) await expect(page.getByText("Release to add a page", { exact: true })).toBeVisible();
      await cdp.send("Input.dispatchTouchEvent", { type: "touchEnd", touchPoints: [] });
      if (!held) {
        await expect(page.getByText("3 / 3", { exact: true })).toBeVisible();
        await expect(hint).toBeVisible();
      }
    }
    await expect(page.getByText(/^[34] \/ 4$/)).toBeVisible();
    await page.keyboard.press("Control+z");
    await expect(page.getByText("3 / 3", { exact: true })).toBeVisible();
    await page.keyboard.press("Control+Shift+z");
    await expect(page.getByText(/^[34] \/ 4$/)).toBeVisible();
    await page.keyboard.press("Control+s");
    await expect(page.getByRole("status", { name: /^Notebook save/ })).toHaveAccessibleName("Notebook save Saved");
    expect((await manifest(first)).pages).toHaveLength(4);
  });

  await test.step("duplicate, delete, reorder, and open pages in the page overview", async () => {
    await choose("Pages", "Page overview");
    const tile = (n: number) => button(`Page ${n}`);
    await expect(tile(4)).toBeVisible();
    const act = async (n: number, action: string) => {
      await button(`Page ${n} actions`).click();
      await button(action).click();
    };
    await act(1, "Duplicate");
    await expect(tile(5)).toBeVisible();
    await act(5, "Delete");
    await expect(tile(5)).toHaveCount(0);
    await longPressDrag(page, await boxOf(tile(1)), await boxOf(tile(3)));
    await shot("page-overview");
    await tile(2).click();
    await expect(page.getByText("2 / 4", { exact: true })).toBeVisible();
    await saved();
    // Pages 0001-0004; the copy of page 1 is 0005 after it; the pulled page
    // (0004) is deleted; page 1 moves to the third place.
    expect((await manifest(first)).pages.map((entry) => entry.file)).toEqual([
      "pages/0005.svg",
      "pages/0002.svg",
      "pages/0001.svg",
      "pages/0003.svg",
    ]);
  });

  await test.step("reload and reopen the set at page one, then go to page two", async () => {
    await page.reload();
    await openNote(first);
    await expect(canvas).toBeVisible();
    await expect(page.getByText("1 / 4", { exact: true })).toBeVisible();
    await goToPage(page, 2);
    await expect(page.getByText("2 / 4", { exact: true })).toBeVisible();
  });

  const goTo = async (number: number) => {
    await choose("Pages", "Go to page");
    await enterText(page.getByRole("textbox"), `${number}`);
    await shot("go-to-page");
    await button("Go").click();
    await expect(page.getByText(new RegExp(`^${number} / \\d$`))).toBeVisible();
  };
  const pages = () => savedPages(page, next, notebook);
  const strokes = async () => (await pages()).map(({ strokes }) => strokes);
  const a4 = [595.28, 841.89], letter = [612, 792];
  // One control changes at a time: the sheet shows the current size and
  // orientation, and the other control keeps its value.
  const papers: [string, number[]][] = [
    ["Letter", letter],
    ["Landscape", letter.toReversed()],
    ["A4", a4.toReversed()],
    ["Portrait", a4],
  ];

  await test.step("start the next set and insert pages before and after its first page", async () => {
    await button("Library").click();
    await button("New note").click();
    await enterText(page.getByRole("textbox", { name: "Title" }), next);
    await button("Create").click();
    await expect(page.getByRole("heading", { name: next, exact: true })).toBeVisible();
    box = await boxOf(canvas);
    await penStroke(cdp, line(box.x + 150, box.x + 300, box.y + 250), 0.6);
    await choose("Pages", /^Insert page before/);
    await expect(page.getByText(/^\d \/ 2$/)).toBeVisible();
    await goTo(2);
    await choose("Pages", /^Insert page after/);
    await expect(page.getByText("2 / 3", { exact: true })).toBeVisible();
    expect((await pages()).map(({ file, strokes }) => ({ file, strokes }))).toEqual([
      { file: "pages/0002.svg", strokes: 0 },
      { file: "pages/0001.svg", strokes: 1 },
      { file: "pages/0003.svg", strokes: 0 },
    ]);
    await choose("Pages", "Clear page");
    expect(await strokes(), "Clear page removes the handwriting of the current page").toEqual([0, 0, 0]);
    await button("Undo").click();
    expect(await strokes(), "undo restores the cleared page").toEqual([0, 1, 0]);
    await goTo(1);
    await goTo(2);
  });

  await test.step("add pages in each paper size and orientation", async () => {
    for (const [index, [control]] of papers.entries()) {
      await choose("Pages", "Paper for new pages");
      await expect(button("Done")).toBeVisible();
      if (index === 1) await shot("paper-sheet");
      await button(control).click();
      await button("Done").click();
      await choose("Pages", "Add page At end");
      await expect(page.getByText(`2 / ${4 + index}`, { exact: true })).toBeVisible();
    }
    expect((await pages()).map(({ size }) => size), "a new page takes the chosen size")
      .toEqual([a4, a4, a4, ...papers.map(([, size]) => size)]);
    await goTo(4);
    await shot("letter-landscape");
  });

  await test.step("delete a page, restore it from the toast, delete the written page, and add a lined page", async () => {
    await button("Pages").click();
    expect(await contrastIn(page, button("Delete page")), "Delete page is legible").toBeGreaterThan(4.5);
    await button("Delete page").click();
    await expect(page.getByText(/^\d \/ 6$/)).toBeVisible();
    // The pointer rests on the toast, which holds it open.
    const toast = page.getByRole("status", { name: "Page 4 deleted", exact: true });
    await toast.hover();
    expect((await pages()).map(({ size }) => size), "the landscape Letter page is deleted")
      .toEqual([a4, a4, a4, ...papers.slice(1).map(([, size]) => size)]);
    await shot("delete-toast");
    // The toast's Undo restores the page.
    await expect(toast).toBeVisible();
    await button("Undo").last().click();
    await expect(page.getByText(/^\d \/ 7$/)).toBeVisible();
    await goTo(2);
    await choose("Pages", "Delete page");
    await expect(page.getByText("2 / 6", { exact: true })).toBeVisible();
    expect(await strokes(), "the written page is deleted").toEqual([0, 0, 0, 0, 0, 0]);

    // The paper style of new pages; the pages that exist keep theirs.
    const rulings = async () => (await pages()).map(({ ruling }) => ruling);
    const before = await rulings();
    await choose("Pages", "Paper for new pages");
    await button("Lined paper").click();
    await button("Done").click();
    await choose("Pages", "Add page At end");
    await expect(page.getByText("2 / 7", { exact: true })).toBeVisible();
    expect(await rulings(), "the new page is lined").toEqual([...before, "lined"]);
  });

  await test.step("switch back to the first set at its page, and mark it a favorite", async () => {
    await button(first).click();
    await expect(page.getByText("2 / 4", { exact: true })).toBeVisible();
    await button("Library").click();
    await button(`${first} actions`).click();
    await button("Pin note").click();
    await page.getByText("Pinned", { exact: true }).click();
    await expect(page.getByRole("button", { name: `Open ${first}`, exact: false })).toBeVisible();
    await expect(page.getByRole("button", { name: `Open ${next}`, exact: false })).not.toBeVisible();
    await expect.poll(() => whenSaved(() => page.evaluate(async (key) => {
      const root = await navigator.storage.getDirectory();
      const metadata = JSON.parse(await (await (await root.getFileHandle(".library.json")).getFile()).text());
      return metadata.notes[key]?.favorite;
    }, `${notebook}/${first}`))).toBe(true);
  });

  await test.step("offline, reopen the first set, add a page, save, and reopen it", async () => {
    await page.context().setOffline(true);
    await page.reload();
    await openNote(first);
    await expect(page.getByText("1 / 4", { exact: true })).toBeVisible();
    await choose("Pages", "Add page At end");
    await saved();
    await page.reload();
    await openNote(first);
    await expect(page.getByText("1 / 5", { exact: true })).toBeVisible();
  });

  await test.step("back online, the favorite stays", async () => {
    await page.context().setOffline(false);
    await page.reload();
    await page.getByText("Pinned", { exact: true }).click();
    await expect(page.getByRole("button", { name: `Open ${first}`, exact: false })).toBeVisible();
  });
});
