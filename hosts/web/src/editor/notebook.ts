// A notebook open in the engine, and its saving: the files that
// ink_document_dirty_files returns, written 1 s after the last committed edit.
import { createStore, del, entries, set } from "idb-keyval";
import type { Engine, FileChange, InkDocument, NotebookFile } from "../engine/engine.ts";
import { EngineError, Orientation, PageSize, Status } from "../engine/engine.ts";
import { files as fileTask, readNotebook, readTemplatePage, storeTemplateForUse, writeFiles, type NotebookFiles } from "../storage/folder.ts";
import { directoryAt, entryNames, nameError } from "../storage/library.ts";
import type { OrientationSetting, PageSizeSetting } from "../storage/metadata.ts";

export const SAVE_DELAY_MS = 1000;

export interface OpenNotebook {
  engine: Engine;
  document: InkDocument;
  root: FileSystemDirectoryHandle;
  dir: FileSystemDirectoryHandle;
  // The template new pages copy (notebook.json "template").
  template: string;
  // Path segments from the root, the notebook directory last.
  path: string[];
  name: string;
  saver: Saver;
}

export type SaveState =
  | { status: "saved" | "pending" | "recoverable" | "saving" }
  | { status: "error"; message: string };

// IndexedDB owns the write-ahead checkpoint; directory handles and typed arrays
// are structured-clone values. See https://github.com/jakearchibald/idb-keyval
// and Chrome's File System Access guide (storing handles in IndexedDB).
const recoveryStore = createStore("math-notes-recovery", "notebooks");

interface Recovery {
  id: string;
  dir: FileSystemDirectoryHandle | string[];
  changes: FileChange[];
  base: NotebookFile[];
}

async function pendingRecovery(dir: FileSystemDirectoryHandle): Promise<Recovery | undefined> {
  const matches: Recovery[] = [];
  const privatePath = await (await navigator.storage.getDirectory()).resolve(dir);
  for (const [, recovery] of await entries<string, Recovery>(recoveryStore)) {
    const same = Array.isArray(recovery.dir)
      ? privatePath !== null && recovery.dir.join("/") === privatePath.join("/")
      : await recovery.dir.isSameEntry(dir);
    if (same) matches.push(recovery);
  }
  if (matches.length > 1) throw new Error("This note has pending edits from multiple browser sessions. Keep both recovery records before resolving the conflict.");
  return matches[0];
}

async function currentFile(dir: FileSystemDirectoryHandle, path: string): Promise<Uint8Array | undefined> {
  try {
    const parts = path.split("/");
    const parent = await directoryAt(dir, parts.slice(0, -1));
    return new Uint8Array(await (await (await parent.getFileHandle(parts.at(-1)!)).getFile()).arrayBuffer());
  } catch (error) {
    if (error instanceof DOMException && error.name === "NotFoundError") return undefined;
    throw error;
  }
}

function sameBytes(left: Uint8Array | undefined, right: Uint8Array | undefined): boolean {
  if (left === undefined || right === undefined) return left === right;
  return left.length === right.length && left.every((byte, index) => byte === right[index]);
}

export class Saver extends EventTarget {
  private readonly document: InkDocument;
  private readonly dir: FileSystemDirectoryHandle;
  // Changes taken from the engine and not yet written, newest per path.
  private readonly pending = new Map<string, FileChange>();
  private timer: ReturnType<typeof setTimeout> | undefined;
  private writing: Promise<void> = Promise.resolve();
  private checkpointing: Promise<void> = Promise.resolve();
  private readonly base: Map<string, Uint8Array<ArrayBuffer>>;
  private readonly recoveryId: string;
  private readonly recoveryLocation: Promise<FileSystemDirectoryHandle | string[]>;
  private revision = 0;
  private readonly conflictCopies = new Map<string, FileChange>();
  state: SaveState = { status: "saved" };

  constructor(document: InkDocument, dir: FileSystemDirectoryHandle, base: NotebookFile[], recovery?: Recovery) {
    super();
    this.document = document;
    this.dir = dir;
    this.base = new Map(base.map((file) => [file.path, file.bytes]));
    this.recoveryId = recovery?.id ?? crypto.randomUUID();
    // OPFS already has an origin-scoped root. Store its resolved path; local
    // folders need their serializable capability handle to retain identity.
    this.recoveryLocation = navigator.storage.getDirectory().then(async (root) => (await root.resolve(dir)) ?? dir);
    if (recovery) {
      for (const change of recovery.changes) {
        this.pending.set(change.path, change);
        this.base.delete(change.path);
      }
      for (const file of recovery.base) this.base.set(file.path, file.bytes);
      this.state = { status: "recoverable" };
    }
  }

