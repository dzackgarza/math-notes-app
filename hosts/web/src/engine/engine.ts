// The web host's typed wrapper over the engine's C ABI (core/include/ink.h).
// Pointers into WASM memory are numbers. Memory can grow on any call that
// allocates, which replaces the buffer under Module.HEAPU8, so every access
// reads HEAPU8 again (Emscripten, "Interacting with code": memory growth).
import type { MainModule } from "./wasm/engine.mjs";

export type EngineFactory = (options?: unknown) => Promise<MainModule>;

export const Status = { ok: 0, argument: 1, parse: 2, gpu: 3, internal: 4 } as const;

export class EngineError extends Error {
  readonly status: number;
  constructor(status: number, message: string) {
    super(message);
    this.status = status;
  }
}

export const Tool = { pen: 0, eraser: 1, touch: 2, mouse: 3 } as const;
export const Phase = { hover: 0, begin: 1, move: 2, end: 3, cancel: 4 } as const;
export const Has = { pressure: 1, altitude: 2, azimuth: 4, roll: 8, hoverHeight: 16 } as const;
export const Brush = { pressurePen: 0, marker: 1, highlighter: 2 } as const;
export const Eraser = { stroke: 0, free: 1 } as const;
export const Selector = { lasso: 0, rect: 1 } as const;

// Struct layouts, wasm32: byteLength, then each field's offset (ink.h).
export const PEN_SAMPLE = {
  byteLength: 64,
  x: 0,
  y: 8,
  time: 16,
  pressure: 24,
  altitude: 28,
  azimuth: 32,
  roll: 36,
  hoverHeight: 40,
  buttons: 44,
  has: 48,
  id: 52,
  tool: 56,
  phase: 57,
  predicted: 58,
  reserved: 59,
} as const;
export const TOOL_SETTINGS = { byteLength: 16, brush: 0, rgb: 4, size: 8, opacity: 12 } as const;
export const INK_PEN = { byteLength: 24, id: 0, name: 4, tool: 8 } as const;
export const INK_FILE = { byteLength: 16, path: 0, bytes: 4, size: 8, kind: 12 } as const;
export const SELECTION_INFO = { byteLength: 40, count: 0, page: 4, x: 8, y: 16, width: 24, height: 32 } as const;
export const PDF_EXPORT_SPEC = { byteLength: 16, firstPage: 0, pageCount: 4, includeLinks: 8, includeHiddenLayers: 12 } as const;
export const FileKind = { write: 0, delete: 1 } as const;
export const PageSize = { a4: 0, letter: 1, custom: 2 } as const;

// InkStruct ids of ink_struct_layout.
export const Struct = { penSample: 0, toolSettings: 1, file: 2, selectionInfo: 3, pen: 4, pdfExportSpec: 5 } as const;

export interface PenSample {
  x: number;
  y: number;
  time: number;
  pressure: number;
  altitude: number;
  azimuth: number;
  roll: number;
  hoverHeight: number;
  buttons: number;
  has: number;
  id: number;
  tool: number;
  phase: number;
  predicted: boolean;
}

// An undo or redo step: the page it changed, or -1 for none.
export interface HistoryStep {
  page: number;
}

export interface ToolSettings {
  brush: number;
  rgb: number;
  size: number;
  // (0, 1]: the strokes' fill-opacity
  opacity: number;
}

// A preset of Notes/.pens.json (docs/FORMAT.md, Other files).
export interface Pen {
  id: string;
  name: string;
  tool: ToolSettings;
}

function writeTool(view: DataView, at: number, tool: ToolSettings): void {
  view.setUint32(at + TOOL_SETTINGS.brush, tool.brush, true);
  view.setUint32(at + TOOL_SETTINGS.rgb, tool.rgb, true);
  view.setFloat32(at + TOOL_SETTINGS.size, tool.size, true);
  view.setFloat32(at + TOOL_SETTINGS.opacity, tool.opacity, true);
}

function readTool(view: DataView, at: number): ToolSettings {
  return {
    brush: view.getUint32(at + TOOL_SETTINGS.brush, true),
    rgb: view.getUint32(at + TOOL_SETTINGS.rgb, true),
    size: view.getFloat32(at + TOOL_SETTINGS.size, true),
    opacity: view.getFloat32(at + TOOL_SETTINGS.opacity, true),
  };
}

