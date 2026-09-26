# TikZ drawing mode

> Product contract for [Drawing mode issue #10](https://github.com/dzackgarza/math-notes-app/issues/10).
> The issue tree owns execution. The project agent-memory plan
> `PLAN-TIKZ-DRAWING-MODE` points here.

## Result

The user turns on Drawing mode while editing a note, draws on a page, and
turns the mode off to complete the figure. The app groups the ink made during
that interval into one selectable figure. A bounding rectangle encloses its
ink. The figure retains the strokes, an editable geometric scene, and editable
TikZ source. The user can inspect the resulting figure and source in a preview
sidebar, revise either view, and reopen the figure later. The page remains a
standalone SVG that shows the figure without the app.

The drawing editor combines the
[Math Notes FreeTikZ fork at `9e5fb05c`](https://github.com/dzackgarza/freetikz/tree/9e5fb05c22dbc5637ff7cebf99f3dbee6f962b68)
with [TikZ Editor `app-v0.5.2` at `b8b0d001`](https://github.com/DominikPeters/tikz-editor/tree/app-v0.5.2).
FreeTikZ owns pen-first capture and original figure ink. TikZ Editor owns the
vector editing surface, semantic parsing, source patches, and CodeMirror
source view. General mathematical
figures use standard TikZ and only the libraries they need. The custom
`freetikz.sty` remains relevant to its specialized string-diagram vocabulary.

## Component ownership

The [component-ownership rules](../ARCHITECTURE.md#component-ownership) and
[figure-component research](../research_notes/Component%20ownership%20decisions/tikz.md)
govern this integration. The selected owners and source pins are:

| Capability | Selected owner and exact boundary |
| --- | --- |
| Ink capture and figure persistence | The FreeTikZ fork at `9e5fb05c` receives one Math Notes capture session. The notebook keeps original samples and stable figure/object IDs in its files. |
| Vector canvas, handles, transforms, snapping, layers and source view | TikZ Editor `app-v0.5.2` / `b8b0d001`, using its full React app, `@tikz-editor/core`, and CodeMirror 6. The notebook adapter maps figure IDs, scene IDs and source spans; TikZ Editor owns the edit interaction. |
| Geometric constraints | Planegcs 1.2.0 / `ee9b156d`, a WebAssembly wrapper of FreeCAD's 2D solver. The adapter maps scene primitives and relation IDs to its `GcsWrapper`, `solve()`, and `apply_solution()`; solver failure leaves the accepted scene intact. |
| Reversible primitive suggestions | The FreeTikZ capture layer adapts [Xournal `xo-shapes.c` at `982874f254c3e03d4def80c44012f1e0bd222377`](https://github.com/ricardoamaro/xournal-code/blob/982874f254c3e03d4def80c44012f1e0bd222377/src/xo-shapes.c) for line/circle/polygon suggestions. Original ink remains; the user accepts or changes the interpretation. |
| Hobby curves | Hobby Curve Editor at `91721714f9ede798fb9396553fbaf4cc48447204` supplies the control interaction and TikZ emission reference, with CTAN `hobby` for TeX-side interpolation. |
| TikZ syntax and patches | TikZ Editor's `@tikz-editor/core` parser, semantic scene, capability report, `applyEdit`, and source-span patch machinery. It owns supported edits; unknown syntax stays authored source. |
| Offline final preview | TeXlyre-BusyTeX 1.4.0 / `f3c8780e` running LuaLaTeX with builder `f544a51a` and its `texlive-extra.profile` extended by `collection-pictures 1`; use its `build/wasm/texlive-extra.fmt-rebuilt` target. Pin the official `texlive2026-20260301.iso` input at SHA-512 `4a9071bb567c3bdd6443378dedc8e485aea4a2f1203ec8ed7c17f6787093b9c37636a037032c0be63352e3d0bf98cf5616dab19fdcd7cb83f766b3e085b620ff` and verify before extraction. Bundle `.js`/`.data` locally with remote package fetching disabled. The adapter assembles exact source, project preamble and declared libraries; BusyTeX returns PDF and diagnostics. |
| Published page-visible vector | MuPDF C SVG device 1.28.0 / `205b8cf4` converts the compiled PDF page to SVG with text as paths. The notebook embeds that SVG in the standalone note page. |
| Shared host panel | The TeXlyre TikZ Editor embed protocol at `b98714d3` loads the same editor in a web iframe and a bounded iPad `WKWebView`. The native notebook canvas and navigation remain UIKit/Metal. |

These choices precede the delivery stages. The complete pinned source links,
candidate comparisons, searches, and package limits are in the
[figure decision](../research_notes/Component%20ownership%20decisions/tikz.md).
The Math Notes code at this boundary connects capture ink, stable IDs,
scene/source mappings, file reads and writes, TeX document assembly, MuPDF
PDF-to-SVG byte transfer, and host messages. Each extension follows an exact
notebook source-preservation rule;
the selected editor, parser, solver, and TeX engine own their mechanisms.

## Mode and page interaction

1. Turning Drawing mode on starts one capture session on the current page.
   Subsequent pen strokes enter that session. Ordinary note ink remains outside
   it. The user can select, move, and edit captured strokes without ending the
   session. Page navigation or closing the note must resolve the active session
   explicitly; it must not lose ink or silently complete the figure.
2. The app preserves every original stroke and its input samples. Recognition
   adds an interpretation; it never destroys the ink. The user can accept,
   reject, or change an interpretation.
3. Turning Drawing mode off completes the current session. The app computes
   the union of the captured strokes' page-space bounds and places a very
   subtle neutral rectangle around them. During capture the boundary uses a
   dashed accent; an active selection uses the normal selection outline. The
   boundary is editor chrome, not part of the exported figure. The figure is
   one selectable page object for move, resize, copy, and delete. Reopening it
   restores the scene, source, and original ink for further editing. An empty
   session creates no figure.
4. The rectangle identifies the work captured in that session. It is an edit
   boundary, not a page background or an image export. If a figure is moved or
   resized, its bounds and contents change together. Two completed sessions
   remain two figures until the user explicitly groups them.
5. The preview sidebar shows the interpreted figure and the current TikZ
   source. It identifies recognition choices and errors. Canvas selection
   selects the corresponding source range; source selection identifies the
   corresponding canvas object. Fast preview may approximate TeX, but any
   final rendered preview used to judge labels or layout uses the project
   preamble and TeX engine.

## Figure representation and ownership

The persistent representation separates three kinds of information:

| Part | Owns |
| --- | --- |
| Original ink | Pen samples and visible stroke outlines, unchanged by recognition. |
| Geometric scene | Objects, styles, control points, constraints, relations, groups, layers, and stable IDs. |
| TikZ source | Authored text, object-to-source ranges, and opaque commands the visual editor cannot interpret. |

The geometric scene starts with `RawStroke` and supports `Point`, `Line`,
`Ray`, `Segment`, `Circle`, `Ellipse`, `Arc`, `BezierCurve`, `Spline`,
`ClosedRegion`, `Node`, `Arrow`, `Text`, `MathLabel`, and `Group`. Relations
include coincidence, point-on-curve, parallelism, perpendicularity, tangency,
equal length or radius, alignment, equal spacing, symmetry, intersection, and
attachment. A domain-specific layer may add mathematical objects and lower
them to this geometric scene; it must not replace the general scene.

The scene is the editable interpretation of the figure, not a coordinate trace.
The source is authoritative wherever the user has edited it. A visual edit
changes only the syntax owned by the edited object or property. Unrecognized
TikZ remains intact as opaque source. TikZ Editor's parser and patch engine retain
source ranges, comments, spacing, and unknown commands. A source edit updates
the visual object when its syntax is understood; otherwise it stays visible as authored
source and reports the visual limitation. Saving never replaces authored TikZ
with regenerated output.

Math Notes stores the figure with the notebook files. The page SVG contains a
standalone visible representation derived from the compiled PDF through
MuPDF's SVG device, plus a stable figure reference. The editable
scene, ink, and `.tikz` source are documented files in the notebook, not a
private app database or a raster-only image. A figure copied to another note
brings those files and receives new object IDs. The on-disk figure schema is
in [FORMAT.md](../FORMAT.md); it preserves independent SVG pages, in-place
saves, rebuild from the folder, and deterministic bytes across hosts.

## Recognition and geometry

The processing path is:

`ink → geometric primitives → constraints and relations → mathematical objects → TikZ`

Freehand recognition is one way to create or revise scene objects. Direct
creation and selection work without recognition. Initial recognition reduces
strokes to salient endpoints, extrema, inflections, intersections, and pinned
points. The user can retain raw ink, accept a suggested primitive, or select a
different one. Sophisticated automatic classification comes after the editable
scene and source workflow. The selected Planegcs and Xournal components under
[Component ownership](#component-ownership) own the initial relation and
primitive-suggestion mechanisms.

Beautification uses relations before independent coordinate snapping. It can
infer a common coordinate frame, exact parallelism and perpendicularity,
midpoints, rectangles, symmetry, and equal spacing. Approximate coordinates
may become small integers or rationals and common angles such as 30, 45, 60,
and 90 degrees. A relation the user accepts must remain exact when the figure
changes. Snapping controls cover grid, points, anchors, midpoints,
intersections, tangencies, horizontal and vertical directions, angle steps,
baselines, and equal spacing. Constraints are inspectable and removable.

## Editing surface

The drawing editor provides select and multiselect, freehand, node/path,
line/polyline, Bézier/spline, circle/ellipse/arc, polygon/region, and TeX-label
tools. Selection exposes handles and numeric position, dimension, radius,
angle, and control-point fields. Bézier nodes support cusp, smooth, and
symmetric modes. The user can group, set layers and z-order, duplicate,
rotate, reflect, align, and distribute objects. Constraints can be created
from a selection, such as two parallel segments or a point on a curve. TikZ
Editor supplies these editing mechanisms through the FreeTikZ fork.

A label stores arbitrary project TeX, including macros. The figure reads the
project preamble or a designated figure preamble. Label properties include
anchor, side, offset, rotation, sloping, swap, alignment, text width, and
background. An edge label belongs to its edge. Browser rendering may be fast
and approximate; final label bounds come from the TeX engine.

## TikZ output

Generated source expresses recognized structure. Named nodes and relative
positioning express layouts; `calc` expresses derived coordinates;
`intersections` expresses intersection points. Repeated styles and spacing
become named definitions when this shortens and clarifies the source. The
generator prefers exact relations, small rational values, standard
constructions, and readable names over unrelated decimal coordinates. It
keeps a plain-TikZ representation available when a specialized backend does
not apply.

Smooth hand-drawn curves are reduced to salient points. The default semantic
backend may emit Hobby splines; the user can convert a curve to explicit
Bézier controls for precision editing. Backend adapters may target TikZ
`positioning`, `calc`, `intersections`, `arrows.meta`,
`decorations.markings`, Hobby, `spath3`, `braids`, `tikz-cd`, graph drawing,
`forest`, `tkz-euclide`, `pgfplots`, `dynkin-diagrams`, and `tikz-3dplot`.
Each adapter declares the required package or library. The plain-TikZ path
continues to work when an adapter is absent. A specialized backend cannot
erase scene semantics or authored source. BusyTeX compiles with the bundled
extra-plus-pictures TeX Live 2026 profile through LuaLaTeX; an unavailable package
produces a visible diagnostic. TikZ Editor's quick SVG supports interaction;
the compiled PDF and MuPDF vector SVG supply the final preview and page view.

Diagram vocabularies may add topology, algebraic geometry, toric and lattice,
or categorical objects. They are modes of one editor, with shared scene and
source rules. Contextual confirmation of a crossing, singularity, branch
point, morphism, or other semantic object can precede automatic recognition.

## Delivery order and acceptance

| Stage | Result and proof |
| --- | --- |
| 1. Scene and capture | Toggle Drawing mode, draw, complete, save, reload, and reopen a figure. The same strokes, samples, IDs, scene objects, bounds, and page SVG survive. Selection and geometric editing work. |
| 2. Source round-trip | Edit a supported TikZ property and see the canvas change; edit the canvas and see only its owned source span change. Comments, whitespace, and unknown commands survive save and reload. Source and canvas selection correspond. |
| 3. Labels | A figure with custom project macros renders with the project preamble. Label moves remain attached to their semantic object; final bounds agree with TeX output. |
| 4. Relations and generation | Accepted constraints remain exact after edits. Generated source uses relative nodes, derived points, and shared styles where those relations exist. |
| 5. Precision editing | Curves, layers, alignment, style controls, and numeric edits survive save and reopen. The sidebar shows the compiled figure and diagnostics. |
| 6. Semantic backends | Each added backend proves a representative semantic figure can be edited through both canvas and source, compiled with its declared libraries, and kept in the note. |
| 7. Recognition | Representative pen sketches offer correct, reversible interpretations without changing the stored ink. |

The first usable research-note workflow is draw, label, inspect, complete,
reopen, and copy TikZ. Publication refinement uses the same figure: constrain,
align, edit controls and source, and compile with the paper preamble. There is
no export-and-reimport step between those workflows.

## Existing feature tree

The root is [#11](https://github.com/dzackgarza/math-notes-app/issues/11).
Drawing work belongs under feature additions
[#17](https://github.com/dzackgarza/math-notes-app/issues/17). The active
editing baseline [#56](https://github.com/dzackgarza/math-notes-app/issues/56)
remains a prerequisite to treating the web app as usable.

| Existing issue or contract | Disposition |
| --- | --- |
| [#10](https://github.com/dzackgarza/math-notes-app/issues/10) drawing mode | Tracks the bounded figure and editor workstream. |
| [#35](https://github.com/dzackgarza/math-notes-app/issues/35) iPad Pencil interactions | Keeps the Write-parity tools and Pencil gestures. Figure-completion feedback applies to the drawing-mode interaction. |
| [#9](https://github.com/dzackgarza/math-notes-app/issues/9) layers | Keep notebook layers. TikZ Editor owns figure-internal layer order; the figure scene stores it. |
| [#29](https://github.com/dzackgarza/math-notes-app/issues/29) PDF export | Keep. Export must paint the page-visible figure. |
| [#33](https://github.com/dzackgarza/math-notes-app/issues/33) clippings | Keep. A completed figure can be selected and clipped without flattening its edit state. |
| [#60](https://github.com/dzackgarza/math-notes-app/issues/60) image tool | Keep. A general image is not a TikZ figure. |
| [#61](https://github.com/dzackgarza/math-notes-app/issues/61) text tool | Keep. General page text is distinct from a TeX label owned by a figure. |
| [#49](https://github.com/dzackgarza/math-notes-app/issues/49), [#58](https://github.com/dzackgarza/math-notes-app/issues/58), [#62](https://github.com/dzackgarza/math-notes-app/issues/62), [#63](https://github.com/dzackgarza/math-notes-app/issues/63) | Keep their notebook, note, tab, and draft behavior. |
| [#8](https://github.com/dzackgarza/math-notes-app/issues/8) PDF annotation | Keep. Its page backgrounds and imported page sizes are independent of figures. |

Issue #10 groups independently trackable scene/capture, source round-trip,
label/preamble, constraints/generation, precision editing, and backend work.
Issue nodes are tracking units, not prescribed PR boundaries. The first
coherent implementation milestone should cover the complete mode-to-embedded-
figure workflow before a PR is opened.

## Integration acceptance

One figure created from a note capture must reopen in both hosts with the
same ink, scene IDs and authored `.tikz` bytes. A visual edit changes only
the source span owned by the edited object. Unsupported TikZ, comments and
macros survive save and reopen. Planegcs keeps accepted relations after a
drag. The bundled extra-plus-pictures TeX Live profile compiles the declared package
set offline and returns a final PDF preview or a package diagnostic. MuPDF
1.28.0 turns that PDF into the page's standalone vector SVG. The iPad figure
panel proves local asset and worker loading on device while the outer note
continues to use its native UIKit canvas. The packaged profile
must fit the actual SideStore install path and the browser's offline storage
on supported devices. The [figure decision](../research_notes/Component%20ownership%20decisions/tikz.md)
records why the full release is not the preload choice; the generated WebAssembly data
package size is not yet established.
