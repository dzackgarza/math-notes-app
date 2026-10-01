# Initial dependency proposal

Source record: an early design proposal supplied for comparison. The text
below is retained as given. Its projects were candidates, not selected pins.
Current choices are in [ARCHITECTURE.md](../ARCHITECTURE.md) and the GitHub
issue tree.

---

Given the iOS + browser focus, I would avoid a general-purpose cross-platform GUI framework. Use a shared document/ink/rendering core, then a native Swift/iPad shell and a thin TypeScript browser shell.

A reasonable modern dependency stack is:

| Subsystem           | Project                     | Role                                                                        |
| ------------------- | --------------------------- | --------------------------------------------------------------------------- |
| Shared core         | C++20 + Emscripten          | One engine compiled natively for iOS and to WASM for browsers               |
| Ink smoothing       | `google/ink-stroke-modeler` | Stylus smoothing, noise rejection, latency prediction                       |
| 2D rendering        | `google/skia` / CanvasKit   | Shared path/image/text renderer; Metal on iOS, WASM/WebGPU/WebGL in browser |
| Text shaping        | HarfBuzz                    | Correct Unicode/OpenType shaping                                            |
| Unicode/i18n        | ICU4X, if needed            | Segmentation, bidi/Unicode/i18n without dragging full ICU everywhere        |
| SVG                 | `linebender/resvg` / `usvg` | Robust SVG parsing/normalization/rendering                                  |
| PDF browser         | Mozilla PDF.js              | PDF page rendering/text extraction                                          |
| PDF browser writing | `pdf-lib`                   | Overlay annotations/export modified PDFs                                    |
| Metadata/search DB  | GRDB.swift / `wa-sqlite`    | Same SQLite schema on iOS and browser; OPFS persistence in browser          |
| Collaboration       | Automerge                   | Optional local-first CRDT/sync layer                                        |
| ML inference        | ONNX Runtime                | Common execution format for OCR/handwriting/shape models on web and iOS     |
| Web UI              | SolidJS + Vite              | Lightweight UI chrome around the drawing surface                            |
| Tests               | Catch2 + Playwright         | Core deterministic tests plus browser end-to-end/input tests                |

The most consequential choices are the first few.

### Ink: `google/ink-stroke-modeler`

This is almost exactly the dependency a modernized Write needs. It is an Apache-2.0 C++ library explicitly designed for handwriting/stylus input. It smooths noisy samples and predicts motion to reduce perceived latency. It is intentionally optimized for handwriting rather than exact pointer reconstruction. It supports CMake and currently requires C++20. ([GitHub][1])

That means Write's existing hand-built stroke pipeline can gradually become:

```text
Pointer samples
    │
    ├─ iOS: UITouch/coalescedTouches/predictedTouches
    └─ Web: PointerEvent/getCoalescedEvents/getPredictedEvents
    │
    ▼
Ink Stroke Modeler
    │
    ▼
modeled centerline + pressure/tilt
    │
    ▼
brush geometry
    │
    ▼
document stroke object
```

I would use this rather than inventing smoothing/prediction algorithms.

Google now also has the newer `google/ink`, which includes brush definitions, geometry, stroke construction, storage and mesh generation. It is actively developed in 2026. However, its own README explicitly says interface stability is not guaranteed, and its rendering integration currently centers on Android. I would therefore use it as a reference/watchlist dependency, not make the first iOS/web version depend deeply on its API. ([GitHub][2])

### Rendering: Skia + CanvasKit

This is probably the largest modernization win.

Skia supplies paths, clipping, antialiasing, images, text, transforms, shaders, blending, effects, color management, SVG/PDF-related facilities, and mature GPU backends. It explicitly supports iOS builds, and its build has Metal support. ([GitHub][3])

On the web, CanvasKit is Google's official Skia-through-WebAssembly package. Current CanvasKit includes WebGPU support and falls back to other supported rendering paths. Its 2026 releases are active; CanvasKit 0.41.x shipped in March/April 2026. ([GitHub][4])

So instead of retaining Write's old custom rendering stack:

```text
usvg
nanovgXC
custom Painter
SDL/OpenGL assumptions
```

the target can become:

```text
              document scene
                    │
              rendering facade
               /          \
         Skia/Metal      CanvasKit
            iPad          browser
```

An even tighter architecture is possible: compile the common C++ rendering code together with Skia into WASM rather than call CanvasKit through JavaScript. I would prototype both, because the all-WASM approach gives greater code identity while CanvasKit gives a much easier web integration boundary.

