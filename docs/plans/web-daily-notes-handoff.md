# Web v1: usable for daily mathematics notes

> Tier: roadmap / execution handoff.
> Parent: [Math Notes roadmap #11](https://github.com/dzackgarza/math-notes-app/issues/11).
> Plan card: `PLAN-WEB-DAILY-NOTES` under `FEATURE-WEB-DAILY-NOTES`.
> Repo export of vault plan key:
> `projects/github.com__dzackgarza__math-notes-app/plans/features/FEATURE-WEB-DAILY-NOTES/plans/PLAN-WEB-DAILY-NOTES/PLAN-WEB-DAILY-NOTES`.
> Execution state: the existing GitHub issue tree. This document defines the
> milestone and handoff; issue bodies own progress and feature acceptance.

## Result

Use the deployed Chrome app for a real mathematics note-taking session:
create and find notes, write across fixed pages, revise earlier work, annotate
reference material, reuse figures, save safely, resume offline, and export a
readable PDF. Complete every specified web workflow in FEATURES.md and the
tablet interface. A rendered control or a successful engine call alone does
not satisfy this milestone.

The [handwritten-draft boundary](../../AGENTS.md#product-boundary-handwritten-drafts)
governs every phase. TikZ mode extracts a geometric skeleton for external
refinement. LaTeX notebook rendering/export, handwriting recognition, and
LaTeX labels are excluded permanently, not postponed to another milestone.

This is web v1 across the web obligations in #14, #15, and #17. #56 is the
first integration checkpoint, not the whole daily-use milestone. Native
acceptance remains with the iPad work; a web result cannot close a parent
issue whose contract also requires iPad.

## Starting point and sources

Start from the adopted framework decision at commit `ea78563` on
`write-core-integration`; inspect the current branch and upstream before
editing. Preserve concurrent work. At handoff, the untracked
`noteful-customize-pencil.webp` and `noteful-pen-tool.webp` are existing
user work.

Read:

- [README](../../README.md) and [TRAPS](../../TRAPS.md).
- [Architecture](../ARCHITECTURE.md#component-ownership) and
  [adopted Flutter decision](../reports/Web%20interface%20framework%20selection.md).
- [Feature contract](../FEATURES.md), [tablet interface](../specs/tablet-ui.md),
  [file format](../FORMAT.md), and [TikZ contract](../specs/tikz-drawing-mode.md).
- The live issue bodies linked below. Source requirements take precedence over
  screenshots with sample content.

The current web GUI is Solid/Ionic. The shared engine, folder services,
metadata, and editing flows already contain working behavior. Open issues
are not proof that their implementation is absent: inspect and exercise each
feature before replacing it. Port working product behavior into Flutter.

Inspect `hosts/web/src/editor/notebook.ts`, storage services, engine bindings,
and the existing editor. TRAPS documents pending-save loss on rapid reload.
The saver currently delays writes and chains them through a promise. Its
failure and retry behavior needs direct acceptance before it can protect
daily work. Commit/push hooks currently run YAML lint; that is not web
product acceptance.

## Fixed ownership and invariants

- Flutter with Cupertino owns the whole web GUI: controls, navigation,
  input dispatch, focus, keyboard behavior, and scroll physics.
  Use mature Flutter packages for standard behavior where needed.
- The existing C++ document model, Google Ink, and Skia remain authoritative.
  App code supplies notebook rules, product layout, and bounded adapters.
- The Skia HTML canvas is passive. Only pen input accepted by the Flutter
  notebook target reaches the engine. Preserve available pressure, tilt,
  coalesced samples, and prediction identity. Dialogs intercept input.
- The TikZ editor is an interactive iframe in its own Flutter platform view.
  Preserve its authored source and its own editing controls.
- Each page remains a standalone SVG in the ordinary notebook directory.
  Assets and original ink samples survive save, reopen, move, and export.
- Save acknowledgment follows durable writes. Failures remain visible and
  recoverable. External edits enter conflict handling before replacement;
  retain the browser concurrent-writer limits in the format contract.
- Dependencies are acceptable. Handwritten standard UI behavior needs the
  ownership evidence required by AGENTS.md.
- The web target is Chrome with pen and touch input.
  The separate iPad GUI and post-v1 ink-owner review keep their existing
  place after the working web product.

## Delivery order

These phases describe product outcomes, not PR boundaries. Resolve
implementation details within each existing work unit; do not restart the
framework survey.

**The order is strict.** A phase starts only after every acceptance item of
the earlier phases passes in the deployed app. Code that already exists for a
later phase gets no further work until its phase starts. Its controls stay
off the primary tool rail until then.

| Phase | Existing owners | Result and acceptance |
| --- | --- | --- |
| A. Core note-taking features | [#56](https://github.com/dzackgarza/math-notes-app/issues/56), under #14 | Every L0 and L1 feature in [core features](../specs/core-features.md) exists and works in the deployed app, in that order. |
| B. Keep, find, and share notes | [#56](https://github.com/dzackgarza/math-notes-app/issues/56), [#62](https://github.com/dzackgarza/math-notes-app/issues/62), [#29](https://github.com/dzackgarza/math-notes-app/issues/29) | Library create, open, rename, move, delete, and trash; search and recent; tabs; paper choice at creation; PDF export of a 10-page notebook. |
| C. Annotate papers | [#8](https://github.com/dzackgarza/math-notes-app/issues/8) | Import a mixed-page-size PDF, annotate it, insert blank pages, export it. |
| D. Revise and reuse mathematics | [#30](https://github.com/dzackgarza/math-notes-app/issues/30), [#31](https://github.com/dzackgarza/math-notes-app/issues/31), [#28](https://github.com/dzackgarza/math-notes-app/issues/28), [#32](https://github.com/dzackgarza/math-notes-app/issues/32), [#33](https://github.com/dzackgarza/math-notes-app/issues/33) | Ruled selection/erase, space insertion and reflow, split view and conflict resolution, bookmarks/links, and clippings on saved mixed-content notes. Undo restores grouped edits across affected pages. |
| E. Additional content and organization | [#58](https://github.com/dzackgarza/math-notes-app/issues/58), [#49](https://github.com/dzackgarza/math-notes-app/issues/49), [#63](https://github.com/dzackgarza/math-notes-app/issues/63), [#60](https://github.com/dzackgarza/math-notes-app/issues/60), [#61](https://github.com/dzackgarza/math-notes-app/issues/61), [#9](https://github.com/dzackgarza/math-notes-app/issues/9) | Metadata, favorites, tags, saved creation settings and drafts, images, typed text, layers. |
| F. Diagram extraction | [#10](https://github.com/dzackgarza/math-notes-app/issues/10); blocked on the TikZ workbench module in `dzackgarza/zettlr-pandoc` | Capture doodled geometry and copy a TikZ skeleton, as defined in the TikZ mode contract. |
| G. Daily-use acceptance | #56 and the web obligations above | The deployed release passes the real-work sessions below. Every blocker has a fix and evidence in its owning issue. |

A is the product. Every later phase is an addition to a notes app that
already works for writing. #30 precedes #31. PDF import and export meet in
the same annotation workflow. Final export acceptance includes links,
layers, text, images, and figures after they land.

Complex work already has owners: #56 for the host, #28 for conflict handling,
#30–#31 for ruled editing, and #10 plus `PLAN-TIKZ-DRAWING-MODE` for figures.
Keep detailed implementation plans with those owners. #50 owns the upstream
fixture reproducibility defect; resolve it before relying on that fixture
as reflow evidence.

## Saving in phase A

Autosave is an L0 feature. It is complete when:

- A committed edit can be saved explicitly and has clear pending/saved/error
  feedback. A displayed saved state means the write completed.
- Switching notes, closing an in-app tab, and returning to the library retain
  the latest edits. Rapid browser reload must preserve durable edits and make
  any remaining pending work recoverable through standard storage facilities.
  Do not rely on an unload handler completing asynchronous filesystem work.
- Denied permission or a failed write does not turn into a saved state or
  poison all subsequent saves. Restoring access lets the user save the same
  pending work. Exercise failure with an actual denied or failed operation.
- Offline restart opens cached application assets and reconnects the folder
  through an explicit user action when Chrome requires permission.
- A stale cached app does not mix incompatible assets after deployment.

Use browser storage and upstream lifecycle mechanisms. Any necessary
recovery representation must follow the existing ownership rules before a
new subsystem is introduced.

## Final acceptance: actual work in deployed Chrome

Use `http://localhost/math-notes/` on the target machine. Preserve
`just web-build` and `just web-deploy` as entry points while adapting their
implementation to Flutter. Rewire the existing web verification entry point
to the real Flutter application.

| Session | Required observation |
| --- | --- |
| Lecture notes | Create a folder and notebook from the UI. Write a multi-page set of mathematics notes with pen and highlighter; navigate while writing; erase, lasso, resize, undo, and redo. Save, close, restart Chrome, reconnect, and continue the same notes. |
| Organize and resume | Rename and move notes, use tags/search/recent/favorites, restore from trash, use a saved template and draft, and switch between notes through tabs. Content and metadata remain attached to the intended note. |
| Revise a proof | Insert a missing argument into existing ruled ink; reflow across pages; undo and redo. Use split view, copy a selection, save/reuse a clipping, and follow bookmarks and links after reopening. |
| Annotate a paper | Import the mixed-page-size PDF fixture, annotate it, insert a blank page, add an image and typed text, close and reopen, then export a selected range. The notebook remains usable without the original PDF. |
| Extract a diagram | Capture doodled geometry, extract a TikZ skeleton, save/reload/reopen, select it, and copy the code for an external figure editor. Original ink and handwritten labels survive. Embedded-editor focus and overlays behave correctly. |
| Recover a save and conflict | Exercise a write failure, restore access, and save pending edits. Reload immediately after editing. Introduce an external page change and resolve it side by side, preserving both versions until the user chooses. |
| Work offline and share | Restart offline after caching, edit and save, then reopen. Export the mixed-content notebook; inspect it in an independent PDF viewer. Open page SVG files outside Math Notes. Content and page dimensions agree. |

Use the existing ten-page notebook acceptance from #14 and the mixed-size
PDF fixture in #8. Extend the working notebook with the text, image, layer,
link, and figure cases above. Record the deployed revision, Chrome version,
saved notebook, exported PDF, and the observations in the
owning issues. Keep private note content local.

After the complete workflows exist, add end-to-end tests that preserve
their product behavior, combined with the engine's relevant existing
checks. A screenshot, synthetic pointer
test, or green lint hook cannot prove pen feel, durable saving, or an
end-to-end workflow. Record rendering and responsiveness on the real
mixed-content notebook; pauses that lose input or interrupt ordinary
writing block the milestone.

## Handoff and completion rules

First inspect the current implementation and live #56, then implement the
complete Flutter host and its save path. Reuse working domain behavior.
Route missing ordinary library/editor behavior to #56 and the existing
feature owner rather than waiting for a later polish phase.

Keep issue evidence current. Close a leaf only when its entire contract is
met; record web completion separately where a contract also requires iPad.
The current grouping order places #16 before #17 even though the adopted
direction is web first. At execution pickup, align traversal with this web
slice without treating native acceptance as complete.

The web milestone is reached only after all phases and final sessions pass.
No inert required controls, silent write loss, unrecoverable save errors,
broken reopening, missing specified feature paths, or input routed through
dialogs remain.

This handoff changes no framework decision and grants no new core
responsibility. Stop for a product decision only when the existing
specifications and source intent cannot determine it.
