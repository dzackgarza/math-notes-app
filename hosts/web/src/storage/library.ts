// The library view of the notes root (docs/specs/tablet-ui.md, "Relation to
// the current model"): a folder is a directory without notebook.json, a note
// is a notebook directory (docs/FORMAT.md). Notes at the top level form the
// "My Notes" group. Dot directories (.templates, .trash, ...) are not folders.

import { conflictNames } from "./conflicts.ts";

export interface Note {
  // Path segments from the root, the note's own directory last.
  path: string[];
  name: string;
  template: string;
  // Latest lastModified of notebook.json and the page files, ms since epoch.
  modified: number;
  conflicts: number;
}

export interface Folder {
  // Path segments from the root; [] for the "My Notes" group.
  path: string[];
  name: string;
  notes: Note[];
  // The latest note modification, or 0 for an empty folder.
  modified: number;
}

export const MY_NOTES = "My Notes";

export const pathKey = (path: readonly string[]): string => path.join("/");

export async function directoryAt(root: FileSystemDirectoryHandle, path: readonly string[]): Promise<FileSystemDirectoryHandle> {
  let dir = root;
  for (const part of path) dir = await dir.getDirectoryHandle(part);
  return dir;
}

async function fileIfPresent(dir: FileSystemDirectoryHandle, name: string): Promise<File | null> {
  try {
    return await (await dir.getFileHandle(name)).getFile();
  } catch (e) {
    if (e instanceof DOMException && (e.name === "NotFoundError" || e.name === "TypeMismatchError")) return null;
    throw e;
  }
}

async function readNote(dir: FileSystemDirectoryHandle, path: string[], json: File): Promise<Note> {
  const { template, pages } = JSON.parse(await json.text()) as { template?: string; pages: { file: string }[] };
  let modified = json.lastModified;
  try {
    for await (const [, handle] of (await dir.getDirectoryHandle("pages")).entries()) {
      if (handle.kind === "file") modified = Math.max(modified, (await handle.getFile()).lastModified);
    }
  } catch (e) {
    if (!(e instanceof DOMException && e.name === "NotFoundError")) throw e;
  }
  const conflicts = (await conflictNames(dir, pages)).length;
  return { path, name: path[path.length - 1], template: template ?? "blank", modified, conflicts };
}

function folder(path: string[], notes: Note[]): Folder {
  notes.sort((a, b) => a.name.localeCompare(b.name));
  return {
    path,
    name: path.length === 0 ? MY_NOTES : path.join(" / "),
    notes,
    modified: Math.max(0, ...notes.map((n) => n.modified)),
  };
}

// Every folder under `root`, nested ones included, with its notes. "My Notes"
// comes first, then the folders by path.
export async function scanLibrary(root: FileSystemDirectoryHandle): Promise<Folder[]> {
  const folders: Folder[] = [];
  const visit = async (dir: FileSystemDirectoryHandle, path: string[]): Promise<void> => {
    const notes: Note[] = [];
    for await (const [name, handle] of dir.entries()) {
      if (handle.kind !== "directory" || name.startsWith(".")) continue;
      const json = await fileIfPresent(handle, "notebook.json");
      if (json) notes.push(await readNote(handle, [...path, name], json));
      else await visit(handle, [...path, name]);
    }
    folders.push(folder(path, notes));
  };
  await visit(root, []);
  return folders.sort((a, b) => (a.path.length === 0 ? -1 : b.path.length === 0 ? 1 : a.name.localeCompare(b.name)));
}

export const TRASH = ".trash";

// The notes moved to Notes/.trash/ (docs/FORMAT.md, Layout), those inside a
// trashed folder included, most recently modified first.
export async function scanTrash(root: FileSystemDirectoryHandle): Promise<Note[]> {
  let trash: FileSystemDirectoryHandle;
  try {
    trash = await root.getDirectoryHandle(TRASH);
  } catch (e) {
    if (e instanceof DOMException && e.name === "NotFoundError") return [];
    throw e;
  }
  const notes: Note[] = [];
  const visit = async (dir: FileSystemDirectoryHandle, path: string[]): Promise<void> => {
    for await (const [name, handle] of dir.entries()) {
      if (handle.kind !== "directory") continue;
      const json = await fileIfPresent(handle, "notebook.json");
      if (json) notes.push(await readNote(handle, [...path, name], json));
      else await visit(handle, [...path, name]);
    }
  };
  await visit(trash, [TRASH]);
  return notes.sort((a, b) => b.modified - a.modified);
}