// The selection: how many elements, their page, and the selection rectangle
// in view coordinates (CSS px).
export interface SelectionInfo {
  count: number;
  page: number;
  x: number;
  y: number;
  width: number;
  height: number;
}

export interface NotebookFile {
  path: string;
  bytes: Uint8Array<ArrayBuffer>;
}

// A file to write or delete after an edit (ink_document_dirty_files).
export type FileChange =
  | { kind: "write"; path: string; bytes: Uint8Array<ArrayBuffer> }
  | { kind: "delete"; path: string };

export function writePenSample(view: DataView, at: number, s: PenSample): void {
  const o = PEN_SAMPLE;
  view.setFloat64(at + o.x, s.x, true);
  view.setFloat64(at + o.y, s.y, true);
  view.setFloat64(at + o.time, s.time, true);
  view.setFloat32(at + o.pressure, s.pressure, true);
  view.setFloat32(at + o.altitude, s.altitude, true);
  view.setFloat32(at + o.azimuth, s.azimuth, true);
  view.setFloat32(at + o.roll, s.roll, true);
  view.setFloat32(at + o.hoverHeight, s.hoverHeight, true);
  view.setUint32(at + o.buttons, s.buttons, true);
  view.setUint32(at + o.has, s.has, true);
  view.setUint32(at + o.id, s.id, true);
  view.setUint8(at + o.tool, s.tool);
  view.setUint8(at + o.phase, s.phase);
  view.setUint8(at + o.predicted, s.predicted ? 1 : 0);
  view.setUint8(at + o.reserved, 0);
}

export function readPenSample(view: DataView, at: number): PenSample {
  const o = PEN_SAMPLE;
  return {
    x: view.getFloat64(at + o.x, true),
    y: view.getFloat64(at + o.y, true),
    time: view.getFloat64(at + o.time, true),
    pressure: view.getFloat32(at + o.pressure, true),
    altitude: view.getFloat32(at + o.altitude, true),
    azimuth: view.getFloat32(at + o.azimuth, true),
    roll: view.getFloat32(at + o.roll, true),
    hoverHeight: view.getFloat32(at + o.hoverHeight, true),
    buttons: view.getUint32(at + o.buttons, true),
    has: view.getUint32(at + o.has, true),
    id: view.getUint32(at + o.id, true),
    tool: view.getUint8(at + o.tool),
    phase: view.getUint8(at + o.phase),
    predicted: view.getUint8(at + o.predicted) !== 0,
  };
}

const encoder = new TextEncoder();
const decoder = new TextDecoder();

export class Engine {
  readonly module: MainModule;

  constructor(module: MainModule) {
    this.module = module;
  }

  static async load(factory: EngineFactory, options?: unknown): Promise<Engine> {
    return new Engine(await factory(options));
  }

  // The current WASM memory: an ArrayBuffer, the module being single-threaded.
  // Emscripten declares HEAPU8 untyped.
  heap(): Uint8Array<ArrayBuffer> {
    return this.module.HEAPU8 as Uint8Array<ArrayBuffer>;
  }

  view(): DataView {
    const heap = this.heap();
    return new DataView(heap.buffer, heap.byteOffset, heap.byteLength);
  }

  malloc(size: number): number {
    const pointer = this.module._malloc(size);
    if (pointer === 0) throw new EngineError(Status.internal, `malloc(${size}) failed`);
    return pointer;
  }

  free(pointer: number): void {
    this.module._free(pointer);
  }

  // Throws when `status` is not INK_OK, with ink_last_error's message.
  check(status: number): void {
    if (status !== Status.ok) throw new EngineError(status, this.readCString(this.module._ink_last_error()));
  }

  readCString(pointer: number): string {
    const heap = this.heap();
    let end = pointer;
    while (heap[end] !== 0) end++;
    return decoder.decode(heap.subarray(pointer, end));
  }

  // Copies `bytes` into a new allocation; the caller frees it.
  copyIn(bytes: Uint8Array): number {
    const pointer = this.malloc(Math.max(bytes.length, 1));
    this.heap().set(bytes, pointer);
    return pointer;
  }

