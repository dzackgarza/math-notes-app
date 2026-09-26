// Note thumbnails: the engine renders page 1 to a PNG 240 px wide
// (ink_document_page_png), cached in the origin-private file system and keyed
// by the note's path and the name, modification time and size of page 1's
// file and of each image it shows, so a thumbnail is rendered again only when
// one of those files changes. Caches are disposable (docs/FORMAT.md,
// invariant 3).
import type { Engine } from "../engine/engine.ts";
import { EngineError, Status } from "../engine/engine.ts";
import { type Note, pathKey } from "./library.ts";
import type { Bytes, Entry, Store } from "./store.ts";

export const THUMBNAIL_WIDTH = 240;

// A dot directory: with ?root=opfs the origin-private file system is also the
// notes root, whose scan skips dot directories.
const CACHE = ".thumbnail-cache";

// Cache reads and engine renders since the page loaded.
export const thumbnailStats = { hits: 0, renders: 0 };

async function hex(text: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return Array.from(new Uint8Array(digest), (b) => b.toString(16).padStart(2, "0")).join("");
}

function notFound(e: unknown): boolean {
  return e instanceof DOMException && (e.name === "NotFoundError" || e.name === "TypeMismatchError");
}

// Page 1 of the notebook at `dir`, drawn by the engine from notebook.json,
// that page and the assets.
function render(engine: Engine, json: Uint8Array<ArrayBuffer>, page: { path: string; bytes: Uint8Array<ArrayBuffer> }, assets: { path: string; bytes: Uint8Array<ArrayBuffer> }[]): Uint8Array<ArrayBuffer> {
  const document = engine.createDocument(1n);
  try {
    document.loadNotebook(json);
    try {
      document.loadPage(page.path, page.bytes);
    } catch (e) {
      // A page that does not parse is drawn as the engine's error page.
      if (!(e instanceof EngineError && e.status === Status.parse)) throw e;
    }
    for (const asset of assets) document.loadAsset(asset.path, asset.bytes);
    return document.pagePng(0, THUMBNAIL_WIDTH);
  } finally {
    document.free();
  }
}

const pending = new Map<string, Promise<Blob | null>>();
// The last thumbnail loaded for each note path, shown while a rescan checks
// the cache again.
const shown = new Map<string, Blob>();

export function lastThumbnail(note: Note): Blob | undefined {
  return shown.get(pathKey(note.path));
}

// The notebook paths of the images page `file` shows: the href of each SVG
// `image`, relative to the page file (docs/FORMAT.md, Page SVG), as the
// engine's NotebookPath resolves it.
export function imagePaths(file: string, svg: string): string[] {
  const base = new URL(file, "notebook:/");
  const page = new DOMParser().parseFromString(svg, "image/svg+xml");
  const paths = new Set<string>();
  for (const image of Array.from(page.getElementsByTagNameNS("http://www.w3.org/2000/svg", "image"))) {
    const href = image.getAttribute("href") ?? image.getAttributeNS("http://www.w3.org/1999/xlink", "href");
    if (!href) continue;
    const url = new URL(href, base);
    if (url.protocol === "notebook:") paths.add(decodeURIComponent(url.pathname.slice(1)));
  }
  return [...paths].sort();
}

async function load(engine: Engine, store: Store, note: Note): Promise<Blob | null> {
  const json = await store.read([...note.path, "notebook.json"]);
  if (!json) return null;
  const { pages } = JSON.parse(new TextDecoder().decode(json)) as { pages?: { file: string }[] };
  const first = pages?.[0]?.file;
  if (!first) return null;
  const pagePath = [...note.path, ...first.split("/")];
  const [page, bytes] = [await store.stat(pagePath), await store.read(pagePath)];
  if (!page || !bytes) return null;
  const svg = new TextDecoder().decode(bytes);
  const images: { path: string; stat: Entry }[] = [];
  for (const path of imagePaths(first, svg)) {
    const stat = await store.stat([...note.path, ...path.split("/")]);
    if (stat?.kind === "file") images.push({ path, stat });
  }

  // The key: page 1's file and each image it shows, by name, modification
  // time and size.
  const stamp = (path: string, file: Entry) => `${path}:${file.modified}:${file.size}`;
  const key = `${await hex([stamp(first, page), ...images.map((i) => stamp(i.path, i.stat))].join("\n"))}.png`;
  const cache = await (await navigator.storage.getDirectory()).getDirectoryHandle(CACHE, { create: true });
  const entry = await cache.getDirectoryHandle(await hex(pathKey(note.path)), { create: true });
  try {
    const cached = await (await entry.getFileHandle(key)).getFile();
    thumbnailStats.hits++;
    return cached;
  } catch (e) {
    if (!notFound(e)) throw e;
  }

  const assets: { path: string; bytes: Bytes }[] = [];
  for (const i of images) {
    const asset = await store.read([...note.path, ...i.path.split("/")]);
    if (asset) assets.push({ path: i.path, bytes: asset });
  }
  const png = render(engine, json, { path: first, bytes }, assets);
  thumbnailStats.renders++;
  for await (const old of entry.keys()) await entry.removeEntry(old);
  const writable = await (await entry.getFileHandle(key, { create: true })).createWritable();
  await writable.write(png);
  await writable.close();
  return new Blob([png], { type: "image/png" });
}

// The thumbnail of `note`'s page 1, or null for a note without one. Requests
// for one note while its thumbnail loads share the load.
export function noteThumbnail(engine: Engine, store: Store, note: Note): Promise<Blob | null> {
  const id = `${pathKey(note.path)}@${note.modified}`;
  let request = pending.get(id);
  if (!request) {
    request = load(engine, store, note)
      .then((blob) => {
        if (blob) shown.set(pathKey(note.path), blob);
        else shown.delete(pathKey(note.path));
        return blob;
      })
      .finally(() => pending.delete(id));
    pending.set(id, request);
  }
  return request;
}
