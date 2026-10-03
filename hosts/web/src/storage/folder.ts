// The notes folder in Chromium: a directory handle from the File System
// Access API, kept in IndexedDB so it survives reloads. Follows Chrome's
// articles "The File System Access API" and "Persistent permissions for the
// File System Access API". A notebook is a subdirectory with notebook.json
// (docs/FORMAT.md).
import { get, set } from "idb-keyval";

import type { Engine, FileChange, NotebookFile } from "../engine/engine.ts";

const ROOT_KEY = "notes-root";

// Every read and write of the notes folder goes through this Web Locks
// queue (https://w3c.github.io/web-locks/). A writer runs alone; readers
// share the lock with each other, so no reader sees a file that a writer has
// created but not yet closed. Web Locks are not reentrant: `task` must not
// call `files` again.
export async function files<T>(task: () => Promise<T>, mode: LockMode = "exclusive"): Promise<T> {
  return await navigator.locks.request("math-notes-files", { mode }, task);
}

export async function pickRoot(): Promise<FileSystemDirectoryHandle> {
  const root = await window.showDirectoryPicker({ id: "notes", mode: "readwrite" });
  await set(ROOT_KEY, root);
  return root;
}

// The folder chosen before, if any.
export async function savedRoot(): Promise<FileSystemDirectoryHandle | undefined> {
  return get<FileSystemDirectoryHandle>(ROOT_KEY);
}

export async function hasPermission(root: FileSystemDirectoryHandle): Promise<boolean> {
  return (await root.queryPermission({ mode: "readwrite" })) === "granted";
}

// Needs a user gesture: call it from a click.
export async function requestPermission(root: FileSystemDirectoryHandle): Promise<boolean> {
  return (await root.requestPermission({ mode: "readwrite" })) === "granted";
}

// Calls `changed` when a file under the notes folder changes, whether this app
// or another program (for example a sync client) changed it.
export async function watchRoot(root: FileSystemDirectoryHandle, changed: () => void): Promise<FileSystemObserver> {
  const observer = new FileSystemObserver(changed);
  await observer.observe(root, { recursive: true });
  return observer;
}

export async function listNotebooks(root: FileSystemDirectoryHandle): Promise<string[]> {
  const names: string[] = [];
  for await (const [name, handle] of root.entries()) {
    if (handle.kind !== "directory") continue;
    try {
      await handle.getFileHandle("notebook.json");
      names.push(name);
    } catch {
      // A directory without notebook.json is not a notebook.
    }
  }
  return names.sort();
}

export interface NotebookFiles {
  notebookJson: Uint8Array<ArrayBuffer>;
  pages: NotebookFile[];
  assets: NotebookFile[];
}

async function readDirectory(dir: FileSystemDirectoryHandle, prefix: string): Promise<NotebookFile[]> {
  const files: NotebookFile[] = [];
  for await (const [name, handle] of dir.entries()) {
    if (handle.kind !== "file") continue;
    const file = await handle.getFile();
    files.push({ path: `${prefix}/${name}`, bytes: new Uint8Array(await file.arrayBuffer()) });
  }
  return files;
}

async function subdirectory(dir: FileSystemDirectoryHandle, name: string): Promise<FileSystemDirectoryHandle | null> {
  try {
    return await dir.getDirectoryHandle(name);
  } catch {
    return null;
  }
}

export async function readNotebook(dir: FileSystemDirectoryHandle, recoveredIndex?: Uint8Array<ArrayBuffer>): Promise<NotebookFiles> {
  const notebookJson = recoveredIndex ?? new Uint8Array(await (await (await dir.getFileHandle("notebook.json")).getFile()).arrayBuffer());
  const pages = await subdirectory(dir, "pages");
  const assets = await subdirectory(dir, "assets");
  return {
    notebookJson,
    pages: pages ? (await readDirectory(pages, "pages")).filter((f) => f.path.endsWith(".svg")) : [],
    assets: assets ? await readDirectory(assets, "assets") : [],
  };
}

// Chromium's exclusive writer: no other writer of the file while this one is
// open. Not yet in the File System Access type definitions.
type ExclusiveWritableOptions = FileSystemCreateWritableOptions & { mode: "exclusive" };

// Writes or deletes each file under `dir`, creating directories on the way.
export async function writeFiles(dir: FileSystemDirectoryHandle, files: readonly FileChange[]): Promise<void> {
  for (const file of files) {
    const parts = file.path.split("/");
    let parent = dir;
    for (const part of parts.slice(0, -1)) parent = await parent.getDirectoryHandle(part, { create: true });
    if (file.kind === "delete") {
      await parent.removeEntry(parts[parts.length - 1]).catch((e: unknown) => {
        if (!(e instanceof DOMException && e.name === "NotFoundError")) throw e;
      });
      continue;
    }
    const handle = await parent.getFileHandle(parts[parts.length - 1], { create: true });
    const options: ExclusiveWritableOptions = { keepExistingData: false, mode: "exclusive" };
    const writable = await handle.createWritable(options);
    await writable.write(file.bytes);
    await writable.close();
  }
}

const TEMPLATES = ".templates";

// Creates Notes/.templates/<name>/ for each built-in template that is
// missing (docs/FORMAT.md, Other files).
export async function ensureTemplates(root: FileSystemDirectoryHandle, engine: Engine): Promise<void> {
  const templates = await root.getDirectoryHandle(TEMPLATES, { create: true });
  for (const name of engine.builtinTemplates()) {
    if (await subdirectory(templates, name)) continue;
    const document = engine.createBuiltinTemplate(name, 1n);
    try {
      await writeFiles(await templates.getDirectoryHandle(name, { create: true }), document.dirtyFiles());
    } finally {
      document.free();
    }
  }
}

export async function listTemplates(root: FileSystemDirectoryHandle): Promise<string[]> {
  const templates = await subdirectory(root, TEMPLATES);
  return templates ? listNotebooks(templates) : [];
}

// Page 1 of template `name`, whose background new pages copy.
export async function readTemplatePage(root: FileSystemDirectoryHandle, name: string): Promise<Uint8Array<ArrayBuffer> | null> {
  try {
    const templates = await root.getDirectoryHandle(TEMPLATES);
    const pages = await (await templates.getDirectoryHandle(name)).getDirectoryHandle("pages");
    const file = await (await pages.getFileHandle("0001.svg")).getFile();
    return new Uint8Array(await file.arrayBuffer());
  } catch (e) {
    if (e instanceof DOMException && e.name === "NotFoundError") return null;
    throw e;
  }
}