  // Runs `body` with a NUL-terminated UTF-8 copy of `text`.
  withCString<T>(text: string, body: (pointer: number) => T): T {
    const bytes = encoder.encode(text);
    const pointer = this.malloc(bytes.length + 1);
    this.heap().set(bytes, pointer);
    this.heap()[pointer + bytes.length] = 0;
    try {
      return body(pointer);
    } finally {
      this.free(pointer);
    }
  }

  // Runs `body` with `size` bytes of zeroed scratch memory for out-parameters.
  withScratch<T>(size: number, body: (pointer: number) => T): T {
    const pointer = this.malloc(size);
    this.heap().fill(0, pointer, pointer + size);
    try {
      return body(pointer);
    } finally {
      this.free(pointer);
    }
  }

  version(): string {
    return this.readCString(this.module._ink_version());
  }

  // The struct's byteLength and field offsets, as the C side lays them out.
  structLayout(which: number): number[] {
    const capacity = 32;
    return this.withScratch(4 * capacity + 4, (out) => {
      const count = out + 4 * capacity;
      this.check(this.module._ink_struct_layout(which, out, capacity, count));
      const view = this.view();
      const n = view.getUint32(count, true);
      return Array.from({ length: n }, (_, i) => view.getUint32(out + 4 * i, true));
    });
  }

  // The bytes of the default Notes/.pens.json.
  defaultPens(): Uint8Array<ArrayBuffer> {
    return this.withScratch(8, (out) => {
      this.check(this.module._ink_pens_default(out, out + 4));
      const view = this.view();
      const at = view.getUint32(out, true);
      return this.heap().slice(at, at + view.getUint32(out + 4, true));
    });
  }

  // The presets of a .pens.json. Throws EngineError with Status.parse when the
  // file is not a pen list.
  readPens(json: Uint8Array): Pen[] {
    const bytes = this.copyIn(json);
    try {
      return this.withScratch(8, (out) => {
        this.check(this.module._ink_pens_read(bytes, json.length, out, out + 4));
        const view = this.view();
        const pens = view.getUint32(out, true);
        return Array.from({ length: view.getUint32(out + 4, true) }, (_, i) => {
          const at = pens + i * INK_PEN.byteLength;
          return {
            id: this.readCString(view.getUint32(at + INK_PEN.id, true)),
            name: this.readCString(view.getUint32(at + INK_PEN.name, true)),
            tool: readTool(view, at + INK_PEN.tool),
          };
        });
      });
    } finally {
      this.free(bytes);
    }
  }

  // The .pens.json of `pens`.
  writePens(pens: readonly Pen[]): Uint8Array<ArrayBuffer> {
    const strings: number[] = [];
    const cString = (text: string) => {
      const bytes = encoder.encode(`${text}\0`);
      strings.push(this.copyIn(bytes));
      return strings[strings.length - 1];
    };
    const array = this.malloc(Math.max(pens.length, 1) * INK_PEN.byteLength);
    try {
      pens.forEach((pen, i) => {
        const at = array + i * INK_PEN.byteLength;
        const id = cString(pen.id), name = cString(pen.name);
        const view = this.view();
        view.setUint32(at + INK_PEN.id, id, true);
        view.setUint32(at + INK_PEN.name, name, true);
        writeTool(view, at + INK_PEN.tool, pen.tool);
      });
      return this.withScratch(8, (out) => {
        this.check(this.module._ink_pens_write(array, pens.length, out, out + 4));
        const view = this.view();
        const at = view.getUint32(out, true);
        return this.heap().slice(at, at + view.getUint32(out + 4, true));
      });
    } finally {
      strings.forEach((s) => this.free(s));
      this.free(array);
    }
  }

  builtinTemplates(): string[] {
    const count = this.withScratch(4, (out) => {
      this.check(this.module._ink_builtin_template_count(out));
      return this.view().getUint32(out, true);
    });
    return Array.from({ length: count }, (_, i) =>
      this.withScratch(4, (out) => {
        this.check(this.module._ink_builtin_template_name(i, out));
        return this.readCString(this.view().getUint32(out, true));
      }),
    );
  }

