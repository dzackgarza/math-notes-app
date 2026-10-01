import type { Engine, FileChange, InkDocument } from "../engine/engine.ts";
import { EngineError, Status } from "../engine/engine.ts";
import { files, readNotebook, writeFiles, type NotebookFiles } from "./folder.ts";

interface NotebookIndex {
  pages: { id: string; file: string }[];
  layers: { id: string; name: string; hidden: boolean; locked: boolean }[];
}

export interface ConflictName { original: string; copy: string; provider: string }
export interface NoteConflict extends ConflictName {
  originalBytes: Uint8Array<ArrayBuffer> | null;
  copyBytes: Uint8Array<ArrayBuffer>;
  left: Uint8Array<ArrayBuffer> | null;
  right: Uint8Array<ArrayBuffer> | null;
  leftSummary: string;
  rightSummary: string;
  notebook: boolean;
  page: boolean;
}

const decode = (bytes: Uint8Array): NotebookIndex => JSON.parse(new TextDecoder().decode(bytes)) as NotebookIndex;

// FORMAT.md adopts the provider-independent prefix rule; provider names label
// the copies, following Nextcloud utility.cpp and Syncthing folder_sendrecv.go.
function provider(name: string): string {
  if (name.includes("math-notes conflict")) return "Math Notes";
  if (name.includes(".sync-conflict-")) return "Syncthing";
  if (name.includes("'s conflicted copy")) return "Dropbox";
  if (name.includes("conflicted copy") || name.includes("case clash from")) return "Nextcloud";
  if (/ \(\d+\)\./.test(name)) return "Google Drive";
  if (/ \d+\./.test(name)) return "iCloud Drive";
  if (/^[^-]+-.+\./.test(name)) return "OneDrive";
  return "Unlisted version";
}

export async function conflictNames(dir: FileSystemDirectoryHandle, pages: { file: string }[]): Promise<ConflictName[]> {
  const result: ConflictName[] = [];
  const listed = new Set(pages.map((page) => page.file));
  const pageDir = await dir.getDirectoryHandle("pages");
  for await (const [name, handle] of pageDir.entries()) {
    const copy = `pages/${name}`;
    if (handle.kind !== "file" || !name.endsWith(".svg") || listed.has(copy)) continue;
    const original = pages.find((page) => copy.startsWith(page.file.slice(0, -4)));
    if (original) result.push({ original: original.file, copy, provider: provider(name) });
  }
  for await (const [name, handle] of dir.entries()) {
    if (handle.kind === "file" && name !== "notebook.json" && name.startsWith("notebook") && name.endsWith(".json")) {
      result.push({ original: "notebook.json", copy: name, provider: provider(name) });
    }
  }
  try {
    const assets = await dir.getDirectoryHandle("assets");
    for await (const [name, handle] of assets.entries()) {
      const match = /^(.*?) \(math-notes conflict .*\)(\.[^.]+)$/.exec(name);
      if (handle.kind === "file" && match) result.push({ original: `assets/${match[1]}${match[2]}`, copy: `assets/${name}`, provider: "Math Notes" });
    }
  } catch (error) {
    if (!(error instanceof DOMException && error.name === "NotFoundError")) throw error;
  }
  return result;
}

async function readFile(dir: FileSystemDirectoryHandle, path: string): Promise<Uint8Array<ArrayBuffer>> {
  const parts = path.split("/");
  for (const part of parts.slice(0, -1)) dir = await dir.getDirectoryHandle(part);
  return new Uint8Array(await (await (await dir.getFileHandle(parts.at(-1)!)).getFile()).arrayBuffer());
}

async function readCurrentFile(dir: FileSystemDirectoryHandle, path: string): Promise<Uint8Array<ArrayBuffer> | null> {
  try { return await readFile(dir, path); }
  catch (error) {
    if (error instanceof DOMException && error.name === "NotFoundError") return null;
    throw error;
  }
}

function load(engine: Engine, files: NotebookFiles, conflict?: ConflictName, copy?: Uint8Array): InkDocument {
  const doc = engine.createDocument(crypto.getRandomValues(new BigUint64Array(1))[0]);
  try {
    doc.loadNotebook(conflict?.original === "notebook.json" ? copy! : files.notebookJson);
    for (const page of files.pages) {
      try { doc.loadPage(page.path, page.path === conflict?.original ? copy! : page.bytes); }
      catch (error) { if (!(error instanceof EngineError && error.status === Status.parse)) throw error; }
    }
    if (conflict?.original.startsWith("pages/") && !files.pages.some(page => page.path === conflict.original)) {
      doc.loadPage(conflict.original, copy!);
    }
    for (const asset of files.assets) doc.loadAsset(asset.path, asset.bytes);
    doc.markSaved();
    return doc;
  } catch (error) {
    doc.free();
    throw error;
  }
}

