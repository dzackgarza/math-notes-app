# V1 ruled ink editing decision

The [initial dependency proposal](source/initial-dependency-proposal.md) and
[initial file-format proposal](source/initial-file-format-proposal.md) are
historical inputs. The current [architecture](ARCHITECTURE.md) and
[format](FORMAT.md) set the v1 contracts. This decision covers issues #30 and
#31 only. The [whole-editor review](ink-reflow-owners.md) is post-v1.

## Selected owner

The current Math Notes `Document`, `Page`, `Editor`, `Selection`, and
`DocumentHistory` own editable notebook ink. Google Ink at
`1b220eee5a05e9b67be9f20f49ae2d574c8667a7` owns stroke outlines and
geometry. For ruled operations, adapt the algorithms in Stylus Labs Write
at `401b65d5fe0294cc83171b76a0273b6df3afc979` under AGPL-3.0. This
is a bounded source port into the current editor, not a linked Write
application or a replacement document model.

The [ink survey](research_notes/Component%20ownership%20decisions/ink.md)
compares Write, MyScript, Rnote, Xournal++, Google Ink, and Lager with source
links, licenses, host support, and format limits. Google Ink's documented
modules stop at strokes and geometry. MyScript's web editor needs its service
for interactive ink. Rnote's pages are a view of a continuous canvas and its
native file is compressed JSON. The inspected Xournal++ sources and manual
show vertical space but do not establish ruled word reflow or both required
hosts. Write is the mature behavior source for these operations, but its
`Selection`, SVG `Element`, `Page`, `ScribbleArea`, and `UndoHistory` are
coupled. Importing those classes would transfer the working ink model and
file semantics. A source port of the applicable operations is the selected
v1 integration.

## Exact mapping

| Reuse at the pinned Write revision | Math Notes boundary | Product-owned residue |
| --- | --- | --- |
| `Page::getLine`, `yruling(true)`, and stroke center-of-mass line assignment in `syncscribble/page.cpp`, plus stroke grouping in `scribblearea.cpp` | Derive a page line index from `Page` ruling fields in `core/src/document/`; expose it to `core/src/selection/`. For a blank page, use Write's default 40-unit spacing (19.2 pt) and anchor its offset to the gesture. | Keep this working grid out of the saved SVG background. |
| `RuledRange`, `RuledSelector::selectRuled`, `findStops`, and `selectRuledAfter` in `syncscribble/selection.cpp` | Add ruled range and column stop calculations beside `core/src/selection/selection.h`; use `ElementBounds` and existing Google Ink hit geometry | Map the selected `ElementRef`s across named layers, preserving IDs and locked-layer rules. |
| Write ruled eraser's selection union and stroke deletion commands in `scribblearea.cpp` | Feed ruled membership into `Editor`'s existing erase/delete and `DocumentHistory::Push` | Keep the Math Notes page/layer membership and one-step history value. |
| `Selection::insertSpace` and `Selection::reflowStrokes` in `syncscribble/selection.cpp`; vertical and horizontal insert-space commands in `scribblearea.cpp` | Adapt the word-gap, column-stop, line-shift, and overflow calculations to immutable `Document` values; commit through one `DocumentHistory::Push` | Continue overflow across independent fixed-size page SVGs, create a page via `NewPage`/`InsertPage`, preserve object IDs and authored source, and include all changed pages in one undo step. |

Use the existing engine's transforms, element bounds, page operations, and
history. Add C ABI commands in `core/include/ink.h` for ruled selection,
ruled erasure, vertical/horizontal/ruled insert space, and reflow. The web
and iPad hosts send tool coordinates and display results; their platform
components retain scroll and gesture control. No host computes notebook
reflow.

The new code is a source-attributed algorithm adaptation where Write's
behavior fits. The novel product rule is fixed-page overflow across
independent SVG files: Write expands a page, while Math Notes has stable page
files. That rule acts on `Document` values and uses existing page creation.
Every altered page remains standalone SVG. A single undo restores all
affected pages; save and reload preserve IDs, samples, layers, and figure
source.

## Acceptance

Issue #30 proves ruled and inferred-line selection, column stops, line
movement, and ruled erasure on saved notebooks. Issue #31 proves each
insert-space mode, word reflow, later-page overflow, template-page creation,
and one-step undo on both hosts. Write tests 7, 8, 9, 11, and 15 supply
behavior examples; Math Notes format and product rules decide the expected
result.