  // The notebook of a built-in template; its dirty files are the files to write.
  createBuiltinTemplate(name: string, seed: bigint): InkDocument {
    const pointer = this.withCString(name, (text) =>
      this.withScratch(4, (out) => {
        this.check(this.module._ink_builtin_template_create(text, seed, out));
        return this.view().getUint32(out, true);
      }),
    );
    return new InkDocument(this, pointer);
  }

  createDocument(seed: bigint): InkDocument {
    const pointer = this.withScratch(4, (out) => {
      this.check(this.module._ink_document_create(seed, out));
      return this.view().getUint32(out, true);
    });
    return new InkDocument(this, pointer);
  }

  // A new notebook on template `name`, whose pages/0001.svg is `page1`:
  // page 1 has the template's background, with no undo step.
  createDocumentFromTemplate(seed: bigint, name: string, page1: Uint8Array, pageSize: number): InkDocument {
    const pointer = this.withCString(name, (text) => {
      const bytes = this.copyIn(page1);
      try {
        return this.withScratch(4, (out) => {
          this.check(this.module._ink_document_create_from_template(seed, text, bytes, page1.length, pageSize, 0, 0, out));
          return this.view().getUint32(out, true);
        });
      } finally {
        this.free(bytes);
      }
    });
    return new InkDocument(this, pointer);
  }
}

export class InkDocument {
  readonly engine: Engine;
  readonly pointer: number;

  constructor(engine: Engine, pointer: number) {
    this.engine = engine;
    this.pointer = pointer;
  }

  loadNotebook(json: Uint8Array): void {
    const e = this.engine;
    const bytes = e.copyIn(json);
    try {
      e.check(e.module._ink_document_load_notebook(this.pointer, bytes, json.length));
    } finally {
      e.free(bytes);
    }
  }

  // Throws EngineError with Status.parse for a page that does not parse; the
  // page stays in the document as an error page.
  loadPage(file: string, svg: Uint8Array): void {
    const e = this.engine;
    e.withCString(file, (name) => {
      const bytes = e.copyIn(svg);
      try {
        e.check(e.module._ink_document_load_page(this.pointer, name, bytes, svg.length));
      } finally {
        e.free(bytes);
      }
    });
  }

  loadAsset(path: string, data: Uint8Array): void {
    const e = this.engine;
    e.withCString(path, (name) => {
      const bytes = e.copyIn(data);
      try {
        e.check(e.module._ink_document_load_asset(this.pointer, name, bytes, data.length));
      } finally {
        e.free(bytes);
      }
    });
  }

  asset(path: string): Uint8Array<ArrayBuffer> {
    const e = this.engine;
    return e.withCString(path, (name) => e.withScratch(8, (out) => {
      e.check(e.module._ink_document_asset(this.pointer, name, out, out + 4));
      const view = e.view();
      const at = view.getUint32(out, true);
      return e.heap().slice(at, at + view.getUint32(out + 4, true));
    }));
  }

  dirtyFiles(): FileChange[] {
    const e = this.engine;
    return e.withScratch(8, (out) => {
      e.check(e.module._ink_document_dirty_files(this.pointer, out, out + 4));
      const view = e.view();
      const files = view.getUint32(out, true);
      const count = view.getUint32(out + 4, true);
      const result: FileChange[] = [];
      for (let i = 0; i < count; i++) {
        const at = files + i * INK_FILE.byteLength;
        const path = e.readCString(view.getUint32(at + INK_FILE.path, true));
        if (view.getUint32(at + INK_FILE.kind, true) === FileKind.delete) {
          result.push({ kind: "delete", path });
          continue;
        }
        const bytes = view.getUint32(at + INK_FILE.bytes, true);
        const size = view.getUint32(at + INK_FILE.size, true);
        result.push({ kind: "write", path, bytes: e.heap().slice(bytes, bytes + size) });
      }
      return result;
    });
  }

  pageCount(): number {
    const e = this.engine;
    return e.withScratch(4, (out) => {
      e.check(e.module._ink_document_page_count(this.pointer, out));
      return e.view().getUint32(out, true);
    });
  }