  // After a committed edit: save once edits pause for SAVE_DELAY_MS.
  schedule(): void {
    this.revision++;
    this.setState({ status: "pending" });
    this.capture();
    const revision = this.revision;
    void this.checkpoint().then(() => {
      if (this.revision === revision && this.state.status === "pending") this.setState({ status: "recoverable" });
    }).catch((error) => this.failed(error));
    clearTimeout(this.timer);
    this.timer = setTimeout(() => void this.save().catch(console.error), SAVE_DELAY_MS);
  }

  private setState(state: SaveState): void {
    this.state = state;
    this.dispatchEvent(new Event("change"));
  }

  private failed(error: Error): void {
    this.setState({ status: "error", message: error.message });
  }

  private capture(): void {
    for (const change of this.document.dirtyFiles()) this.pending.set(change.path, change);
    this.document.markSaved();
  }

  private checkpoint(): Promise<void> {
    const changes = [...this.pending.values()];
    const base = [...this.base].filter(([path]) => this.pending.has(path)).map(([path, bytes]) => ({ path, bytes }));
    const write = async () => {
      const recovery: Recovery = { id: this.recoveryId, dir: await this.recoveryLocation, changes, base };
      if (changes.length) await set(this.recoveryId, recovery, recoveryStore);
      else await del(this.recoveryId, recoveryStore);
    };
    this.checkpointing = this.checkpointing.then(write, write);
    return this.checkpointing;
  }

  // Retire only the pending bytes included in an explicit comparison.
  async resolved(path: string, original: Uint8Array | null, copy: Uint8Array): Promise<void> {
    clearTimeout(this.timer);
    await this.writing.catch(() => {});
    const change = this.pending.get(path);
    if (change?.kind === "write" && (sameBytes(change.bytes, original ?? undefined) || sameBytes(change.bytes, copy))) {
      this.pending.delete(path);
    }
    await this.checkpoint();
  }

  // Takes the dirty files and marks them saved in the same task, so no edit
  // falls between; a failed write keeps them pending for the next save.
  save(): Promise<void> {
    clearTimeout(this.timer);
    this.capture();
    const revision = this.revision;
    const writePending = async () => {
      const changes = [...this.pending.values()];
      this.setState({ status: "saving" });
      try {
        await this.checkpoint();
        // Check bytes before replacement, including a retry after a partial
        // write. Chrome cannot make this check atomic with an external writer;
        // docs/FORMAT.md records that platform limit.
        const conflicts: FileChange[] = [];
        for (const change of changes) {
          const current = await currentFile(this.dir, change.path);
          const target = change.kind === "write" ? change.bytes : undefined;
          if (!sameBytes(current, this.base.get(change.path)) && !sameBytes(current, target)) {
            conflicts.push(change);
          }
        }
        if (conflicts.length) {
          const safe = changes.filter((change) => !conflicts.includes(change));
          await writeFiles(this.dir, safe);
          for (const change of safe) {
            if (change.kind === "write") this.base.set(change.path, change.bytes);
            else this.base.delete(change.path);
            if (this.pending.get(change.path) === change) this.pending.delete(change.path);
          }
          for (const change of conflicts) {
            if (change.kind !== "write" || this.conflictCopies.get(change.path) === change) continue;
            const extension = change.path.lastIndexOf(".");
            const stamp = new Date().toISOString().replaceAll(":", "");
            const path = `${change.path.slice(0, extension)} (math-notes conflict ${stamp} ${crypto.randomUUID()})${change.path.slice(extension)}`;
            await writeFiles(this.dir, [{ ...change, path }]);
            this.conflictCopies.set(change.path, change);
          }
          await this.checkpoint();
          throw new Error(`External changes in ${conflicts.map((change) => change.path).join(", ")}. Compare the conflict copies before saving.`);
        }
        await writeFiles(this.dir, changes);
      } catch (error) {
        this.setState({ status: "error", message: error instanceof Error ? error.message : String(error) });
        throw error;
      }
      for (const change of changes) {
        if (change.kind === "write") this.base.set(change.path, change.bytes);
        else this.base.delete(change.path);
        if (this.pending.get(change.path) === change) this.pending.delete(change.path);
        if (change.kind === "write") window.mathNotesWrites?.push({ path: change.path, bytes: change.bytes });
      }
      try {
        await this.checkpoint();
      } catch (error) {
        this.setState({ status: "error", message: error instanceof Error ? error.message : String(error) });
        throw error;
      }
      this.setState({ status: revision === this.revision && this.pending.size === 0 ? "saved" : "pending" });
    };
    // A new save is an explicit retry after failure. Both promise outcomes
    // serialize it behind the previous attempt; its own failure still rejects.
    const coordinated = () => fileTask(writePending);
    this.writing = this.writing.then(coordinated, coordinated);
    return this.writing;
  }
}

