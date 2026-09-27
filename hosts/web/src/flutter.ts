// The Dart host calls the existing engine and filesystem services through
// dart:js_interop. Flutter owns controls, hit testing, and notebook motion.
import { createNotebook, openNotebook } from "./editor/notebook.ts";
import type { OpenNotebook } from "./editor/notebook.ts";
import { loadEngine } from "./engine/load.ts";
import type { Canvas, Engine } from "./engine/engine.ts";
import { PageSize } from "./engine/engine.ts";
import { capabilities, penSamples } from "./input/pointer.ts";
import { ensureTemplates, hasPermission, listTemplates, pickRoot, readTemplatePage, requestPermission, savedRoot } from "./storage/folder.ts";
import { createFolder, moveEntry, moveToTrash, scanLibrary, scanTrash } from "./storage/library.ts";
import { emptyFolder, emptyNote, moveNotes, readMetadata, writeMetadata } from "./storage/metadata.ts";
import { readPens, writePens } from "./storage/pens.ts";
import { Workbox } from "workbox-window";

async function paperPreview(engine: Engine, root: FileSystemDirectoryHandle, paper: string, size: "a4" | "letter"): Promise<Uint8Array<ArrayBuffer>> {
  const page = await readTemplatePage(root, paper);
  if (!page) throw new Error(`Template ${paper} has no first page.`);
  const document = engine.createDocumentFromTemplate(1n, paper, page, PageSize[size]);
  try {
    return document.pagePng(0, 480);
  } finally {
    document.free();
  }
}

async function cacheApp(): Promise<void> {
  const worker = new Workbox(new URL("sw.js", document.baseURI).pathname);
  await worker.register();
  await worker.active;
}

// Flutter 3.47 expands coalesced samples and uses microsecond timestamps:
// engine/src/flutter/lib/web_ui/lib/src/engine/pointer_binding.dart,
// _PointerAdapter._convertEventsToPointerData. Retain the original batch until
// Flutter accepts its hit target. Reading browser events never sends ink.
const rawEvents = new Map<number, PointerEvent>();
const consumed = new WeakSet<PointerEvent>();
const sampleIds = { next: 0 };
for (const type of ["pointerdown", "pointermove", "pointerup", "pointercancel"]) {
  window.addEventListener(type, (event) => {
    if (!(event instanceof PointerEvent) || event.pointerType !== "pen") return;
    const events = event.getCoalescedEvents();
    for (const sample of [event, ...events]) rawEvents.set(Math.trunc(sample.timeStamp * 1000), event);
    // Only recent browser batches can be dispatched by Flutter. Entries for
    // rejected targets expire without touching the engine.
    for (const [stamp] of rawEvents) if (stamp < event.timeStamp * 1000 - 5_000_000) rawEvents.delete(stamp);
  }, true);
}

async function startRoot() {
  if (new URLSearchParams(location.search).get("root") === "opfs") {
    window.mathNotesWrites = [];
    return { root: await navigator.storage.getDirectory(), needsGesture: false };
  }
  const root = await savedRoot();
  return { root: root ?? null, needsGesture: root ? !(await hasPermission(root)) : false };
}

async function library(root: FileSystemDirectoryHandle, engine: Engine) {
  await ensureTemplates(root, engine);
  const [folders, trash, metadata, templates] = await Promise.all([
    scanLibrary(root), scanTrash(root), readMetadata(root), listTemplates(root),
  ]);
  return { folders, trash, metadata, templates };
}

function acceptPen(canvas: Canvas, element: HTMLCanvasElement, stamp: number): boolean {
  const event = rawEvents.get(stamp);
  if (!event || consumed.has(event)) return false;
  consumed.add(event);
  const bounds = element.getBoundingClientRect();
  canvas.input(penSamples(event, bounds, capabilities(event.pointerType), sampleIds));
  return event.type === "pointerup" || event.type === "pointercancel";
}

async function mountCanvas(note: OpenNotebook, element: HTMLCanvasElement): Promise<Canvas> {
  element.style.pointerEvents = "none";
  element.id = `ink-canvas-${note.document.pointer}`;
  // HtmlElementView's creation callback precedes DOM attachment. ResizeObserver
  // is the attachment hook documented by Flutter's HtmlElementView API.
  await new Promise<void>((resolve) => {
    const observer = new ResizeObserver(() => {
      if (!element.isConnected) return;
      observer.disconnect();
      resolve();
    });
    observer.observe(element);
  });
  const canvas = note.document.createCanvas(`#${element.id}`);
  canvas.setUtcOffset(performance.timeOrigin);
  return canvas;
}

function exportPdf(note: OpenNotebook, first: number, count: number): void {
  const bytes = note.document.exportPdf(note.name, first, count);
  const url = URL.createObjectURL(new Blob([bytes], { type: "application/pdf" }));
  const link = document.createElement("a");
  link.href = url;
  link.download = `${note.name}.pdf`;
  link.click();
  setTimeout(() => URL.revokeObjectURL(url), 10_000);
}

async function insertImage(note: OpenNotebook, canvas: Canvas, page: number, x: number, y: number): Promise<boolean> {
  const file = await new Promise<File | null>((resolve) => {
    const input = document.createElement("input");
    input.type = "file";
    input.accept = "image/png,image/jpeg";
    input.onchange = () => resolve(input.files?.item(0) ?? null);
    input.oncancel = () => resolve(null);
    input.click();
  });
  if (!file) return false;
  if (file.type !== "image/png" && file.type !== "image/jpeg") throw new Error("Choose a PNG or JPEG image.");
  const bitmap = await createImageBitmap(file);
  const rect = note.document.pageRect(page);
  const scale = Math.min(1, rect.width * 0.8 / bitmap.width, rect.height * 0.8 / bitmap.height);
  const width = bitmap.width * scale;
  const height = bitmap.height * scale;
  bitmap.close();
  const url = await new Promise<string>((resolve, reject) => {
    const reader = new FileReader();
    reader.onerror = () => reject(reader.error);
    reader.onload = () => typeof reader.result === "string" ? resolve(reader.result) : reject(new Error("Could not read image."));
    reader.readAsDataURL(file);
  });
  // SVG 2 image embedding uses the engine's existing clipboard import; the
  // engine extracts the original image bytes into the notebook assets folder.
  canvas.paste(`<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1 1"><g id="import"><image href="${url}" x="${-width - 1}" y="${-height - 1}" width="${width}" height="${height}"/></g></svg>`, x, y);
  return true;
}

const api = {
  cacheApp, paperPreview, exportPdf, insertImage, loadEngine, startRoot, pickRoot, requestPermission, library,
  createNotebook, openNotebook, createFolder, moveEntry, moveToTrash,
  emptyFolder, emptyNote, moveNotes, readMetadata, writeMetadata, readPens, writePens, acceptPen, mountCanvas,
};

declare global {
  interface Window { mathNotes: typeof api }
}
window.mathNotes = api;
