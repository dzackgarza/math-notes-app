// The Dart host calls the existing engine and filesystem services through
// dart:js_interop. Flutter owns controls, hit testing, and notebook motion.
import { createNotebook, openNotebook } from "./editor/notebook.ts";
import type { OpenNotebook } from "./editor/notebook.ts";
import { loadEngine } from "./engine/load.ts";
import type { Canvas, Engine } from "./engine/engine.ts";
import { capabilities, penSamples } from "./input/pointer.ts";
import { ensureTemplates, hasPermission, listTemplates, pickRoot, requestPermission, savedRoot } from "./storage/folder.ts";
import { createFolder, moveEntry, moveToTrash, scanLibrary, scanTrash } from "./storage/library.ts";
import { readMetadata, writeMetadata } from "./storage/metadata.ts";
import { readPens, writePens } from "./storage/pens.ts";

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

const api = {
  loadEngine, startRoot, pickRoot, requestPermission, library,
  createNotebook, openNotebook, createFolder, moveEntry, moveToTrash,
  readMetadata, writeMetadata, readPens, writePens, acceptPen, mountCanvas,
};

declare global {
  interface Window { mathNotes: typeof api }
}
window.mathNotes = api;