  exportPdf(title: string, firstPage: number, pageCount: number): Uint8Array<ArrayBuffer> {
    const e = this.engine;
    return e.withCString(title, (name) => e.withScratch(PDF_EXPORT_SPEC.byteLength + 8, (scratch) => {
      const view = e.view();
      view.setUint32(scratch + PDF_EXPORT_SPEC.firstPage, firstPage, true);
      view.setUint32(scratch + PDF_EXPORT_SPEC.pageCount, pageCount, true);
      view.setUint32(scratch + PDF_EXPORT_SPEC.includeLinks, 0, true);
      view.setUint32(scratch + PDF_EXPORT_SPEC.includeHiddenLayers, 0, true);
      const out = scratch + PDF_EXPORT_SPEC.byteLength;
      e.check(e.module._ink_export_pdf(this.pointer, name, scratch, out, out + 4));
      const result = e.view();
      const bytes = result.getUint32(out, true);
      const size = result.getUint32(out + 4, true);
      return e.heap().slice(bytes, bytes + size);
    }));
  }

  // Before page `index`; the page count appends.
  insertPage(index: number): void {
    this.engine.check(this.engine.module._ink_document_insert_page(this.pointer, index));
  }

  deletePage(index: number): void {
    this.engine.check(this.engine.module._ink_document_delete_page(this.pointer, index));
  }

  movePage(from: number, to: number): void {
    this.engine.check(this.engine.module._ink_document_move_page(this.pointer, from, to));
  }

  setPageSize(size: number, width = 0, height = 0): void {
    this.engine.check(this.engine.module._ink_document_set_page_size(this.pointer, size, width, height));
  }

  // `page1` is the template notebook's pages/0001.svg.
  setTemplate(name: string, page1: Uint8Array): void {
    const e = this.engine;
    e.withCString(name, (text) => {
      const bytes = e.copyIn(page1);
      try {
        e.check(e.module._ink_document_set_template(this.pointer, text, bytes, page1.length));
      } finally {
        e.free(bytes);
      }
    });
  }

  // The laid-out pages' extent in content coordinates (pt).
  contentSize(): { width: number; height: number } {
    const e = this.engine;
    return e.withScratch(16, (out) => {
      e.check(e.module._ink_document_content_size(this.pointer, out, out + 8));
      const view = e.view();
      return { width: view.getFloat64(out, true), height: view.getFloat64(out + 8, true) };
    });
  }

  markSaved(): void {
    this.engine.check(this.engine.module._ink_document_mark_saved(this.pointer));
  }

  // One step back; null at the start of the history.
  undo(): HistoryStep | null {
    return this.step((moved, page) => this.engine.module._ink_undo(this.pointer, moved, page));
  }

  redo(): HistoryStep | null {
    return this.step((moved, page) => this.engine.module._ink_redo(this.pointer, moved, page));
  }

  private step(call: (moved: number, page: number) => number): HistoryStep | null {
    const e = this.engine;
    return e.withScratch(8, (out) => {
      e.check(call(out, out + 4));
      const view = e.view();
      return view.getInt32(out, true) !== 0 ? { page: view.getInt32(out + 4, true) } : null;
    });
  }

  // Listed page `index`'s rectangle in content coordinates (pt).
  // A PNG of listed page `index`, `width` pixels wide: the library thumbnail.
  pagePng(index: number, width: number): Uint8Array<ArrayBuffer> {
    const e = this.engine;
    return e.withScratch(8, (out) => {
      e.check(e.module._ink_document_page_png(this.pointer, index, width, out, out + 4));
      const view = e.view();
      const png = view.getUint32(out, true);
      return e.heap().slice(png, png + view.getUint32(out + 4, true));
    });
  }

  pageRect(index: number): { x: number; y: number; width: number; height: number } {
    const e = this.engine;
    return e.withScratch(32, (out) => {
      e.check(e.module._ink_document_page_rect(this.pointer, index, out, out + 8, out + 16, out + 24));
      const view = e.view();
      const at = (i: number) => view.getFloat64(out + 8 * i, true);
      return { x: at(0), y: at(1), width: at(2), height: at(3) };
    });
  }

  // A canvas that draws into the WebGL2 canvas element matched by `selector`.
  createCanvas(selector: string): Canvas {
    const e = this.engine;
    const pointer = e.withCString(selector, (name) =>
      e.withScratch(4, (out) => {
        e.check(e.module._ink_canvas_create_webgl(this.pointer, name, out));
        return e.view().getUint32(out, true);
      }),
    );
    return new Canvas(e, pointer);
  }

