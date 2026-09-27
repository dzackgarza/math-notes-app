# Architecture

One portable document and ink engine (C++20), with two platform hosts: a web
app and an iPad app. This repository is the monorepo for all of it.
[Stylus Labs Write](https://github.com/styluslabs/Write) is the reference
implementation for the behaviors that no library supplies (reflow, insert
space, ruled select and erase, free erase, bookmarks, clippings). The engine
ports those algorithms from Write's source onto its own data model and
libraries (google/ink, Skia, immer) and checks them against fixtures recorded
from Write.

Write is a source of algorithms, code patterns, features and extension
points, and fixtures check behavior, never appearance. The look and the
everyday interaction patterns (page layout, scrolling, adding pages, tool
chrome, colors, paper) follow GoodNotes and Noteful and the tablet spec
([specs/tablet-ui.md](specs/tablet-ui.md)); nothing visual is taken from
Write.

The GitHub issue tree rooted at
[#11](https://github.com/dzackgarza/math-notes-app/issues/11)
records requirements and gaps. MVP work lands as integrated product slices
on `main`, chosen by the next missing end-to-end behavior.

```text
            ink engine (C++20, built to WASM and to iOS arm64)
   document model, stroke building, geometry, selection, reflow,
   undo/redo, rendering, page SVG read/write, PDF export
                         │  stable C ABI (core/include/ink.h)
                ┌────────┴─────────┐
            Web host           iPadOS host
     TypeScript + WASM         Swift, UIKit, Metal
```

| Host | Role |
| --- | --- |
| Web (WASM, PWA) | Built first. The product on Linux, Windows, and macOS, in desktop Chrome. |
| iPadOS (UIKit) | Built second. Native host, not a WKWebView. Needed for Pencil double tap, Pencil Pro squeeze and barrel roll, hover pose, haptics, and the shortest input-to-display path. |

## Rules

- `core/` calls no platform API and does no file I/O. The host reads files
  and passes their bytes to the engine. The engine returns the bytes of each
  file that changed, and the host writes them. Storage, clipboard, and PDF
  rasterization are host services.
- Swift and TypeScript see only the C ABI: opaque handles plus plain structs
  with fixed layouts. No C++ type crosses the boundary. The header has a
  `static_assert(offsetof(...))` for every struct field, and the TypeScript
  wrapper mirrors the same offsets.
- One renderer: Skia inside the engine, Ganesh backend, WebGL2 in WASM and
  Metal on iOS. The host supplies the surface (a canvas element, a
  `CAMetalLayer`). Strokes are drawn as filled `SkPath`s built from the same
  outline walk that writes the SVG `d`.
- One input record. Every host fills what its platform measures and sets a
  capability bit for it. The bits come from the platform, never from the
  values: the web reports 0.5 pressure and 0 twist when the hardware has no
  sensor.
  ```c
  typedef struct {
    double x, y;          /* view coordinates: CSS px, UIKit points */
    double time;          /* ms, monotonic clock of the host */
    float pressure;       /* 0..1 */
    float altitude;       /* rad, 0 = parallel to the screen */
    float azimuth;        /* rad */
    float roll;           /* rad: Pencil Pro rollAngle, web twist */
    float hover_height;   /* 0..1, UIKit zOffset; iPad only */
    uint32_t buttons;     /* web buttons bits; 32 = eraser */
    uint32_t has;         /* INK_HAS_* capability bits */
    uint32_t id;          /* host sample id, for later updates */
    uint8_t tool;         /* InkTool: pen, eraser, touch, mouse */
    uint8_t phase;        /* InkPhase: hover, begin, move, end, cancel */
    uint8_t predicted;    /* 1 for a predicted sample */
    uint8_t reserved;
  } InkPenSample;
  ```
  `ink_input(canvas, samples, n)` takes a batch per platform event.
  `ink_input_update(canvas, samples, n)` replaces the values of earlier
  samples with the same `id`: UIKit sends the final force and angles later,
  through `touchesEstimatedPropertiesUpdated`, sometimes after the touch
  ends.
- Pages are discrete, fixed-size, and printable: one notebook page is one
  printed sheet. A4 by default; the size is a notebook setting, and an
  imported PDF page keeps its own size. There is no infinite canvas. Reflow
  and insert space that push ink past the bottom of a page move it onto the
  next page and add a page when needed.
- Storage and file format: [FORMAT.md](FORMAT.md).
- Document state is an immutable value (immer). Undo and redo move an index
  in a list of document values. A page is dirty when its value is not the
  same object as in the last saved document.
- New features go in the engine or in a host service that both hosts
  supply, never in one host only. Layers belong to the document model.
- Each port of reference code cites the source file, symbol, and pinned
  commit in a comment. A work unit's specification approves the new code
  that it describes. Other code that no library or reference covers needs
  the user's approval first.

## Dependencies

### Engine

| Concern | Library | Pin and acquisition | Introduced in |
| --- | --- | --- | --- |
| Brushes, stroke input smoothing, stroke outlines, hit tests, lasso coverage | [google/ink](https://github.com/google/ink) (Apache-2.0) | Commit `1b220eee` (2026-09-23). Built from source by the engine's CMake, from a source list that follows Chromium's `third_party/ink/BUILD.gn`. Modules: `brush`, `color`, `geometry`, `strokes`, `types`. | [#18](https://github.com/dzackgarza/math-notes-app/issues/18) |
| google/ink dependencies | abseil-cpp, libtess2 | abseil `20260526.0`, libtess2 `446bae6`: the pins in google/ink's `MODULE.bazel` | [#18](https://github.com/dzackgarza/math-notes-app/issues/18) |
| 2D rendering, PDF export | [Skia](https://skia.org) | Prebuilt [JetBrains/skia](https://github.com/JetBrains/skia) release `m154-ab5932137b`: the `wasm` zip and the `ios-arm64` and `iosSim-arm64` zips, each pinned by SHA-256 | [#2](https://github.com/dzackgarza/math-notes-app/issues/2) |
| Page XML read and write | pugixml 1.16 | vcpkg | [#3](https://github.com/dzackgarza/math-notes-app/issues/3) |
| Number parsing | fast_float 8.3.0 | vcpkg | [#3](https://github.com/dzackgarza/math-notes-app/issues/3) |
| Number formatting | `std::to_chars` (fixed precision) | libc++ (iOS 16.3+, Emscripten) | [#3](https://github.com/dzackgarza/math-notes-app/issues/3) |
| Document values, undo history | immer 0.9.1 | vcpkg | [#3](https://github.com/dzackgarza/math-notes-app/issues/3) |
| Free-erase interval union | boost-icl (Boost.Icl `interval_set`) 1.92 | vcpkg | [#23](https://github.com/dzackgarza/math-notes-app/issues/23) |
| Lasso simplification (Ramer-Douglas-Peucker) | boost-geometry (Boost.Geometry `simplify`) 1.92 | vcpkg | [#24](https://github.com/dzackgarza/math-notes-app/issues/24) |
| Engine tests | Catch2 3.16.0 | vcpkg; tests run in the WASM build under Node | [#2](https://github.com/dzackgarza/math-notes-app/issues/2) |
| InkML compatibility check of written pages | Wacom [universal-ink-library](https://github.com/Wacom-Developer/universal-ink-library) 2.1.1 (`InkMLParser`) | PyPI, run with `uvx` in CI; test-only | [#3](https://github.com/dzackgarza/math-notes-app/issues/3) |

Toolchain: emsdk 4.0.7 for every WASM object (Emscripten has no ABI
stability between versions, and the Skia prebuilt uses 4.0.7); Xcode on the
`macos-26` runner; CMake with Ninja (`CMAKE_SYSTEM_NAME=iOS` for iOS); vcpkg
in manifest mode with a pinned `builtin-baseline` and overlay triplets for
`wasm32-emscripten` and `arm64-ios`. WASM is single-threaded, so the web host
needs no COOP/COEP headers.

### Web host

| Concern | Library | Introduced in |
| --- | --- | --- |
| UI chrome (toolbars, library, panels) | SolidJS 1.9, [Ionic](https://ionicframework.com/docs/components) 8 web components in iOS mode, so the web chrome matches the iPad host's SwiftUI controls, through the Solid components of [@ionic-solidjs/core](https://github.com/ionic-solidjs/ionic-solidjs); tool icons from lucide-solid | [#57](https://github.com/dzackgarza/math-notes-app/issues/57) |
| Build, dev server, PWA | Vite 8 (run with `bunx --bun vite`), vite-plugin-pwa 1.3 | [#5](https://github.com/dzackgarza/math-notes-app/issues/5) |
| Folder handle persistence (Chromium) | idb-keyval 6.3 | [#5](https://github.com/dzackgarza/math-notes-app/issues/5) |
| PDF page rasterizer | [mupdf](https://www.npmjs.com/package/mupdf) (Artifex's WASM build), in a Web Worker, loaded only at import | [#8](https://github.com/dzackgarza/math-notes-app/issues/8) |
| Tests | Vitest 5 Browser Mode with the Playwright 1.63 provider (Chromium) | [#5](https://github.com/dzackgarza/math-notes-app/issues/5) |

Pointer events go straight to the engine; no pen sample passes through Solid
state.

### iPad host

| Concern | API | Introduced in |
| --- | --- | --- |
| UI chrome, library | SwiftUI, Swift Observation | [#7](https://github.com/dzackgarza/math-notes-app/issues/7) |
| Canvas | UIKit view with a `CAMetalLayer`; frame timing by `UIUpdateLink` (iOS 18) | [#7](https://github.com/dzackgarza/math-notes-app/issues/7) |
| Notebook root | `UIDocumentPickerViewController` for folders, security-scoped bookmarks, `NSFileCoordinator`, one `NSFilePresenter` on the root, `NSFileVersion` for iCloud edit conflicts | [#7](https://github.com/dzackgarza/math-notes-app/issues/7), [#34](https://github.com/dzackgarza/math-notes-app/issues/34) |
| PDF intake and rasterizer | `CFBundleDocumentTypes` for `com.adobe.pdf` (Files "Open in" and the share sheet), PDFKit | [#8](https://github.com/dzackgarza/math-notes-app/issues/8) |
| Engine linkage | `InkEngine.xcframework` from the CMake build, linked by XcodeGen with `embed: false` and `libc++.tbd` | [#2](https://github.com/dzackgarza/math-notes-app/issues/2) |

## Reference implementations

Read the reference before writing the code. Line ranges and algorithm notes
are in each work-unit issue; this table is the index.

| Engine or host concern | Port or follow | License |
| --- | --- | --- |
| Reflow, ruled insert space | Write `syncscribble/selection.cpp` `Selection::reflowStrokes`, `Selection::insertSpace`; tool glue in `syncscribble/scribblearea.cpp` `doPressEvent`/`doMoveEvent`/`doReleaseEvent` (`MODE_INSSPACERULED`) | AGPL-3.0 |
| Vertical and horizontal insert space | Write `scribblearea.cpp` (`MODE_INSSPACEVERT`, `MODE_INSSPACEHORZ`), `RectSelector` | AGPL-3.0 |
| Ruled select, ruled erase, column detection | Write `selection.cpp` `RuledSelector::selectRuled`, `findStops`, `containedRuled`, `overlapRuled`, `RuledRange` | AGPL-3.0 |
| Line assignment of strokes | Write `strokebuilder.cpp` `calcCom`, `scribblearea.cpp` `groupStrokes`, `page.cpp` `getLine` | AGPL-3.0 |
| Free erase (split strokes) | Write `element.cpp` `Element::freeErase`, `erasePenPoints`, `getEraseSubPaths`; Xournal++ `src/core/model/eraser/ErasableStroke.cpp` (interval union over the centerline) | AGPL-3.0, GPL-2.0+ |
| Stroke eraser | google/ink `Intersects(PartitionedMesh, Quad)`; Jetpack Ink geometry guide; Google's Cahier sample `DrawingCanvasViewModel.kt` | Apache-2.0 |
| Lasso select | google/ink `geometry_internal::CreateClosedShape`, `CreateMeshFromPolyline`, `PartitionedMesh::CoverageIsGreaterThan`, as in `ink/strokes/internal/jni/mesh_creation_native.cc`; lasso point handling from Write `LassoSelector::addPoint` | Apache-2.0, AGPL-3.0 |
| Move, resize, rotate a selection | Write `selection.cpp` `Selection::translate`/`scale`/`commitTransform`, `RectSelector::scaleHandleHit`/`rotHandleHit` | AGPL-3.0 |
| Stroke outline to SVG `d` and `SkPath` | google/ink `ink/rendering/skia/native/internal/path_drawable.cc`; Chromium `pdf/pdfium/pdfium_ink_writer.cc` (outline walk, nonzero fill) | Apache-2.0, BSD-3 |
| InkML trace text and `traceFormat` | W3C InkML Recommendation §3; microsoft/InkMLjs `InkMLjs/inkml.js` (`InkTrace`, `InkTraceFormat`); checked against Wacom universal-ink-library `uim/codec/parser/inkml.py` | Apache-2.0 |
| google/ink without Bazel | Chromium `third_party/ink/BUILD.gn` (source list) | BSD-3 |
| Undo history | lager `doc/modularity.rst` `history_model` (about 40 lines; lager itself is not a dependency) | MIT |
| Page ruling and templates | Write `page.cpp` `Page::generateRuleLayer`, `rulingdialog.cpp` presets | AGPL-3.0 |
| Bookmarks and links | Write `scribblearea.cpp` (`MODE_BOOKMARK`, hyperref groups), `page.cpp` `Page::getHyperRef`, `bookmarkview.cpp` | AGPL-3.0 |
| Clippings | Write `clippingview.cpp` | AGPL-3.0 |
| Library list: sort orders, name checks, rename, move, delete | Write `syncscribble/documentlist.cpp` `DocumentList::setCurrDir` (sort), `NewDocDialog` (name checks), `renameItem`, `pasteItem`, `deleteItem` | AGPL-3.0 |
| Shape recognition | Xournal `src/xo-shapes.c` (inertia fitting, `try_rectangle`, `try_arrow`, `try_closed_polygon`, recent-stroke queue); ellipse by Halíř–Flusser direct least squares (OpenCV `fitEllipseDirect`); hold trigger from mathnotes-app/mobile-ink `cpp/ShapeRecognition.cpp` | GPL-2.0+, Apache-2.0 |
| PDF export, link annotations | Skia `docs/examples/PDF.cpp`, `include/core/SkAnnotation.h` | BSD-3 |
| WebGL surface | Skia `modules/canvaskit/canvaskit_bindings.cpp` (`MakeGrContext`, `MakeOnScreenGLSurface`) | BSD-3 |
| Metal surface | Skia `tools/window/ios/MetalWindowContext_ios.mm`, `SkSurfaces::WrapCAMetalLayer` | BSD-3 |
| Catch2 under Node | adobe/lagrange `cmake/lagrange/lagrange_add_executable.cmake`, `lagrange_add_test.cmake` | Apache-2.0 |
| Pointer Events adapter | W3C Pointer Events Level 3, coalesced and predicted events | — |
| Pencil input | Apple sample "Leveraging touch input for drawing apps" | — |
| iPad folder access | Apple article "Providing access to directories" | — |
| Sync conflict names | Nextcloud desktop `src/common/utility.cpp` `makeConflictFileName`; Syncthing `lib/model/folder_sendrecv.go` `conflictName`; Apple TN2336 | — |

Pinned commits: Write `401b65d`, google/ink `1b220eee`, Xournal
(GitHub mirror ricardoamaro/xournal-code) `982874f`, Xournal++ `b8b3a59`,
mobile-ink `12af61a`. The repository license is AGPL-3.0-or-later, which
admits every source above.

## Target layout

```text
core/      include/ink.h  src/{document,format,strokes,geometry,layout,selection,
           ruled,reflow,undo,render,export}/  tests/
hosts/     web/  ios/
tests/     fixtures/write/   (traces and expected results recorded from Write)
.github/workflows/  engine.yml  web.yml  ios.yml
```
