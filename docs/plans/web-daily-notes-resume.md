# Web daily-use implementation handoff

Date: 2026-09-28. Branch: `write-core-integration`.

## Next work: core note-taking features

The [delivery order](web-daily-notes-handoff.md#delivery-order) is strict.
Phase A, the core note-taking features in #56, is the only active work. Earlier
sessions built later-phase features (PDF import, split view, conflicts,
layers, clippings, ruled editing, bookmarks, typed text, figures, a TeX
compiler) before phase A passed. That code stays. It gets no further work
until its phase starts.

Preserve these pre-existing user files with their current untracked status.
They are the reference for the pen tool popover:

- `noteful-customize-pencil.webp`
- `noteful-pen-tool.webp`

### Phase A work, in order

Phase A is every L0 and L1 feature of [core features](../specs/core-features.md).
The missing ones, in order:

1. **Page orientation (L1).**
2. **Remove the superseded TeX compiler integration.** Compiler, preamble,
   compiled-page view, their build recipes, and cache entries.

## Current application

| Address | State |
| --- | --- |
| `http://localhost/math-notes/` | Existing Solid host; primary transition remains required. |
| `http://localhost/math-notes/flutter/` | Flutter preview, with the saved folder connection. |
| `http://localhost/math-notes/flutter/?root=opfs` | Flutter preview using browser storage. |

## Implemented paths and ownership

| Checkpoint | Implementation |
| --- | --- |
| `f9de046` | MuPDF worker PDF import, per-page durable saves, fixed page sizes, Flutter split views sharing live documents. |
| `7f73750` | External-change conflict copies, file comparison, byte rechecks, keep-current/copy/both choices. |
| `a24689c` | Layer visibility, locking, order, merge/delete, and PDF layer selection. |
| `f45771c` | Editable clippings, page-positioned drops, recovery of interrupted initial notebook saves. |
| `1d75313` | Ruled selection/erase and fixed-page space insertion/reflow. |
| `dbfd524` | Bookmarks, links, destination navigation, PDF annotations. |
| `d355bc2` | Skia Paragraph text shaping, wrapping, bidi, source retention, and pinned font assets. |
| `caa4c8d` | Complete upstream TikZ Editor iframe and durable source drafts. |
| `827fdf3` | LuaLaTeX adapter, project preamble UI, MuPDF SVG output, compiled vector/PDF/source acceptance. |
| `cd7eddb` | Conflict comparison when an indexed page's current file was externally deleted. |
| `890c083` | Creation location picker, shared removable tags, resumable TeX input download. |

Figure integration lives in `hosts/web/src/editor/figure-*.ts`,
`hosts/web/flutter/lib/figure_editor.dart`, `core/src/document/figures.*`,
`core/src/render/figure_view.*`, and the figure C ABI in `core/src/ink.cpp`.
`build-tikz.mjs` builds the pinned full editor and embed protocol. Generated
upstream workspaces are under `.ci`; preserve the vendor boundary.

The installed MuPDF JavaScript `DocumentWriter` already exposes the native
SVG writer with `text=path`. A new MuPDF binding is unnecessary for this path.
Compiled figure acceptance stores immutable source/scene/PDF sidecars, an
embedded SVG view, and preserved original ink in one history edit. The scene's
`editor` record keeps source and preamble. Its original FreeTikZ geometry is
still the capture geometry; it is not a complete semantic mapping of edits.

## Later-phase gaps

Record only. These wait for their phase.

- Phase B: primary Flutter deployment; tablet-spec creation details, paper
  names, singular note counts, Settings placement.
- Phase D: multiple pending browser recovery records make `pendingRecovery`
  in `editor/notebook.ts` throw; conflict comparison uses static previews
  without selective stroke transfer; deletion conflicts lack a selectable
  version; split-view drag copies instead of moving; ruled reflow on mixed
  pages and columns, negative space, live preview, and Write's
  timestamp-grouped stroke centers; #50 fixture reproducibility.
- Phase F: diagram-skeleton extraction and Copy TikZ per the
  [TikZ contract](../specs/tikz-drawing-mode.md).

## Evidence and practical limits

Native engine targets and the Flutter/TypeScript host build succeeded for
the figure changes. The tag-form Dart analyzer reported no issues. The
final preview build includes the tag form. These are
implementation checks, not full product acceptance.

A headless Chromium session rendered the preview library and creation form.
The form exposed the new location picker and removable tag control. Creating
`Lecture notes` with the `algebra` tag produced the corresponding folder and
tag controls in the library. This used an isolated browser-storage context.
Screenshot: `/tmp/math-notes-creation.png`. Full deployed daily-use sessions
and the complete interpreted-diagram copy workflow remain unverified.

The configured Chrome MCP tool expects a missing Google Chrome executable.
The existing Chromium executable works with the installed CLI:

```sh
bunx --package chrome-devtools-mcp chrome-devtools start \
  --executablePath /bin/chromium --headless --no-usage-statistics
```

CLI page commands require the page ID as the first positional argument.
Use a fresh isolated context for a new deployment inspection; existing
Workbox-controlled pages retain the active version until its pages close.
The browser daemon was stopped for this handoff.

Build logs: `/tmp/math-notes-final-host-build.log`,
`/tmp/math-notes-figure-compile-host-build.log`, and
`/tmp/math-notes-tex-build.log`. Generated sources, fonts, and compiler inputs
remain in ignored `.ci` paths for resumption.

For future native rebuilds, keep emcc in `PATH` during CMake regeneration.
Build `engine` and `engine_test` targets, then copy both generated module/type
triples to `hosts/web/src/engine/wasm/` before the host build. This generates
the wrapper types without requiring a test-suite run.
