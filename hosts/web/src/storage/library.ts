// The library view of the notes root (docs/specs/tablet-ui.md, "Relation to
// the current model"): a folder is a directory without notebook.json, a note
// is a notebook directory (docs/FORMAT.md). Notes at the top level form the
// "My Notes" group. Dot directories (.templates, .trash, ...) are not folders.
import type { Entry, Path, Store } from "./store.ts";

export interface Note {
  // Path segments from the root, the note's own directory last.
  path: string[];
  name: string;
  template: string;
  // Latest modification of notebook.json and the page files, ms since epoch.
  modified: number;
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

async function readNote(store: Store, path: string[], json: Entry): Promise<Note> {
  const bytes = await store.read([...path, "notebook.json"]);
  const { template } = JSON.parse(new TextDecoder().decode(bytes ?? new Uint8Array())) as { template?: string };
  let modified = json.modified;
  for (const entry of (await store.list([...path, "pages"])) ?? []) {
    if (entry.kind === "file") modified = Math.max(modified, entry.modified);
  }
  return { path, name: path[path.length - 1], template: template ?? "blank", modified };
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

// Visits the directories under `dir`: `onNote` for each notebook; each other
// directory is visited in turn when `enter` accepts it.
async function walk(store: Store, dir: string[], onNote: (note: Note) => void, enter: (path: string[]) => boolean): Promise<void> {
  for (const entry of (await store.list(dir)) ?? []) {
    if (entry.kind !== "directory") continue;
    const path = [...dir, entry.name];
    const json = await store.stat([...path, "notebook.json"]);
    if (json?.kind === "file") onNote(await readNote(store, path, json));
    else if (enter(path)) await walk(store, path, onNote, enter);
  }
}

// Every folder under the root, nested ones included, with its notes. "My
// Notes" comes first, then the folders by path.
export async function scanLibrary(store: Store): Promise<Folder[]> {
  const notes = new Map<string, Note[]>([["", []]]);
  await walk(
    store,
    [],
    (note) => notes.get(pathKey(note.path.slice(0, -1)))!.push(note),
    (path) => {
      if (path[path.length - 1].startsWith(".")) return false;
      notes.set(pathKey(path), []);
      return true;
    },
  );
  const folders = [...notes].map(([key, list]) => folder(key ? key.split("/") : [], list));
  return folders.sort((a, b) => (a.path.length === 0 ? -1 : b.path.length === 0 ? 1 : a.name.localeCompare(b.name)));
}

export const TRASH = ".trash";

// The notes moved to Notes/.trash/ (docs/FORMAT.md, Layout), those inside a
// trashed folder included, most recently modified first.
export async function scanTrash(store: Store): Promise<Note[]> {
  const notes: Note[] = [];
  await walk(store, [TRASH], (note) => notes.push(note), () => true);
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
export async function entryNames(store: Store, path: Path): Promise<string[]> {
  return ((await store.list(path)) ?? []).map((e) => e.name);
}

export async function createFolder(store: Store, parent: Path, name: string): Promise<string[]> {
  const error = nameError(name, await entryNames(store, parent));
  if (error) throw new Error(error);
  const path = [...parent, name.trim()];
  await store.makeDirectory(path);
  return path;
}

// Moves the notebook or folder at `from` into folder `toParent` as `name`: a
// rename when the parent is the same. Returns the new path. Follows Write's
// DocumentList::renameItem and pasteItem (documentlist.cpp:567-592,
// 648-681): the target must not exist, and a move into the same folder
// under the same name does nothing.
export async function moveEntry(store: Store, from: Path, toParent: Path, name: string): Promise<string[]> {
  const to = [...toParent, name.trim()];
  if (pathKey(to) === pathKey(from)) return to;
  if (toParent.length >= from.length && from.every((part, i) => toParent[i] === part)) {
    throw new Error("A folder cannot move into itself.");
  }
  const error = nameError(name, await entryNames(store, toParent));
  if (error) throw new Error(error);
  await store.move(from, to);
  return to;
}

// Moves the notebook or folder at `path` into Notes/.trash/, where any file
// manager can restore it, keeping its name; a name already in the trash gets
// " 2", " 3", ... appended.
export async function moveToTrash(store: Store, path: Path): Promise<void> {
  await store.makeDirectory([TRASH]);
  const taken = new Set(await entryNames(store, [TRASH]));
  const name = path[path.length - 1];
  let target = name;
  for (let i = 2; taken.has(target); i++) target = `${name} ${i}`;
  await moveEntry(store, path, [TRASH], target);
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
