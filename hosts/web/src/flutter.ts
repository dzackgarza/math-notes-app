// The Dart host calls the existing engine and filesystem services through
// dart:js_interop. Flutter owns controls, hit testing, and notebook motion.
import { applyTemplate, createNotebook, openNotebook } from "./editor/notebook.ts";
import { deserializeScene } from "@dzackgarza/freetikz/scene";
import { generateTikz } from "@dzackgarza/freetikz/tikz";
import type { OpenNotebook } from "./editor/notebook.ts";
import { loadEngine } from "./engine/load.ts";
import type { Canvas, Engine, ToolSettings } from "./engine/engine.ts";
import { Orientation, PageSize, Phase, Tool } from "./engine/engine.ts";
import { capabilities, penSamples } from "./input/pointer.ts";
import { ensureTemplates, hasPermission, listTemplates, pickRoot, readTemplatePage, requestPermission, savedRoot } from "./storage/folder.ts";
import { createFolder, moveEntry, moveToTrash, scanLibrary, scanTrash, type Note } from "./storage/library.ts";
import { emptyFolder, emptyNote, moveNotes, readMetadata, writeMetadata, TAG_COLORS } from "./storage/metadata.ts";
import { noteThumbnail } from "./storage/thumbnails.ts";
import { readPens, writePens } from "./storage/pens.ts";
import { Workbox } from "workbox-window";
import { importPdf } from "./editor/pdf.ts";
import { noteConflicts, resolveConflict } from "./storage/conflicts.ts";
import { listClippings, saveClipping, clippingSvg, changeClipping } from "./editor/clippings.ts";
import { mountFigureEditor } from "./editor/figure-editor.ts";

async function paperPreview(engine: Engine, root: FileSystemDirectoryHandle, paper: string, size: "a4" | "letter", orientation: "portrait" | "landscape"): Promise<Uint8Array<ArrayBuffer>> {
  const page = await readTemplatePage(root, paper);
  if (!page) throw new Error(`Template ${paper} has no first page.`);
  const document = engine.createDocumentFromTemplate(1n, paper, page, PageSize[size], Orientation[orientation]);
  try {
    return document.pagePng(0, 480);
  } finally {
    document.free();
  }
}

async function thumbnail(engine: Engine, root: FileSystemDirectoryHandle, note: Note): Promise<Uint8Array<ArrayBuffer> | null> {
  const blob = await noteThumbnail(engine, root, note);
  return blob ? new Uint8Array(await blob.arrayBuffer()) : null;
}

function penPreview(engine: Engine, tool: ToolSettings, width: number, height: number, scale: number): Uint8Array<ArrayBuffer> {
  return engine.penPreviewPng(tool, width, height, scale);
}

function finishFigure(canvas: Canvas): string {
  const scene = deserializeScene(canvas.figureScene());
  return canvas.completeFigure(JSON.stringify(scene), generateTikz(scene).source);
}

function figureSource(note: OpenNotebook, canvas: Canvas, capturing: boolean): string {
  if (capturing) return generateTikz(deserializeScene(canvas.figureScene())).source;
  const id = canvas.selectedFigure();
  return id ? note.document.figureSource(id) : "";
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
    if (!(event instanceof PointerEvent) || event.pointerType === "mouse") return;
    const events = event.getCoalescedEvents();
    for (const sample of [event, ...events]) rawEvents.set(Math.trunc(sample.timeStamp * 1000), event);
    // Only recent browser batches can be dispatched by Flutter. Entries for
    // rejected targets expire without touching the engine.
    for (const [stamp] of rawEvents) if (stamp < event.timeStamp * 1000 - 5_000_000) rawEvents.delete(stamp);
  }, true);
}
// The pen's side button erases; the browser would also open its context menu.
window.addEventListener("contextmenu", (event) => {
  if (event instanceof PointerEvent && event.pointerType === "pen") event.preventDefault();
}, true);

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

// `fingerDraws` makes a touch draw with the selected tool.
function acceptPen(canvas: Canvas, element: HTMLCanvasElement, stamp: number, fingerDraws: boolean): boolean {
  const event = rawEvents.get(stamp);
  if (!event || consumed.has(event)) return false;
  consumed.add(event);
  const bounds = element.getBoundingClientRect();
  canvas.input(penSamples(event, bounds, capabilities(event.pointerType), sampleIds, fingerDraws));
  return event.type === "pointerup" || event.type === "pointercancel";
}

// Discards the stroke in progress: a finger stroke becomes a two-finger
// pan or zoom when a second finger lands.
function cancelStroke(canvas: Canvas): void {
  canvas.input([{
    x: 0, y: 0, time: performance.now(), pressure: 0, altitude: 0, azimuth: 0, roll: 0, hoverHeight: 0,
    buttons: 0, has: 0, id: sampleIds.next++, tool: Tool.pen, phase: Phase.cancel, predicted: false,
  }]);
}

let nextCanvas = 0;
async function mountCanvas(note: OpenNotebook, element: HTMLCanvasElement): Promise<Canvas> {
  element.style.pointerEvents = "none";
  element.id = `ink-canvas-${nextCanvas++}`;
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

function exportPdf(note: OpenNotebook, first: number, count: number, layers: string[]): void {
  const bytes = note.document.exportPdf(note.name, first, count, layers);
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
  mountFigureEditor,
  listClippings, saveClipping, clippingSvg, changeClipping,
  noteConflicts, resolveConflict,
  importPdf,
  applyTemplate, listTemplates, finishFigure, figureSource,
  thumbnail, tagColors: TAG_COLORS,
  cacheApp, paperPreview, exportPdf, insertImage, loadEngine, startRoot, pickRoot, requestPermission, library,
  createNotebook, openNotebook, createFolder, moveEntry, moveToTrash,
  emptyFolder, emptyNote, moveNotes, readMetadata, writeMetadata, readPens, writePens, penPreview, acceptPen, cancelStroke, mountCanvas,
};

declare global {
  interface Window { mathNotes: typeof api }
}
window.mathNotes = api;