I would not use Vello as the primary renderer yet. It is interesting and modern, but its project currently describes Vello GPU as still maturing and the original compute-centric renderer as experimental. Skia is much lower risk for a note application. ([GitHub][5])

### Text: HarfBuzz, preferably through Skia's text stack

Typed text should become a real document element, unlike current Write.

HarfBuzz is the standard open-source OpenType shaping engine used throughout Chrome, Firefox, Android, Qt, LibreOffice and many other systems. It handles complex scripts, kerning, ligatures, variable fonts and AAT/OpenType shaping. ([GitHub][6])

Skia can itself be built with its paragraph/text stack using HarfBuzz and ICU. If that satisfies the application's text requirements, I would not create a second custom text engine.

For example:

```text
TextElement
 ├── UTF-8 content
 ├── font family / fallback
 ├── size
 ├── paragraph width
 ├── alignment
 ├── style spans
 └── transform
       │
       ▼
SkParagraph / HarfBuzz
       │
       ▼
glyph runs
       │
       ▼
Skia
```

If more direct Unicode machinery becomes necessary, ICU4X is preferable to casually embedding full ICU. It is explicitly designed for small/client-side environments and targets both web and iOS. ([GitHub][7])

### SVG: `resvg` / `usvg`

Write's SVG-native approach is worth preserving, but its SVG implementation need not remain bespoke.

`linebender/resvg` is a modern Rust SVG implementation with a large SVG regression suite. The parsing/normalization component, `usvg`, is intentionally separate from rendering, which makes it particularly interesting for this application: arbitrary imported SVG can be normalized into a predictable internal tree before being converted into the application's scene representation. It supports WASM and exposes a C API. ([GitHub][8])

I would not immediately replace Write's SVG serializer with it. Instead:

```text
Write SVG compatibility
         │
         ▼
existing parser initially
         │
         ├─────────────► compatibility tests
         │
external SVG
         ▼
      usvg
         │
         ▼
canonical app scene
```

Once equivalence is established, the older SVG machinery can be retired.

The downside is introducing Rust into an otherwise C++ core. That is acceptable behind a narrow C interface, but not required for the first milestone.

### PDF: intentionally platform-specific

I would not force the PDF implementation into the shared engine.

On iOS, use Apple's PDFKit/CoreGraphics.

On the browser, Mozilla's PDF.js is the obvious renderer/parser. It is the PDF engine built into Firefox and is specifically designed as a general-purpose browser PDF platform. ([GitHub][9])

The app should keep PDF pages as immutable backgrounds with native app objects above them:

```text
Page
├── PDF background reference
│      page = 17
│      cropBox = ...
│
└── editable overlay scene
       ├── ink
       ├── text
       ├── highlights
       ├── shapes
       └── images
```

This is substantially cleaner than converting PDF pages into giant images as old Write does.

For browser-side PDF modification/export, `pdf-lib` can create and modify existing PDFs, embed pages/images/fonts and draw vector paths. It is MIT-licensed. ([GitHub][10])

There is another very attractive alternative if AGPL is acceptable: MuPDF/MuPDF.js. MuPDF.js now wraps the actual MuPDF C engine in WASM and supports rendering, annotation, redaction, merging, splitting and saving. The native and browser versions can therefore use almost exactly the same PDF semantics. But both MuPDF and MuPDF.js are AGPL/commercial-license software. ([GitHub][11])

If the new app is itself an AGPL derivative of Write, that licensing may be entirely compatible. If Write is used only as a behavioral reference and permissive licensing is desired, PDFKit + PDF.js is safer.

### Search, tags and library metadata: SQLite

I would make the notebook library an SQLite database, while keeping actual notebooks/documents as ordinary files.

For iOS, `groue/GRDB.swift` is a mature MIT-licensed Swift SQLite layer. ([GitHub][12])

For the browser, `rhashimoto/wa-sqlite` provides SQLite compiled to WebAssembly and supports both IndexedDB and the Origin Private File System, including several OPFS VFS implementations. ([GitHub][13])

The schema can therefore be identical:

```sql
documents
pages
tags
document_tags
bookmarks
text_index
ocr_index
recent_documents
```

and FTS5 can drive:

```text
search title
search typed text
search PDF text
search OCR handwriting
search tags
```

