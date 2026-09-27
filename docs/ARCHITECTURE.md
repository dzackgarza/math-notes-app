# Architecture

Math Notes uses one portable C++20 ink document engine with web and iPad hosts.
The existing engine owns notebook pages, SVG editing, selection, erasure, and
history. [Google Ink](https://github.com/google/ink) supplies brush construction,
stroke geometry, and hit testing; [Skia](https://skia.org) renders pages. The v1
plan continues this engine. Flutter with Cupertino owns the complete web GUI;
UIKit owns the independent iPad GUI. The shared boundary is the document,
ink, and rendering core. The [adopted framework decision](reports/Web%20interface%20framework%20selection.md)
records alternatives and integration evidence. [#56](https://github.com/dzackgarza/math-notes-app/issues/56)
owns the web host transition and deployed acceptance.
The [Write assessment](ink-reflow-owners.md) is input to a post-v1 refactoring
decision, after the product works on both hosts.

Earlier architecture sketches listed candidate libraries for ink, text, SVG,
PDF, indexing, sync, and recognition. They were options to test, not required
dependencies. Later subsystem decisions and working integrations set the v1
owners. Optional services enter when their feature is built. The hosts use
native iPad UI and a browser UI; the document, ink, and rendering engine is
shared across them.

The look and the
everyday interaction patterns (page layout, scrolling, adding pages, tool
chrome, colors, paper) follow GoodNotes and Noteful and the tablet spec
([specs/tablet-ui.md](specs/tablet-ui.md)); nothing visual is taken from
Write.

Work order and milestones: the GitHub issue tree rooted at
[#11](https://github.com/dzackgarza/math-notes-app/issues/11)
(`itree next dzackgarza/math-notes-app` gives the next work unit).

```text
       Existing C++20 document and editing engine
        Google Ink strokes + Skia rendering/PDF
                         │  stable C ABI (core/include/ink.h)
                ┌────────┴─────────┐
            Web host           iPadOS host
     Flutter/Dart + WASM       Swift, UIKit, Metal
```

| Host | Role |
| --- | --- |
| Web (WASM, PWA) | Built first. The product on Linux, Windows, and macOS, in desktop Chrome. |
| iPadOS (UIKit) | Built second. Native notebook canvas and navigation. A bounded `WKWebView` hosts only the shared TikZ figure editor. UIKit owns Pencil double tap, Pencil Pro squeeze and barrel roll, hover pose, haptics, and the input-to-display path for note ink. |

## Engine integration

These boundaries describe the v1 engine and its host integration. The
[component assessments](research_notes/Component%20ownership%20decisions/)
record candidates for specific gaps. They do not change the engine owner.

- `core/` calls no platform API and does no file I/O. The host reads files
  and passes their bytes to the engine. The engine returns the bytes of each
  file that changed, and the host writes them. Storage, clipboard, and PDF
  rasterization are host services.
- Swift imports the existing C ABI through Clang. The web host uses its
  current WASM binding to call the same engine. The
  [binding assessment](research_notes/Component%20ownership%20decisions/interfaces.md)
  can guide a bounded binding improvement; it does not require an ink-model
  change.
- Skia renders the current document through WebGL2 in WASM and Metal on iOS.
  The host supplies a canvas element or `CAMetalLayer`.
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
- The current document model keeps fixed-size pages as standalone SVG files.
  Immer values and `DocumentHistory` own undo/redo and changed-page identity.
- Google Ink constructs brush outlines and supplies geometry for selection and
  erasure. The existing engine maps those results to editable notebook
  elements and preserves the original sensor samples.
- Notebook-wide layers map stable IDs, names, order, visibility, and lock
  state from `notebook.json` to page SVG groups. The app owns this notebook
  rule and uses its existing document history for grouped edits.
- New features go in the engine or in a host service that both hosts
  supply, never in one host only. Layers belong to the document model.
- Every custom implementation links its ownership decision from the source.
  A justified upstream adaptation also cites the source file, symbol, pinned
  commit, and license.

## Component ownership

### Philosophy and invariants

Math Notes composes mature application components around research notes.
Its reasonable domain includes writing and editing ink, notebook pages and
objects, mathematical relationships, durable authored source, and the
connection between note ink and TikZ figures. An existing domain capability
stays in its current owner during v1 unless a specific defect requires change.

Navigation, scrolling, edge motion, zoom, tabs, text editing, layout,
drag-and-drop, and other common app behavior belong to platform APIs or
complete framework components. Use their interaction, accessibility, input,
and lifecycle contracts together with their appearance. The product
specification describes the user's task and any real departure from those
contracts. Standard behavior is inherited from the owner. An observed
missing detail, such as scroll velocity or bounce, is evidence that the
selected owner or its integration is wrong; it is not a request to reproduce
one observed effect with local gesture code.

Within the reasonable app domain, prefer a dependency that owns the entire
new problem when it fits the supported hosts, file format, and product rules.
Use reference implementations for behavior and algorithms when a complete
dependency does not fit. The app owns the residue: product rules and adapters
that no suitable dependency can supply. New ungrounded code is valid only
for necessary residue with no suitable dependency or reference implementation.
Record that gap before building it. A reference alone does not require a
runtime dependency or transfer ownership of working code.

An adapter translates representations or commands at a named boundary. A
replacement interaction controller, parser, layout engine, or solver is a
subsystem, regardless of its size, filename, or description as glue. Writing
and editing notebook ink are reasonable app responsibilities; replacing their
existing owner is a separate refactoring decision, not a prerequisite for
standard host interaction.

Complete owner research before accepting an implementation plan. The plan
names the selected owner, pin, interface, and exact product-specific adapter.
An acceptance check proves that choice; it does not postpone the choice.
Before writing a new subsystem or expanding an existing boundary, its owning
issue must contain an **ownership decision** with the following evidence. One
decision may cover functions within one stated boundary.

| Required evidence | Content |
| --- | --- |
| Requirement | The exact product outcome, its source, and the data that must survive it. Separate user requirements from assumptions introduced by existing code or plans. |
| Search record | Date, actual search queries, sources searched, and links to primary documentation, APIs, source, and working examples inspected. Search for complete applications, embeddable editors, SDKs, frameworks, and maintained forks as well as small packages. |
| Candidate assessment | For each credible owner, record supported behavior, extension points, version, maintenance evidence, license, host support, offline operation, and source/data fidelity. Consider large dependencies and commercial SDKs. Size, unfamiliarity, or mismatch with the current architecture alone cannot reject a candidate. |
| Gap evidence | Cite the documented restriction or a reproducible integration result for each rejection. Distinguish an untested fit from an unsupported capability. Explain why configuration, composition, a plugin, or an upstream extension cannot satisfy the requirement. |
| Necessary local ownership | State why Math Notes must own the remaining behavior, rather than a library or fork. Name the smallest custom operation, its inputs and outputs, and the behavior still owned upstream. Distinguish a working existing domain capability from a proposed new subsystem. |
| Core scope | Explain how the operation follows from the mathematical note model or source-preservation contract. Any additional responsibility needs an explicit architecture decision and user approval before implementation. |
| Decision and proof | Name the selected owner and version pin, the adapter boundary, integration acceptance on supported hosts, and the approval for any custom subsystem. A justified port also needs upstream provenance and license. |

A dependency that covers a new requirement owns the whole behavior it covers.
Keep the decision with the issue and link it here. Revisit it when a proposed
change expands the boundary. The same evidence applies to new subsystems,
reference ports, and project-maintained forks. A broad transfer of existing
ink ownership belongs to the post-v1 refactoring decision.

### Integration targets

These are the v1 owners and integration targets, not claims that every current
call site already uses them. Source evidence and exact pins are in
[ink](research_notes/Component%20ownership%20decisions/ink.md),
[UI](research_notes/Component%20ownership%20decisions/ui.md), and
[TikZ](research_notes/Component%20ownership%20decisions/tikz.md), and
[host interfaces](research_notes/Component%20ownership%20decisions/interfaces.md).

| Concern | Owner and Math Notes boundary |
| --- | --- |
| Web page scrolling and page-end insertion | Flutter owns the notebook interaction surface and standard scroll physics. Cupertino scrollables supply fling, resistance, and rebound. A framework-owned pull interaction reports a held-ready release; Math Notes issues one add-page command and supplies its template. #56 proves the complete surface on physical touch hardware. |
| Web pen/finger arbitration | Flutter owns hit testing, input dispatch, focus, and cancellation. A bounded browser adapter supplies original, coalesced, and predicted pen samples, pressure, and both tilt axes only for the accepted notebook input target. The embedded Skia canvas is passive (`pointer-events: none`). |
| iPad page navigation | [`UIScrollView`](https://developer.apple.com/documentation/uikit/uiscrollview) owns scrolling and zoom around the Metal drawing surface. UIKit arbitrates direct touches and Pencil input. |
| iPad page-end insertion | [MJRefresh 3.7.9 `MJRefreshBackFooter`](https://github.com/CoderMJLee/MJRefresh/tree/3.7.9) owns bottom-pull behavior on the `UIScrollView`. A held-ready release issues the notebook add-page command. |
| Web document zoom | Flutter owns touch scaling and navigation. Its `InteractiveViewer` supplies pan, pinch, scale bounds, and friction; Cupertino scrollables supply bounce. #56 must integrate these contracts without an application motion state machine. |
| Chrome, sheets, menus, and forms | Flutter Cupertino on web; UIKit and SwiftUI on iPad. Framework controls own input, focus, keyboard behavior, and accessibility. Math Notes supplies content, layout, and document commands. |
| Document tabs | Flutter owns web focus, selection, keyboard input, and semantics; UIKit owns native controls. Math Notes maps note IDs to open documents and view state. #62 delivers the note picker and tabs. |
| Typed text | Flutter `CupertinoTextField` and UIKit `UITextView` own input, composition, caret, and selection. [Skia Paragraph](https://skia.org/docs/user/modules/quickstart/) owns shared page-text shaping and layout. The app stores authored text and SVG baselines. |
| Drag-and-drop and selection manipulation | Flutter owns web input sessions and in-app drag targets; UIKit owns native interaction and external transfers. The current engine owns selection membership and committed object transforms. App adapters map accepted interactions to document coordinates. |
| Split panes | Flutter owns web layout and input; UIKit/SwiftUI own native panes. #28 composes framework controls and mature Flutter packages where needed for resize behavior and keyboard access. Math Notes stores proportions and links document positions. |
| History | The existing `DocumentHistory` and Immer document values own undo/redo. The notebook model tracks saved-file identity. |
| Ink editing | Google Ink owns brush and stroke geometry. The current engine owns document edits, selection, erasure, and notebook mapping. #30 and #31 add ruled tools and reflow at this boundary, using the [Write assessment](ink-reflow-owners.md) as reference evidence. |
| Persistence and offline lifecycle | File System Access, IndexedDB/idb-keyval, and Apple file coordination own storage mechanisms. #56 integrates offline asset caching and updates with the Flutter web build. The notebook-format and save-transaction adapters retain interruption and conflict behavior. |
| Source syntax and graphics | pugixml 1.16 maps page SVG and InkML/namespaced metadata; nlohmann-json at vcpkg baseline `10541e31` owns notebook JSON syntax. Skia renders the current document. `@tikz-editor/core` owns TikZ syntax and source patches. The adapter maps documented fields and preserves authored source. |
| Mathematical figures | The [TikZ mode contract](specs/tikz-drawing-mode.md) extracts a geometric TikZ skeleton for external figure refinement. The [permanent product boundary](../AGENTS.md#product-boundary-handwritten-drafts) keeps handwriting as ink and typesetting in external tools. FreeTikZ owns capture, TikZ Editor supplies supported geometry/source operations, and the app owns persistence and Copy TikZ. |

### Ink reflow owner survey

Issues #30 and #31 deliver ruled selection, erasure, insert space, and reflow
within the current engine. The [ink assessment](ink-reflow-owners.md) provides
reference algorithms and a candidate for later ownership review. It does not
select a v1 engine replacement.

## Dependencies

### Selected v1 components

The [research notes](research_notes/Component%20ownership%20decisions/)
record alternatives and actual searches. These pins identify v1 integrations;
they do not claim that every component is installed.

| Capability | Owner and pin | Boundary |
| --- | --- | --- |
| Ink strokes and geometry | [Google Ink `1b220eee`](https://github.com/google/ink/tree/1b220eee5a05e9b67be9f20f49ae2d574c8667a7), Apache-2.0 | Existing brush, outline, and hit-test owner; the app maps results to its notebook model. |
| Page rendering | [Skia](https://skia.org) within the pinned Skia build | Render the current document on SkCanvas. |
| Rendered page text layout | [Skia Paragraph](https://skia.org/docs/user/modules/quickstart/) within the pinned Skia build | Shape and lay out stored authored text. |
| Complete web GUI | [Flutter with Cupertino](reports/Web%20interface%20framework%20selection.md) | Controls, navigation, input, focus, scrolling, semantics, and HTML platform views. #56 pins the SDK and packages in the host build. |
| iPad editor scroll and bottom pull | [UIScrollView](https://developer.apple.com/documentation/uikit/uiscrollview), [MJRefresh 3.7.9](https://github.com/CoderMJLee/MJRefresh/tree/3.7.9) | Native motion and bottom action. |
| TikZ figure editor and source patching | [TikZ Editor `app-v0.5.2` / `b8b0d001`](https://github.com/DominikPeters/tikz-editor/tree/app-v0.5.2), MIT; [Math Notes FreeTikZ fork `9e5fb05c`](https://github.com/dzackgarza/freetikz/tree/9e5fb05c22dbc5637ff7cebf99f3dbee6f962b68) | Complete React editor, `@tikz-editor/core`, CodeMirror 6; FreeTikZ keeps pen-first capture. |
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

This inventory describes the implemented Solid/Ionic host. #56 replaces its
GUI with the selected Flutter host while preserving working notebook features,
folder access, offline operation, and the shared engine. The current build and
test tools below describe the existing implementation.

| Concern | Library | Introduced in |
| --- | --- | --- |
| UI chrome (toolbars, library, panels) | SolidJS 1.9, [Ionic](https://ionicframework.com/docs/components) 8 web components in iOS mode, through the Solid components of [@ionic-solidjs/core](https://github.com/ionic-solidjs/ionic-solidjs); tool icons from lucide-solid | [#57](https://github.com/dzackgarza/math-notes-app/issues/57) |
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

## Source ownership and behavior references

The Write source rows are reference implementations for specific editing
behavior. They do not select a runtime dependency or transfer ownership of
the current engine. Other rows identify external contracts at named boundaries.

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
| Stroke outline to SVG `d` | Google Ink stroke outlines in the current engine; Write `StrokeBuilder` and `SvgWriter` are comparison sources | Apache-2.0, AGPL-3.0 |
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

Write reference revision: `401b65d5fe0294cc83171b76a0273b6df3afc979`.
The Google Ink pin is `1b220eee`. The repository license is
AGPL-3.0-or-later.

## Target layout

```text
core/      include/ink.h  current document engine + Google Ink + Skia renderer
hosts/     web/  ios/
tests/     fixtures/write/   (traces and expected results recorded from Write)
.github/workflows/  engine.yml  web.yml  ios.yml
```
