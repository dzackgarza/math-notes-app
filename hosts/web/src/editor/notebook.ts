// A notebook open in the engine, and its saving: the files that
// ink_document_dirty_files returns, written 1 s after the last committed edit.
import type { Engine, FileChange, InkDocument, NotebookFile } from "../engine/engine.ts";
import { EngineError, Status } from "../engine/engine.ts";
import { ensureTemplates, type NotebookFiles, readNotebook, readTemplatePage, writeFiles } from "../storage/folder.ts";
import type { Path, Store } from "../storage/store.ts";
import { imagePaths } from "../storage/thumbnails.ts";

export const SAVE_DELAY_MS = 1000;

export interface OpenNotebook {
  engine: Engine;
  document: InkDocument;
  // The notes root and the notebook's saver; null for a notebook opened
  // read-only from a URL.
  storage: { store: Store; saver: Saver } | null;
  // The template new pages copy (notebook.json "template").
  template: string;
  // Path segments from the root, the notebook directory last.
  path: string[];
  name: string;
}

export class Saver {
  private readonly document: InkDocument;
  private readonly store: Store;
  private readonly dir: Path;
  // Changes taken from the engine and not yet written, newest per path.
  private readonly pending = new Map<string, FileChange>();
  private timer: ReturnType<typeof setTimeout> | undefined;
  private writing: Promise<void> = Promise.resolve();

  constructor(document: InkDocument, store: Store, dir: Path) {
    this.document = document;
    this.store = store;
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
      await writeFiles(this.store, this.dir, changes);
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
export async function applyTemplate(store: Store, document: InkDocument, name: string): Promise<void> {
  const page1 = await readTemplatePage(store, name);
  if (page1) document.setTemplate(name, page1);
}

// A new notebook directory `name` in folder `parent`, with template `template`.
export async function createNotebook(
  engine: Engine,
  store: Store,
  parent: readonly string[],
  name: string,
  template: string,
): Promise<OpenNotebook> {
  await ensureTemplates(store, engine);
  const path = [...parent, name];
  const page1 = await readTemplatePage(store, template);
  if (!page1) throw new Error(`template ${template} has no pages/0001.svg`);
  const document = engine.createDocumentFromTemplate(randomSeed(), template, page1);
  const saver = new Saver(document, store, path);
  await saver.save();
  return { engine, document, storage: { store, saver }, template, path, name };
}

// The engine document of a notebook's files.
function loadDocument(engine: Engine, files: NotebookFiles): InkDocument {
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
  return document;
}

const templateOf = (json: Uint8Array) => (JSON.parse(new TextDecoder().decode(json)) as { template?: string }).template;

export async function openNotebook(engine: Engine, store: Store, path: readonly string[]): Promise<OpenNotebook> {
  await ensureTemplates(store, engine);
  const files = await readNotebook(store, path);
  const document = loadDocument(engine, files);
  const template = templateOf(files.notebookJson);
  if (template) await applyTemplate(store, document, template);
  return {
    engine,
    document,
    storage: { store, saver: new Saver(document, store, path) },
    template: template ?? "blank",
    path: [...path],
    name: path[path.length - 1],
  };
}

async function fetchBytes(url: URL): Promise<Uint8Array<ArrayBuffer>> {
  const response = await fetch(url);
  if (!response.ok) throw new Error(`${url}: ${response.status} ${response.statusText}`);
  return new Uint8Array(await response.arrayBuffer());
}

// A notebook on a static web server, opened read-only by the URL of its
// notebook.json (docs/FORMAT.md, Access per host). A static server lists no
// directories, so the notebook is the pages that notebook.json lists, each
// loaded relative to that URL, and the images those pages show.
export async function openPublishedNotebook(engine: Engine, url: string): Promise<OpenNotebook> {
  const base = new URL(url, location.href);
  const notebookJson = await fetchBytes(base);
  const { pages = [] } = JSON.parse(new TextDecoder().decode(notebookJson)) as { pages?: { file: string }[] };
  const files: NotebookFile[] = await Promise.all(pages.map(async ({ file }) => ({ path: file, bytes: await fetchBytes(new URL(file, base)) })));
  const images = new Set(files.flatMap((page) => imagePaths(page.path, new TextDecoder().decode(page.bytes))));
  const assets = await Promise.all([...images].map(async (path) => ({ path, bytes: await fetchBytes(new URL(path, base)) })));
  const document = loadDocument(engine, { notebookJson, pages: files, assets });
  const name = decodeURIComponent(base.pathname.split("/").slice(-2, -1)[0] ?? "") || base.hostname;
  return { engine, document, storage: null, template: templateOf(notebookJson) ?? "blank", path: [name], name };
}
