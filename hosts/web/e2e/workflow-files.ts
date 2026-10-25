import { readFile } from "node:fs/promises";
import { join } from "node:path";
import type { Page } from "@playwright/test";
import { expect } from "@playwright/test";
import { save } from "./workflow-actions.ts";

// Read the actual selected directory from outside the browser. Parsing the
// saved SVG with DOMParser does not call the application's document engine.
async function notebookFiles(root: string, path: string[]) {
  const directory = join(root, ...path);
  const manifest: {
    layers: { id: string; name: string; hidden: boolean; locked: boolean }[];
    pages: { file: string }[];
  } = JSON.parse(await readFile(join(directory, "notebook.json"), "utf8"));
  const files = await Promise.all(manifest.pages.map(async entry => ({
    file: entry.file, svg: await readFile(join(directory, entry.file), "utf8"),
  })));
  return { manifest, files };
}

export async function storedNote(page: Page, root: string, path: string[]) {
  const { manifest, files } = await notebookFiles(root, path);
  const pages = await page.evaluate(files => files.map(({ file, svg }) => {
    const parsed = new DOMParser().parseFromString(svg, "image/svg+xml");
    if (parsed.querySelector("parsererror")) throw new Error(`Invalid saved SVG: ${file}`);
    const groups = Array.from(parsed.documentElement.children).filter(g => g.tagName === "g" && g.id !== "background");
    return {
      file,
      groups: groups.map(g => ({
        id: g.id, xml: g.outerHTML,
        strokes: Array.from(g.querySelectorAll('path[id^="s-"]'), stroke => ({ id: stroke.id, d: stroke.getAttribute("d") })),
      })),
      links: Array.from(parsed.querySelectorAll("a"), link => link.getAttribute("href")),
      bookmarks: Array.from(parsed.querySelectorAll("g.mn-bookmark"), bookmark => bookmark.id),
      texts: Array.from(parsed.querySelectorAll("text"), box => Array.from(box.querySelectorAll("tspan"), line => line.textContent)),
    };
  }), files);
  return { layers: manifest.layers, pages };
}

export async function storedPages(page: Page, root: string, title: string, notebook = "Test Notebook") {
  const { files } = await notebookFiles(root, [notebook, title]);
  return page.evaluate(files => files.map(({ file, svg }) => {
    const parsed = new DOMParser().parseFromString(svg, "image/svg+xml");
    if (parsed.querySelector("parsererror")) throw new Error(`Invalid saved SVG: ${file}`);
    return {
      file,
      size: parsed.documentElement.getAttribute("viewBox")?.split(" ").slice(2).map(Number),
      strokes: svg.match(/<path id="s-/g)?.length ?? 0,
      ruling: parsed.getElementById("background")?.getAttribute("mn:ruling"),
      text: Array.from(parsed.querySelectorAll("text"), box => box.textContent).join("\n"),
    };
  }), files);
}

export async function savedPages(page: Page, root: string, title: string, notebook = "Test Notebook") {
  await save(page);
  await expect(page.getByRole("status", { name: /^Notebook save/ })).toHaveAccessibleName("Notebook save Saved");
  return storedPages(page, root, title, notebook);
}

export async function storedFills(_page: Page, root: string, path: string[], file: string) {
  const svg = await readFile(join(root, ...path, "pages", file), "utf8");
  return [...svg.matchAll(/<path id="s-[^"]*"[^>]* fill="(#[0-9A-F]{6})"/g)].map(match => match[1]);
}