// Why `name` cannot name a new entry of a directory holding `siblings`, or
// null when it can. Follows Write's NewDocDialog name check
// (syncscribble/documentlist.cpp:836-854, styluslabs/Write 401b65d): empty,
// "/" or an existing name is refused. A leading "." is refused too: the scan
// skips dot entries, as Write's list does (documentlist.cpp:418).
export function nameError(name: string, siblings: readonly string[]): string | null {
  const trimmed = name.trim();
  if (!trimmed) return "Enter a name.";
  if (trimmed.includes("/") || trimmed.includes("\\")) return "A name cannot contain / or \\.";
  if (trimmed.startsWith(".")) return "A name cannot start with a dot.";
  if (siblings.includes(trimmed)) return `“${trimmed}” already exists here.`;
  return null;
}

// The names in the directory at `path`.
export async function entryNames(root: FileSystemDirectoryHandle, path: readonly string[]): Promise<string[]> {
  const names: string[] = [];
  for await (const name of (await directoryAt(root, path)).keys()) names.push(name);
  return names;
}

export async function createFolder(root: FileSystemDirectoryHandle, parent: readonly string[], name: string): Promise<string[]> {
  const error = nameError(name, await entryNames(root, parent));
  if (error) throw new Error(error);
  await (await directoryAt(root, parent)).getDirectoryHandle(name.trim(), { create: true });
  return [...parent, name.trim()];
}

// Copies directory `source` with its contents to a new directory `name` in
// `parent`. File System Access has no directory move outside the
// origin-private file system (FileSystemHandle.move moves files only), so a
// move is this copy, then the removal of the source.
async function copyDirectory(source: FileSystemDirectoryHandle, parent: FileSystemDirectoryHandle, name: string): Promise<void> {
  const target = await parent.getDirectoryHandle(name, { create: true });
  for await (const [entry, handle] of source.entries()) {
    if (handle.kind === "directory") {
      await copyDirectory(handle, target, entry);
      continue;
    }
    const writable = await (await target.getFileHandle(entry, { create: true })).createWritable();
    await writable.write(await handle.getFile());
    await writable.close();
  }
}

// Moves the notebook or folder at `from` into folder `toParent` as `name`: a
// rename when the parent is the same. Returns the new path. Follows Write's
// DocumentList::renameItem and pasteItem (documentlist.cpp:567-592,
// 648-681): the target must not exist, and a move into the same folder
// under the same name does nothing.
export async function moveEntry(
  root: FileSystemDirectoryHandle,
  from: readonly string[],
  toParent: readonly string[],
  name: string,
): Promise<string[]> {
  const to = [...toParent, name.trim()];
  if (pathKey(to) === pathKey(from)) return to;
  if (toParent.length >= from.length && from.every((part, i) => toParent[i] === part)) {
    throw new Error("A folder cannot move into itself.");
  }
  const error = nameError(name, await entryNames(root, toParent));
  if (error) throw new Error(error);
  const source = await directoryAt(root, from);
  await copyDirectory(source, await directoryAt(root, toParent), name.trim());
  await (await directoryAt(root, from.slice(0, -1))).removeEntry(from[from.length - 1], { recursive: true });
  return to;
}

// Moves the notebook or folder at `path` into Notes/.trash/, where any file
// manager can restore it, keeping its name; a name already in the trash gets
// " 2", " 3", ... appended.
export async function moveToTrash(root: FileSystemDirectoryHandle, path: readonly string[]): Promise<string[]> {
  await root.getDirectoryHandle(TRASH, { create: true });
  const taken = new Set(await entryNames(root, [TRASH]));
  const name = path[path.length - 1];
  let target = name;
  for (let i = 2; taken.has(target); i++) target = `${name} ${i}`;
  return moveEntry(root, path, [TRASH], target);
}

export type Sort = "modified" | "name";

// The library's orders, as Write's list sorts (documentlist.cpp:438-449): by
// name, case-insensitively, or most recently modified first, with the name
// breaking ties and ordering entries without a modification time.
export function compareBy(sort: Sort): (a: { name: string; modified: number }, b: { name: string; modified: number }) => number {
  const byName = (a: { name: string }, b: { name: string }) => a.name.localeCompare(b.name, undefined, { sensitivity: "base" });
  if (sort === "name") return byName;
  return (a, b) => (a.modified > 0 && b.modified > 0 && a.modified !== b.modified ? b.modified - a.modified : byName(a, b));
}