  free(): void {
    this.engine.check(this.engine.module._ink_document_free(this.pointer));
  }
}

export class Canvas {
  readonly engine: Engine;
  readonly pointer: number;
  private samples = 0; // InkPenSample buffer
  private capacity = 0;

  constructor(engine: Engine, pointer: number) {
    this.engine = engine;
    this.pointer = pointer;
  }

  setView(a: number, b: number, c: number, d: number, e: number, f: number): void {
    this.engine.check(this.engine.module._ink_canvas_set_view(this.pointer, a, b, c, d, e, f));
  }

  setSurfaceSize(width: number, height: number, pixelRatio: number): void {
    this.engine.check(this.engine.module._ink_canvas_set_surface_size(this.pointer, width, height, pixelRatio));
  }

  setTool(tool: ToolSettings): void {
    const e = this.engine;
    e.withScratch(TOOL_SETTINGS.byteLength, (at) => {
      writeTool(e.view(), at, tool);
      e.check(e.module._ink_canvas_set_tool(this.pointer, at));
    });
  }

  // The eraser of the pen's eraser end; with `active`, the eraser tool is on and
  // pen and mouse input erase.
  setEraser(kind: number, active: boolean): void {
    this.engine.check(this.engine.module._ink_canvas_set_eraser(this.pointer, kind, active ? 1 : 0));
  }

  // The lasso or rectangle selector; with `active`, pen and mouse input select.
  setSelector(kind: number, active: boolean): void {
    this.engine.check(this.engine.module._ink_canvas_set_selector(this.pointer, kind, active ? 1 : 0));
  }

  beginFigure(page: number, layer = 0): void {
    this.engine.check(this.engine.module._ink_canvas_figure_begin(this.pointer, page, layer));
  }

  figureScene(): string {
    const e = this.engine;
    return e.withScratch(8, (out) => {
      e.check(e.module._ink_canvas_figure_scene(this.pointer, out, out + 4));
      const view = e.view();
      const at = view.getUint32(out, true);
      return decoder.decode(e.heap().subarray(at, at + view.getUint32(out + 4, true)));
    });
  }

  completeFigure(scene: string, tikz: string): string {
    const e = this.engine;
    const sceneBytes = encoder.encode(scene), tikzBytes = encoder.encode(tikz);
    const sceneAt = e.copyIn(sceneBytes), tikzAt = e.copyIn(tikzBytes);
    try {
      return e.withScratch(8, (out) => {
        e.check(e.module._ink_canvas_figure_complete(
          this.pointer, sceneAt, sceneBytes.length, tikzAt, tikzBytes.length, out, out + 4,
        ));
        const view = e.view();
        const at = view.getUint32(out, true);
        return decoder.decode(e.heap().subarray(at, at + view.getUint32(out + 4, true)));
      });
    } finally {
      e.free(sceneAt);
      e.free(tikzAt);
    }
  }

  // The selection, or null when nothing is selected.
  selection(): SelectionInfo | null {
    const e = this.engine;
    return e.withScratch(SELECTION_INFO.byteLength, (at) => {
      e.check(e.module._ink_canvas_selection(this.pointer, at));
      const view = e.view();
      const o = SELECTION_INFO;
      const count = view.getUint32(at + o.count, true);
      if (count === 0) return null;
      return {
        count,
        page: view.getInt32(at + o.page, true),
        x: view.getFloat64(at + o.x, true),
        y: view.getFloat64(at + o.y, true),
        width: view.getFloat64(at + o.width, true),
        height: view.getFloat64(at + o.height, true),
      };
    });
  }

  selectedFigure(): string {
    const e = this.engine;
    return e.withScratch(8, (out) => {
      e.check(e.module._ink_canvas_selected_figure(this.pointer, out, out + 4));
      const view = e.view();
      const at = view.getUint32(out, true);
      return decoder.decode(e.heap().subarray(at, at + view.getUint32(out + 4, true)));
    });
  }

  selectAll(page: number): void {
    this.engine.check(this.engine.module._ink_canvas_select_all(this.pointer, page));
  }

  clearSelection(): void {
    this.engine.check(this.engine.module._ink_canvas_clear_selection(this.pointer));
  }