The actual source-of-truth note files remain independent of that index and can always be rebuilt into it.

That preserves one of Write's major strengths: files remain files.

### Optional collaboration/synchronization: Automerge

If live collaboration or robust offline merging eventually matters, Automerge fits this architecture better than a custom sync protocol.

Its current implementation is Rust, exposed to JavaScript through WASM and also through a C FFI. Automerge 3 substantially reduced its previous memory overhead, and the project specifically targets local-first applications and concurrent merging. ([GitHub][14])

I would not put every sampled pen point into a CRDT.

Use operations at the semantic level:

```text
add stroke S
delete stroke S
transform stroke S
change style of S
insert page P
edit text object T
reorder layer L
```

Finished strokes are immutable values.

That makes distributed merging much simpler.

### OCR / handwriting recognition: ONNX Runtime as infrastructure

Do not bind the document model to one handwriting recognizer.

ONNX Runtime is useful because the web build executes ONNX models through WASM/WebGPU and Microsoft also supplies Apple/iOS frameworks and Objective-C integration. ([GitHub][15])

Then:

```text
RecognitionService
       │
       ├── Apple Vision implementation
       │
       └── ONNX implementation
              ├── browser WASM/WebGPU
              └── iOS/CoreML execution provider
```

Tesseract/Tesseract.js can be useful for scanned printed documents. Tesseract.js itself is a WASM wrapper and supports 100+ languages, but it should not be confused with a serious handwriting recognizer. ([GitHub][16])

For handwritten mathematical notes, a specialized model will ultimately be required. ONNX Runtime provides the deployment layer, not the recognition quality.

### Web UI: SolidJS, but keep it away from the ink loop

For the browser shell, SolidJS is a good match because it is small, fine-grained, does not use a virtual DOM, and explicitly supports current Firefox/Safari/Chrome/Edge. ([GitHub][17])

Use it for:

```text
toolbars
document browser
settings
layer panel
tags
search results
dialogs
menus
```

Do **not** send every Pencil sample through Solid state.

The hot path should be:

```text
PointerEvent
    ↓
direct event handler
    ↓
WASM/core
    ↓
renderer
```

with effectively zero framework involvement.

Vite is sufficient as the browser build shell.

### iOS UI: mostly Apple frameworks

I would deliberately use fewer third-party dependencies here:

```text
SwiftUI
UIKit
Metal/MTKView
PDFKit
Vision / VisionKit
AVFoundation
UniformTypeIdentifiers
UIDocument / FileDocument
```

SwiftUI handles application chrome and library UI; the canvas itself can be a UIKit/Metal-backed view because Pencil handling and frame scheduling are latency-sensitive.

GRDB is the one iOS dependency I would add immediately.

I would not initially add The Composable Architecture. TCA is mature and provides explicit state/effect/test machinery, ([GitHub][18]) but this app already has a complex shared engine state machine. Duplicating that into another elaborate state architecture would create unnecessary conceptual layers. Swift's native Observation/concurrency model should be enough for the shell.

### Testing/tooling

For the C++ engine, Catch2 is a modern, low-friction C++ test and microbenchmark framework. ([GitHub][19])

For the browser, use Playwright for actual Chrome/Firefox/WebKit integration tests.

More importantly, inherit the earlier proposal of **event-trace tests**:

```text
input:
[
  {t: 0,   x: 12, y: 30, pressure: .4},
  {t: 4,   x: 13, y: 31, pressure: .5},
  ...
]

expected:
document tree / stroke geometry / rendered golden
```

Then run the identical traces against native and WASM builds.

That catches exactly the sort of platform drift that handwriting applications are vulnerable to.

The resulting dependency topology would look roughly like:

```text
                       COMMON ENGINE
                    C++20 / Emscripten
                           │
          ┌────────────────┼────────────────┐
          │                │                │
 Ink Stroke Modeler     HarfBuzz        Skia scene
          │                                 │
          └──────────── Document ────────────┘
                           │
                     SVG compatibility
                           │
                       resvg/usvg
                      (optional)

             ┌─────────────┴─────────────┐
             │                           │
          iPadOS                       Browser
             │                           │
 SwiftUI/UIKit                    SolidJS
 Skia/Metal                      CanvasKit
 PDFKit                          PDF.js
 GRDB                            wa-sqlite/OPFS
 Vision                          ONNX Runtime Web
 AVFoundation                    Web Audio
             │                           │
             └──────── optional ─────────┘
                       Automerge
```

