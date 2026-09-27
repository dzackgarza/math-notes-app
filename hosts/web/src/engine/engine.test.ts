// The wrapper against the engine module built for Node (engine_test, with the
// sample round-trip exports of core/tests/wasm_abi). Run by `just web-engine-test`.
import assert from "node:assert/strict";
import { test } from "node:test";

import {
  Engine,
  EngineError,
  INK_FILE,
  INK_PEN,
  PDF_EXPORT_SPEC,
  PEN_SAMPLE,
  SELECTION_INFO,
  Status,
  Struct,
  TOOL_SETTINGS,
  readPenSample,
  writePenSample,
  type PenSample,
} from "./engine.ts";
import factory, { type MainModule as TestModule } from "./wasm/engine_test.mjs";

const module: TestModule = await factory();
const engine = new Engine(module);

// Every field distinct and non-trivial, each exactly representable in its C type.
function sample(i: number): PenSample {
  return {
    x: i * 1.25 - 3000.5,
    y: 0.1 * i + 1e-9,
    time: 1.7e12 + i * 4.1666,
    pressure: Math.fround((i % 1000) / 999),
    altitude: Math.fround(0.001 * (i % 1571)),
    azimuth: Math.fround(-3.14 + 0.0007 * i),
    roll: Math.fround(Math.sin(i)),
    hoverHeight: Math.fround((i % 7) / 7),
    buttons: i % 64,
    has: i % 32,
    id: 0xfffffff0 - i,
    tool: i % 4,
    phase: i % 5,
    predicted: i % 3 === 0,
  };
}

// Allocates and frees 64 MB, which grows memory and replaces HEAPU8's buffer.
function growMemory(): void {
  const before = engine.heap().buffer;
  engine.free(engine.malloc(64 << 20));
  assert.notEqual(engine.heap().buffer, before);
}

test("10,000 pen samples written through the wrapper reach C unchanged across memory growth", () => {
  const sent = Array.from({ length: 10_000 }, (_, i) => sample(i));
  for (const half of [sent.slice(0, 5_000), sent.slice(5_000)]) {
    const at = engine.malloc(half.length * PEN_SAMPLE.byteLength);
    const view = engine.view();
    half.forEach((s, i) => writePenSample(view, at + i * PEN_SAMPLE.byteLength, s));
    module._test_store_samples(at, half.length);
    engine.free(at);
    growMemory();
  }
  const out = engine.malloc(sent.length * PEN_SAMPLE.byteLength);
  assert.equal(module._test_load_samples(out), sent.length);
  const view = engine.view();
  const received = sent.map((_, i) => readPenSample(view, out + i * PEN_SAMPLE.byteLength));
  engine.free(out);
  assert.deepEqual(received, sent);
});

test("the wrapper's struct layouts are the ones C exports", () => {
  const offsets = (layout: Record<string, number>) => Object.values(layout);
  assert.deepEqual(engine.structLayout(Struct.penSample), offsets(PEN_SAMPLE));
  assert.deepEqual(engine.structLayout(Struct.toolSettings), offsets(TOOL_SETTINGS));
  assert.deepEqual(engine.structLayout(Struct.file), offsets(INK_FILE));
  assert.deepEqual(engine.structLayout(Struct.selectionInfo), offsets(SELECTION_INFO));
  assert.deepEqual(engine.structLayout(Struct.pen), offsets(INK_PEN));
  assert.deepEqual(engine.structLayout(Struct.pdfExportSpec), offsets(PDF_EXPORT_SPEC));
});

test("bad page bytes give a parse error and its message", () => {
  const document = engine.createDocument(1n);
  const bad = new TextEncoder().encode("<svg>\n<<<<<<< HEAD\n</svg>");
  assert.throws(
    () => document.loadPage("pages/0001.svg", bad),
    (e: unknown) =>
      e instanceof EngineError &&
      e.status === Status.parse &&
      e.message === "pages/0001.svg: Could not determine tag type at offset 7",
  );
  document.free();
});

test("a new notebook's files, and none after it is marked saved", () => {
  const document = engine.createDocument(1n);
  assert.deepEqual(document.dirtyFiles().map((f) => f.path), ["notebook.json", "pages/0001.svg"]);
  const [first] = document.dirtyFiles();
  assert.equal(first.kind, "write");
  const json = JSON.parse(new TextDecoder().decode(first.kind === "write" ? first.bytes : new Uint8Array()));
  assert.equal(json.format, "math-notes");
  document.markSaved();
  assert.deepEqual(document.dirtyFiles(), []);
  assert.equal(document.undo(), null);
  document.free();
});

test("pen presets written through the wrapper read back unchanged, names in UTF-8", () => {
  const pens = engine.readPens(engine.defaultPens());
  assert.deepEqual(
    pens.map((p) => p.id),
    ["black-pen", "blue-pen", "red-pen", "marker", "highlighter"],
  );
  pens[1] = { id: "blue-pen", name: "Stift ✎ blau", tool: { brush: 1, rgb: 0x2f6feb, size: 3.25, opacity: 0.5 } };
  assert.deepEqual(engine.readPens(engine.writePens(pens)), pens);
});
