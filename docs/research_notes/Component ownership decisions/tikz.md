# FreeTikZ drawing editor: component ownership decision

## Which component owns the complete vector and TikZ editing surface?

### Takeaway

Select [TikZ Editor `app-v0.5.2`](https://github.com/DominikPeters/tikz-editor/tree/app-v0.5.2), pinned to commit `b8b0d0019790c512466b62ebd444b95e9db0b1fc`, as the editor integrated into the [Math Notes FreeTikZ fork at `9e5fb05c22dbc5637ff7cebf99f3dbee6f962b68`](https://github.com/dzackgarza/freetikz/tree/9e5fb05c22dbc5637ff7cebf99f3dbee6f962b68). Use its complete React editor, `@tikz-editor/core` parser/semantic/patch/SVG pipeline, and CodeMirror source editor. The FreeTikZ fork retains pen-first capture, original ink, and its specialized string-diagram vocabulary; it does not rebuild the vector editor's tools.

### Cited Findings

- The [product contract](../../specs/tikz-drawing-mode.md) requires original ink, an editable geometric scene, authored TikZ, reversible recognition, object/source selection, precision handles, layers, source-preserving edits, and a standalone page SVG. The FreeTikZ fork's [scene editor](https://github.com/dzackgarza/freetikz/blob/9e5fb05c22dbc5637ff7cebf99f3dbee6f962b68/js/editor.js) currently has freehand, point, segment, circle, label, selection/translation, JSON scene save/open, and a generated TikZ draft; its [README](https://github.com/dzackgarza/freetikz/blob/9e5fb05c22dbc5637ff7cebf99f3dbee6f962b68/README.md) makes no source-round-trip claim.
- [TikZ Editor v0.5.2](https://tikz.dev/editor/) is MIT-licensed, works in the web and a Tauri desktop app, imports existing TikZ, provides source and canvas views, paths/nodes/rectangles/circles, position/size edits, snapping, guides, group/layer order, inspectors, and a CodeMirror source panel. It states that unsupported or unusual TeX may not be interpreted visually.
- Its [repository map](https://github.com/DominikPeters/tikz-editor/blob/app-v0.5.2/AGENTS.md) separates reusable `packages/core` from the shared React `packages/app`; the [core exports](https://github.com/DominikPeters/tikz-editor/blob/app-v0.5.2/packages/core/src/index.ts) include parsing, edit sessions, semantic evaluation, SVG rendering, capability reporting, and snapping. The [package manifest](https://github.com/DominikPeters/tikz-editor/blob/app-v0.5.2/packages/app/package.json) pins its app/core/lang packages to `0.5.2` and includes CodeMirror 6 and React 19.
- TeXlyre has already integrated this editor as a [static iframe-friendly embed](https://github.com/TeXlyre/tikz-editor-embed-mirror/blob/b98714d3584ee849178f19cf44c7768ff9063f6e/README.md) with `load`, `save`, and `export` host actions and `change`, `autosave`, `save`, and SVG export events. Its [build script](https://github.com/TeXlyre/tikz-editor-embed-mirror/blob/b98714d3584ee849178f19cf44c7768ff9063f6e/scripts/build-from-upstream.cjs) accepts `TIKZ_EDITOR_REF`; pin that to `app-v0.5.2`, not its default `master`.
- [SVG-Edit V7](https://github.com/SVG-Edit/svgedit) is a complete offline-hostable SVG editor (editor plus svgcanvas), but its documented interchange is SVG, not authored TikZ source or TikZ-aware source spans. [Penpot](https://github.com/penpot/penpot) offers a full SVG design application and plugins, but its [frontend configuration](https://github.com/penpot/penpot/blob/develop/docs/technical-guide/configuration.md) requires backend and exporter endpoints; it is not a bounded folder-file figure editor. [TikZiT](https://github.com/tikzit/tikzit) is a GPL-3 Qt/TikZ diagram editor; its desktop Qt application does not supply this web/iPad embedded editor boundary. [TeXlyre](https://github.com/TeXlyre/texlyre) already embeds TikZ Editor and TeX compilation but is a complete collaborative LaTeX workspace, not a bounded figure editor within a Math Notes folder.

### Inferences

- Integrate the TikZ Editor `core` and app through the FreeTikZ fork. Keep FreeTikZ's `RawStroke` and original samples in the Math Notes scene files. On opening a figure, pass its authored `.tikz` source to the editor. On visual edits, accept only TikZ Editor's source patch for an understood object, then update the mapped scene object and page-visible SVG. This is a representation adapter: `{figure ID, source, scene, ink}` in; `{source patch, mapped geometry, visible SVG}` out. TikZ Editor owns tools, handles, snapping, grouping, layers, source editing, and its own semantic evaluation.
- The exact unsupported-syntax rule is to keep the original `.tikz` bytes, including comments, spacing and opaque commands, and show a visual limitation. Never regenerate the whole file from the scene. The [TikZ Editor capability model](https://github.com/DominikPeters/tikz-editor/blob/app-v0.5.2/packages/core/src/index.ts) and its limited parser make this an explicit interface condition, not a claim that all TeX can be parsed.
- Do not add SVG-Edit, Fabric, Paper, or a second canvas toolkit beneath TikZ Editor. They would duplicate the complete edit surface while leaving authored-TikZ semantics unresolved.

### Gaps

- The FreeTikZ scene has not yet been mapped to TikZ Editor objects. The smallest necessary local operation is stable figure/object-ID mapping between Math Notes' ink/scene files and the editor's source references; no dependency owns Math Notes' notebook identity or raw-stroke record.
- TikZ Editor's visual coverage is not arbitrary TeX. A supported-property edit must be proven against comments, macros, unknown commands, and overlapping source spans before its result is saved.

## Which component owns source-preserving TikZ parsing and source editing?

### Takeaway

Use TikZ Editor's `@tikz-editor/core` parser and source-patch engine at `app-v0.5.2`, with its CodeMirror 6 editor. Do not create a parallel `unified-latex` or tree-sitter parser for the same TikZ edit path.

### Cited Findings

- TikZ Editor builds a parser-to-semantic-scene-to-SVG pipeline and records source ranges; it reports that its edits apply small patches without replacing the source formatting ([project explanation](https://tikz.dev/editor/), [repository map](https://github.com/DominikPeters/tikz-editor/blob/app-v0.5.2/AGENTS.md)). Its [`replaceSpan`](https://github.com/DominikPeters/tikz-editor/blob/app-v0.5.2/packages/core/src/edit/patch.ts) concatenates source slices around one span; [`applyEdit`](https://github.com/DominikPeters/tikz-editor/blob/app-v0.5.2/packages/core/src/edit/apply.ts) checks target and source fingerprints and returns `unsupported` for shared or unrewritable spans.
- The [core public exports](https://github.com/DominikPeters/tikz-editor/blob/app-v0.5.2/packages/core/src/index.ts) include `parseTikz`, `createIncrementalParseSession`, `applyEdit`, `applyEditIntent`, `EditorSession`, `evaluateTikzFigure`, and `renderTikzToSvg`; the [React app manifest](https://github.com/DominikPeters/tikz-editor/blob/app-v0.5.2/packages/app/package.json) includes CodeMirror 6. The [AST](https://github.com/DominikPeters/tikz-editor/blob/app-v0.5.2/packages/core/src/ast/types.ts) has `UnknownStatement` and `UnknownPathItem`; their [mapping](https://github.com/DominikPeters/tikz-editor/blob/app-v0.5.2/packages/core/src/transform/unknown.ts) retains `raw` source slices and spans. The [round-trip tests](https://github.com/DominikPeters/tikz-editor/blob/app-v0.5.2/test/roundtrip.spec.ts) check unchanged source prefix/suffix, surrounding comments, and stable IDs for untouched items after a local edit.
- [`unified-latex`](https://github.com/siefkenj/unified-latex/blob/main/CHANGELOG.md) documents TikZ environment parsing and source positions, but its changelog does not establish an interactive TikZ semantic edit/patch surface. [`tree-sitter-latex`](https://github.com/latex-lsp/tree-sitter-latex) explicitly describes best-effort LaTeX parsing focused on language-server constructs and says full TeX parsing is impossible in its grammar.

### Inferences

- The authoritative unit is the exact `.tikz` source file. The editor parser supplies recognized object spans; source edits change those spans only. Unknown syntax remains opaque source, and the figure's visual scene is partial when the parser cannot interpret it.
- CodeMirror selection ranges and TikZ Editor semantic source references should carry source-to-canvas highlighting. Math Notes' adapter only relates its stable scene ID to that source reference.

### Gaps

- The examined parser and patch source establish a suitable mechanism, not full coverage of all TikZ libraries or macros. The source-round-trip acceptance set in the product contract still needs fixture proof.

## Which component owns nonlinear geometric relations and recognition?

### Takeaway

Select [`@salusoft89/planegcs` 1.2.0](https://github.com/Salusoft89/planegcs/tree/1.2.0), pinned to `ee9b156da9827a91a56a888a53520f63d5cffaa6`, for persistent nonlinear geometric constraints. Select [Xournal's `xo-shapes.c` at `982874f254c3e03d4def80c44012f1e0bd222377`](https://github.com/ricardoamaro/xournal-code/blob/982874f254c3e03d4def80c44012f1e0bd222377/src/xo-shapes.c) as the primitive recognition reference, adapted to reversible suggestions; select [Hobby Curve Editor `91721714f9ede798fb9396553fbaf4cc48447204`](https://github.com/max-schwegele/hobby-editor/tree/91721714f9ede798fb9396553fbaf4cc48447204) as the reference/adapted owner of pen-first Hobby-curve controls and TikZ emission.

### Cited Findings

- Planegcs is an LGPL-2.1 [WebAssembly wrapper of FreeCAD's 2D geometric solver](https://github.com/Salusoft89/planegcs). Its documented `GcsWrapper` API accepts JSON primitives, calls `solve()` and `apply_solution()`, and covers points, lines, circles, arcs, ellipses, conics, B-splines, and the upstream constraints. It supports non-driving and temporary drag constraints, and documents DogLeg, Levenberg–Marquardt, BFGS and SQP methods ([README](https://github.com/Salusoft89/planegcs/tree/1.2.0#readme)).
- [SolveSpace `libslvs`](https://github.com/solvespace/solvespace/blob/master/include/slvs.h) has a C solver API with equal length/radius, parallel, perpendicular, point-on-circle, arc/curve tangency and drag constraints. [SolveSpace](https://github.com/solvespace/solvespace) is GPL-3.0 and offers a native C/C++ library interface; its [library documentation](https://solvespace.github.io/solvespace-web/library.html) does not provide a supported browser package. Planegcs is selected because it already exposes the broad FreeCAD solver in browser WASM with a TypeScript boundary.
- [Penrose](https://github.com/penrose/penrose/wiki/Getting-started) uses differentiable penalty/objective functions and an optimizer; it describes possible `NaN` results for unsatisfiable programs. That is not the same contract as preserving accepted exact CAD-style relations after a drag. [JSketcher](https://github.com/xibyte/jsketcher) has a full browser CAD sketcher and JavaScript solver, including tangent/equal-length constraints, but adopting it as the figure editor would displace TikZ Editor's source-aware edit surface. [Assemble2D](https://github.com/tab58/assemble2d) lists tangent/equal length and uses L-BFGS energy minimization, but documents fewer geometry types than Planegcs.
- [Xournal `xo-shapes.c`](https://github.com/ricardoamaro/xournal-code/blob/982874f254c3e03d4def80c44012f1e0bd222377/src/xo-shapes.c) implements inertia, segment fitting, polygons, circles and a recent-stroke recognition queue under GPL-2.0-or-later. [Hobby Curve Editor](https://github.com/max-schwegele/hobby-editor) is an MIT-licensed visual TikZ editor for Hobby curves with point/angle controls, snapping and `\usetikzlibrary{hobby}` source output; [CTAN's `hobby` package](https://ctan.org/pkg/hobby) owns TeX-side interpolation.

### Inferences

- Map scene point/segment/circle/ellipse/spline IDs to Planegcs primitive IDs; map the relation IDs to solver constraints. Submit a drag as a temporary constraint, accept the solved coordinates only on successful solve, and apply the corresponding TikZ Editor source patches. Planegcs owns the solve and failure result; the adapter owns only ID/unit mapping and transaction grouping. Relation metadata remains in the Math Notes scene file because authored TikZ need not encode every interactive constraint.
- Recognition is an offered, reversible interpretation of original ink. The recognizer cannot replace stored samples. Hobby output is an additional semantic backend; explicit Bézier control editing remains TikZ Editor's path tool where supported.

### Gaps

- Planegcs supports broad geometry but its documented API does not prove every figure relation in the contract, especially equal spacing and attachment semantics. These are composition rules over its lower-level constraints, not license to write another nonlinear solver. No recognition classifier for all mathematical domain objects was found in the inspected primary sources; contextual user confirmation and domain-specific adapters are required.

## Which component owns offline TeX compilation and final preview?

### Takeaway

Select [`texlyre-busytex` 1.4.0](https://github.com/TeXlyre/texlyre-busytex/blob/f3c8780e85939ced63133501d66b6386d89f69e4/package.json), pinned to source `f3c8780e85939ced63133501d66b6386d89f69e4`, as the shared WebAssembly TeX engine. Fork its [upstream builder](https://github.com/TeXlyre/texlyre-busytex-build/blob/f544a51a99e7d3978bb70608e927a9a23f96d4a7/Makefile) at `f544a51a99e7d3978bb70608e927a9a23f96d4a7`; add `collection-pictures 1` to its existing `texlive-extra.profile` recipe and use its existing `build/wasm/texlive-extra.fmt-rebuilt` target. Pin the builder's `URL_texlive_full_iso` to the dated official [`texlive2026-20260301.iso`](https://ctan.org/tex-archive/systems/texlive/Images), SHA-512 `4a9071bb567c3bdd6443378dedc8e485aea4a2f1203ec8ed7c17f6787093b9c37636a037032c0be63352e3d0bf98cf5616dab19fdcd7cb83f766b3e085b620ff`, and verify that digest before extraction. Bundle the resulting `.js`/`.data` locally and disable remote package fetches. Select **LuaLaTeX** for figures because PGF graph drawing requires LuaTeX. The final preview and page-visible SVG derive from compiled TeX, not TikZ Editor's approximate SVG.

### Cited Findings

- [TeXlyre-BusyTeX](https://github.com/TeXlyre/texlyre-busytex) is AGPL-3.0-or-later, exposes `BusyTexRunner`, `XeLatex`, `PdfLatex`, and `LuaLatex`, supports Web Workers, `additionalFiles`, `preloadDataPackages`, multi-file projects, PDF bytes and diagnostics. Its [1.4.0 source manifest](https://github.com/TeXlyre/texlyre-busytex/blob/f3c8780e85939ced63133501d66b6386d89f69e4/package.json) names TeX Live 2026. The [builder's profiles](https://github.com/TeXlyre/texlyre-busytex-build/blob/f544a51a99e7d3978bb70608e927a9a23f96d4a7/Makefile) show that the released basic/recommended/extra assets omit `collection-pictures`; the [builder README](https://github.com/TeXlyre/texlyre-busytex-build/blob/f544a51a99e7d3978bb70608e927a9a23f96d4a7/README.md) sends missing packages to a remote server. Thus the [`assets-v1.4.0`](https://github.com/TeXlyre/texlyre-busytex/releases/tag/assets-v1.4.0) archive is not the selected offline package set. The same pinned Makefile installs TeX Live through a profile, removes documentation and source, packages selected files with Emscripten, and rebuilds Lua formats for WebAssembly in `.fmt-rebuilt`.
- The official TeX Live [`collection-pictures.tlpobj`](https://www.tug.org/texlive/Contents/live/tlpkg/tlpobj/collection-pictures.tlpobj) lists `braids`, `dynkin-diagrams`, `forest`, `hobby`, `pgf`, `pgfplots`, `spath3`, `tikz-cd`, `tkz-euclide`, and `tikz-3dplot`. The [fixed full-release file inventory](https://github.com/TeXlyre/texlyre-busytex-build/releases/download/texlive-full-2026.1.0/texlive-full.txt) confirms PGF `positioning`, `calc`, `intersections`, `decorations`, `arrows.meta`, and graphdrawing TeX/Lua files, plus those specialty packages. The [official ISO digest](https://mirrors.ibiblio.org/pub/mirrors/CTAN/systems/texlive/Images/texlive2026-20260301.iso.sha512) fixes the builder's package source. The [full release](https://github.com/TeXlyre/texlyre-busytex-build/releases/tag/texlive-full-2026.1.0) has a 1,443,469,895-byte compressed tree, while the upstream packager uses Emscripten `--preload`; this makes the full tree an unsuitable default preload on iPad. The selected profile includes the whole TeX Live picture collection plus the existing extra profile and its transitive package dependencies.
- [TeXlyre](https://github.com/TeXlyre/texlyre) uses BusyTeX/SwiftLaTeX in a local-first browser workspace and embeds TikZ Editor. [Tectonic 0.17.0](https://docs.rs/tectonic/latest/tectonic/) is a mature embeddable XeTeX-based Rust library with pluggable bundles and native PDF output, but the cited package does not supply a browser-WASM artifact for the shared editor. [Siglum](https://github.com/SiglumProject/siglum) offers browser TeX Live 2025 and local bundles, but its documented default fetches uncommon packages on demand and relies on prior cache for offline use.
- TikZ Editor's [project description](https://tikz.dev/editor/) says its browser text/math view uses MathJax and approximates TeX. [PGF's graph-drawing manual](https://tikz.dev/gd) uses Lua algorithms, and the [PGF source README](https://github.com/pgf-tikz/pgf) recommends LuaTeX for the broadest feature coverage. [MuPDF 1.28.0's C SVG device](https://mupdf.readthedocs.io/en/1.28.0/_static/generated/c/html/output-svg_8h.html) emits a single-page SVG from rendered page commands and supports text-as-path for exact appearance; the [1.28.0 tag](https://github.com/ArtifexSoftware/mupdf/tree/1.28.0) is pinned to `205b8cf43551279d1215e88fe2845c5d595bade9`. The existing [web architecture](../../ARCHITECTURE.md) names MuPDF WASM for PDF rasterization, but the examined [`mupdf.js` package documentation](https://github.com/ArtifexSoftware/mupdf.js) only establishes pixmap rendering, not a public JS PDF-to-SVG API.

### Inferences

- Build one standalone TeX document from the project preamble, the figure's declared package/library set, and its exact `.tikz` source. Pass the preamble and source as local files through `additionalFiles`; return PDF bytes and diagnostics. This is a document-assembly adapter, not a TeX implementation. Fail visibly if a package is absent; never silently fetch it or substitute MathJax output for the final proof.
- Use TikZ Editor's SVG only for fast interaction. Run compiled PDF through MuPDF 1.28.0's `fz_new_svg_device` with text-as-path and put that vector SVG into the standalone note-page SVG; retain the PDF as the final preview and the `.tikz` as the editable source. The bounded local binding is PDF bytes in and SVG bytes out; MuPDF owns PDF interpretation and vector emission. This avoids publishing an approximate rendering when project macros or unsupported TikZ commands are present.

### Gaps

- The selected picture-inclusive `.data` asset is not prebuilt. Its size and LuaLaTeX format behavior are integration checks, not open package choices. A package failure must produce a diagnostic, not a network request.
- Embedded TeX-to-PDF compilation in an iPad `WKWebView` needs an on-device asset-loading and worker smoke test. The selected owner and bundle are fixed; this is integration proof, not a postponed component choice.

## How is the figure editor shared between the web app and native iPad app?

### Takeaway

Use the same bundled TikZ Editor/FreeTikZ figure editor on both hosts. Embed it in an isolated iframe in the web app and a bounded `WKWebView` figure panel on iPad. Keep notebook navigation, storage, ink capture and Metal canvas native on iPad. Use TeXlyre's pinned postMessage protocol as the figure document boundary; bridge it to native `WKScriptMessageHandlerWithReply` on iPad.

### Cited Findings

- The [architecture](../../ARCHITECTURE.md) requires a native UIKit/Metal iPad notebook canvas and permits host services to feed file bytes into the engine. The [drawing-mode contract](../../specs/tikz-drawing-mode.md) separates note ink/page persistence from the FreeTikZ figure editor.
- The [TeXlyre embed](https://github.com/TeXlyre/tikz-editor-embed-mirror/blob/b98714d3584ee849178f19cf44c7768ff9063f6/README.md) is a static iframe bundle with JSON-string postMessage `load`, `save`, `export` and corresponding source/SVG events. Its [integration guide](https://github.com/TeXlyre/tikz-editor-embed-mirror/blob/b98714d3584ee849178f19cf44c7768ff9063f6/TEXLYRE_INTEGRATION.md) shows the host load message; the [embed source](https://github.com/TeXlyre/tikz-editor-embed-mirror/blob/b98714d3584ee849178f19cf44c7768ff9063f6/embed/src/main.tsx) uses a virtual file reference.
- Apple's [`WKScriptMessageHandlerWithReply`](https://developer.apple.com/documentation/webkit/wkscriptmessagehandlerwithreply) defines the native-to-JavaScript request/reply bridge; [`WKURLSchemeHandler`](https://developer.apple.com/documentation/webkit/wkurlschemehandler) serves app-owned local resources. WebKit has [reported CORS restrictions on custom-scheme requests](https://bugs.webkit.org/show_bug.cgi?id=201180), so asset/worker loading must be proven on device rather than presumed from desktop Chromium.

### Inferences

- Open the bounded figure editor only after the native canvas resolves the drawing capture session. Send `{action:'load', source, autosave:1}` and figure-scene/ink data through a versioned extension to the embed protocol; receive source, SVG and explicit save/close. The host writes files into the chosen notebook folder. A source/SVG message does not grant the embedded editor direct folder access. The iPad's outer notebook scroll and inner figure-editor gestures are separate modes; the editor owns pan/zoom only while its panel has focus.
- Reuse the [TeXlyre embed mirror commit](https://github.com/TeXlyre/tikz-editor-embed-mirror/tree/b98714d3584ee849178f19cf44c7768ff9063f6) as the integration reference, with upstream built at `app-v0.5.2`. Do not copy its default `master` build setting. The unavoidable host-specific code is the two transport bindings, folder-file reads/writes, stable figure IDs, and capture-to-figure transfer; the shared editor owns the editing interactions.

### Gaps

- The current iPad app [ContentView](https://github.com/dzackgarza/math-notes-app/blob/v1-usable-library-editor/Sources/ContentView.swift) is a `TextEditor` stub. The native notebook canvas/storage prerequisite is absent, so the figure panel cannot yet attach to a real selected note. This does not alter the chosen shared editor boundary.
- `WKURLSchemeHandler` and worker/WASM loading require an on-device proof before shipping the iPad panel. If custom-scheme worker loading fails, the selected bounded web editor remains; the asset transport must use a supported local WebKit loading mechanism, not a remote compiler.

## What exact searches support this decision?

### Takeaway

The search covered complete TikZ and SVG editors, source parsers, nonlinear solvers, Hobby/recognition implementations, offline TeX engines, and iPad embedding. It found a complete TikZ-native editor, so extending FreeTikZ's elementary canvas is not the selected route.

### Cited Findings

- Searches on 2026-09-27: `SVG-Edit API embedding license releases`; `Penpot architecture frontend editor plugins self host`; `TikZiT TikZ editor`; `unified latex util tikz parser positions`; `tree sitter latex tikz grammar`; `TeXlyre TikZ editor plugin`; `TikZ Editor WYSIWYG existing figures github`; `tikz.dev editor github source` led to [TikZ Editor](https://github.com/DominikPeters/tikz-editor), [TeXlyre's embed](https://github.com/TeXlyre/tikz-editor-embed-mirror), [SVG-Edit](https://github.com/SVG-Edit/svgedit), [Penpot](https://github.com/penpot/penpot), [TikZiT](https://github.com/tikzit/tikzit), [`unified-latex`](https://github.com/siefkenj/unified-latex), and [`tree-sitter-latex`](https://github.com/latex-lsp/tree-sitter-latex).
- Searches: `javascript nonlinear geometric constraint solver tangency equal length`; `sketch solver geometric constraints wasm`; `SolveSpace libslvs constraint solver C API`; `JSketcher constraint solver wasm`; `Penrose optimizer constraints geometric API` led to [Planegcs](https://github.com/Salusoft89/planegcs), [SolveSpace](https://github.com/solvespace/solvespace), [JSketcher](https://github.com/xibyte/jsketcher), [Assemble2D](https://github.com/tab58/assemble2d), and [Penrose](https://github.com/penrose/penrose).
- Searches: `Hobby spline javascript implementation`; `Xournal shape recognizer xo-shapes.c`; `Tectonic webassembly browser offline bundle`; `SwiftLaTeX browser offline package`; `BusyTeX wasm browser package`; `Siglum bundle offline API`; `WKURLSchemeHandler local resources`; `WKScriptMessageHandlerWithReply` led to [Hobby Curve Editor](https://github.com/max-schwegele/hobby-editor), [Xournal++](https://github.com/xournalpp/xournalpp), [Tectonic](https://docs.rs/tectonic/latest/tectonic/), [TeXlyre-BusyTeX](https://github.com/TeXlyre/texlyre-busytex), [Siglum](https://github.com/SiglumProject/siglum), and [Apple's reply bridge](https://developer.apple.com/documentation/webkit/wkscriptmessagehandlerwithreply).

### Inferences

- The selected owners divide at existing product boundaries: Math Notes ink/page storage; FreeTikZ capture and semantic vocabulary; TikZ Editor vector/source interactions; Planegcs constraints; Xournal/Hobby recognition and curve intent; BusyTeX final compilation. That leaves only notebook identity, figure transport, and semantic-model mapping as local adapters.

### Gaps

- No inspected complete editor combines lossless arbitrary TeX interpretation, full nonlinear relation solving, pen-first raw-sample preservation, and native notebook storage. The selected components deliberately keep these representations separate rather than claiming one editor supplies them all.
