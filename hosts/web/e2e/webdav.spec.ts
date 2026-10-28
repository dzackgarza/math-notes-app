// The notes root through WebDAV in Firefox and WebKit (#27): each test starts
// `rclone serve webdav` on an empty directory with the command of
// docs/FORMAT.md, and checks the files on disk. RCLONE names the binary
// (`just setup` installs it; CI downloads the same release).
import { spawn } from "node:child_process";
import { mkdir, readdir, readFile } from "node:fs/promises";
import { join, relative } from "node:path";
import { createInterface } from "node:readline";

import { expect, test as base, type Page } from "@playwright/test";

import { penStroke, pixel } from "./input.ts";

interface Dav {
  url: string;
  dir: string;
}

const test = base.extend<{ dav: Dav }>({
  dav: async ({ baseURL }, use, testInfo) => {
    const dir = testInfo.outputPath("notes");
    await mkdir(dir, { recursive: true });
    const rclone = spawn(
      process.env.RCLONE ?? "rclone",
      ["serve", "webdav", dir, "--addr", "127.0.0.1:0", "--allow-origin", new URL(baseURL!).origin, "--dir-cache-time", "0s"],
      { stdio: ["ignore", "ignore", "pipe"] },
    );
    // rclone logs the address it listens on once it serves.
    let url = "";
    for await (const line of createInterface({ input: rclone.stderr })) {
      const started = /WebDav Server started on \[(http:\/\/[^\]]+?)\/?\]/.exec(line);
      if (started) {
        url = started[1];
        break;
      }
    }
    await use({ url, dir });
    rclone.kill();
  },
});

// Every file under `dir`, as sorted paths relative to it.
async function filesUnder(dir: string): Promise<string[]> {
  const entries = await readdir(dir, { recursive: true, withFileTypes: true });
  return entries
    .filter((e) => e.isFile())
    .map((e) => relative(dir, join(e.parentPath, e.name)))
    .sort();
}

const strokeIds = (svg: string) => [...svg.matchAll(/<path id="(s-[a-z2-7]+)"/g)].map((m) => m[1]);

async function connect(page: Page, dav: Dav): Promise<void> {
  await page.goto("");
  await page.getByRole("textbox", { name: "WebDAV server" }).fill(dav.url);
  await page.getByRole("button", { name: "Connect" }).click();
}

async function newNote(page: Page, title: string): Promise<void> {
  await page.getByRole("button", { name: "New Note", exact: true }).click();
  await page.getByRole("textbox", { name: "Title" }).fill(title);
  await page.getByText("Plain Paper", { exact: true }).click();
  await page.getByRole("button", { name: "Create Note" }).click();
  await expect(page.locator("#ink-canvas")).toBeVisible({ timeout: 60000 });
}

// A horizontal wave `row` × 60 px below the top of the canvas.
async function wave(page: Page, row: number): Promise<{ x: number; y: number }[]> {
  const box = (await page.locator("#ink-canvas").boundingBox())!;
  const points = Array.from({ length: 30 }, (_, i) => ({ x: box.x + 200 + i * 6, y: box.y + 120 + row * 60 + 4 * Math.sin(i / 3) }));
  await penStroke(page.locator("#ink-canvas"), points);
  return points;
}

const TEMPLATES = ["blank", "dotted", "grid-coarse", "grid-fine", "grid-medium", "lined-medium", "lined-narrow", "lined-wide"];

test("a note written through rclone is on disk as FORMAT.md lays it out and renders after a reload", async ({ page, dav }) => {
  await connect(page, dav);
  await newNote(page, "Algebra");
  const points = await wave(page, 0);
  const pagePath = join(dav.dir, "Algebra/pages/0001.svg");
  await expect.poll(async () => strokeIds(await readFile(pagePath, "utf8")), { timeout: 5000 }).toHaveLength(1);

  expect(await filesUnder(dav.dir)).toEqual(
    [
      ".pens.json",
      "Algebra/notebook.json",
      "Algebra/pages/0001.svg",
      ...TEMPLATES.flatMap((t) => [`.templates/${t}/notebook.json`, `.templates/${t}/pages/0001.svg`]),
    ].sort(),
  );
  const notebook = JSON.parse(await readFile(join(dav.dir, "Algebra/notebook.json"), "utf8"));
  expect(notebook).toMatchObject({ format: "math-notes", version: 1, template: "blank", pages: [{ file: "pages/0001.svg" }] });
  const svg = await readFile(pagePath, "utf8");
  expect(svg).toContain('mn:brush="pressure-pen"');
  expect(svg).toMatch(/<inkml:trace contextRef="#[a-z]+">[^<]+<\/inkml:trace>/);

  // The reload reconnects to the saved server without a click.
  await page.reload();
  await page.getByRole("button", { name: "My Notes", exact: true }).click();
  await page.getByRole("list", { name: "Notes" }).getByRole("listitem").filter({ hasText: "Algebra" }).getByRole("button").first().click();
  await expect(page.locator("#ink-canvas")).toBeVisible();
  await expect.poll(async () => Math.max(...(await pixel(page, points[15].x, points[15].y)).slice(0, 3))).toBeLessThan(80);
  expect(Math.min(...(await pixel(page, points[15].x, points[15].y + 40)).slice(0, 3))).toBeGreaterThan(240);
});

test("a write stopped between the PUT and the MOVE leaves the page file as it was, and the next save writes it", async ({ page, dav }) => {
  await connect(page, dav);
  await newNote(page, "Algebra");
  await wave(page, 0);
  const pagePath = join(dav.dir, "Algebra/pages/0001.svg");
  await expect.poll(async () => strokeIds(await readFile(pagePath, "utf8")), { timeout: 5000 }).toHaveLength(1);
  const original = await readFile(pagePath);

  // The MOVE of each write fails: the PUT to the swap file has landed.
  await page.route(`${dav.url}/**`, (route) => (route.request().method() === "MOVE" ? route.abort() : route.fallback()));
  await wave(page, 1);
  const swapStrokes = async () =>
    (await filesUnder(dav.dir)).includes("Algebra/pages/0001.svg.crswap") ? strokeIds(await readFile(`${pagePath}.crswap`, "utf8")).length : 0;
  await expect.poll(swapStrokes, { timeout: 5000 }).toBe(2);
  expect(await readFile(pagePath)).toEqual(original);

  await page.unroute(`${dav.url}/**`);
  await wave(page, 2);
  await expect.poll(async () => strokeIds(await readFile(pagePath, "utf8")), { timeout: 5000 }).toHaveLength(3);
  expect(await filesUnder(join(dav.dir, "Algebra"))).toEqual(["notebook.json", "pages/0001.svg"]);
});
