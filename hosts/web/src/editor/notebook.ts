// A notebook open in the engine, and its saving: the files that
// ink_document_dirty_files returns, written 1 s after the last committed edit.
import type { Engine, FileChange, InkDocument } from "../engine/engine.ts";
import { EngineError, PageSize, Status } from "../engine/engine.ts";
import { ensureTemplates, readNotebook, readTemplatePage, writeFiles } from "../storage/folder.ts";
import { directoryAt } from "../storage/library.ts";
import type { PageSizeSetting } from "../storage/metadata.ts";

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

export class Saver {
  private readonly document: InkDocument;
  private readonly dir: FileSystemDirectoryHandle;
  // Changes taken from the engine and not yet written, newest per path.
  private readonly pending = new Map<string, FileChange>();
  private timer: ReturnType<typeof setTimeout> | undefined;
  private writing: Promise<void> = Promise.resolve();

  constructor(document: InkDocument, dir: FileSystemDirectoryHandle) {
    this.document = document;
    this.dir = dir;
  }

  // After a committed edit: save once edits pause for SAVE_DELAY_MS.
  schedule(): void {
    clearTimeout(this.timer);
    this.timer = setTimeout(() => void this.save(), SAVE_DELAY_MS);
  }

  // Takes the dirty files and marks them saved in the same task, so no edit
  // falls between; a failed write keeps them pending for the next save.
  save(): Promise<void> {
    clearTimeout(this.timer);
    for (const change of this.document.dirtyFiles()) this.pending.set(change.path, change);
    this.document.markSaved();
    this.writing = this.writing.then(async () => {
      const changes = [...this.pending.values()];
      if (changes.length === 0) return;
      await writeFiles(this.dir, changes);
      for (const change of changes) {
        if (this.pending.get(change.path) === change) this.pending.delete(change.path);
        if (change.kind === "write") window.mathNotesWrites?.push({ path: change.path, bytes: change.bytes });
      }
    });
    return this.writing;
  }
}

function randomSeed(): bigint {
  return crypto.getRandomValues(new BigUint64Array(1))[0];
}

// Gives the document its template's page 1 from Notes/.templates/.
export async function applyTemplate(root: FileSystemDirectoryHandle, document: InkDocument, name: string): Promise<void> {
  const page1 = await readTemplatePage(root, name);
  if (page1) document.setTemplate(name, page1);
}

// A new notebook directory `name` in folder `parent`, with template `template`.
export async function createNotebook(
  engine: Engine,
  root: FileSystemDirectoryHandle,
  parent: readonly string[],
  name: string,
  template: string,
  pageSize: PageSizeSetting,
): Promise<OpenNotebook> {
  await ensureTemplates(root, engine);
  const dir = await (await directoryAt(root, parent)).getDirectoryHandle(name, { create: true });
  const page1 = await readTemplatePage(root, template);
  if (!page1) throw new Error(`template ${template} has no pages/0001.svg`);
  const document = engine.createDocumentFromTemplate(randomSeed(), template, page1, PageSize[pageSize]);
  const saver = new Saver(document, dir);
  await saver.save();
  return { engine, document, root, dir, template, path: [...parent, name], name, saver };
}

export async function openNotebook(engine: Engine, root: FileSystemDirectoryHandle, path: readonly string[]): Promise<OpenNotebook> {
  await ensureTemplates(root, engine);
  const dir = await directoryAt(root, path);
  const name = path[path.length - 1];
  const files = await readNotebook(dir);
  const document = engine.createDocument(randomSeed());
  document.loadNotebook(files.notebookJson);
  for (const page of files.pages) {
    try {
      document.loadPage(page.path, page.bytes);
    } catch (e) {
      // A page that does not parse stays in the notebook as an error page.
      if (!(e instanceof EngineError && e.status === Status.parse)) throw e;
    }
  }
  for (const asset of files.assets) document.loadAsset(asset.path, asset.bytes);
  const { template } = JSON.parse(new TextDecoder().decode(files.notebookJson)) as { template?: string };
  if (template) await applyTemplate(root, document, template);
  return { engine, document, root, dir, template: template ?? "blank", path: [...path], name, saver: new Saver(document, dir) };
}