// The count alone, for a menu that shows the comparison only when it exists.
export async function conflictCount(dir: FileSystemDirectoryHandle): Promise<number> {
  return (await conflictNames(dir, decode(await readFile(dir, "notebook.json")).pages)).length;
}

export async function noteConflicts(engine: Engine, dir: FileSystemDirectoryHandle): Promise<NoteConflict[]> {
  const files = await readNotebook(dir);
  const index = decode(files.notebookJson);
  const result: NoteConflict[] = [];
  for (const name of await conflictNames(dir, index.pages)) {
    const originalBytes = await readCurrentFile(dir, name.original);
    const copyBytes = await readFile(dir, name.copy);
    const notebook = name.original === "notebook.json";
    const page = name.original.startsWith("pages/");
    const preview = (replacement: boolean): { image: Uint8Array<ArrayBuffer> | null; summary: string } => {
      try {
        if (!replacement && originalBytes === null) return { image: null, summary: "This file was deleted outside Math Notes." };
        if (!notebook && !page) {
          const bytes = replacement ? copyBytes : originalBytes!;
          return /\.(png|jpe?g)$/i.test(name.original)
            ? { image: bytes, summary: name.original }
            : { image: null, summary: new TextDecoder().decode(bytes) };
        }
        if (notebook) {
          const value = decode(replacement ? copyBytes : originalBytes!);
          return { image: null, summary: `Pages\n${value.pages.map((p) => p.file).join("\n")}\n\nLayers\n${value.layers.map((l) => `${l.name}${l.hidden ? " (hidden)" : ""}${l.locked ? " (locked)" : ""}`).join("\n")}` };
        }
        const doc = load(engine, files, replacement ? name : undefined, copyBytes);
        try {
          return { image: doc.pagePng(index.pages.findIndex((page) => page.file === name.original), 1000), summary: replacement ? name.copy : name.original };
        } finally { doc.free(); }
      } catch (error) { return { image: null, summary: String(error) }; }
    };
    const left = preview(false), right = preview(true);
    result.push({ ...name, originalBytes, copyBytes, notebook, page, left: left.image, right: right.image, leftSummary: left.summary, rightSummary: right.summary });
  }
  return result;
}

function same(a: Uint8Array | null, b: Uint8Array | null): boolean {
  if (a === null || b === null) return a === b;
  return a.length === b.length && a.every((value, index) => value === b[index]);
}

export async function resolveConflict(engine: Engine, dir: FileSystemDirectoryHandle, conflict: NoteConflict, choice: "original" | "copy" | "both"): Promise<void> {
  await files(async () => {
    if (!same(await readCurrentFile(dir, conflict.original), conflict.originalBytes) || !same(await readFile(dir, conflict.copy), conflict.copyBytes)) {
      throw new Error("A version changed during comparison. Reopen the conflict before choosing.");
    }
    let changes: FileChange[] = [];
    if (choice === "original" && conflict.originalBytes === null && conflict.page) {
      const files = await readNotebook(dir);
      const doc = load(engine, files);
      try {
        const index = decode(files.notebookJson).pages.findIndex(page => page.file === conflict.original);
        if (index >= 0) doc.deletePage(index);
        changes = doc.dirtyFiles();
      } finally { doc.free(); }
    }
    if (choice === "copy") {
      const files = await readNotebook(dir);
      const doc = load(engine, files);
      try {
        if (conflict.notebook) doc.loadNotebook(conflict.copyBytes);
        else if (conflict.page) doc.loadPage(conflict.original, conflict.copyBytes);
      } finally { doc.free(); }
      changes = [{ kind: "write", path: conflict.original, bytes: conflict.copyBytes }];
    }
    if (choice === "both") {
      if (conflict.originalBytes === null) throw new Error("Restore the conflict copy or keep the deletion.");
      if (!conflict.page) throw new Error("Choose one version of this file.");
      const files = await readNotebook(dir);
      const doc = load(engine, files);
      try {
        doc.importPageSvg(decode(files.notebookJson).pages.findIndex((page) => page.file === conflict.original) + 1, conflict.copyBytes);
        changes = doc.dirtyFiles();
      } finally { doc.free(); }
    }
    // Publish assets and pages before the index; remove only the selected copy
    // after all retained content has been written.
    changes.sort((a, b) => Number(a.path === "notebook.json") - Number(b.path === "notebook.json"));
    await writeFiles(dir, changes);
    await writeFiles(dir, [{ kind: "delete", path: conflict.copy }]);
  });
}
