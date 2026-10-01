# V1 ownership and integration map

The [initial dependency proposal](source/initial-dependency-proposal.md) and
[initial file-format proposal](source/initial-file-format-proposal.md) record
the starting ideas. The [product contract](FEATURES.md),
[format](FORMAT.md), [architecture](ARCHITECTURE.md), and linked GitHub issues
set the later decisions. This map assigns each v1 behavior to a complete
owner, a concrete integration boundary, and the remaining Math Notes rule.
Package and source revisions are selection pins, including for work that is
not yet installed. The [component assessments](research_notes/Component%20ownership%20decisions/)
contain the searches, rejected alternatives, source links, and license review.

**Wiring** maps an owner API to the existing engine or notebook files.
**Residue** is a product rule that the owner cannot supply. Existing Math
Notes code is named as an existing owner, rather than counted as new code.

| V1 behavior | Selected import or reused implementation | Wiring location and API boundary | Math Notes residue |
| --- | --- | --- | --- |
| Ink samples, brush, outline, hit geometry | Google Ink `1b220eee5a05e9b67be9f20f49ae2d574c8667a7`: `ink::InProgressStroke`, `ink::Brush`, `ink::PartitionedMesh` | `core/src/editor/editor.*`, `core/src/selection/selection.*`, and `core/third_party/ink.cmake` map host `InkPenSample` records and completed geometry to `Stroke` values. | Stable stroke identity, editable source samples, page/layer membership, and notebook history are existing document rules. |
| SVG page rendering and PDF output | JetBrains Skia `m154-ab5932137b`: `SkCanvas`, `SkPath`, `SkPDF::MakeDocument`; Skia Paragraph for text layout | `core/src/render/`, `core/src/export/pdf.*`, and `core/cmake/Skia.cmake` draw `Document` values into WebGL2, Metal, or PDF pages. | The mapping from stored SVG/InkML objects and fixed notebook pages to the scene is existing Math Notes code. The PDF page range and reproducible metadata are product rules in #29. |
| Standalone page SVG and notebook JSON | pugixml 1.16, nlohmann-json at vcpkg baseline `10541e31`, `std::to_chars`; existing page serializer | `core/src/format/` maps documented fields to independent `pages/NNNN.svg` and `notebook.json` bytes. | Stable IDs, deterministic ordering, preserved authored source, and per-page file identity follow `FORMAT.md`. |
| Web finger scrolling and bottom pull | Browser native scrolling inside Framework7 9.1.2 `page-content`; `PullToRefresh` through `framework.ptr.create`, `pullMove`, `refresh`, and `done` | `hosts/web/src/editor/Editor.tsx` owns the viewport element and maps its `scrollTop` to the Skia view; a completed pull calls the existing add-page command. Chromium PDF ink-host event routing sends pen samples to the engine while finger contact stays with the scroll owner. | Accept an add-page command only after the framework reaches its ready state and the user holds it before release; map the new page to the selected template. The host does not compute scroll momentum, resistance, or bounce. |
| Web pinch and selected-object sessions | `@use-gesture/vanilla` 10.3.1 `PinchGesture`; interact.js 1.10.28 `draggable`, `resizable`, `dropzone` | `hosts/web/src/editor/Editor.tsx` maps pinch scale/focal point to the render matrix; selected overlays report completed moves/resizes to the existing engine transform command. | Notebook-coordinate conversion and object/page identity at commit. Ordinary page touch remains with Framework7/browser scrolling. |
| iPad scrolling, zoom, Pencil input, bottom pull | UIKit `UIScrollView`, Pencil interaction APIs, and MJRefresh 3.7.9 `MJRefreshBackFooter` | The Swift/UIKit editor host places the Metal canvas in `UIScrollView`, forwards Pencil/coalesced/predicted samples through `core/include/ink.h`, and maps scroll/zoom callbacks to the engine view. The footer invokes add-page after release. | The same held-ready add-page command and template mapping as the web host. UIKit owns motion, bounce, zoom interaction, and Pencil event delivery. |
| Toolbars, lists, tabs, split panes, text entry | Web: SolidJS 1.9 with Ionic 8 controls, Kobalte Tabs 0.13.14, corvu Resizable 0.2.5, Ionic `ion-textarea`; iPad: SwiftUI/UIKit and `UITextView` | `hosts/web/src/editor/Editor.tsx` and library components bind controls to document commands; the iPad host binds native controls to the same C ABI. Skia Paragraph maps committed text to page baselines. | Stable note/tab IDs, saved panel positions, and SVG text/source mapping. Controls keep their framework focus, composition, keyboard, layout, and accessibility behavior. |
| Browser folder access and saved files | File System Access `showDirectoryPicker`, `FileSystemFileHandle.createWritable`, idb-keyval 6.3 for the retained handle | `hosts/web/src/storage/` reads the chosen directory and writes changed engine bytes to their existing paths, awaiting `close()` before save acknowledgment. | The file change set, write order, conflict-copy policy, and interrupted multi-file recovery in `FORMAT.md`. OPFS holds caches and test data, not the user's selected library. |
| iPad folder access and saved files | `UIDocumentPickerViewController`, security-scoped bookmarks, `NSFileCoordinator`, root `NSFilePresenter`, `NSFileVersion` | The Swift host reads and coordinates individual changed files in the user-selected folder, then passes their bytes through the C ABI. | The same notebook change set and conflict choices as the browser. The user's folder and standalone SVG files remain authoritative. |
| PDF import | Artifex `mupdf` WASM `Document.openDocument`/`Page.toPixmap` in a web worker; iPad PDFKit `PDFDocument`/`PDFPage` and `UIGraphicsImageRenderer` | The host rasterizer returns PNG bytes and PDF media-box size to the engine's page-image import command (#8). | One 4128-pixel PNG background per source page, fixed page size, asset name, and notebook title follow the later `FEATURES.md` decision. |
| Ruled select, erase, insert space, reflow | Existing Math Notes editor/history and Google Ink geometry; bounded adaptation of Stylus Labs Write `401b65d5fe0294cc83171b76a0273b6df3afc979` `Page::getLine`, `RuledSelector`, `Selection::insertSpace`, `Selection::reflowStrokes` | [The v1 ruled-editing decision](v1-ruled-editing-decision.md) names each `core/src/` owner and C ABI command for #30 and #31. | Continue editable objects across independent fixed-size SVG pages, creating a template page and committing one history value. |
| Mathematical figures | FreeTikZ fork `9e5fb05c` with TikZ Editor `app-v0.5.2`, Planegcs 1.2.0, BusyTeX 1.4.0, and MuPDF C SVG device 1.28.0 | [Drawing mode plan](specs/tikz-drawing-mode.md#component-ownership) names the editor iframe/WKWebView protocol, scene/constraint/source APIs, and TeX/SVG pipeline. | Map captured note ink to one stable figure and preserve original samples, scene, authored TikZ, and notebook assets. |

The original proposal also discussed Automerge collaboration, ONNX
recognition, ICU4X, resvg/usvg, SQLite full-text indexes, and a Firefox
filesystem bridge. The v1 [feature contract](FEATURES.md) excludes
collaboration and contains no recognition work unit. Current page SVG syntax
and rendering use pugixml and Skia. Current library metadata lives in documented files;
its database is not authoritative. The v1 web host targets desktop Chrome
and uses direct folder access. These source proposals create no deferred
owner choices inside the v1 work units.

## Acceptance boundary

An issue is ready to implement when its selected row and linked decision
name the version, API, adapter, and residue. Device and saved-file checks
then prove that integration. A failed check returns to the selected owner
or its wiring; it does not authorize a local replacement for standard GUI
behavior. The issue tree rooted at [#11](https://github.com/dzackgarza/math-notes-app/issues/11)
tracks the work and its product acceptance.
