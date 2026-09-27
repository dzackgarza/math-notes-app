# Ink editor, reflow, and history ownership

Status: candidate research for a post-v1 refactoring decision. The v1 engine
continues to use Google Ink and the Math Notes document, editing, and history
code. The implementation proposals below describe the cost of a possible
Write-based engine; they are not selected v1 work.

## Which complete editor owns offline ink editing on both hosts?

### Takeaway

Stylus Labs Write at `401b65d5fe0294cc83171b76a0273b6df3afc979` is one candidate for a later whole-editor comparison. Its document and edit operations are coupled. Adopting them would replace working Math Notes document, stroke, and history code; a small isolated library import would not perform that transfer.

### Cited Findings

- Write is an actively maintained AGPL-3.0 application with native iOS and Emscripten build branches, and SVG as its native document format. The pin is its 2026-06-23 head; the source repository documents iOS builds and contains `Makefile.wasm` and an Emscripten branch in `syncscribble/Makefile`. — [repository and license](https://github.com/styluslabs/Write/tree/401b65d5fe0294cc83171b76a0273b6df3afc979); [build instructions](https://github.com/styluslabs/Write/blob/401b65d5fe0294cc83171b76a0273b6df3afc979/README.md); [Wasm build branch](https://github.com/styluslabs/Write/blob/401b65d5fe0294cc83171b76a0273b6df3afc979/syncscribble/Makefile#L256-L265); [upstream SVG format](https://styluslabs.com/).
- Write's `Selection::reflowStrokes`, `insertSpace`, `RuledSelector`, `Page::getLine`, and stroke grouping operate on its `Element` objects and SVG tree. The editing commands call them from `ScribbleArea`; these classes are coupled to `Page`, `Document`, and `UndoHistory`. — [selection implementation](https://github.com/styluslabs/Write/blob/401b65d5fe0294cc83171b76a0273b6df3afc979/syncscribble/selection.cpp); [page model](https://github.com/styluslabs/Write/blob/401b65d5fe0294cc83171b76a0273b6df3afc979/syncscribble/page.h); [tool commands](https://github.com/styluslabs/Write/blob/401b65d5fe0294cc83171b76a0273b6df3afc979/syncscribble/scribblearea.cpp); [undo model](https://github.com/styluslabs/Write/blob/401b65d5fe0294cc83171b76a0273b6df3afc979/syncscribble/syncundo.h).
- MyScript iink has handwritten responsive layout and can export stroke details through JIIX. Its web editor performs recognition on a server and requires a server connection; its native product has device activation and deployment licensing. It cannot be the complete local offline browser editor under the stated requirement. — [responsive layout](https://developer.myscript.com/docs/interactive-ink/4.4/concepts/responsive-layout/); [JIIX stroke export](https://developer.myscript.com/doc/interactive-ink/4.1/reference/jiix/); [web architecture](https://developer.myscript.com/docs/interactive-ink/latest/web/websockets/architecture/); [platform choice](https://developer.myscript.com/doc/interactive-ink/4.2/overview/platforms/); [license pricing](https://developer.myscript.com/pricing).
- PencilKit provides native iPad ink editing, including selection and insert space, but is an Apple platform component and does not own the browser host. — [Apple PencilKit session](https://developer.apple.com/videos/play/wwdc2020/10107/); [PKCanvasView](https://developer.apple.com/documentation/pencilkit/pkcanvasview).
- Rnote is a maintained GPL-3.0 Rust/GTK editor with fixed-page visual layouts, a vertical-space tool, and SVG export. Its author says the engine has no page objects: pages are a view over continuous canvas coordinates. Its native `.rnote` file is compressed JSON. It is a poor owner for independently identified SVG pages and ruled word reflow on web and iPad. — [repository](https://github.com/flxzt/rnote); [vertical-space source](https://github.com/flxzt/rnote/blob/29ea24a1edcf7c9413b0896daf6663ea0f852254/crates/rnote-engine/src/pens/tools/verticalspace.rs); [author's page-model statement](https://github.com/flxzt/rnote/discussions/1316).
- Xournal++ is a maintained GPL-2.0 C++/GTK handwriting application with vertical space, selection, undo, and SVG export; its published host list is desktop Linux, macOS, and Windows. The inspected manual and source description do not establish ruled word reflow or iPad/browser builds. — [repository](https://github.com/xournalpp/xournalpp); [manual](https://github.com/xournalpp/xournalpp/wiki/User-Manual).
- The existing Google Ink library documents stroke construction, geometry, and rendering, but its public module contract does not include word/line editing or notebook reflow. — [Google Ink](https://github.com/google/ink).

### Inferences

- A Write engine would need `Document`, `Page`, `Element`, `Selection`, `RuledSelector`, `UndoHistory`, its SVG parser/writer, and commands currently embedded in `ScribbleArea`. It would also need a host-neutral command entry point. This is a whole-engine integration cost, not a reason to change the current engine during v1. — [Write input code](https://github.com/styluslabs/Write/blob/401b65d5fe0294cc83171b76a0273b6df3afc979/syncscribble/scribblearea.cpp); [Write painter dependency](https://github.com/styluslabs/Write/blob/401b65d5fe0294cc83171b76a0273b6df3afc979/ulib/painter.h).
- Write's `StrokeBuilder`, input filters, and `Element::freeErase` share an SVG path encoding. `Element::toPenPoints` decodes shapes emitted by Write's builders. Retaining Google Ink outlines inside that model would require a compatibility erasure and rebuild path. — [Write stroke builder](https://github.com/styluslabs/Write/blob/401b65d5fe0294cc83171b76a0273b6df3afc979/syncscribble/strokebuilder.cpp); [Write eraser decoder](https://github.com/styluslabs/Write/blob/401b65d5fe0294cc83171b76a0273b6df3afc979/syncscribble/element.cpp#L266-L357).
- Skia `SkSVGDOM` could render a serialized Write page as a derived cache. That would replace the current element renderer and requires separate fidelity proof. — [SkSVGDOM API](https://skia.googlesource.com/skia/+/7a2127711a40/modules/svg/include/SkSVGDOM.h); [current renderer](https://github.com/dzackgarza/math-notes-app/blob/c35122671bfef9e7941f1dd2ef3f9b89ba226ef0/core/src/render/renderer.cpp).

### Gaps

- This source assessment does not prove that an extracted Write editor works on both hosts or preserves the notebook format. The post-v1 decision must compare those costs against the working engine.
- A Write candidate needs proof of exact `mn:` and InkML namespace preservation, authored TikZ figure groups, original sample metadata, page identifiers, and byte stability. `Page::loadSVG` contains a branch that copies only standard attributes for non-Write documents. — [load/save source](https://github.com/styluslabs/Write/blob/401b65d5fe0294cc83171b76a0273b6df3afc979/syncscribble/page.cpp).
- Write's builder receives pressure, tilt, and timestamp samples, but the inspected builder writes a rendered SVG path and does not persist the complete input sequence. A fork would need to attach the original trace to the same `Element` and preserve source segments through transforms and free erase. — [sample input and builder](https://github.com/styluslabs/Write/blob/401b65d5fe0294cc83171b76a0273b6df3afc979/syncscribble/strokebuilder.h); [builder output](https://github.com/styluslabs/Write/blob/401b65d5fe0294cc83171b76a0273b6df3afc979/syncscribble/strokebuilder.cpp); [eraser implementation](https://github.com/styluslabs/Write/blob/401b65d5fe0294cc83171b76a0273b6df3afc979/syncscribble/element.cpp#L266-L357).

## Who owns fixed-page reflow and a single undo action?

### Takeaway

Write provides a reference implementation of handwriting structure and reflow. Its ruled-space command grows the page; Math Notes requires fixed-page overflow. A post-v1 owner review may compare a Write fork with the v1 implementation.

### Cited Findings

- `Selection::reflowStrokes` moves original selected elements to later ruled lines using word gaps and line stops; `Selection::insertSpace` moves elements while preserving their SVG identities. — [selection source](https://github.com/styluslabs/Write/blob/401b65d5fe0294cc83171b76a0273b6df3afc979/syncscribble/selection.cpp#L452-L570).
- The ruled insert command calls reflow and then `growPage` when moved content extends below the current page. This establishes the precise mismatch with fixed-size pages. — [ruled command](https://github.com/styluslabs/Write/blob/401b65d5fe0294cc83171b76a0273b6df3afc979/syncscribble/scribblearea.cpp#L1850-L1873).
- Write's `UndoHistory` groups actions, records stroke and page changes, and has a `MULTIPAGE` marker; `ScribbleDoc` uses multi-page groups for page operations. — [history declaration](https://github.com/styluslabs/Write/blob/401b65d5fe0294cc83171b76a0273b6df3afc979/syncscribble/syncundo.h#L192-L219); [history implementation](https://github.com/styluslabs/Write/blob/401b65d5fe0294cc83171b76a0273b6df3afc979/syncscribble/syncundo.cpp); [document operations](https://github.com/styluslabs/Write/blob/401b65d5fe0294cc83171b76a0273b6df3afc979/syncscribble/scribbledoc.cpp).
- Lager's `history_model` is an illustrative code block in `doc/modularity.rst`; the distributable `lager/` directory has `store.hpp` and extras, but no `history_model` facility. The current Math Notes history follows that example, so naming Lager as the owner would misstate the implementation. — [Lager example](https://github.com/arximboldi/lager/blob/ddf87b467dca57cb03fb5ff94dff9ca2c633a15e/doc/modularity.rst#L186-L284); [Lager library tree](https://github.com/arximboldi/lager/tree/master/lager); [current history source](https://github.com/dzackgarza/math-notes-app/blob/c35122671bfef9e7941f1dd2ef3f9b89ba226ef0/core/src/editor/history.h).

### Inferences

- A Write fork would need a transaction that moves overflowing original elements to later fixed pages, creates a template page when needed, and groups the changes in one undo action. This is candidate integration work, not the v1 implementation path.
- This operation extends the notebook's fixed-page document rule rather than handwriting recognition. It is the only identified new ink-layout behavior. Its exact inputs are the reflow result, fixed page geometry, ruling, and following pages; outputs are page membership, positions, and one upstream history action.

### Gaps

- The inspected sources do not establish an existing Write operation that spills ruled content into the next fixed page. Rnote moves strokes across visual page regions in a continuous canvas but cannot directly supply the independent page identity and SVG-file semantics of this notebook. — [Write ruled command](https://github.com/styluslabs/Write/blob/401b65d5fe0294cc83171b76a0273b6df3afc979/syncscribble/scribblearea.cpp#L1850-L1873); [Rnote page model](https://github.com/flxzt/rnote/discussions/1316).
- A post-v1 ownership decision must compare the complete candidate with the then-working engine before any fork extension or replacement is planned.

## Who owns named layers across independent SVG pages?

### Takeaway

The existing Math Notes document owns named layers across its independent SVG pages. A later Write candidate would need to map stable notebook layer IDs into its SVG group and history commands.

### Cited Findings

- Write creates an SVG group for page content, wraps SVG nodes in `Element`, and records stroke additions/deletions through `UndoHistory`. It has SVG group operations but the inspected `Page` and `Document` declarations do not define a notebook-wide named-layer list. — [Write Page source](https://github.com/styluslabs/Write/blob/401b65d5fe0294cc83171b76a0273b6df3afc979/syncscribble/page.cpp), [Page model](https://github.com/styluslabs/Write/blob/401b65d5fe0294cc83171b76a0273b6df3afc979/syncscribble/page.h), [Document model](https://github.com/styluslabs/Write/blob/401b65d5fe0294cc83171b76a0273b6df3afc979/syncscribble/document.h), [history](https://github.com/styluslabs/Write/blob/401b65d5fe0294cc83171b76a0273b6df3afc979/syncscribble/syncundo.h).
- Xournal++ `LayerController` provides insert, remove, reorder, rename, visibility and page-specific layer selection through its own `PageRef`, `Layer`, `Control`, document listeners and undo actions. That complete subsystem belongs to Xournal++'s separate document model. — [Xournal++ LayerController](https://github.com/xournalpp/xournalpp/blob/b8b3a59ce49c3c68260c09569ad040ccdb1b8d1c/src/core/control/layer/LayerController.h), [implementation](https://github.com/xournalpp/xournalpp/blob/b8b3a59ce49c3c68260c09569ad040ccdb1b8d1c/src/core/control/layer/LayerController.cpp).
- Math Notes' format places the ordered layer definitions in notebook JSON and one group for each layer in every independent page SVG. — [format contract](https://github.com/dzackgarza/math-notes-app/blob/c35122671bfef9e7941f1dd2ef3f9b89ba226ef0/docs/FORMAT.md).

### Inferences

- A Write candidate would need to map `{layer ID, name, order, lock/visibility}` from the notebook record to corresponding SVG groups and integrate grouped history. The v1 engine already has its own page element mutation path. Xournal++ supplies a comparison of complete layer operations.

### Gaps

- Write does not document a notebook-wide layer ID API in the inspected source; this remains a candidate integration gap.

## What search supports this choice?

### Takeaway

The search included complete editors and SDKs, including commercial and heavy choices, and inspected source modules rather than using dependency size as a filter.

### Cited Findings

- Search queries used on 2026-09-27: `Stylus Labs Write reflowStrokes license repository latest commit`; `Stylus Labs Write web app WebAssembly source build browser`; `github styluslabs Write Emscripten wasm Makefile browser`; `MyScript iink web offline recognition server required web SDK`; `MyScript iink responsive layout export JIIX strokes original`; `Rnote source reflow handwriting insert space page`; `Rnote engine fixed pages continuous canvas vertical space shifts across page`; `Xournal++ handwriting reflow insert space text line smart selection`; `xournalpp vertical space across pages implementation source`; `site:github.com/arximboldi/lager history_model undo header`; `site:github.com/arximboldi/lager time machine undo history API`; `site:github.com/xournalpp/xournalpp LayerController layers source`; `site:github.com/styluslabs/Write layer contentNode page`. Source inspection then covered the pinned Write modules, Xournal++ layer controller, Rnote vertical-space source, Lager library/documentation, and the current Math Notes core. — [Write](https://github.com/styluslabs/Write/tree/401b65d5fe0294cc83171b76a0273b6df3afc979); [Rnote](https://github.com/flxzt/rnote); [Xournal++](https://github.com/xournalpp/xournalpp); [MyScript](https://developer.myscript.com/doc/interactive-ink/4.2/overview/platforms/); [Lager](https://github.com/arximboldi/lager).

### Inferences

- This search identifies a candidate and reference algorithms. It does not compare a complete integrated Write fork with the working Math Notes engine after v1, so it cannot select a replacement.

### Gaps

- No representative notebook integration was compiled or run during this research assignment. Adapter cost and format fidelity remain open for a post-v1 review.