function randomSeed(): bigint {
  return crypto.getRandomValues(new BigUint64Array(1))[0];
}

// Gives the document template `name`, storing the template in Notes/.templates/
// when a notebook first uses it.
export async function applyTemplate(root: FileSystemDirectoryHandle, document: InkDocument, name: string): Promise<void> {
  await storeTemplateForUse(root, document.engine, name);
  document.setTemplate(name, await readTemplatePage(root, document.engine, name));
}

// A new notebook directory `name` in folder `parent`, with template `template`.
export async function createNotebook(
  engine: Engine,
  root: FileSystemDirectoryHandle,
  parent: readonly string[],
  name: string,
  template: string,
  pageSize: PageSizeSetting,
  orientation: OrientationSetting,
): Promise<OpenNotebook> {
  const title = name.trim();
  const { dir, page1 } = await fileTask(async () => {
    const error = nameError(title, await entryNames(root, parent));
    if (error) throw new Error(error);
    await storeTemplateForUse(root, engine, template);
    const dir = await (await directoryAt(root, parent)).getDirectoryHandle(title, { create: true });
    return { dir, page1: await readTemplatePage(root, engine, template) };
  });
  const document = engine.createDocumentFromTemplate(randomSeed(), template, page1, PageSize[pageSize], Orientation[orientation]);
  const saver = new Saver(document, dir, []);
  await saver.save();
  return { engine, document, root, dir, template, path: [...parent, title], name: title, saver };
}

export function openNotebook(engine: Engine, root: FileSystemDirectoryHandle, path: readonly string[]): Promise<OpenNotebook> {
  return fileTask(() => readOpenNotebook(engine, root, path), "shared");
}

async function readOpenNotebook(engine: Engine, root: FileSystemDirectoryHandle, path: readonly string[]): Promise<OpenNotebook> {
  const dir = await directoryAt(root, path);
  const name = path[path.length - 1];
  const recovery = await pendingRecovery(dir);
  let files: NotebookFiles;
  try { files = await readNotebook(dir); }
  catch (error) {
    const index = recovery?.changes.find((file) => file.path === "notebook.json" && file.kind === "write");
    if (!(error instanceof DOMException && error.name === "NotFoundError") || index?.kind !== "write") throw error;
    files = await readNotebook(dir, index.bytes);
  }
  const base = [{ path: "notebook.json", bytes: files.notebookJson }, ...files.pages, ...files.assets];
  const restored = new Map(base.map((file) => [file.path, file.bytes]));
  for (const change of recovery?.changes ?? []) {
    if (change.kind === "write") restored.set(change.path, change.bytes);
    else restored.delete(change.path);
  }
  const notebookJson = restored.get("notebook.json");
  if (!notebookJson) throw new Error("The recovered notebook has no notebook.json");
  const document = engine.createDocument(randomSeed());
  document.loadNotebook(notebookJson);
  for (const [path, bytes] of restored) {
    if (!path.startsWith("pages/")) continue;
    try {
      document.loadPage(path, bytes);
    } catch (e) {
      // A page that does not parse stays in the notebook as an error page.
      if (!(e instanceof EngineError && e.status === Status.parse)) throw e;
    }
  }
  for (const [path, bytes] of restored) if (path.startsWith("assets/")) document.loadAsset(path, bytes);
  const { template } = JSON.parse(new TextDecoder().decode(notebookJson)) as { template?: string };
  if (template) await applyTemplate(root, document, template);
  return { engine, document, root, dir, template: template ?? "blank", path: [...path], name, saver: new Saver(document, dir, base, recovery) };
}
