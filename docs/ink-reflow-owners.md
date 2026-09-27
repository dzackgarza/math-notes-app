# Post-v1 ink ownership candidate

Review scope: a post-v1 refactor of the shared ink editor. The current
Google Ink and Math Notes engine remain the v1 owners. The research below
records one candidate and its integration costs; it is not a selected
replacement or a prerequisite for [#30](https://github.com/dzackgarza/math-notes-app/issues/30)
and [#31](https://github.com/dzackgarza/math-notes-app/issues/31).
Survey date: 2026-09-27. Full search queries, sources, license and host evidence:
[ink ownership research](research_notes/Component%20ownership%20decisions/ink.md).
Implementation policy: [component ownership](ARCHITECTURE.md#component-ownership).

## Write candidate

[Stylus Labs Write at `401b65d5fe0294cc83171b76a0273b6df3afc979`](https://github.com/styluslabs/Write/tree/401b65d5fe0294cc83171b76a0273b6df3afc979)
is a candidate for a later whole-editor comparison. Its native iOS and
Emscripten build branches and AGPL-3.0 source make it relevant to both hosts.
The upstream application supplies:

| Behavior | Upstream owner |
| --- | --- |
| SVG document, pages, elements, page load/save | `Document`, `Page`, `Element`, `usvg` parser/writer |
| Pen and highlighter paths, pressure, filters | `StrokeBuilder`, `ScribblePen`, input processors |
| Ruled line/word/column selection, lasso, transforms | `Selection`, `RuledSelector`, `Page::getLine`, relevant `ScribbleArea` commands |
| Ruled reflow, horizontal/vertical insert space | `Selection::reflowStrokes`, `insertSpace`, relevant `ScribbleArea` commands |
| Free erase and path rebuild | `Element::freeErase`, `toPenPoints`, stroke builder path classes |
| Undo/redo across pages | `UndoHistory`, stroke/page undo items, multi-page action groups |

The inspected replacement would require extracting commands from
`ScribbleArea`, changing the authoritative SVG document and history model,
replacing Google Ink brush output, and adapting page rendering. It also
requires the source-fidelity and pagination extensions below. A build of a
headless subset alone proves none of those product boundaries. A post-v1
review must compare this whole cost with the then-working engine and other
complete editors before deciding whether to transfer ownership.

Write's free eraser reconstructs the path encoding produced by its own pen
builders, so retaining Google Ink outlines would require a second
erasure/rebuild path.
[Stroke builder](https://github.com/styluslabs/Write/blob/401b65d5fe0294cc83171b76a0273b6df3afc979/syncscribble/strokebuilder.cpp),
[eraser decoder](https://github.com/styluslabs/Write/blob/401b65d5fe0294cc83171b76a0273b6df3afc979/syncscribble/element.cpp#L266-L357).

## Candidate integration gaps

The notebook defines fixed-size, independently identified SVG pages and
requires original samples and authored figure source to survive editing.
Write's ruled insertion currently grows the page when reflow passes its
bottom. A fork would need to transfer the same SVG
elements to the corresponding line of the next fixed page, shift following
content, add a template page at the end, and record the whole operation in
one `UndoHistory` multi-page action.
[Write ruled command](https://github.com/styluslabs/Write/blob/401b65d5fe0294cc83171b76a0273b6df3afc979/syncscribble/scribblearea.cpp#L1850-L1873),
[multi-page history](https://github.com/styluslabs/Write/blob/401b65d5fe0294cc83171b76a0273b6df3afc979/syncscribble/syncundo.h#L192-L219).

The fork would also need SVG load/save and edit paths that preserve the notebook's
`mn:` and InkML namespaces, original sensor trace, stable IDs, figure group
and source reference. Write's non-Write import path copies only standard
attributes, and its stroke builder emits a visible path without the complete
sensor trace. A candidate implementation would keep that trace on the same
`Element` in stroke-local coordinates through transforms and erasure, and
record the change in its history.
[Page load/save](https://github.com/styluslabs/Write/blob/401b65d5fe0294cc83171b76a0273b6df3afc979/syncscribble/page.cpp),
[stroke input](https://github.com/styluslabs/Write/blob/401b65d5fe0294cc83171b76a0273b6df3afc979/syncscribble/strokebuilder.h).

Such a notebook adapter would own page identity, template choice, stable layer IDs,
names, order, visibility and lock state, changed-file list, TikZ figure
references, and the format's exact bytes. Write would own underlying element
changes and history. The layer extension would map notebook metadata to
matching SVG groups on each independent page. The [source comparison](research_notes/Component%20ownership%20decisions/ink.md#who-owns-named-layers-across-independent-svg-pages)
shows Write's existing group support and why Xournal++'s complete layer
controller cannot be used without its separate document model.
These are candidate gaps for the post-v1 comparison, not v1 implementation
instructions.

## Other candidates

| Candidate | Decision evidence |
| --- | --- |
| [MyScript iink](https://developer.myscript.com/docs/interactive-ink/4.4/concepts/responsive-layout/) | It supplies handwritten responsive layout and JIIX stroke export, but its [web architecture](https://developer.myscript.com/docs/interactive-ink/latest/web/websockets/architecture/) performs recognition on a server; the notebook must edit offline in the browser. Native use adds [device activation and licensing](https://developer.myscript.com/pricing). |
| [PencilKit](https://developer.apple.com/videos/play/wwdc2020/10107/) | Native iPad selection and insert space are available, but it has no browser host and does not own the shared document engine. |
| [Rnote](https://github.com/flxzt/rnote) | Its vertical-space tool moves strokes over visual page boundaries; [its author states](https://github.com/flxzt/rnote/discussions/1316) that pages are regions of one continuous canvas, not independently identified page objects. Its Rust/GTK app stores `.rnote` JSON. |
| [Xournal++](https://github.com/xournalpp/xournalpp) | It offers vertical space and SVG export in its desktop GTK app. Its inspected [manual](https://github.com/xournalpp/xournalpp/wiki/User-Manual) does not establish ruled word reflow or iPad/browser builds. |
| [Google Ink](https://github.com/google/ink) | It owns brush construction and geometry in the deployed engine; Math Notes already supplies document history and editing around it. Its documented modules do not own ruled word/line reflow. |
| [Lager](https://github.com/arximboldi/lager/blob/ddf87b467dca57cb03fb5ff94dff9ca2c633a15e/doc/modularity.rst#L186-L284) | Its `history_model` is a documentation example, not a distributed history facility. The current app uses its example to structure its own history. |

## Post-v1 review criteria

Compare the working v1 engine with candidates using saved mixed-content
notebook fixtures on web and iPad. Ruled and unruled
selection, erasure, insertion, and reflow preserve editability, page/layer
membership, source IDs and original samples. Overflow crosses the final page,
creates a template page, and one undo restores all affected pages. Save and
reopen preserve the same source, SVG figure, InkML traces, and visible result.
Page rendering must show ink, text, images, labels, and figure groups on
both hosts. Host pen/finger behavior is accepted under
[tablet-ui.md](specs/tablet-ui.md) and the [UI owner decision](research_notes/Component%20ownership%20decisions/ui.md).
