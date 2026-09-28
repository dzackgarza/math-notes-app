# Web daily-use implementation handoff

Date: 2026-09-28. Branch: `write-core-integration`.

## Next work: the editor toolbar and tool popovers

The [delivery order](web-daily-notes-handoff.md#delivery-order) is strict.
Phase A, the core note-taking features, is the active work. The editor chrome
does not match the [tablet interface](../specs/tablet-ui.md#editor): the rail
shows presets as separate tools, the pen popover mixes tool kinds, and the
bottom bar holds zoom and paper controls. Earlier sessions built later-phase
features (PDF import, split view, conflicts, layers, clippings, ruled
editing, bookmarks, typed text, figures) before their phase. That code
stays. It gets no further work until its phase starts.

### Phase A work in order

All work is in `hosts/web/flutter/lib/notebook.dart` and `main.dart`.
Dependencies: `flex_color_picker` (HSV wheel), `pull_down_button` (iOS
pull-down menus), `popover`.

1. Dark Cupertino theme for the whole app.
2. Floating vertical icon toolbar, one icon per tool kind, scrollable.
3. Per-tool popovers: pen (stroke sample, pressure pen or marker, size
   presets, slider, advanced tab with opacity), highlighter, eraser modes,
   lasso modes (freehand, rectangle, oval, ruled). Oval selection needs an
   engine selector kind.
4. Color swatches on the toolbar; the HSV wheel edits a swatch; **+** edits
   the visible palette. Delete the browser color input.
5. Saved pens: **Save** in the popover adds a toolbar shortcut.
   Per-kind tool settings and the palette persist in `.pens.json`; extend
   [FORMAT.md](../FORMAT.md) first.
6. Undo and redo on the toolbar, with the rewind dial from Write's
   `ButtonDragDial`.
7. Top-right pull-down menus: pages, view, and ⋯ as specified.
8. Delete the bottom bar, the zoom menu, the paper menu, and the in-note tag
   control. Fit width keeps the scroll position.

Preserve these pre-existing user files with their current untracked status.
They are the reference for the pen tool popover:

- `noteful-customize-pencil.webp`
- `noteful-pen-tool.webp`

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
| `cd7eddb` | Conflict comparison when an indexed page's current file was externally deleted. |
| `890c083` | Creation location picker and shared removable tags. |

Figure integration lives in `hosts/web/src/editor/figure-editor.ts`,
`hosts/web/flutter/lib/figure_editor.dart`, `core/src/document/figures.*`,
and the figure C ABI in `core/src/ink.cpp`.
`build-tikz.mjs` builds the pinned full editor and embed protocol. Generated
upstream workspaces are under `.ci`; preserve the vendor boundary.

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
- Phase F: an integration layer on the reusable TikZ workbench module,
  blocked until that module is complete. Diagram-skeleton extraction and
  Copy TikZ follow the
  [TikZ contract](../specs/tikz-drawing-mode.md).

## Evidence and practical limits

Native engine targets, the Flutter/TypeScript host build, and the Dart
analyzer succeeded for the tag form. These are implementation checks, not
full product acceptance.

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

Build log: `/tmp/math-notes-final-host-build.log`. Generated sources and
fonts remain in ignored `.ci` paths for resumption.

For future native rebuilds, keep emcc in `PATH` during CMake regeneration.
Build `engine` and `engine_test` targets, then copy both generated module/type
triples to `hosts/web/src/engine/wasm/` before the host build. This generates
the wrapper types without requiring a test-suite run.
