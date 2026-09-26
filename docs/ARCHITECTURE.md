# Architecture

The selected replacement architecture uses one portable C++20 ink document
engine with web and iPad hosts. Its authoritative editor is a fork of
[Stylus Labs Write at `401b65d5fe0294cc83171b76a0273b6df3afc979`](https://github.com/styluslabs/Write/tree/401b65d5fe0294cc83171b76a0273b6df3afc979).
The fork owns the SVG document tree, stroke construction, selection, erasure,
reflow, and history. [Skia SVG DOM](https://skia.googlesource.com/skia/+/7a2127711a40/modules/svg/include/SkSVGDOM.h)
renders a derived page view to each host's canvas. This replacement requires
the architecture approval named below; the deployed engine still uses its
current document and brush code. This repository contains both hosts.

The look and the
everyday interaction patterns (page layout, scrolling, adding pages, tool
chrome, colors, paper) follow GoodNotes and Noteful and the tablet spec
([specs/tablet-ui.md](specs/tablet-ui.md)); nothing visual is taken from
Write.

Work order and milestones: the GitHub issue tree rooted at
[#11](https://github.com/dzackgarza/math-notes-app/issues/11)
(`itree next dzackgarza/math-notes-app` gives the next work unit).

```text
          Write fork (C++20, built to WASM and iOS arm64)
   SVG document, stroke builder, selection, reflow, history
              + Skia SVG rendering and PDF export
                         │  stable C ABI (core/include/ink.h)
                ┌────────┴─────────┐
            Web host           iPadOS host
     TypeScript + WASM         Swift, UIKit, Metal
```

| Host | Role |
| --- | --- |
| Web (WASM, PWA) | Built first. The product on Linux, Windows, and macOS, in desktop Chrome. |
| iPadOS (UIKit) | Built second. Native notebook canvas and navigation. A bounded `WKWebView` hosts only the shared TikZ figure editor. UIKit owns Pencil double tap, Pencil Pro squeeze and barrel roll, hover pose, haptics, and the input-to-display path for note ink. |

## Engine integration

These boundaries describe the selected replacement. The
[ink-owner assessment](ink-reflow-owners.md) and
[component search](research_notes/Component%20ownership%20decisions/ink.md)
give the alternatives, source evidence, and exact fork extensions.

- `core/` calls no platform API and does no file I/O. The host reads files
  and passes their bytes to the engine. The engine returns the bytes of each
  file that changed, and the host writes them. Storage, clipboard, and PDF
  rasterization are host services.
- Swift imports a narrow C ABI through Clang. The web host uses
  [Emscripten 4.0.7 Embind and `--emit-tsd`](https://emscripten.org/docs/porting/connecting_cpp_and_javascript/embind.html)
  to generate typed TypeScript command bindings. Both expose the same fork
  command interface. The app supplies command names, sample fields and byte
  lifetimes; no hand-maintained TypeScript field offsets represent C structs.
  See the [binding decision](research_notes/Component%20ownership%20decisions/interfaces.md).
- One renderer: Skia SVG DOM parses the fork's page SVG as a derived render
  cache, then draws through Skia Ganesh to WebGL2 in WASM and Metal on iOS.
  The host supplies a canvas element or `CAMetalLayer`. The fork's SVG tree
  is the only authoritative document; Skia's DOM is a read-only render value.
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
- The Write fork's `Document`, `Page`, and `Element` are the document model.
  Its `UndoHistory` owns undo/redo and groups edits across pages. The notebook
  adapter tracks saved-file identity and the changed page paths. The current
  `immer` document and copied Lager example are replaced by this single model.
- Write's `StrokeBuilder`, input filters, path encoding, and `Element::freeErase`
  own brush creation and ink erasure together. A committed stroke stores its
  original sensor samples in InkML metadata attached to the same SVG element.
  The trace stays in stroke-local coordinates when an element transform changes.
  The fork's free erase retains source trace segments and endpoint mappings in
  resulting elements. [The source assessment](research_notes/Component%20ownership%20decisions/ink.md)
  explains why mixing Google Ink outlines with Write's path decoder would
  require a second erasure implementation. This changes the current brush
  requirement in [FEATURES.md](FEATURES.md) and awaits approval.
- Write's SVG group and undo machinery owns page element changes. It does not
  supply notebook-wide named layers in the inspected `Page` and `Document`
  sources. The selected fork extension maps stable layer IDs, names, order,
  visibility and lock state from `notebook.json` to matching groups in each
  page SVG, then applies group moves through Write actions in one history
  transaction. [Xournal++'s LayerController](https://github.com/xournalpp/xournalpp/blob/b8b3a59ce49c3c68260c09569ad040ccdb1b8d1c/src/core/control/layer/LayerController.h)
  covers generic layer commands but depends on Xournal++'s separate page,
  document and undo model. The [layer decision](research_notes/Component%20ownership%20decisions/ink.md#who-owns-named-layers-across-independent-svg-pages)
  confines local code to the notebook-to-SVG mapping.
- New features go in the engine or in a host service that both hosts
  supply, never in one host only. Layers belong to the document model.
- Every custom implementation links its ownership decision from the source.
  A justified upstream adaptation also cites the source file, symbol, pinned
  commit, and license.

## Component ownership

### Philosophy and invariants

Math Notes composes mature application components around research notes.
The project defines the notebook's meaning: page and object identity,
mathematical relationships, durable editable source, and the connection
between note ink and TikZ figures. Established libraries and platform services
own the mechanisms that present, edit, render, and store that content.

Navigation, tabs, text editing and layout, drag-and-drop, and other common app
behavior belong to complete framework components. Use their interaction,
accessibility, input, and lifecycle contracts together with their appearance.
The product specification describes the user's task and any real departure
from those contracts. Standard behavior is inherited from the owner; observed
examples are not a substitute for that contract.

Ink reflow is an ink-editor capability. Its use in mathematical notes does
not make its implementation project-specific. The same dependency search
applies to reflow, selection, recognition, persistence, and TikZ tooling.
Even a mathematical data model requires evidence before it gains a new
custom mechanism. Folder layout and source-preservation requirements justify
format mappings; they do not confer ownership of XML parsing, text shaping,
file coordination, or general editor infrastructure.

Custom code is limited to a demonstrated product rule or the smallest adapter
needed to connect selected owners. An adapter translates representations or
commands at a named boundary. A replacement interaction controller, parser,
layout engine, solver, or history implementation is a subsystem, regardless
of its size, filename, or description as glue.

Complete owner research before accepting an implementation plan. The plan
names the selected owner, pin, interface, and exact product-specific adapter.
An acceptance check proves that choice; it does not postpone the choice.
Before writing or extending any custom behavior, its owning issue must
contain an **ownership decision** with the following evidence. One decision
may cover functions within one stated boundary; each function stays within it.

| Required evidence | Content |
| --- | --- |
| Requirement | The exact product outcome, its source, and the data that must survive it. Separate user requirements from assumptions introduced by existing code or plans. |
| Search record | Date, actual search queries, sources searched, and links to primary documentation, APIs, source, and working examples inspected. Search for complete applications, embeddable editors, SDKs, frameworks, and maintained forks as well as small packages. |
| Candidate assessment | For each credible owner, record supported behavior, extension points, version, maintenance evidence, license, host support, offline operation, and source/data fidelity. Consider large dependencies and commercial SDKs. Size, unfamiliarity, or mismatch with the current architecture alone cannot reject a candidate. |
| Gap evidence | Cite the documented restriction or a reproducible integration result for each rejection. Distinguish an untested fit from an unsupported capability. Explain why configuration, composition, a plugin, or an upstream extension cannot satisfy the requirement. |
| Necessary local ownership | State why Math Notes must own the remaining behavior, rather than its library or fork. Name the smallest custom operation, its inputs and outputs, and the behavior still owned upstream. An existing implementation, issue, fixture, or reference algorithm does not establish this necessity. |
| Core scope | Explain how the operation follows from the mathematical note model or source-preservation contract. Any additional responsibility needs an explicit architecture decision and user approval before implementation. |
| Decision and proof | Name the selected owner and version pin, the adapter boundary, integration acceptance on supported hosts, and the approval for any custom subsystem. A justified port also needs upstream provenance and license. |

A dependency that covers the requirement owns the whole behavior.
Any exception requires the completed evidence above and explicit user approval.
Keep the decision with the issue and link it here. Revisit it when a proposed
change expands the boundary. This rule applies equally to new code, extensions
of existing code, copied examples, and project-maintained forks.

### Integration targets

These are the selected owners for the replacement plan, not claims that every
current call site already uses them. Source evidence and exact pins are in
[ink](research_notes/Component%20ownership%20decisions/ink.md),
[UI](research_notes/Component%20ownership%20decisions/ui.md), and
[TikZ](research_notes/Component%20ownership%20decisions/tikz.md), and
[host interfaces](research_notes/Component%20ownership%20decisions/interfaces.md).

| Concern | Owner and Math Notes boundary |
| --- | --- |
| Web page scrolling and page-end insertion | [Framework7 9.1.2 `page-content` and bottom pull](https://framework7.io/docs/pull-to-refresh.html) own the editor viewport's browser scroll and pull motion. It is a nested editor root; Ionic keeps outer chrome and does not scroll that viewport. A held-ready release callback issues the notebook add-page command. The [UI assessment](research_notes/Component%20ownership%20decisions/ui.md) defines the pen/finger input adapter and device acceptance. |
| Web pen/finger arbitration | Follow [Chromium PDF viewer's ink host](https://chromium.googlesource.com/chromium/src/+/be0366525a33fc4df00ab2b4164cb0f506dcc47b/chrome/browser/resources/pdf/elements/viewer-ink-host.ts): retain `touch-action: auto`, identify pen contact, and cancel only its drawing touch sequence through a non-passive touch listener. Finger touch remains in native browser scroll. This host adapter sends pen samples to the Write fork; Framework7 and the browser retain motion. Device acceptance proves pen input, one-finger pan, pinch, and bottom pull together. |
| iPad page navigation | [`UIScrollView`](https://developer.apple.com/documentation/uikit/uiscrollview) owns scrolling and zoom around the Metal drawing surface. UIKit arbitrates direct touches and Pencil input. |
| iPad page-end insertion | [MJRefresh 3.7.9 `MJRefreshBackFooter`](https://github.com/CoderMJLee/MJRefresh/tree/3.7.9) owns bottom-pull behavior on the `UIScrollView`. A held-ready release issues the notebook add-page command. |
| Web document zoom | [`@use-gesture/vanilla` 10.3.1 PinchGesture](https://use-gesture.netlify.app/docs/gestures/) recognizes touch/trackpad pinch and reports scale and focal point to the renderer. Framework7 remains scroll owner. |
| Chrome, sheets, menus, and forms | Ionic components on the web; SwiftUI and UIKit on iPad. Use their full control behavior and accessibility. App code supplies content and document commands. |
| Document tabs | [Kobalte Tabs 0.13.14](https://kobalte.dev/docs/core/components/tabs/) owns selection, linked panels, focus, and keyboard behavior. The app maps stable tab IDs to notes. |
| Typed text | Ionic `ion-textarea` and UIKit `UITextView` own input, composition, caret, and selection. [Skia Paragraph](https://skia.org/docs/user/modules/quickstart/) owns shared shaping and line layout for rendered page text. The app stores authored text and SVG baselines. |
| Drag-and-drop and selection manipulation | [interact.js 1.10.28](https://interactjs.io/docs/draggable/) owns web selected-object handles and drag sessions. On iPad, the Write fork's `RectSelector::scaleHandleHit`/`rotHandleHit`/`drawBG` and `ScribbleArea::selectionHit` scale/rotate/release state flow own the native handles and transform commands; UIKit supplies contact events and [drag-and-drop](https://developer.apple.com/documentation/uikit/drag-and-drop) for external transfers. Both hosts commit transforms to the same Write document and history. |
| Split panes | [corvu Resizable 0.2.5](https://corvu.dev/docs/primitives/resizable/) owns the web splitter; UIKit/SwiftUI own native panes. The host stores proportions and connects document position callbacks. |
| History | Write `UndoHistory` at `401b65d5` owns grouped edit actions across the authoritative SVG model. The notebook adapter tracks saved-file identity. |
| Ink and reflow | The Write fork at `401b65d5` owns `StrokeBuilder`, `Selection`, `RuledSelector`, `Element::freeErase`, and ruled reflow. Its page model is extended for fixed-page overflow and exact metadata preservation, as specified in the [ink decision](ink-reflow-owners.md). |
| Persistence and offline lifecycle | File System Access, IndexedDB/idb-keyval, Apple file coordination, and Vite PWA/Workbox own their respective platform mechanisms. #3, #5, and #7 define the minimum notebook-format and save-transaction adapters, including interruption and conflict behavior. |
| Source syntax and graphics | Write's `usvg` parser/writer owns editable page SVG; pugixml 1.16 maps InkML/namespaced metadata; nlohmann-json at vcpkg baseline `10541e31` owns notebook JSON syntax. Skia SVG DOM renders SVG. `@tikz-editor/core` owns TikZ syntax and source patches. The adapter maps documented fields and preserves authored source. |
| Mathematical figures | The [FreeTikZ integration plan](specs/tikz-drawing-mode.md#component-ownership) uses TikZ Editor `app-v0.5.2`, Planegcs 1.2.0, BusyTeX 1.4.0 with the pinned TeX Live extra-plus-pictures profile, and MuPDF C SVG output 1.28.0. The app owns capture-to-figure identity and notebook file mapping. |

### Ink reflow owner survey

Issues #30 and #31 integrate the pinned Write fork. The
[ink assessment](ink-reflow-owners.md) gives the candidate decision and the
bounded fixed-page and source-preservation extensions. The recommendation
awaits explicit architecture approval before replacing the deployed engine.

## Dependencies

### Selected replacement components

The [research notes](research_notes/Component%20ownership%20decisions/)
record alternatives and actual searches. These pins are the selected plan;
they do not claim the replacement is installed. The ink replacement awaits
explicit architecture approval.

| Capability | Owner and pin | Boundary |
| --- | --- | --- |
| Ink document, strokes, selection, reflow, erasure, history | [Stylus Labs Write fork `401b65d5`](https://github.com/styluslabs/Write/tree/401b65d5fe0294cc83171b76a0273b6df3afc979), AGPL-3.0 | One authoritative SVG tree; extract host-neutral edit commands. |
| Page SVG rendering | [Skia `SkSVGDOM`](https://skia.googlesource.com/skia/+/7a2127711a40/modules/svg/include/SkSVGDOM.h) within the pinned Skia build | Read-only derived page render on SkCanvas. |
| Rendered page text layout | [Skia Paragraph](https://skia.org/docs/user/modules/quickstart/) within the pinned Skia build | Shape and lay out stored authored text. |
| Web editor scroll and bottom pull | [Framework7 9.1.2](https://framework7.io/docs/pull-to-refresh.html) | Nested editor viewport and completed pull callback. |
| iPad editor scroll and bottom pull | [UIScrollView](https://developer.apple.com/documentation/uikit/uiscrollview), [MJRefresh 3.7.9](https://github.com/CoderMJLee/MJRefresh/tree/3.7.9) | Native motion and bottom action. |
| Web pinch, object handles, tabs, split panes | [`@use-gesture/vanilla` 10.3.1](https://use-gesture.netlify.app/docs/gestures/), [interact.js 1.10.28](https://interactjs.io/), [Kobalte Tabs 0.13.14](https://kobalte.dev/docs/core/components/tabs/), [corvu Resizable 0.2.5](https://corvu.dev/docs/primitives/resizable/) | Host reports completed gestures and commands to the document. |
| TikZ figure editor and source patching | [TikZ Editor `app-v0.5.2` / `b8b0d001`](https://github.com/DominikPeters/tikz-editor/tree/app-v0.5.2), MIT; [Math Notes FreeTikZ fork `9e5fb05c`](https://github.com/dzackgarza/freetikz/tree/9e5fb05c22dbc5637ff7cebf99f3dbee6f962b68) | Complete React editor, `@tikz-editor/core`, CodeMirror 6; FreeTikZ keeps pen-first capture. |
| Figure geometric constraints | [Planegcs 1.2.0 / `ee9b156d`](https://github.com/Salusoft89/planegcs/tree/1.2.0), LGPL-2.1 | Solve accepted scene relations; map stable IDs and units. |
| Offline final TeX preview | [TeXlyre-BusyTeX 1.4.0 / `f3c8780e`](https://github.com/TeXlyre/texlyre-busytex/blob/f3c8780e85939ced63133501d66b6386d89f69e4/package.json), AGPL-3.0-or-later; [upstream builder `f544a51a`](https://github.com/TeXlyre/texlyre-busytex-build/tree/f544a51a99e7d3978bb70608e927a9a23f96d4a7) `texlive-extra.profile` plus `collection-pictures 1`, `build/wasm/texlive-extra.fmt-rebuilt`; official dated `texlive2026-20260301.iso` SHA-512 `4a9071bb567c3bdd6443378dedc8e485aea4a2f1203ec8ed7c17f6787093b9c37636a037032c0be63352e3d0bf98cf5616dab19fdcd7cb83f766b3e085b620ff` | Verify ISO before extraction, package local `.js`/`.data`, and disable remote fetches. LuaLaTeX compiles exact source and preamble; retain PDF and diagnostics. |
| Compiled figure to page-visible SVG | [MuPDF C SVG device 1.28.0 / `205b8cf4`](https://mupdf.readthedocs.io/en/1.28.0/_static/generated/c/html/output-svg_8h.html), AGPL-3.0-or-later | Convert compiled PDF to vector SVG with text as paths; embed it in the standalone page SVG. |
| Figure editor host bridge | [TeXlyre embed mirror `b98714d3`](https://github.com/TeXlyre/tikz-editor-embed-mirror/tree/b98714d3584ee849178f19cf44c7768ff9063f6e) protocol, web iframe and bounded iPad `WKWebView` | Host reads/writes notebook files; embedded editor sends source/SVG results. |

### Current engine

| Concern | Library | Pin and acquisition | Introduced in |
| --- | --- | --- | --- |
| Brushes, stroke input smoothing, stroke outlines, hit tests, lasso coverage | [google/ink](https://github.com/google/ink) (Apache-2.0) | Commit `1b220eee` (2026-09-23). Built from source by the engine's CMake, from a source list that follows Chromium's `third_party/ink/BUILD.gn`. Modules: `brush`, `color`, `geometry`, `strokes`, `types`. | [#18](https://github.com/dzackgarza/math-notes-app/issues/18) |
| google/ink dependencies | abseil-cpp, libtess2 | abseil `20260526.0`, libtess2 `446bae6`: the pins in google/ink's `MODULE.bazel` | [#18](https://github.com/dzackgarza/math-notes-app/issues/18) |
| 2D rendering, PDF export | [Skia](https://skia.org) | Prebuilt [JetBrains/skia](https://github.com/JetBrains/skia) release `m154-ab5932137b`: the `wasm` zip and the `ios-arm64` and `iosSim-arm64` zips, each pinned by SHA-256 | [#2](https://github.com/dzackgarza/math-notes-app/issues/2) |
| Page XML read and write | pugixml 1.16 | vcpkg | [#3](https://github.com/dzackgarza/math-notes-app/issues/3) |
| Number parsing | fast_float 8.3.0 | vcpkg | [#3](https://github.com/dzackgarza/math-notes-app/issues/3) |
| Number formatting | `std::to_chars` (fixed precision) | libc++ (iOS 16.3+, Emscripten) | [#3](https://github.com/dzackgarza/math-notes-app/issues/3) |
| Immutable document values | immer 0.9.1 | vcpkg | [#3](https://github.com/dzackgarza/math-notes-app/issues/3) |
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

### Current web host

| Concern | Library | Introduced in |
| --- | --- | --- |
| UI chrome (toolbars, library, panels) | SolidJS 1.9, [Ionic](https://ionicframework.com/docs/components) 8 web components in iOS mode, so the web chrome matches the iPad host's SwiftUI controls, through the Solid components of [@ionic-solidjs/core](https://github.com/ionic-solidjs/ionic-solidjs); tool icons from lucide-solid | [#57](https://github.com/dzackgarza/math-notes-app/issues/57) |
| Build, dev server, PWA | Vite 8 (run with `bunx --bun vite`), vite-plugin-pwa 1.3 | [#5](https://github.com/dzackgarza/math-notes-app/issues/5) |
| Folder handle persistence (Chromium) | idb-keyval 6.3 | [#5](https://github.com/dzackgarza/math-notes-app/issues/5) |
| PDF page rasterizer (planned) | [mupdf](https://www.npmjs.com/package/mupdf) (Artifex's WASM build), in a Web Worker, loaded only at import | [#8](https://github.com/dzackgarza/math-notes-app/issues/8) |
| Tests | Vitest 5 Browser Mode with the Playwright 1.63 provider (Chromium) | [#5](https://github.com/dzackgarza/math-notes-app/issues/5) |

Pen samples go straight to the engine; no pen sample passes through Solid
state. Platform navigation stays with the host's interaction components.

### Current iPad host and selected platform APIs

| Concern | API | Introduced in |
| --- | --- | --- |
| UI chrome, library | SwiftUI, Swift Observation | [#7](https://github.com/dzackgarza/math-notes-app/issues/7) |
| Canvas and navigation | `UIScrollView` containing a UIKit view with a `CAMetalLayer`; frame timing by `UIUpdateLink` (iOS 18) | [#7](https://github.com/dzackgarza/math-notes-app/issues/7) |
| Notebook root | `UIDocumentPickerViewController` for folders, security-scoped bookmarks, `NSFileCoordinator`, one `NSFilePresenter` on the root, `NSFileVersion` for iCloud edit conflicts | [#7](https://github.com/dzackgarza/math-notes-app/issues/7), [#34](https://github.com/dzackgarza/math-notes-app/issues/34) |
| PDF intake and rasterizer | `CFBundleDocumentTypes` for `com.adobe.pdf` (Files "Open in" and the share sheet), PDFKit | [#8](https://github.com/dzackgarza/math-notes-app/issues/8) |
| Engine linkage | `InkEngine.xcframework` from the CMake build, linked by XcodeGen with `embed: false` and `libc++.tbd` | [#2](https://github.com/dzackgarza/math-notes-app/issues/2) |

## Selected source ownership and behavior references

The Write source rows identify the fork's authoritative implementation. Other
rows identify external contracts used at a named boundary. Their presence
does not authorize a copied replacement for a selected component.

| Engine or host concern | API or behavior reference | License |
| --- | --- | --- |
| Reflow, ruled insert space | Write `syncscribble/selection.cpp` `Selection::reflowStrokes`, `Selection::insertSpace`; tool glue in `syncscribble/scribblearea.cpp` `doPressEvent`/`doMoveEvent`/`doReleaseEvent` (`MODE_INSSPACERULED`) | AGPL-3.0 |
| Vertical and horizontal insert space | Write `scribblearea.cpp` (`MODE_INSSPACEVERT`, `MODE_INSSPACEHORZ`), `RectSelector` | AGPL-3.0 |
| Ruled select, ruled erase, column detection | Write `selection.cpp` `RuledSelector::selectRuled`, `findStops`, `containedRuled`, `overlapRuled`, `RuledRange` | AGPL-3.0 |
| Line assignment of strokes | Write `strokebuilder.cpp` `calcCom`, `scribblearea.cpp` `groupStrokes`, `page.cpp` `getLine` | AGPL-3.0 |
| Free erase (split strokes) | Write `element.cpp` `Element::freeErase`, `erasePenPoints`, `getEraseSubPaths`; Xournal++ `src/core/model/eraser/ErasableStroke.cpp` (interval union over the centerline) | AGPL-3.0, GPL-2.0+ |
| Stroke eraser | Write `PathSelector::selectPath` and `MODE_ERASESTROKE` | AGPL-3.0 |
| Lasso select | Write `LassoSelector` and `Selection` | AGPL-3.0 |
| Selection transform and iPad handles | Write `selection.cpp` `Selection::translate`/`scale`/`rotate`/`commitTransform`, `RectSelector::scaleHandleHit`/`rotHandleHit`/`drawBG`, and `scribblearea.cpp` `selectionHit` plus `MODEMOD_SCALESEL`/`MODEMOD_ROTATESEL` motion and release | AGPL-3.0 |
| Stroke outline to SVG `d` | Write `StrokeBuilder` and `SvgWriter`; Skia SVG DOM renders the resulting page | AGPL-3.0, BSD-3 |
| InkML trace text and `traceFormat` | W3C InkML Recommendation §3; microsoft/InkMLjs `InkMLjs/inkml.js` (`InkTrace`, `InkTraceFormat`); checked against Wacom universal-ink-library `uim/codec/parser/inkml.py` | Apache-2.0 |
| Grouped history | Write `syncundo.h`/`syncundo.cpp` `UndoHistory` and page/stroke action items | AGPL-3.0 |
| Page ruling and templates | Write `page.cpp` `Page::generateRuleLayer`, `rulingdialog.cpp` presets | AGPL-3.0 |
| Bookmarks and links | Write `scribblearea.cpp` (`MODE_BOOKMARK`, hyperref groups), `page.cpp` `Page::getHyperRef`, `bookmarkview.cpp` | AGPL-3.0 |
| Clipping data and insertion semantics | Write `clippingview.cpp`; host components own panel controls and drag-and-drop | AGPL-3.0 |
| TikZ drawing editor | TikZ Editor `app-v0.5.2` owns canvas/source editing; the FreeTikZ fork owns pen-first capture; see [drawing mode](specs/tikz-drawing-mode.md) | MIT |
| PDF export, link annotations | Skia `docs/examples/PDF.cpp`, `include/core/SkAnnotation.h` | BSD-3 |
| WebGL surface | Skia `modules/canvaskit/canvaskit_bindings.cpp` (`MakeGrContext`, `MakeOnScreenGLSurface`) | BSD-3 |
| Metal surface | Skia `tools/window/ios/MetalWindowContext_ios.mm`, `SkSurfaces::WrapCAMetalLayer` | BSD-3 |
| Catch2 under Node | adobe/lagrange `cmake/lagrange/lagrange_add_executable.cmake`, `lagrange_add_test.cmake` | Apache-2.0 |
| Pointer Events adapter | W3C Pointer Events Level 3, coalesced and predicted events | — |
| Pencil input | Apple sample "Leveraging touch input for drawing apps" | — |
| iPad folder access | Apple article "Providing access to directories" | — |
| Sync conflict names | Nextcloud desktop `src/common/utility.cpp` `makeConflictFileName`; Syncthing `lib/model/folder_sendrecv.go` `conflictName`; Apple TN2336 | — |

Selected Write pin: `401b65d5fe0294cc83171b76a0273b6df3afc979`.
The current Google Ink pin is `1b220eee`. The repository license is
AGPL-3.0-or-later.

## Target layout

```text
core/      include/ink.h  selected Write fork + notebook adapter + Skia renderer
hosts/     web/  ios/
tests/     fixtures/write/   (traces and expected results recorded from Write)
.github/workflows/  engine.yml  web.yml  ios.yml
```
