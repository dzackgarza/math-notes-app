// The notes folder: which store holds it, kept in IndexedDB so it survives
// reloads, and the notebook files in it. A notebook is a directory with
// notebook.json (docs/FORMAT.md).
import { del, get, set } from "idb-keyval";

import type { Engine, FileChange, NotebookFile } from "../engine/engine.ts";
import { type Bytes, FolderStore, type Path, type Store, SWAP_SUFFIX, WebDavStore } from "./store.ts";

const ROOT_KEY = "notes-root";
const WEBDAV_KEY = "notes-webdav";

// Chromium only: the File System Access folder picker.
export const canPickFolder = (): boolean => "showDirectoryPicker" in window;

export async function pickRoot(): Promise<FolderStore> {
  const root = await window.showDirectoryPicker({ id: "notes", mode: "readwrite" });
  await set(ROOT_KEY, root);
  await del(WEBDAV_KEY);
  return new FolderStore(root);
}

// Connects to the WebDAV server at `url`: a listing of the root checks that
// it answers and allows this origin.
export async function connectWebDav(url: string): Promise<WebDavStore> {
  const store = new WebDavStore(url);
  if (!(await store.list([]))) throw new Error(`${url} has no root directory`);
  await set(WEBDAV_KEY, url);
  await del(ROOT_KEY);
  return store;
}

export type SavedRoot = { kind: "folder"; handle: FileSystemDirectoryHandle } | { kind: "webdav"; url: string };

// The notes folder chosen before, if any.
export async function savedRoot(): Promise<SavedRoot | undefined> {
  const url = await get<string>(WEBDAV_KEY);
  if (url) return { kind: "webdav", url };
  const handle = await get<FileSystemDirectoryHandle>(ROOT_KEY);
  return handle ? { kind: "folder", handle } : undefined;
}

export async function hasPermission(root: FileSystemDirectoryHandle): Promise<boolean> {
  return (await root.queryPermission({ mode: "readwrite" })) === "granted";
}

// Needs a user gesture: call it from a click.
export async function requestPermission(root: FileSystemDirectoryHandle): Promise<boolean> {
  return (await root.requestPermission({ mode: "readwrite" })) === "granted";
}

export interface NotebookFiles {
  notebookJson: Bytes;
  pages: NotebookFile[];
  assets: NotebookFile[];
}

// The files of directory `sub` of notebook `dir`, without swap files.
async function readDirectory(store: Store, dir: Path, sub: string): Promise<NotebookFile[]> {
  const files: NotebookFile[] = [];
  for (const entry of (await store.list([...dir, sub])) ?? []) {
    if (entry.kind !== "file" || entry.name.endsWith(SWAP_SUFFIX)) continue;
    const bytes = await store.read([...dir, sub, entry.name]);
    if (bytes) files.push({ path: `${sub}/${entry.name}`, bytes });
  }
  return files;
}

export async function readNotebook(store: Store, dir: Path): Promise<NotebookFiles> {
  const json = await store.read([...dir, "notebook.json"]);
  if (!json) throw new Error(`${dir.join("/")} has no notebook.json`);
  return {
    notebookJson: json,
    pages: (await readDirectory(store, dir, "pages")).filter((f) => f.path.endsWith(".svg")),
    assets: await readDirectory(store, dir, "assets"),
  };
}

// Writes or deletes each file under `dir`.
export async function writeFiles(store: Store, dir: Path, files: readonly FileChange[]): Promise<void> {
  for (const file of files) {
    const path = [...dir, ...file.path.split("/")];
    if (file.kind === "delete") await store.remove(path);
    else await store.write(path, file.bytes);
  }
}

const TEMPLATES = ".templates";

// The notebook directories directly in `dir`, by name.
export async function listNotebooks(store: Store, dir: Path): Promise<string[]> {
  const names: string[] = [];
  for (const entry of (await store.list(dir)) ?? []) {
    if (entry.kind === "directory" && (await store.stat([...dir, entry.name, "notebook.json"]))) names.push(entry.name);
  }
  return names.sort();
}

// Creates Notes/.templates/<name>/ for each built-in template that is
// missing (docs/FORMAT.md, Other files).
export async function ensureTemplates(store: Store, engine: Engine): Promise<void> {
  const present = new Set(((await store.list([TEMPLATES])) ?? []).map((e) => e.name));
  for (const name of engine.builtinTemplates()) {
    if (present.has(name)) continue;
    const document = engine.createBuiltinTemplate(name, 1n);
    try {
      await writeFiles(store, [TEMPLATES, name], document.dirtyFiles());
    } finally {
      document.free();
    }
  }
}

export async function listTemplates(store: Store): Promise<string[]> {
  return listNotebooks(store, [TEMPLATES]);
}

// Page 1 of template `name`, whose background new pages copy.
export async function readTemplatePage(store: Store, name: string): Promise<Bytes | null> {
  return store.read([TEMPLATES, name, "pages", "0001.svg"]);
}
