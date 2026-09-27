# Web daily-use implementation handoff

Date: 2026-09-27. Branch: `write-core-integration`.
Implementation checkpoint: `890c083`.

## Scope and stopping point

Continue the complete [daily-use milestone](web-daily-notes-handoff.md).
The milestone remains incomplete. The current pause is a requested session
handoff. Framework selection and feature scope remain settled by
[ARCHITECTURE.md](../ARCHITECTURE.md) and the linked product contracts.

Prioritize the usable product and complete user workflows. Defer broad test
expansion and release administration until the working v1 warrants them.
There is no restriction to execution on this machine. Use standard platform
pen and touch interfaces. Browser automation provides synthetic input evidence;
it does not establish physical-input acceptance.

The source tree contains committed implementation work. Preserve these
pre-existing user files with their current untracked status:

- `noteful-customize-pencil.webp`
- `noteful-pen-tool.webp`

## Current application

| Address | State |
| --- | --- |
| `http://localhost/math-notes/` | Existing Solid host; primary transition remains required. |
| `http://localhost/math-notes/flutter/` | Flutter preview, with the saved folder connection. |
| `http://localhost/math-notes/flutter/?root=opfs` | Flutter preview using browser storage. |

The preview includes the implementation through `890c083`. The figure editor
loads, but its compiler assets are still absent. Compilation cannot complete
until the source build below is installed and the host is rebuilt.

## Compiler build running in the background

The compiler recipe is running under `nohup`, with output in
`/tmp/math-notes-tex-build.log`. Inspect that log and the running process before
starting another build. Downloads and builds can continue across this handoff.
The recipe resumes partial downloads and verifies the complete pinned
SHA-512 digest before extraction. Retain the ISO at
`.ci/busytex-build/source/texlive2026.iso`.

If the process has exited before completion, resume with:

```sh
MATH_NOTES_TEX_BUILD="$PWD/.ci/busytex-build" just web-figure-compiler \
  > /tmp/math-notes-tex-build.log 2>&1
```

The builder is pinned to `f544a51a99e7d3978bb70608e927a9a23f96d4a7`.
The input is `texlive2026-20260301.iso`. The recipe extends the generated
extra profile with `collection-pictures 1` and builds
`build/wasm/texlive-extra.fmt-rebuilt`. The source build has not reached
extraction or compilation. Resolve actual build errors against upstream
sources; preserve the selected compiler and package profile.

`gperf` and `strace` were installed from system packages. Other inspected
prerequisites include `7z`, `bsdtar`, `dos2unix`, `bwrap`, `tex`, Perl, and wget.
The recipe uses the repository Emscripten environment. Successful completion
places browser assets and a manifest in `.ci/figure-compiler`.

Then run `just _flutter-host` and copy `hosts/web/flutter/build/web/` to
`/var/www/math-notes/flutter/` with `rsync -a`. Exercise actual source editing,
compilation, save, reopen, undo, copy, and PDF export before calling the figure
workflow complete. `just web-deploy` still deploys the primary host and can
delete the preview directory; adapt the primary entry points when completing
the Flutter transition.

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

## Remaining required work

### Figures: issue #10

- Finish source-object identity and scene/source mappings for edited geometry.
- Integrate the selected Planegcs constraint solver, reversible primitive
  suggestions, Hobby curves, and the specified precision tools and labels.
- Preserve authored and opaque source through all visual edits. Use the
  selected editor and dependency owners rather than a replacement subsystem.
- Complete compiled preview and saved/reopened figure workflows after the
  compiler build. The existing iframe and compiler button alone do not meet
  the complete figure contract.

### Durability, conflicts, and transfers

- Multiple pending browser recovery records currently cause `pendingRecovery`
  in `editor/notebook.ts` to throw. Provide a usable recovery path preserving
  each version.
- Conflict comparison uses static previews. Editable comparison and selective
  stroke transfer remain required.
- Pending local deletions that conflict with external edits lack a selectable
  deletion version. Unlisted pages whose original is removed from the index
  and malformed lone pages need complete discovery/recovery behavior.
- Split-view drag transfers currently copy. Complete the specified move and
  undo behavior across documents, with durable assets and source identity.
- Exercise actual write failures, permission recovery, interrupted saves,
  external edits, and offline restart in the finished user workflows.

### Editing and host completion

- Complete ruled/reflow behavior on mixed pages and columns, including
  negative space changes. The current implementation lacks a live translated
  preview and Write's timestamp-grouped stroke center calculation.
- Resolve #50's fixture reproducibility problem before treating that fixture
  as evidence for reflow.
- Finish remaining tablet-spec details, including creation preview details,
  user-facing paper names, singular note counts, and Settings placement.
  Survey actual behavior before replacing an existing path.
- Finish the primary Flutter deployment and the complete daily-use sessions
  in the milestone. Native iPad obligations remain separate.

## Evidence and practical limits

Native engine targets and the Flutter/TypeScript host build succeeded for
the figure changes. The tag-form Dart analyzer reported no issues. The
final preview build includes the final tag accessibility action. These are
implementation checks, not full product acceptance.

A headless Chromium session rendered the preview library and creation form.
The form exposed the new location picker and removable tag control. Creating
`Lecture notes` with the `algebra` tag produced the corresponding folder and
tag controls in the library. This used an isolated browser-storage context.
Screenshot: `/tmp/math-notes-creation.png`. Full deployed daily-use sessions,
physical pen/touch, and actual TeX compilation remain unverified.

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