For an initial implementation I would actually import only **Emscripten, Skia, Ink Stroke Modeler, HarfBuzz, PDF.js, GRDB, wa-sqlite, SolidJS, Catch2 and Playwright**. Everything else should enter only when the corresponding feature is implemented.

That is enough to replace most of Write's aged infrastructure while retaining the parts that are genuinely distinctive: SVG/vector-native documents, editable ink, reflow, ruled operations, bookmarks, links, insert-space semantics, clipping, and deterministic document structure.

[1]: https://github.com/google/ink-stroke-modeler?utm_source=chatgpt.com "GitHub - google/ink-stroke-modeler: C++ library for beautifully smoothing freehand (touch/stylus/pointer) input. · GitHub"
[2]: https://github.com/google/ink?utm_source=chatgpt.com "GitHub - google/ink: Google Ink · GitHub"
[3]: https://github.com/google/skia/blob/main/site/docs/user/build.md?utm_source=chatgpt.com "skia/site/docs/user/build.md at main · google/skia · GitHub"
[4]: https://github.com/google/skia/blob/main/modules/canvaskit/CHANGELOG.md?utm_source=chatgpt.com "skia/modules/canvaskit/CHANGELOG.md at main · google/skia · GitHub"
[5]: https://github.com/linebender/vello?utm_source=chatgpt.com "GitHub - linebender/vello: A GPU compute-centric 2D renderer. · GitHub"
[6]: https://github.com/harfbuzz/harfbuzz?utm_source=chatgpt.com "GitHub - harfbuzz/harfbuzz: HarfBuzz text shaping engine · GitHub"
[7]: https://github.com/unicode-org/icu4x?utm_source=chatgpt.com "GitHub - unicode-org/icu4x: Solving i18n for client-side and resource-constrained environments. · GitHub"
[8]: https://github.com/linebender/resvg?utm_source=chatgpt.com "GitHub - linebender/resvg: An SVG rendering library. · GitHub"
[9]: https://github.com/mozilla/pdf.js/?utm_source=chatgpt.com "GitHub - mozilla/pdf.js: PDF Reader in JavaScript · GitHub"
[10]: https://github.com/Hopding/pdf-lib?utm_source=chatgpt.com "GitHub - Hopding/pdf-lib: Create and modify PDF documents in any JavaScript environment · GitHub"
[11]: https://github.com/ArtifexSoftware/mupdf.js/?utm_source=chatgpt.com "GitHub - ArtifexSoftware/mupdf.js: JavaScript bindings for MuPDF · GitHub"
[12]: https://github.com/groue/GRDB.swift?utm_source=chatgpt.com "GitHub - groue/GRDB.swift: A toolkit for SQLite databases, with a focus on application development · GitHub"
[13]: https://github.com/rhashimoto/wa-sqlite?utm_source=chatgpt.com "GitHub - rhashimoto/wa-sqlite: WebAssembly SQLite with support for browser storage extensions · GitHub"
[14]: https://github.com/automerge/automerge?utm_source=chatgpt.com "GitHub - automerge/automerge: A JSON-like data structure (a CRDT) that can be modified concurrently by different users, and merged again automatically. · GitHub"
[15]: https://github.com/microsoft/onnxruntime/blob/main/js/web/README.md?utm_source=chatgpt.com "onnxruntime/js/web/README.md at main · microsoft/onnxruntime · GitHub"
[16]: https://github.com/naptha/tesseract.js/?utm_source=chatgpt.com "GitHub - naptha/tesseract.js: Pure Javascript OCR for more than 100 Languages 📖🎉🖥 · GitHub"
[17]: https://github.com/solidjs/solid?utm_source=chatgpt.com "GitHub - solidjs/solid: A declarative, efficient, and flexible JavaScript library for building user interfaces. · GitHub"
[18]: https://github.com/pointfreeco/swift-composable-architecture?utm_source=chatgpt.com "GitHub - pointfreeco/swift-composable-architecture: A library for building applications in a consistent and understandable way, with composition, testing, and ergonomics in mind. · GitHub"
[19]: https://github.com/catchorg/catch2?utm_source=chatgpt.com "GitHub - catchorg/Catch2: A modern, C++-native, test framework for unit-tests, TDD and BDD - using C++14, C++17 and later (C++11 support is in v2.x branch, and C++03 on the Catch1.x branch) · GitHub"
