# Ink editing owner

Decision scope: [#22](https://github.com/dzackgarza/math-notes-app/issues/22),
[#23](https://github.com/dzackgarza/math-notes-app/issues/23),
[#24](https://github.com/dzackgarza/math-notes-app/issues/24),
[#30](https://github.com/dzackgarza/math-notes-app/issues/30), and
[#31](https://github.com/dzackgarza/math-notes-app/issues/31).
Survey date: 2026-09-27. Full search queries, sources, license and host evidence:
[ink ownership research](research_notes/Component%20ownership%20decisions/ink.md).
Implementation policy: [component ownership](ARCHITECTURE.md#component-ownership).

## Selected replacement

Fork [Stylus Labs Write at `401b65d5fe0294cc83171b76a0273b6df3afc979`](https://github.com/styluslabs/Write/tree/401b65d5fe0294cc83171b76a0273b6df3afc979)
as the single ink editor model on both hosts. Its native iOS and Emscripten
build branches and AGPL-3.0 source permit one code base. The fork owns:

| Behavior | Upstream owner |
| --- | --- |
| SVG document, pages, elements, page load/save | `Document`, `Page`, `Element`, `usvg` parser/writer |
| Pen and highlighter paths, pressure, filters | `StrokeBuilder`, `ScribblePen`, input processors |
| Ruled line/word/column selection, lasso, transforms | `Selection`, `RuledSelector`, `Page::getLine`, relevant `ScribbleArea` commands |
| Ruled reflow, horizontal/vertical insert space | `Selection::reflowStrokes`, `insertSpace`, relevant `ScribbleArea` commands |
| Free erase and path rebuild | `Element::freeErase`, `toPenPoints`, stroke builder path classes |
| Undo/redo across pages | `UndoHistory`, stroke/page undo items, multi-page action groups |

Extract the command boundary from Write's `ScribbleArea` into the fork.
The browser host supplies pen samples and standard viewport controls; UIKit
supplies Pencil samples and standard scroll/zoom. Both call the same fork
commands. The fork's SVG document tree is authoritative. The current `immer`
document, copied Lager history example, custom selection/reflow, and custom
element renderer are replaced in the selected architecture.
[Skia `SkSVGDOM`](https://skia.googlesource.com/skia/+/7a2127711a40/modules/svg/include/SkSVGDOM.h)
renders a derived cache from the fork's page SVG to the existing SkCanvas
surfaces. The SVG cache is never edited as a second document.

This recommendation awaits explicit architecture approval. The deployed code
still uses Google Ink brushes and its current document model. The selection
changes the brush owner named in [FEATURES.md](FEATURES.md); Write's free
eraser reconstructs the path encoding produced by its own pen builders, so
retaining Google Ink outlines would require a second erasure/rebuild path.
[Stroke builder](https://github.com/styluslabs/Write/blob/401b65d5fe0294cc83171b76a0273b6df3afc979/syncscribble/strokebuilder.cpp),
[eraser decoder](https://github.com/styluslabs/Write/blob/401b65d5fe0294cc83171b76a0273b6df3afc979/syncscribble/element.cpp#L266-L357).

## Bounded fork extensions

The notebook defines fixed-size, independently identified SVG pages and
requires original samples and authored figure source to survive editing.
Write's ruled insertion currently grows the page when reflow passes its
bottom. Extend that command within the fork to transfer the same SVG
elements to the corresponding line of the next fixed page, shift following
content, add a template page at the end, and record the whole operation in
one `UndoHistory` multi-page action.
[Write ruled command](https://github.com/styluslabs/Write/blob/401b65d5fe0294cc83171b76a0273b6df3afc979/syncscribble/scribblearea.cpp#L1850-L1873),
[multi-page history](https://github.com/styluslabs/Write/blob/401b65d5fe0294cc83171b76a0273b6df3afc979/syncscribble/syncundo.h#L192-L219).

Extend the fork's SVG load/save and edit paths to preserve the notebook's
`mn:` and InkML namespaces, original sensor trace, stable IDs, figure group
and source reference. Write's non-Write import path copies only standard
attributes, and its stroke builder emits a visible path without the complete
sensor trace. Keep that trace on the same `Element` in stroke-local
coordinates. Move and resize change the element transform, not the trace.
Free erase retains the source segments and their endpoint mapping in the
resulting elements; the fork records that change in its history.
[Page load/save](https://github.com/styluslabs/Write/blob/401b65d5fe0294cc83171b76a0273b6df3afc979/syncscribble/page.cpp),
[stroke input](https://github.com/styluslabs/Write/blob/401b65d5fe0294cc83171b76a0273b6df3afc979/syncscribble/strokebuilder.h).

The notebook adapter owns page identity, template choice, stable layer IDs,
names, order, visibility and lock state, changed-file list, TikZ figure
references, and the format's exact bytes. Write owns underlying element
changes and history. The selected layer extension maps notebook metadata to
matching SVG groups on each independent page and commits group edits through
Write actions. The [source comparison](research_notes/Component%20ownership%20decisions/ink.md#who-owns-named-layers-across-independent-svg-pages)
shows Write's existing group support and why Xournal++'s complete layer
controller cannot be used without its separate document model.
The custom extensions above follow from fixed-page and source-preservation
requirements. Their source modules, inputs, outputs, and approval are the
architecture decision; they do not authorize another ink editor subsystem.

## Candidate decision

| Candidate | Decision evidence |
| --- | --- |
| [MyScript iink](https://developer.myscript.com/docs/interactive-ink/4.4/concepts/responsive-layout/) | It supplies handwritten responsive layout and JIIX stroke export, but its [web architecture](https://developer.myscript.com/docs/interactive-ink/latest/web/websockets/architecture/) performs recognition on a server; the notebook must edit offline in the browser. Native use adds [device activation and licensing](https://developer.myscript.com/pricing). |
| [PencilKit](https://developer.apple.com/videos/play/wwdc2020/10107/) | Native iPad selection and insert space are available, but it has no browser host and does not own the shared document engine. |
| [Rnote](https://github.com/flxzt/rnote) | Its vertical-space tool moves strokes over visual page boundaries; [its author states](https://github.com/flxzt/rnote/discussions/1316) that pages are regions of one continuous canvas, not independently identified page objects. Its Rust/GTK app stores `.rnote` JSON. |
| [Xournal++](https://github.com/xournalpp/xournalpp) | It offers vertical space and SVG export in its desktop GTK app. Its inspected [manual](https://github.com/xournalpp/xournalpp/wiki/User-Manual) does not establish ruled word reflow or iPad/browser builds. |
| [Google Ink](https://github.com/google/ink) | It owns brush construction and geometry in the deployed engine; its documented modules do not own ruled word/line reflow or full notebook history. Mixing its outline with Write's erase path requires a new path decoder. |
| [Lager](https://github.com/arximboldi/lager/blob/ddf87b467dca57cb03fb5ff94dff9ca2c633a15e/doc/modularity.rst#L186-L284) | Its `history_model` is a documentation example, not a distributed history facility. Write's own grouped history operates on the selected authoritative model. |

## Integration acceptance

Use saved mixed-content notebook fixtures on web and iPad. Ruled and unruled
selection, erasure, insertion, and reflow preserve editability, page/layer
membership, source IDs and original samples. Overflow crosses the final page,
creates a template page, and one undo restores all affected pages. Save and
reopen preserve the same source, SVG figure, InkML traces, and visible result.
Skia SVG rendering must show ink, text, images, labels, and figure groups on
both hosts. Host pen/finger behavior is accepted under
[tablet-ui.md](specs/tablet-ui.md) and the [UI owner decision](research_notes/Component%20ownership%20decisions/ui.md).