  deleteSelection(): void {
    this.engine.check(this.engine.module._ink_canvas_delete_selection(this.pointer));
  }

  // The selection as a standalone SVG document; a cut deletes it. Empty when
  // nothing is selected.
  copySelection(cut: boolean): string {
    const e = this.engine;
    return e.withScratch(8, (out) => {
      e.check(e.module._ink_canvas_copy_selection(this.pointer, cut ? 1 : 0, out, out + 4));
      const view = e.view();
      const at = view.getUint32(out, true);
      return decoder.decode(e.heap().subarray(at, at + view.getUint32(out + 4, true)));
    });
  }

  // Pastes a clipboard document on the page under view point (x, y). Throws
  // EngineError with Status.parse when the text is not a page SVG.
  paste(svg: string, x: number, y: number): void {
    const e = this.engine;
    const text = encoder.encode(svg);
    const bytes = e.copyIn(text);
    try {
      e.check(e.module._ink_canvas_paste(this.pointer, bytes, text.length, x, y));
    } finally {
      e.free(bytes);
    }
  }

  insertText(value: string, x: number, y: number): void {
    const e = this.engine;
    const text = encoder.encode(value);
    const bytes = e.copyIn(text);
    try {
      e.check(e.module._ink_canvas_insert_text(this.pointer, bytes, text.length, x, y));
    } finally {
      e.free(bytes);
    }
  }

  selectTextAt(x: number, y: number): boolean {
    const e = this.engine;
    return e.withScratch(4, (out) => {
      e.check(e.module._ink_canvas_select_text_at(this.pointer, x, y, out));
      return e.view().getInt32(out, true) !== 0;
    });
  }

  selectedText(): string {
    const e = this.engine;
    return e.withScratch(8, (out) => {
      e.check(e.module._ink_canvas_selected_text(this.pointer, out, out + 4));
      const view = e.view();
      const at = view.getUint32(out, true);
      return decoder.decode(e.heap().subarray(at, at + view.getUint32(out + 4, true)));
    });
  }

  setSelectedText(value: string): void {
    const e = this.engine;
    const text = encoder.encode(value);
    const bytes = e.copyIn(text);
    try {
      e.check(e.module._ink_canvas_set_selected_text(this.pointer, bytes, text.length));
    } finally {
      e.free(bytes);
    }
  }

  duplicateSelection(): void {
    this.engine.check(this.engine.module._ink_canvas_duplicate_selection(this.pointer));
  }

  setUtcOffset(utcMinusHostMs: number): void {
    this.engine.check(this.engine.module._ink_canvas_set_utc_offset(this.pointer, utcMinusHostMs));
  }

  // One platform event's samples.
  input(samples: readonly PenSample[]): void {
    const at = this.writeSamples(samples);
    this.engine.check(this.engine.module._ink_input(this.pointer, at, samples.length));
  }

  inputUpdate(samples: readonly PenSample[]): void {
    const at = this.writeSamples(samples);
    this.engine.check(this.engine.module._ink_input_update(this.pointer, at, samples.length));
  }

  // The page under view point (x, y): its index, or -1.
  pageAt(x: number, y: number): number {
    const e = this.engine;
    return e.withScratch(4, (out) => {
      e.check(e.module._ink_canvas_page_at(this.pointer, x, y, out));
      return e.view().getInt32(out, true);
    });
  }

  // Draws a frame when something changed; returns whether it drew.
  render(): boolean {
    const e = this.engine;
    return e.withScratch(4, (out) => {
      e.check(e.module._ink_render(this.pointer, out));
      return e.view().getInt32(out, true) !== 0;
    });
  }

  free(): void {
    if (this.samples) this.engine.free(this.samples);
    this.engine.check(this.engine.module._ink_canvas_free(this.pointer));
  }

  private writeSamples(samples: readonly PenSample[]): number {
    const e = this.engine;
    if (samples.length > this.capacity) {
      if (this.samples) e.free(this.samples);
      this.capacity = Math.max(samples.length, 2 * this.capacity, 16);
      this.samples = e.malloc(this.capacity * PEN_SAMPLE.byteLength);
    }
    const view = e.view();
    samples.forEach((s, i) => writePenSample(view, this.samples + i * PEN_SAMPLE.byteLength, s));
    return this.samples;
  }
}
