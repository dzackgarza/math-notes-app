# Math Notes iPad remediation — real daily-use journeys, black-box qualification and repairs

## 0. Governing acceptance: user actions and observable results, not implementation proxies

For a particular user story, the acceptance criterion is exactly this: **the actual installed app receives actions A → B → C through its visible interface, and independent observation establishes outcomes X, Y, Z.** Nothing about controller state, callbacks, engine return codes, mocked windows, serialization internals, or passing unit tests supplies additional acceptance evidence for that user story. Such internals may help developers locate a defect after an externally observed failure; they must never be used as a replacement for demonstrating that the user can complete an action.

**The more serious failure of v343 is that tests did not follow how people actually use the app.** Replaying the 21 previously reported defects—even against the running app—would preserve the selection bias. The primary qualification starts with **20 complete daily-use journeys J01–J20**, designed from ordinary mathematical work rather than bug reports, and then explores further user-visible action sequences that were not previously enumerated. Known defects remain regression seeds, not the acceptance boundary.

Use **Appium XCUITest** as the OS-level action transport on an iPadOS Simulator, driving the separately installed production app via an external TypeScript runner. Its role is intentionally narrow: find user-visible controls and geometry, deliver taps/typing/swipes/multisegment drags, relaunch apps, and capture observable results. The exploration strategy operates **entirely on the UI presented by that app**; it must not read/modify internal model state, import app code, create replacement windows, invoke callbacks, or install test-only controls. [Appium black-box driver][appium-overview] · [Gestures][appium-gestures]

### 0.1 Discover interactions, rather than enumerating only reported bugs

At each step, inspect the rendered screenshot and accessible visible controls. Derive feasible actions from the **current user-facing state**: tap/activate reachable controls, open/close sheets and menus, type into visible inputs, draw or gesture on the canvas, drag/resize selectable objects, undo/redo, change page/layer/tool, navigate the library, rotate/split/resume, background/relaunch, and retry or cancel pending operations. Some gestures on a canvas are not discoverable from accessibility alone; include a small **domain action vocabulary** (line, scribble, lasso polygon, erase swipe, zoom/pan, resize/drag) generated against the visible canvas bounds. Neither the state graph nor the sequence selection may be derived from the set of already filed defects.

Execute **long, uninterrupted, state-dependent sessions**, not only short isolated scripts. Choose the next action from feasible UI actions conditioned on what is currently visible, carrying forward the actual edits, open sheets, selected tools, files and history. Generate realistic and adversarial variants: short/long text, multiple languages, long note names, multiple pages/layers, mixed object types, changes of tool during editing, rapid repeated actions, different orientations, import/edit/export, undo/redo, reopen/close, offline/slow provider, and sequences that compose features across surfaces. Prioritize **unvisited UI states, untried action transitions, combinations and longer sequences**, while retaining some ordinary-use weighting; save the seed and full action trace of each exploration. A novel failure is a real remediation obligation even when no previous complaint mentions it. [Event-flow GUI testing literature][gui-event-flow] · [Comparative GUI testing study][gui-comparison]

### 0.2 Judge only externally observable properties

Check the displayed screen and the result of the *next independent user action* after every meaningful transition. A visible enabled action must respond or visibly explain why it cannot; the app must not crash, freeze, dismiss unexpectedly, obscure necessary controls, change the wrong object/tool, lose edits, duplicate visible effects, or misrepresent completion. Verify reversible operations by observing **undo and redo on the page**; verify preservation by **closing/terminating, relaunching and reopening through the normal UI**; verify exports by opening the exported artifact in an independent viewer where applicable. Compare screenshots and accessible labels/states with the expected visible state. For generated sequences, derive expected behavior from general user-level relations—e.g., undo then redo restores the previous visible document, toggling visibility twice restores the display, a change canceled before commit does not appear after reopen, adding a page preserves all earlier pages, a note reopened without editing retains content. These are user-visible *metamorphic* properties, not internal equality assertions.

Observed UI is the primary evidence. Record screen video, snapshots at meaningful transitions, accessibility data and OS crash/hang signals on successful as well as failing sessions so that automated and visual evaluation can discover unexpected bugs. Artifacts and logs aid inspection; their presence, a test count, or a coverage statistic is **not** proof of correct behavior. An exploratory sequence passes only when its observable oracles pass; otherwise it is a reproducible failure (trace, seed, initial external fixture, recording). If an observation cannot reliably be established, the action is **not certified**; do not substitute a callback or dirty bit.

### 0.3 Acceptance and limits

The initial M0 result is **execution and recording of ordinary day-to-day journeys J01–J20 against the actual v343 app, with the real failures retained**, alongside an exploratory campaign finding and replaying defects independently of the 21 known complaints. Start with representative everyday journeys, not defect-specific smoke scripts. The exploratory campaign then extends beyond both the ordinary journey corpus and the complaint corpus. Each later milestone is accepted only after **the same general exploration engine** runs on the candidate and all observed failures in its scope are repaired. The 20 everyday journeys are a *required realistic-use baseline*, the existing 21 scenarios are known-defect regression seeds, and neither is the exploratory system's search boundary. All three are complementary black-box activities with the same externally visible acceptance standard.

An iPad Simulator and W3C finger events cannot prove device-specific Apple Pencil pressure/azimuth/roll/estimates. Genuine on-device Pencil use is therefore a separate **real-world external qualification** of that physical input class; in-process Hammer samples are engineering diagnostics only and cannot discharge it. Similarly, no finite collection of concrete runs proves correctness for every theoretically possible interaction sequence; the purpose of systematic state/action exploration is to find classes of **unanticipated** errors, rather than declaring universal correctness from a finite predetermined checklist.

**Release rule: ordinary long-form use J01–J20 + open-ended exploration + known-defect regression C01–C21, all against the same real installed application and judged solely by the observed user outcomes. No internal proxies.**

## 1. Scope and release baseline

This is an implementation handoff for repairing the native iPad application in **dzackgarza/math-notes-app**. The baseline is **2da1707e1d4f28a609550268ef30459731985aaf**, shipped as **v343 / 0.1.343 (343)** on 10 October 2026. Both newly reported device failures, [#93][issue93] and [#94][issue94], identify that build and its binary UUID, **3D31E112-55F2-3664-B4D6-2B4F0EE9D97D**. They are failures of the current release. [Release][release] · [Audited source][baseline]

The priorities are to stop the confirmed hang and abort, remove synchronous persistence from input and presentation, make editing operate on the geometry actually displayed, restore complete figure transactions, and finish the native interface with visible, durable user outcomes as release gates.

The archaeology includes the supplied complaint report, native Swift code, shared C++ code, relevant history, actual pinned dependencies, shipped IPA and dSYM, and the passing release's CI log. The two device stacks were resolved against the shipped binary. The figure transport loop was reproduced using the actual pinned JavaScript functions. Layout findings distinguish source-established structural defects from the user's observed pixels; this report does not claim a new live iPad session.

The attachment also contains a historical Flutter/web design audit. The shipped iPad product is now SwiftUI/UIKit over the shared C++ engine. Its current light palette, bundled Alegreya families, vertical rail, native menus and other completed improvements must be the starting point. Reapplying old Roboto, navy-palette, horizontal-toolbar or 900-by-800-dialog fixes to this host would address superseded code. Section 7 records that disposition explicitly.

All work below is remediation and verification of identified defects. There is no discovery milestone, library-selection spike, or instruction to find the causes later. No application source was changed as part of this handoff.

## 2. Findings that determine the plan

### 2.1 The reported hang is a command and Observation feedback cycle

Issue #93 resolves to this application call chain:

**InkEditorHost.updateUIViewController → InkEditorViewController.handlePageCommand → onEditCommitted → OpenNotebookSession.scheduleAutosave → Observation mutation / SwiftUI transaction flushing.**

The source executes document commands synchronously from the representable update. Text Done submits commitText; handlePageCommand edits the canvas, increments the observed document revision, changes observed save status, and starts a synchronous recovery checkpoint before the update returns. Other commands and layout callbacks cross the same boundary. The existing duringUpdateTraced function logs the violation and then performs it. Deferring a few callbacks did not eliminate the cycle. [Command application][s-command] · [Text submission and callbacks][s-callbacks] · [Autosave][s-autosave]

The binary establishes the command/save boundary in the actual device hang. The optimized command frame has compiler-generated line attribution, so it does not establish which switch case the user invoked in that particular report. Text Done independently follows this same path in source. Its remediation is therefore definite without inventing an unrecorded gesture.

### 2.2 The reported abort is an empty mesh in lasso coverage

Issue #94 resolves to:

**PartitionedMesh::Data::TotalAbsoluteArea → CoverageIsGreaterThan → LassoSelects → Editor::FinishSelect → SelectInput → ink_input → InkCanvasView.touchesEnded.**

Lasso accepts a non-null PartitionedMesh whose mesh list is empty. Google Ink's TotalAbsoluteArea asserts that the list is nonempty and aborts; the app's C++ exception boundary cannot catch that check. Ordinary whole-stroke erasing instead treats the empty shape as a miss. [Lasso implementation][s-selection] · [Pinned upstream check][g-coverage]

There is a concrete route to this state: live Pencil input normalizes azimuth and roll, but persisted-stroke reconstruction passes raw angles and ignores rejected sample statuses. For example, raw roll -0.5 with its capability flag draws successfully through the live adapter but is invalid when reconstructed without normalization. All rejected samples produce the empty shape. A valid prefix and rejected tail produce incomplete hit geometry and apparently random eraser misses. The normalization fix in d1a0c7f repaired only one adapter. [Live adapter and history][s-editor] · [Reconstruction][s-erase] · [Input validation][g-input] · [Partial fix][angle-fix]

The abort endpoint is device-confirmed. Negative roll is a proven source-derived route, not a claim that the user's unexported page contained that exact value. Lasso scans candidate ink near images; the symbolicated report does not implicate bitmap decoding.

### 2.3 Figure saving has a self-feeding message loop

The pinned editor is loaded at the top level of WKWebView. Its bridge replies with window.parent.postMessage, while its receiver interprets message.action OR message.event as a command. Here parent is the same window. A save reply becomes another save command indefinitely. Every reply can trigger another synchronous native save. [Native host][s-figure-host] · [Actual bridge sender and receiver][embed-source]

Running the exact source-extracted functions with this topology produced 25 save events from one command, with another event queued at the diagnostic cap. With a distinct iframe parent, the same command produced one event and drained. Independently, the successful build-343 native CI log contains **16 identical save notifications in approximately 9 ms**. Its test accepts the first callback and deduplicates all saved values with Set, allowing the loop to pass. [Figure test][t-figure] · [Release CI][ci]

This is independent of the SwiftUI command hang. Both must be fixed.

### 2.4 Autosave delays only the later write

OpenNotebookSession.scheduleAutosave executes checkpointRecovery before starting its one-second delay. The checkpoint serializes pending pages/assets, reads and merges recovery state, base64-encodes changed and base files inside JSON, atomically rewrites that recovery record, and marks the engine saved. These operations run on MainActor. Provider coordination/writes and several conflict and thumbnail operations also still block main. The first text addition can introduce bundled font assets into this path. [Scheduling][s-autosave] · [Recovery][s-recovery] · [Provider save][s-save]

Simply moving current calls to a detached task is unsafe. dirtyFiles mutates live backing assets and exposes temporary buffers; MarkSaved acknowledges the current live document and clears all new assets, rather than the revision actually written. A slow save could therefore mark newer, unwritten edits as saved. The snapshot and acknowledgment contract in N2 is a prerequisite to asynchronous persistence. [C ABI][s-dirty] · [History][s-history]

### 2.5 Visible geometry has several independent correctness failures

The renderer draws persisted stroke outlines, while hit testing and partial erasing reconstruct or cut raw samples. Thick visible edges can be missed; rebuilding fragments changes caps and smoothing; reconstructing an already cut outline from its original samples can restore erased ink. Rotated shape broadphase bounds transform only two opposing corners. Image/text/figure lasso coverage is approximated with two triangles: a tiny lasso crossing the diagonal can intersect both and count as full coverage. [Eraser][s-erase] · [Broadphase and editing][s-editor] · [Selection][s-selection]

Highlighter opacity is applied separately to each stroke. At the default opacity 0.35, two same-style passes have combined alpha 0.5775. SelfOverlap::kDiscard addresses overlap within one Google Ink stroke, not between separate app strokes. Live highlighter also paints above ordinary ink, while committed highlighter is placed underneath it. These are rendering and ordering defects, not color-picker settings. [Renderer][s-renderer] · [SVG serialization][s-svg]

### 2.6 Figure source and the notebook picture are disconnected

The native decoder ignores editor SVG, and ink_document_figure_draft changes a source sidecar only. The page keeps drawing the original Figure children. Commit 5398b68 removed FigureView and the complete source/view acceptance path together with the TeX compiler. Restoring a bounded editor-produced SVG view is required; restoring a TeX compiler is not. [Figure draft][s-figures] · [Figure model][s-model] · [Deletion][figure-deletion]

Accepting the existing SVG field without changing the editor contract would still be wrong: source changes carry lastKnownSvg, which can belong to an older render; later SVG-only updates do not emit another source event. The chosen repair is a revision-matched snapshot, followed by one atomic source/scene/view transaction.

### 2.7 Passing tests do not establish the reported outcomes

The release passed **220 Swift tests** and **95 engine cases / 36,422 assertions**. Its logs nevertheless include repeated main-thread stall reports and the figure save echo. Simulator stall logs are diagnostic signals, not device performance measurements. The release workflow does not enforce responsiveness from them. [CI][ci]

Specific missing boundaries explain the false confidence:

| Existing coverage | What it misses |
| --- | --- |
| TextPersistenceTests directly calls InkCanvasView.editText, root.save and reload | The real text sheet, Done button, representable command, Observation feedback and scheduled recovery |
| ClippingPersistenceTests uses typed text and Select All | Image import, resize, actual lasso, neighboring Pencil ink and app survival |
| Core image transfer test uses rectangular selection | Lasso coverage and its empty-mesh abort |
| FigureEditorSheetWorkflowTests substitutes persistence and compares Set of drafts | Duplicate save count, real storage, closing, visible figure update and subsequent interaction |
| Some pencil tests use real Hammer samples but change tool state directly | Rail hit targets, rendered highlight, accepted tool and actual drawing agreeing |
| Current LibraryWorkflowTests does tap Lasso/Pen in real ContentView | It does not prove a nonempty lasso selection first; samples lack roll and image context |
| Tool constants and settings tests | Some explicitly assert that opacity is hidden behind Advanced |

[Text test][t-text] · [Clipping test][t-clipping] · [Core selection test][t-selection] · [Figure test][t-figure] · [Pencil test][t-pencil] · [Library test][t-library] · [Tool tests][t-tools]

## 3. Architecture and ownership decisions

| Responsibility | Selected owner and boundary |
| --- | --- |
| iPad shell, standard controls, text entry, menus and accessibility | Keep SwiftUI/UIKit. Use the existing controller with a stable Coordinator/command adapter. UITextView owns editing, selection and IME; Skia Paragraph owns document text layout. |
| Notebook lifecycle, autosave and external file presentation | UIDocument per open note/document, with the existing SVG-folder format adapter. NotesRootAccess continues to own security-scoped root access and library inventory. |
| Durable local recovery and incremental notebook files | A bounded adapter for this format, using immutable generation snapshots and Apple-coordinated background I/O. Preserve and import existing recovery records. This is not a second general sync engine. |
| Ink and filled geometry | Keep Google Ink at inspected pin 1b220eee5a05e9b67be9f20f49ae2d574c8667a7 and Skia. One bounded geometry adapter owns conversion between persisted contours and the pinned library's representations. |
| Structured Figure editing | Use dzackgarza/visual-tikz-editor, inspected baseline 60d007f0520777c4195079507d296bb79e086cd7. Extend its maintained host/embedded-editor boundary; Math Notes supplies notebook identity, placement, transport and persistence. |
| Structured Figure display | Existing Skia pin ab5932137bb327b627b44f15fbe34ba59d775d0e, using SkSVGDOM and a bounded resource provider for editor-produced SVG. |
| Undo | The existing shared-core DocumentHistory remains authoritative. Bridge user transactions into the native undo interface/change tracking; do not add an independent native document history. |
| Crash and hang capture | Keep KSCrash and matching release dSYMs. Improve the diagnostic export and use OS signposts for bounded operation timing. |
| User-observed application qualification | Appium XCUITest driver + external TypeScript/Bun **stateful exploratory runner** on the iPadOS Simulator. Drive the installed production app, discover its user-visible action graph, generate and replay long sequences, assert visible outcomes/reopen durability, and retain videos/screenshots. Existing Hammer/core tests are debugging aids; Pencil-specific results must be observed with real device/Pencil. [Driver][appium-overview] · [Gestures][appium-gestures] · [GUI exploration research][gui-event-flow] |

Apple documents UIDocument's background I/O, lifecycle and incremental override points. Its contents(forType:) runs on the calling queue: adopting the class while serializing the whole document there would retain the hang. N2/N3 specify the required boundary. [UIDocument][apple-document] · [Save calling-queue contract][apple-save] · [Incremental writer][apple-write]

The maintained figure workbench already has a host interface, iframe isolation, autosave:0, canvasOnly layout, source identity checks, touch work, primitive interpretation and bundled local assets. It still needs the explicit revision-matched snapshot and raw-ink preservation additions below. It is a selected, inspected owner, not an assertion that its current version can be dropped in unchanged. [Host interface][vte-host] · [Provider][vte-provider] · [Owned patch][vte-patch]

### Milestones

Milestones are dependency and user-observed acceptance boundaries, not calendar estimates. **M0 establishes replayable ordinary daily-use journeys AND a general external exploration system, not an issue-by-issue script collection.** Repairs may proceed concurrently, but no milestone closes from a unit test, synthetic callback or predetermined regression story alone. A candidate must survive new generated, cross-feature interaction sequences at its exact SHA.

| Milestone | Packages | Completion condition |
| --- | --- | --- |
| M0 — Explore the actual released application broadly | Q1 first; D1 can proceed concurrently | Appium launches v343 as a separate process. **First implement and execute J01–J20, the ordinary multi-step use journeys in section 6**, recording their actual outcomes, screenshots and video (failures on v343 are expected, not waived). The same external runner discovers visible states/actions and executes additional generated multi-feature sequences, including transitions absent from both the daily journeys and known complaints. Replay known defects as secondary regression cases. Failing observations become direct repair work; no direct API/host substitutes are allowed. |
| M1 — Stop the confirmed failures | N1, C1 including minimum outline adapter, F1 transport containment | The original observable failures are gone in the installed app; **fresh generated sequences** combining editing, tool changes, image selection, text and figure entry also complete with correct visible effects. Real Pencil input is required to qualify sensor-specific crashes; internal reconstruction fixtures are not an acceptance replacement. Full figure transactions and background durability remain M2/M4. |
| M2 — Make persistence and input revisions correct | N2 → N3; N4 coordinated with N2 | Slow storage cannot block input; revision A cannot acknowledge B; recovery, late estimates, backgrounding and external changes preserve the right data. |
| M3 — Make ordinary editing behave correctly | C2 → C3/C4; U1 | Erasing acts on visible geometry; lasso uses the defined coverage rule; highlighting is uniform; text reflows visually; tool state and saved presets match their effects. |
| M4 — Complete Structured Figure | F2 → F3, after F1 and the N2/N3 persistence boundary; common bounds from C2 | One fullscreen visual editor; optional code; current source and picture commit together; retry, reopen, undo and old figures work. |
| M5 — Finish library and editor interaction | U2, U3; visual layout work can begin earlier | One library surface, usable cards, correct creation contrast, contextual navigation/actions, scalable native controls, quiet status. |
| M6 — Qualify the complete iPad release | All packages; section 6 exploratory campaign and fixed regression seeds | **All J01–J20 daily-use journeys succeed end-to-end** on the installed candidate, as do relevant known-defect seeds; uninterrupted stateful black-box exploration of the same installed candidate also finds no unresolved externally observed incorrect outcomes. New action traces beyond either enumerated suite are required. Confirm real-pencil workflows on device. Review replayable records/screenshots/videos from the exact candidate SHA before publishing. |

An M1 build can qualify only as a limited command/mesh/message-loop repair. It cannot claim asynchronous save performance or complete figure behavior before M2/M4; the complete remediation release requires M6.

### Agent lanes and merge boundaries

| Lane | Owns | Integration rule |
| --- | --- | --- |
| A — Native state and storage | N1–N4; command, lifecycle and save portions of ContentView/InkEditorView | Own the shared native command and document APIs. UI/figure agents consume them; do not create alternate save paths. |
| B — Core geometry and rendering | C1–C4; shared-core part of N2/N4 and F2 | One integration owner for editor.cpp, document model, serialization and ABI. Merge C1 before broader geometry changes. |
| C — Structured Figure | F1–F3; maintained editor dependency and native figure presentation | Land owner changes in visual-tikz-editor, then consume an immutable pin. Coordinate F2 schema/ABI with B and save calls with A. |
| D — Interface and qualification | Q1, D1, U1–U3 and M6 evidence | Own view layout, **external Appium runner**, actual installed-app workflows and screenshot/video gallery; no alternate fake application host as an acceptance runner. Submit focused integrations into A's controller files after the command boundary lands. |

Start Q1 immediately and establish broad v343 **externally discovered** interaction evidence before accepting any repair. N1, C1, the F1 protocol correction and D1 may be implemented concurrently, but cannot **close** before Q1 has exercised their user-observable consequences inside an ongoing exploratory campaign. N2's ABI must land before N3 uses background serialization. N4 uses stable identity/generation semantics from N2. C2 precedes geometry erasure and final Figure hit bounds. F2/F3 must use N3; no temporary figure-specific saver should survive. Every pull request is exercised by the same black-box runner, including the affected ordinary journeys J01–J20, newly generated cross-feature sequences and relevant known-defect seeds. A defect replay is not the acceptance boundary; the continuing campaign must seek and assess previously unanticipated interactions.

## 4. Work packages

### Q1. Independently launch, explore and judge the real iPad app (release prerequisite)

**Files:** `.github/workflows/ios.yml`; one `tests/ipad-e2e/` TypeScript/Bun runner with pinned Appium/XCUITest driver; stable production accessibility identifiers only as needed. The existing `AppTests` target is not the user-experience acceptance runner. [Current project][s-project] · [Workflow][s-workflow] · [Appium][appium-overview]

**Transport, not a second application.** On the existing macOS runner, boot the chosen iPadOS Simulator, build/install the actual candidate `MathNotes.app`, and launch it with Appium from a separate process. Use the real app's controls and production navigation, typing, touch input, system permission dialogs, OS lifecycle and file import/export. Never create a `UIWindow`, `UIHostingController`, a fake `ContentView`, session/document object, controller callback or test-only state inside the app. For drawing with externally generated finger touches, turn on **Draw with finger through the visible Settings UI**; `InkCanvasView.sendFingerTouches` then uses the real production path. Construct multi-point drawing, lasso, erasing and drag gestures through Appium W3C actions at visible coordinates. Sensor-only Pencil qualities require actual-device Pencil checks; neither a fake touch nor Hammer makes those externally observed. [Gestures][appium-gestures]

**Ordinary end-to-end use comes first, then exploration goes beyond it.** Implement the complete user journeys J01–J20 in section 6 as replayable OS-driven workflows with realistic data and observable results; these are not condensed smoke tests. Maintain a small action vocabulary: tap visible control, enter/replace visible text, draw line/curve/scribble/polygon, pan/pinch/drag/resize, long press, select tool/color, undo/redo, open/close menu/sheet, switch pages/notes, import/export, dismiss/cancel, background/relaunch, rotate. At each step read the **current screenshot and accessibility tree**; select only currently feasible actions and discover any newly revealed controls, states and routes. Record a state/action transition graph derived from the live app. Prefer unexplored edges and compositions of edges, but also sample ordinary usage. Generate long sequences without resetting between every gesture, to expose delayed side effects and conflicts across features. Add reproducible input variants: text length/language, object count, line width, selection scale, view size/orientation, library density and interaction timing. Keep an immutable external starting fixture, random seed, action trace, viewport coordinates and full-run recording for every run. Do not infer the graph from complaint categories or internal enums. The event-flow method is established GUI-testing research, not an application-specific state proxy. [Event-flow model][gui-event-flow] · [Empirical comparison][gui-comparison]

**Oracle = what the user could see and do.** After every meaningful action, inspect the visual result and accessibility information, and confirm that the next legitimate action is still accepted. General requirements apply to *all* generated traces, not only known defects: enabled controls respond; no overlapping/inaccessible action targets; action effect agrees with chosen tool/target; no spontaneous sheet dismissal; no incorrect item changed; no crash or unexplained unresponsiveness; undo/redo reflect the visible edit; cancel does not commit; rereading through the UI after OS relaunch preserves the visible committed content. Exported files are independently opened/compared when relevant. Image/screenshot inspection and user-visible state assertions are authoritative. Internal callbacks, engine status, dirty bits, instrumentation counters or mere existence of a generated recording do not count as the outcome.

**Three suites, one runner and one acceptance standard.** (1) Replay the ordinary long-form journeys J01–J20 exactly as users would, including persistence and externally opened exports; (2) replay C01–C21 as defect-specific regressions; (3) run a stateful discovery mode that chooses feasible actions and explores unfamiliar sequences not contained in either list. All three drive the same installed app from outside its process. Run smoke plus a bounded discovery campaign on each candidate PR, and longer campaigns (multiple seeds, sessions, content sizes, rotation, app lifecycle) before release and on the scheduled extended CI run. Report actual unique user-visible states/transitions explored, action-sequence length distribution, unvisited reachable edges and time spent; **none of those counts substitutes for correct observed outcomes**.

**Failure handling and evidence.** Every unexpected crash, freeze, wrong action, lost document, unusable control or visual defect becomes a complete replay: starting external fixture, seed, ordered UI actions/timing, screen video, checkpoints/screenshots, accessibility observations, affected app SHA and OS crash report if any. Shrink a failing action sequence only if its externally observed failure remains; keep the original full trace. Address such failures even if their behavior is absent from the user's initial complaints. On a repaired SHA, replay the failure and continue broader discovery in the same app build—do not stop after restoring the known green cases. Preserve artifacts for green and red runs for visual sampling and verification; report limitations rather than inventing passes for hardware-only channels.

**Gate:** the real release and candidates execute and record the complete everyday journeys J01–J20 against the installed app, with genuine visible outcomes; a separate ongoing exploratory campaign discovers and traverses additional states/actions independently of both those journeys and known bugs, checks results through the UI, and retains reproducible unexpected failures. Only that runner establishes user-story acceptance. No implementation package can close merely because its reported-bug seed passes.

### N1. Execute commands outside representable updates

**Files:** Sources/InkEditorView.swift, TextEditorSheet.swift, OpenNotesState.swift, InkCanvasView.swift, relevant ContentView callbacks.

Use the existing UIKit controller and representable Coordinator as a stable per-session adapter. UI actions submit typed operations directly to it outside updateUIViewController. That update applies idempotent display/configuration only: no document transaction, recovery write or observed-state publication. Programmatic scroll/layout/configuration must suppress or defer deduplicated feedback with an identity/generation guard.

Commands carry request ID, originating session/document identity, target page/element IDs and document coordinates, plus a result. A bounded pre-attachment queue can retain pending operations. Execute each once; reject detached/stale targets explicitly. Consecutive commands must not overwrite the current optional command slot. Do not replace this with scattered main.async closures that can arrive after a pane changes.

Text requests currently lack stable target identity and use view coordinates/current selection. Bind the actual element/page and preserve the typed draft until the command succeeds. Done dismisses after successful document-command acceptance; it does not await provider storage. Rejection before acceptance retains the sheet/draft with an actionable error. A later recovery/provider failure leaves the already accepted text in the dirty document under N3, with save retry; it must not replay the edit or reopen a stale draft. Apply the command identity/result rule to clear, bookmark, links, recolor, paste, capture, fit and viewport feedback.

Keep during-update diagnostics as a test assertion during migration; do not treat logging as a guard. A successful tool application returns its accepted configuration; failed core configuration cannot advance appliedTool or its highlight.

**Gate:** externally tap tools, insert text, switch notes and continue working without a frozen sheet, stale edit, lost content or wrong visible tool. Confirm persistence by ordinary reopen; the representable-update rule is an implementation repair constraint, not additional acceptance evidence.

### C1. Contain the confirmed lasso abort and invalid input

**Files:** core/src/editor/editor.cpp, erase.cpp, selection/selection.cpp, geometry/affine.h, format/page_svg.cpp; shared ABI status handling.

Before coverage calls, validate actual mesh count, finite positive geometry and nonsingular transforms. Check Brush::Create and all input-append results. Return InkStatus for invalid native data; do not dereference failed results or invoke assertion-bearing upstream APIs with invalid preconditions.

Factor one checked sensor-to-Google-Ink adapter for live samples, reconstruction, refinements and fragment construction. Normalize cyclic azimuth/roll consistently while preserving the raw sensor values and capability flags in InkML. Existing stored visible outlines remain available when sensor data is malformed; do not turn a crash fix into permanently unselectable or uneraseable visible ink.

Distinguish ordinary imported SVG paths from native strokes. The current parser accepts an unmarked path as a native stroke with default size zero and no samples. Preserve supported vector outlines without fabricating stylus input; reject unsupported structures recoverably. Include the minimum checked persisted-outline-to-mesh/hit portion of section 5 in C1 so visible legacy ink remains operable immediately. C2 extends that same adapter with exact area coverage, complete shape expansion and common bounds.

Add the actual WithEmptyGroups case, not only a default-null PartitionedMesh, plus all-invalid and valid-prefix/invalid-tail raw-angle fixtures. Enclose an image beside that ink through the real lasso input path, before and after reopen. Keep the already-fixed recursive erasing of Link/Bookmark children.

**Gate:** the crash-survival and preserved-geometry portions of C03/C04; #94's abort route cannot be reached and visible legacy geometry remains operable. The full accuracy/transform/round-trip scenarios close with C2/C3, using the same adapter.

### F1. Make figure transport finite and save ownership singular

**Files:** Sources/FigureEditorSheet.swift, ContentView.swift, hosts/web/build-tikz.mjs; maintained Visual TikZ Editor host/embedded bridge.

Immediately separate action and notification message types. Receivers execute only an explicit action; remove the action-or-event fallback. Replies must not become executable in either top-level or iframe placement. Validate expected message source. This finite-transport containment and save-reply cardinality regression are the M1 subgate; the remainder of F1 integrates with N2/N3 and F2 in M2/M4.

Use one bundled host page with the maintained editor iframe, preserving WKURLSchemeHandler's local origin. Swift invokes host functions through callAsyncJavaScript; the host forwards typed events through WKScriptMessageHandlerWithReply. Each message carries protocol version, session UUID, originating document/figure, load generation, source revision and request ID where a reply is expected.

Bind callbacks to the originating session, not the currently active pane. Same-source/same-revision notifications are no-ops before native invalidation. Change notifications update lightweight draft state; the shared saver owns coalescing and durability. Persist a separate figure-session draft record containing origin/figure identity, expected committed revision, source bytes and draft revision. These draft checkpoints do not create document-history transactions or provider saves per event. Disable the embedded independent autosave timer. No WebKit callback may synchronously serialize/checkpoint/save a notebook.

Only an explicit Done request and its matching successful commit acknowledgment may close the editor. Timers, unsolicited save events, inspector closing and attempted swipe dismissal cannot close it. Replace missing-session/root early returns with typed failure. Decode the actual error notification fields.

Startup, snapshot and commit requests need cancellable completion and deadlines; WebKit termination invalidates pending IDs. Retain the latest durable draft, offer reload/retry in the same presentation, and ignore late results from old load generations.

**Gate:** through the real UI, one Done produces the expected figure exactly once; the editor closes predictably, its picture/source correspond, the notebook remains responsive, a failure preserves the editable draft, and a stale result never changes another visible figure. Transport cardinality/queue state is a debugging check, not an acceptance proxy. Full presentation replacement is F3.

### N2. Add immutable snapshots and revision-specific acknowledgment

**Files:** core/src/ink.cpp, editor/history.h, document and asset ownership; Sources/EngineDocument.swift and OpenNotesState.swift.

Introduce these semantics in the core ABI; these names describe required operations, not existing functions:

| Operation | Required semantics |
| --- | --- |
| Capture snapshot | MainActor takes a bounded immutable document/assets root and revision token. It does not serialize all pages or copy every asset. |
| Serialize snapshot | An owned worker snapshot produces changed files and baseline comparisons with owning buffers. It never touches a live editor, mutable native scratch buffer or main canvas. |
| Acknowledge local durability | Advance only the exact committed recovery generation after its payloads and publication record are durable. |
| Acknowledge provider persistence | Advance only the written revision/baseline. Later edits and assets remain dirty. Stale or out-of-order completions cannot regress the baseline or delete newer recovery. |
| Release/coalesce | Release owned buffers after completion; one provider commit per document in flight; coalesce superseded pending snapshots and enforce bounded memory. |

Track current, locally recoverable and provider-persisted generations independently of the presentation status enum. Real edits, undo/redo and accepted estimate refinements advance document state; selection-only gestures and identical figure notifications do not.

Provide generation-aware replacement for MarkSaved and new_assets clearing. The existing recovery checkpoint marks the live engine clean before the provider saves; preserve the distinction in the new API rather than assuming a single saved bit is sufficient.

Serialization calls text layout. The current process-shared FontCollection/SkUnicode helpers must have explicit per-worker/thread confinement before worker serialization and main rendering run concurrently. Share immutable font bytes where supported; keep interactive renderer state on its existing owner.

**Gate:** under an externally imposed slow/failed provider write, the actual app accepts subsequent edit B without blocking, never falsely displays Saved for B, and shows B intact after the write resumes and the document is reopened or the app relaunched. A stale write cannot cause a visible loss of edits. The internal generation protocol is a design constraint, not acceptance evidence.

### N3. Adopt UIDocument without changing the public notebook format

**Files:** Sources/NotebookStorage.swift, OpenNotesState.swift, EngineDocument.swift, ContentView.swift; a small notebook UIDocument subclass/format adapter.

UIDocument owns each open document's URL, open/close, change tracking, asynchronous save and external file presentation. NotesRootAccess owns the selected security-scoped root and library inventory. Do not retain a second competing presenter/save lifecycle for the same document.

Return N2's bounded immutable snapshot from contents(forType:). Use the documented read(from:) and incremental writeContents overrides to parse/serialize/write on the document's worker. Preserve individual SVG pages/assets, unknown files and raw parse-error pages. Preserve base-versus-current conflict checks, conflict copies and the existing required asset/page/index/deletion ordering. Do not use an indiscriminate whole-directory replacement that drops external or unknown files. Do not synchronously wait for main from inside coordinated worker access.

Keep local recovery. UIDocument's periodic autosave is not proof that an edit made immediately before process termination reached disk. Import the existing recovery JSON. Replace full accumulated JSON/base rewrites per edit with changed-file payloads referenced by an atomically published generation record. Keep each base once for the pending transaction, coalesce by file path, and clean only generations acknowledged by the notebook write. Ignore incomplete publication records on recovery. The same bounded worker also checkpoints F1's separate session drafts by document/figure/draft revision; a draft can recover without an accepted page transaction or current SVG. Clear it only after the matching complete figure revision is locally durable, without deleting a newer draft. This is a format-specific durability adapter, with bounded queues and explicit disk/provider failures.

Dirty state must survive a failed checkpoint; current savePending skips sessions whose visible status is failed. Retry dirty failed sessions on appropriate lifecycle actions. Hold the background task assertion until actual async completion or expiration. Never label a queued or failed write Saved.

Apply clean external changes to open documents through UIDocument; preserve both sides when dirty conflicts require resolution. Move parsing, remaining cover/cache reads, rendering and encoding to worker-owned snapshots. Preserve last valid thumbnails while replacements load, with revision/request cancellation checks. Restore document/page/zoom scene state using stable identity, not stale controller pointers.

**Gate:** real delayed file coordination while the UI remains usable; exact A/B persistence; legacy recovery import; process termination after acknowledged local durability; background failure/retry; clean external refresh and dirty conflict preservation.

### N4. Integrate late Pencil estimates with identity, history and saving

**Files:** core/src/editor/editor.cpp InputUpdate/committed records, nested element replacement; Sources/InkCanvasView.swift touchesEstimatedPropertiesUpdated.

Replace cached page/layer indices and stale original stroke replacement with stable page/layer/element identity and originating stroke transaction. Preserve the element's current transform, style and semantic container when refining its input geometry. Deleted/replaced targets cannot be resurrected. Traversal must include the existing semantic containers.

Merge refinement with the originating stroke's user undo transaction. Do not create a new user undo step or truncate redo when no element changed. Expire pending estimate records when UIKit says estimates are final and bound their lifetime/memory.

Notify N2's authoritative dirty-generation path after an actual accepted refinement, including one arriving after the last save. Preserve transformations, partial erasure and later user edits when deciding whether a refinement still applies.

**Gate:** draw, move/recolor or erase, receive delayed estimates, undo/redo, save and reopen; later edits survive, no deleted stroke returns, and final accepted geometry is saved.

### C2. Make persisted visible geometry authoritative

**Files:** core/src/editor/erase.cpp, selection/selection.cpp, editor/editor.cpp, geometry/affine.h; one bounded StrokeGeometry adapter; existing Google Ink build inputs.

Use Stroke.outline as the authoritative filled shape for selection, erasing, bounds and reopened fragments. Preserve raw samples separately as provenance. Cache derived geometry by immutable element identity and geometry revision. Sample reconstruction remains for actual input modeling, not a substitute for an already authored outline.

Use the pinned Google Ink outline/subtraction utilities and its existing libtess2-backed multi-contour tessellator. Canonicalize contours using nonzero winding; preserve outer boundaries and holes. Construct meshes with explicit boundary-outline indices. A PartitionedMesh made from triangles without those indices is not a valid subtraction mask: subtraction derives masks from outlines.

There is an important inspected dependency constraint: geometry_internal::ComputeTriangulation explicitly drops holes, and public Stroke::Subtract uses it internally. Do not use either uncorrected operation for this repair. Use ComputeSubtraction → ComputeBoundaryLoops and Tessellate<PointTessellationHelper> with TESS_WINDING_NONZERO in the bounded adapter. The algorithms and tessellator already belong to the pinned dependency; do not implement a new polygon engine. Isolate internal-header use in one place, retain the pin, and include a conformance fixture so a future dependency update cannot silently change this contract. [Pinned outline processing][g-outlines] · [Subtraction implementation][g-subtraction] · [Tessellator][g-tessellation]

Replace product lasso's approximate coverage with a defined rule: select a visible filled stroke region or a box-like object's transformed rectangle only when the actual covered area exceeds 90% of its area. Compute target-minus-lasso boundary loops, then sum signed areas, subtracting holes. Close and canonicalize concave/self-crossing lasso input through the same nonzero-winding adapter. Invalid, nonfinite or zero-area targets are safe failures. This removes the two-triangle diagonal false positive and avoids a second hit metric for thick ink.

For an Image, transparent pixels remain part of its whole-object rectangle; selection does not decode or trace the bitmap. Text uses its laid-out box. A Figure with a current editor view uses that displayed view's bounds; original hidden ink is not selectable in place of the edited picture.

Use all transformed visible geometry for broadphase bounds, including stroke width and all rectangle corners/ellipse extrema. Remove the two-corner and determinant-scaled approximations. Finite invertible transforms are required throughout.

Native Shape elements also need the renderer's actual geometry. Current ShapeStrokes re-models them as round Google Ink Marker strokes, while the renderer uses butt caps and miter joins. Reuse the renderer's ShapePath/StrokePaint and the pinned Skia skpathutils::FillPathWithPaint expansion, with the same transform and miter limit. Flatten the filled contours to the declared screen-space error bound, then use the common adapter. A false result denotes a hairline; retain the original element and return recoverable unsupported geometry rather than treating it as empty/deleted. [Pinned Skia path expansion][skia-fill]

**Gate:** tiny diagonal lasso does not select a box; 89% and 91% cases behave as specified; concave/self-crossing masks, rotated/nonuniform objects, holes, imported vector outlines and sampleless geometry stay selectable, erasable and stable on reopen. Cutting a rectangle miter corner or butt-ended line leaves untouched pixels/caps unchanged.

### C3. Subtract the eraser footprint from visible ink

**Files:** core/src/editor/editor.cpp and erase.cpp, common geometry adapter and fragment serialization.

Replace PagePath/sample-centerline cutting and RebuildOutline of surviving samples with filled-shape subtraction through C2's inspected hole-preserving path. Build each swept eraser segment as a round capsule; a stationary point is a disk. Use a screen-space chord-error tolerance for round boundaries. Transform the mask and visible shape into a common coordinate system.

Apply successive gesture segments against a stable gesture base and cached current result. Commit one undoable transaction on completion; cancel restores the exact base. Use the existing checked SegmentSpatially helper for disconnected geometry, with deterministic fragment order and new fragment IDs. Its multi-component output at this pin omits outline metadata: reconstruct each fragment's canonical boundaries from its triangle loops before persisting it. Preserve original z-position, Link/Bookmark containment, raw input, brush/version, color, opacity and original-stroke provenance.

Persist the resulting contours, including holes. Reopening or erasing a fragment again must use those contours, never regenerate the pre-erase stroke from retained raw samples. Structural geometry edits invalidate outstanding estimate replacements for that shape; a late estimate cannot recreate a cut-out region.

Whole-stroke erasing uses the same accurate hit geometry and removes the whole target. Expose the distinction between Stroke eraser and Partial eraser clearly. Show the chosen footprint during contact and supported Pencil hover. Respect hidden/locked layers and keep structured figure internals owned by their editor.

**Gate:** grazing a thick marker edge erases the visible intersection; an interior disk produces a persistent hole; pixels outside the swept mask remain unchanged within antialias tolerance; fast sparse gestures, zoom/rotation, cancel, undo/redo, semantic containers, reopen, second erase and exports preserve the result.

### C4. Make highlighter coverage uniform across each layer

**Files:** core/src/render/renderer.cpp, shared paint-plan helper, format/page_svg.cpp/parser, export/pdf.cpp, live-ink metadata and format documentation.

Adopt this explicit behavior: within one notebook layer, strokes with identical highlighter RGB and authored opacity paint one uniform coverage region, including strokes inside Link/Bookmark groups. Different styles compose in stable first-appearance order; ordinary displayed content paints above highlighting. Layers remain separate compositing boundaries. A Figure with an editor view is atomic; its hidden original ink is not included in notebook highlighting.

Create one shared paint plan for screen, PDF and standalone SVG. In Skia, paint each same-style group's outlines at full opacity into a bounds-limited layer and apply authored opacity once when restoring it. Include the live highlighter in the same pass and actual layer so pen-up does not change its appearance. Cache by immutable membership and affected bounds. Keep each original stroke individually selectable, erasable and undoable.

For standalone SVG, use an explicit paint-model marker and retain the single complete editable layer/semantic tree in the existing root-level layer groups, marked display="none". Keep original IDs, order, transforms, InkML, source/asset references and authored fill-opacity attributes. On highlighter paths only, add style="fill-opacity:1" so derived SVG references paint full coverage. Generate visible use references inside a nested SVG view with x/y=0, width/height=100%, overflow="visible" and mn:role="paint". Use each style group's opacity attribute, not fill-opacity. Paint each layer's highlighting then its ordinary content before proceeding to the next layer.

The paint plan references displayed leaves or atomic Figure views; the ordinary pass must not reference a whole Link/Bookmark subtree containing highlights, which would paint them again. Apply collected ancestor transforms on leaf references and preserve link behavior with presentation-only link wrappers. Include href/xlink:href for the existing SVG compatibility convention. Do not duplicate editable elements or destructively union their data.

The marked-file reader reads the authored root-level tree and ignores the derived nested view. This placement is a compatibility requirement: v343 ignores notebook format/version and reads root-level groups only. Moving the authored tree into defs would make it read an empty page and risk destructive rewriting. With the selected placement, v343 ignores display/style overrides and the nested SVG view, retains the original editable content and authored opacity, and can rewrite it with its old additive appearance. New readers/writers, shared-host compatibility, schema documentation and golden round trips must land together. Unknown future markers must fail safely in the updated reader.

The compatibility construction was independently rendered with Inkscape: isolated and overlapping same-style regions, including across a Bookmark, had identical interior pixels; the ordinary black pen was unchanged. That validates the standalone-SVG construction, not the complete future app implementation.

**Gate:** repeated same-style passes have the same interior color as one; live/committed/export/reopened appearances agree; cross-Link/Bookmark coverage stays uniform; different styles follow the defined order; one Undo removes one original stroke; no source, identity or hole is lost.

### U1. Finish tool behavior, presets and text sizing

**Files:** Sources/EditorTools.swift, PenEditorPopover.swift, ColorPalettePopover.swift, TextEditorSheet.swift, InkEditorView.swift, InkCanvasView.swift; existing text-width C API.

Use one accepted tool/configuration state from N1. Render one adaptive rail, with one set of stable controls and hit regions; remove the duplicated railContents alternatives under ViewThatFits. Adapt with one scrollable layout when necessary. Verify the physical tap target, selected accessibility trait, rendered highlight and resulting operation together.

The current enum/icon mapping has no numeric offset, and Image is explicitly unselected. Do not implement a guessed index shift to address the reported Highlighter→Lasso, Eraser→Image or Lasso→Figure highlights. The known repairs are the unsafe feedback boundary, accepted tool-state contract and duplicated-layout removal. The separate screenshot/action oracle must prove these reports are resolved. Keep the eraser glyph legible in its selected state as well as implementing the missing eraser footprint.

Keep the existing Google Ink Marker family as the fixed-width tool; use a coherent nib icon and Marker label, a pressure-ramp preview, and a visibly wider fresh default (3 pt). Preserve users' saved custom widths. Pen remains pressure responsive. Do not introduce another brush engine merely to distinguish the tools.

Show size, color and opacity together in the ordinary tool popover, with a live preview. Remove the Advanced gate for opacity. Replace Save pen with Add to favorites; immediately show the saved style as a labeled/accessible preset in the rail's quick-access section. A preset has stable identity and selects tool, width, color and opacity together; edit/remove/reorder through a native menu. Persist and restore it. Saving cannot depend on an incidental onDisappear.

Remove the unexplained default 300 field. New text uses existing intrinsic paragraph sizing, bounded by usable page width for long content. Put wrapping-width handles on the selected text box. Width gestures call the existing SetSelectedText width operation and reflow through Skia Paragraph without scaling glyphs; one gesture is one undo step. Retain UITextView's marked-text/IME and direction fixes. Use labeled optional typography settings if exact values are exposed.

Make Follow links an independent persisted boolean, default true. Direct finger taps follow links while Pencil keeps the chosen drawing tool; selection/menu actions edit links. If Draw with finger is enabled, disambiguate a stationary tap from a drawing drag at the gesture boundary. Setting the default tool to Navigate would suppress ink and is not the fix.

**Gate:** all tool states agree with their effects in each layout; presets survive switching/relaunch; size and opacity are simultaneously reachable; text Done succeeds, boxes reflow visually, IME works and links follow without disabling Pencil writing.

### F2. Commit a complete structured figure revision

**Files:** maintained Visual TikZ Editor snapshot/render scheduler and raw-ink interface; core Figure model, document/figures.cpp, ink.cpp/ABI, page SVG reader/writer, renderer, selection bounds; native EngineDocument adapter; core/scripts/build-skia-ios.sh, core/CMakeLists.txt, C header/WASM exports and both host bindings.

Add a revision-matched snapshot operation to the maintained editor. Await its existing compute scheduler until the rendered snapshot's source and revision equal the requested current source. Return exact source, source revision, SVG, viewBox and associated scene/original-ink data or an explicit error. Emit render completion even if the source string did not change. A fresh source string plus lastKnownSvg is never a valid commit.

Add create/commit operations with figure ID, expected revision, exact source, original-ink/scene references, editor SVG and bounds. A new draft lives outside the notebook page until the first Done passes validation and its model transaction is accepted; the old capture-only creation function cannot create the required blank visual editor object. Dismissal still waits for local durability, as specified below.

Commit all figure fields and dirty sidecars in one DocumentHistory transaction. Store an optional revisioned editor view on Figure. Render it through the existing pinned SkSVGDOM and a bounded local/data resource provider; figures without a view keep rendering their original children. The prior ParseFigureView adapter in commit 827fdf3 supplies the relevant bounded representation. Do not pass arbitrary editor SVG through the app's elementary ReadElements converter or rebuild SVG semantics in Swift/C++. [Prior adapter][prior-figure-view] · [Skia pin][s-skia]

Update common selection/hit bounds to match the current displayed view. Undo/redo restores source, scene and picture together. Duplicate/paste remaps figure IDs and sidecars, preserving independent edit identity. Validation, snapshot or stale-target failure before acceptance changes none of the committed figure. Once accepted, later storage failure leaves that complete revision dirty and retryable; it does not replay or silently roll back the edit. Preserve unknown source/comment bytes and original InkML.

Expose the maintained editor's existing primitive interpretation and curve fitting to explicit raw-ink import, retaining stable stroke IDs/samples. Preserve original ink durably behind Restore drawing; its current transient React result state is insufficient. Handwritten labels remain ink; this does not add OCR or full TeX compilation.

Retire the parallel native FigureTikZGenerator/FreeTikZ preview path after the new editor handles creation and explicit conversion from selected ink. Preserve read compatibility with scene-v1 and existing raw-child figures.

Restore skia_enable_svg=true and the svg Ninja target in the iOS Skia build script; the deletion removed the compiled capability as well as the adapter. Restore the bounded renderer source in core/CMakeLists.txt and export create/commit/read-state/finalize-load operations through the C header, WASM exports and host bindings. Require device, simulator and WASM linking plus rendering actual editor-produced SVG. Keep compiler/preamble/TeX-recipe code removed. [Build script][s-skia] · [Core build][s-cmake]

**Gate:** immediate Done during a pending render saves matching source/picture; delayed old render is rejected; create/edit/duplicate/move/undo/reopen/export all refer to the same correct figure revision; C21 proves conversion, original-ink restoration and old-reader compatibility.

#### F2 durable scene and page-SVG representation

Use the Figure's existing scene/tikz/draft asset contract. For each accepted revision, create immutable flat files named assets/f-INSTANCE-rREVISION.scene.json and assets/f-INSTANCE-rREVISION.tikz, and point the existing scene/tikz attributes at them. Clear the accepted draft reference with the complete model transaction.

The version-2 scene envelope contains:

```json
{
  "format": "math-notes-figure",
  "version": 2,
  "revision": "opaque-revision-token",
  "committed": {
    "sourceBase64": "exact-authored-source-bytes",
    "sourceSHA256": "digest",
    "svgBase64": "self-contained-editor-SVG",
    "svgSHA256": "digest",
    "svgViewBox": [0, 0, 400, 300],
    "localRect": [100, 150, 200, 150]
  },
  "original": {
    "kind": "ink",
    "sceneV1Base64": "original-scene-v1-bytes-when-present",
    "inkSVGBase64": "original-geometry-and-InkML-archive",
    "objectKeys": ["o1", "o2"]
  },
  "editorState": {
    "format": "owned-editor-state-format",
    "version": 1,
    "dataBase64": "owned-state-and-raw-ink-associations"
  }
}
```

The envelope is self-contained: no required extra sidecar, notebook-relative internal path or global Figure ID. Embed SVG resources as data/geometry. Preserve the original scene-v1 bytes and ink archive, carrying them forward without recursively wrapping earlier envelopes. Existing FigureAssetPaths, dirty-file filtering and clipboard logic track/copy only scene/tikz/draft payloads; an untracked view sidecar hidden inside JSON would be lost. [Asset reachability][s-notebook-json] · [Dirty filtering][s-dirty] · [Clipboard sidecars][s-selection]

Keep original Figure children in their existing direct tree. When a valid committed view exists, mark each serialized original child root display="none" and append one nested SVG containing an image whose data URI embeds the complete editor SVG:

```xml
<svg x="100" y="150" width="200" height="150"
     viewBox="0 0 400 300">
  <image x="0" y="0" width="400" height="300"
         href="data:image/svg+xml;base64,..."
         xlink:href="data:image/svg+xml;base64,..."/>
</svg>
```

Declare the xlink namespace. Explicit dimensions and compatible href/xlink:href aliases belong to the maintained editor's snapshot/export normalization. The image embedding isolates internal SVG IDs and definitions between figures. Do not add a new hidden group wrapper: the old parser turns non-Figure groups into Bookmarks, changing the semantic tree.

For a figure created entirely in the visual editor, original.kind is none. Store one ordinary thin rectangle child as its legacy display/hit fallback, using the committed localRect. Updated readers hide it and do not treat it as original ink; Restore drawing is unavailable for that case. This avoids a zero-bounds object in old readers.

The isolated-view construction was rendered as a standalone SVG: two adjacent editor images with the same internal glyph ID rendered independently, while the original children remained hidden. The compatible xlink aliases were necessary for that renderer. This verifies the encoding construction, not the future native implementation.

| Read/write case | Required behavior |
| --- | --- |
| v343 reads new Figure | It ignores display attributes, reads original children/fallback rectangle, and skips nested SVG. It displays the original ink/fallback. |
| v343 rewrites new Figure | It drops presentation attributes/view but retains the Figure ID/transform, three known sidecar references and their opaque payloads. Editable data and the complete new revision survive. |
| Updated reader opens that rewrite | Resolve the envelope after assets load, hydrate the current view and restore its display; regenerate presentation SVG on the next write. |
| Updated reader opens scene-v1 | Keep original children and opaque scene bytes; upgrade only on an explicit accepted structured revision. |
| Unknown/malformed/missing envelope | Preserve children and raw files; expose a recoverable Figure error. Do not replace unknown data or treat the object as empty. |

Add finalize-load / resolve-Figure-records after pages and assets load, before establishing the saved baseline. Page parsing alone is insufficient because assets arrive later. Both native/web loaders and the copy/import path must call it after sidecars are installed and before the inserted object is exposed. The envelope is authoritative; nested SVG is regenerable presentation.

Read editable source through the existing preference: draft when present, otherwise tikz. Compare exact bytes with the envelope's committed source; hashes accelerate checking but do not replace equality. A mismatch preserves both pending source and the last complete committed source/SVG pair. Show the last committed picture with a visible draft-changes state; open the editor on the pending source. Ordinary load/save cannot overwrite that pending source or claim the old SVG renders it. Explicit Done with a matching snapshot replaces the pair. Cancel preserves any draft that already existed when the session opened.

Use Figure-local editor/object keys, whose live identity is the Figure ID plus local key. Original archived stroke IDs are provenance, not global live references. Keep ordered associations to original-tree leaves. The existing old copy operation remaps Figure/child IDs and copies opaque sidecars unchanged, so new readers bind local keys to current child IDs by checked tree position and geometry/sample identity, excluding remapped ID/time labels. New-client duplication remaps live IDs once and allocates independent sidecar paths without rewriting the original archive or source bytes. Restore drawing reuses corresponding live child IDs where possible and allocates fresh IDs for real collisions; persist that mapping in the accepted transaction. Preserve and report a mismatching legacy child tree as an association conflict, rather than overwriting it from the archive.

Map svgViewBox into localRect and apply Figure.transform. Selection, lasso, resize and invalidation use those four transformed corners; hidden originals do not set the current view bounds.

#### F2 acknowledgment and retry

Validate identity, expected revision, exact source/SVG association and finite bounds before acceptance. Accept one complete model/history revision. Done waits for that revision's **local durable acknowledgment**, never remote/provider completion. A later provider failure keeps the accepted revision dirty; Retry retries persistence for the same revision and cannot add another history entry.

If local persistence fails after model acceptance, retain the session with explicit saved-state failure and retry. The complete accepted figure remains in the note; do not claim it was never changed. Continuing to edit produces subsequent revisions through the same contract. Cancel discards only unaccepted session edits, and cannot silently remove an already accepted revision.

### F3. Deliver one fullscreen Structured Figure editor

**Files:** Sources/FigureEditorSheet.swift, InkEditorView.swift, ContentView.swift, EditorTools.swift; maintained workbench host mode and asset build.

Use the name **Structured Figure** and one shape/connection pictogram throughout. The toolbar action always opens the same native fullscreen presentation with a stable edit session. New figures start on a blank visual canvas; existing figures open through their badge or selected Edit action. Existing-ink conversion is separately named Create structured figure from selection.

Default to the maintained editor's canvasOnly workspace. Show essential visual tools; hide source and developer inspection surfaces. Properties opens a contextual dismissible panel. Show TikZ opens an independently closable source panel; Copy TikZ obtains the current source without initiating a save. Suppress redundant desktop file menus, document tabs and unavailable providers through the host configuration, not overlays covering DOM controls.

Use explicit Done/Cancel navigation. Done commits through F1/F2/N3; errors retain the session and draft with Retry or Continue editing. Cancel discards only the uncommitted session changes, with confirmation when appropriate. Fullscreen touch/rotation/multitasking and backgrounding must not create another session or trigger a save-and-close gesture.

Add a small persistent on-page figure badge, a selected frame and a named Edit action. Exclude that chrome from exports. Preserve original page placement and fit new figures inside page margins; ordinary whole-object resize remains available afterward.

Bundle the maintained editor, its local MathJax/fonts and required assets at a recorded pin. Cold startup and normal editing must work without network requests. Keep WKURLSchemeHandler's already-fixed local module transport.

**Gate:** C10–C13; one visual workflow on every entry, optional code, no unsolicited closing, distinguishable stored objects and real source/picture persistence.

### U2. Make the library one coherent surface

**Files:** Sources/NativeLibraryView.swift, NotebookStorage.swift, ContentView.swift, folder/note details sheets; small shared metadata types and docs/FORMAT.md.

Replace Search and Recent sidebar destinations with one LibraryQuery: search text, favorites toggle, tags, sort and direction applied to one listing. Keep folder navigation/breadcrumbs within that surface and Trash as an explicit filter/view state. Use search directly; it must not be a sidebar item that merely moves focus. Favorites and tags must compose with search and sort instead of silently resetting each other.

Add Most recently used, descending by default. Current Recent sorts modification times, so simply relabeling it would be false. Record successful user opening/focus transitions, including reading without editing, and roll note use up to containing Notebook folders. Saving, scanning and thumbnail refresh never count as use.

Store local recency in a small Application Support plist on the existing storage worker: persistent local root UUID/bookmark, entry UUID/kind/bookmark/last-known relative path, last-used date and monotonic use sequence. Keep path references as I/O locators; use the local UUID as stable library item identity. Do not persist fileResourceIdentifier/inode as cross-restart identity.

Own moves already remap metadata and descendant draft/template paths. Extend that operation to preserve recency IDs. Forward external subitem old/new URLs, which the current presenter discards, to the same idempotent remap. Resolve bookmarks on launch/foreground for missed moves and whole-root renames. If a provider copy/delete loses identity, preserve unmatched metadata/history and treat the new item as new; do not guess by name/mtime or overwrite a conflicting destination record.

The user-visible Notebook is currently FolderReference; Note is backed by the internal NotebookReference. Folder tags already exist. Add folder favorite=false as an optional field in existing .library.json metadata, preserving Note favorites/tags and shared-reader defaults. Tag creation belongs in the selected Notebook's assignment sheet: show known tags and Create and assign tag. Registration and assignment commit together; Cancel creates neither. Remove the global New tag row.

Replace whole-card fixed aspect ratios with a natural-height card: fixed-aspect cover, then metadata/footer, with the 44-by-44 menu as a sibling control. The current bottom-trailing overlay competes with variable title/tag height, inadequate trailing padding and the enclosing aspect constraint. Do not mask this with arbitrary zIndex. Limit visible tag rows with a clear remainder indicator while preserving full tags in Details. Retain the last valid thumbnail during async replacement instead of setting it to nil on every modified-key change.

Use one prominent plus creation menu with New notebook and New note, and one consistent creation action in empty-state guidance. Set an explicit accessible primary-button foreground/background pair; current inherited ink foreground and ink tint can make the prominent New notebook button unreadable. Collapsing navigation and the toolbar must work at narrow widths; remove the permanent 220-point sidebar constraint.

**Gate:** C14/C15: long titles/many tags and repeated thumbnail refresh cannot hide the menu; all filters compose; reading changes recency; tags/favorites survive moves/relaunch; creation remains legible and reachable in every layout.

### U3. Finish the editor shell, theme and native interaction

**Files:** Sources/NativeTheme.swift, NativeLibraryView.swift, ContentView.swift, EditorTools.swift, EditorSettingsSheet.swift, CreationSheetLayout.swift, PageOverviewSheet.swift, LayersSheet.swift and associated sheets.

Keep the adopted light book/paper design and bundled type families. Complete semantic tokens for text, muted text, selected state, accent, on-accent, surface and destructive actions. Avoid blanket foregroundStyle/tint combinations that erase contrast on prominent buttons. Use explicit type roles; SwiftUI custom fonts already scale relative to body by default, so do not claim all current fonts are fixed. Assign appropriate relative roles and UIFontMetrics to UIKit text controls, with layouts that expand under larger type.

Reserve canvas content insets for the tool rail and inspectors, including fit-width/page calculations. The current rail overlays the canvas and can cover writing. Keep navigation at a stable leading edge, frequent page actions together and document actions separate. Retain the existing rule that one open note does not need an open-note strip. Rename Show tab strip to **Show open notes**.

Replace the long Pages action menu plus separate overview modal with a collapsible native inspector containing **Pages, Bookmarks and Layers**. Put Before, After and At end on the relevant add-page control and show the destination. Put clear/delete beside their target page; retain action-specific Undo and confirmation for destructive clearing. Do not add a new Outlines subsystem solely because an older comparison mentioned it.

In Layers, replace the seven competing text buttons in each row with name/selection, visibility, lock and a native contextual menu for rename/reorder/merge/delete. Keep current content visible while managing pages/layers. Selection actions such as paste, clipping, link and text editing belong with the selection/page interaction, using native edit/context menus where appropriate.

Use one Share flow: content/page range and supported format, then the system destination flow for Files, apps or printing. Preserve existing PDF/export functionality, move duplicate Share PDF/Export PDF entry points into this flow, and show version comparison only for an actual conflict with understandable choices.

Replace self-announcing autosave text with a compact reserved-width visual indicator. Delay transient animation until a save remains active long enough to be meaningful; use a nonanimated equivalent for Reduce Motion. Expose the current state to accessibility on focus, and announce actionable failure/recovery rather than every stroke's pending/recoverable/saved transitions.

Use native navigation, menus, sheets and adaptive forms. Retain dirty-dismiss protection already added to creation sheets. Remove redundant Preview/details labels, unexplained settings names and inconsistent action wording; use sentence case. Ensure forms scroll with the software keyboard and retain drafts through rotation. Use contextual elevation/page margins without reverting to the obsolete web palette or adding decorative controls.

**Gate:** screenshot and interaction coverage for every exposed surface, including populated pages/layers, keyboard, long text, narrow layouts, selection, destructive Undo, share and error states; 44-point primary touch regions, visible keyboard focus and meaningful VoiceOver state. Text contrast meets the chosen 4.5:1 normal / 3:1 large and essential non-text targets. [Apple controls][apple-controls] · [Apple contrast][apple-contrast]

### D1. Make the next report directly debuggable

**Files:** Sources/CrashReporting.swift, PreviousFailureSheet.swift, InputTrace.swift, MathNotesApp.swift, release metadata and symbolication helper/workflow.

Keep the existing KSCrash capture and release dSYM upload. The current issue formatter drops image load addresses, reduces stack content to 40 frames with nearest exported names, and exposes the richer stored report only as a separate manual share. Export a coherent diagnostic packet from the already captured raw report, Apple-format report and release identity.

Include incident ID/time, app version/build, source SHA, device/OS, image UUIDs and load addresses, architecture, exception/signal details and relevant thread stacks. Include bounded recent semantic actions, command/session/revision IDs, accepted tool, object types/counts, save stage/queue depth, figure request IDs and operation timing. Exclude note contents, raw source and user paths by default; the user can choose to attach a reproducing document separately.

Provide one reviewable report/share flow with concise reproduction notes and the packet ready to attach. Keep reports until the user acknowledges export/handling; do not call a copied issue URL a successful upload. Add a standard macOS atos symbolication command/helper that refuses mismatched UUIDs and resolves the exact archived dSYM.

Replace unconditional UIWindow/UIGestureRecognizer swizzling and per-touch public string logging in the normal input path with bounded opt-in tracing and cheap OS signposts around commands, snapshot capture, serialization, file coordination and figure commits. Use KSCrash's hang facilities; do not add another permanent custom polling watchdog. Diagnostic initialization failure must not become a separate startup crash, and reducing instrumentation must not hide the underlying failures.

Preserve enableSwapCxaThrow=false: the repository explicitly disables it for a known SDK/Metal interaction. Re-enabling it is not necessary to recover the missing stack information.

**Gate:** a deliberate test crash and test hang produce a packet that resolves to the exact source build with useful operation context; normal drawing does not continuously format/log whole touch arrays or document source.

## 5. Exact geometry adapter contract

The following call sequence is selected at the inspected Google Ink pin. It closes the hole-loss and mask-outline traps before implementation begins.

1. Use ink::geometry_internal::Tessellate<ink::geometry_internal::PointTessellationHelper> with an absl::Span of contour spans and TESS_WINDING_NONZERO. The multi-contour overload returns vertices plus flat triangle indices and preserves holes. Remove zero-area triangles; orient the surviving triangles counterclockwise.
2. Construct ink::geometry_internal::ShapeOutline from those triangle loops. ComputeBoundaryLoops(const ShapeOutline&) returns canonical outer and hole boundaries.
3. For lasso, use the existing CreateClosedShape closure behavior, then the same canonicalization. ComputeSubtraction(targetRegion, lassoRegion) yields the uncovered region. Sum signed shoelace areas of its boundary loops, with their consistent orientation, rather than summing absolute loop areas. Select only when uncoveredArea is less than 0.1 times targetArea. Degenerate gestures produce no new selection or document mutation; nonfinite inputs return a recoverable status.
4. For erase, construct the swept filled capsule and run the same subtraction/canonical-boundary operations. An interior eraser hole remains a hole.
5. To make a PartitionedMesh, tessellate the canonical loops with the same multi-contour overload. Its vertex output begins with the concatenated input contour vertices, allowing contour-offset indices. Use MutableMesh's float2/32-bit-index format, AppendVertex, counterclockwise AppendTriangleIndices and ValidateTriangles. Supply explicit boundary-outline index spans to PartitionedMesh::FromMutableMesh; follow the pinned Ink clockwise-outline convention, preserving the hole orientation relationship. That factory partitions/remaps outlines.
6. For disconnected erase fragments, call the checked ink::strokes_internal::SegmentSpatially(const PartitionedMesh&, const AffineTransform&, float) with zero-distance separation. Its multi-component ConstructMeshes path sets outlines to an empty list, so calling StrokeOutline directly would lose the visible fragments on persistence. For each returned fragment, enumerate its counterclockwise triangles into ShapeOutline, obtain ComputeBoundaryLoops, then reverse the canonical loops into the persisted Ink winding convention. Alternatively rebuild the fragment through step 5 with those boundaries before using StrokeOutline. Preserve holes and copy the original model's raw input/brush/style/provenance. Sort fragments deterministically.
7. Editing/hit testing does not need to construct ink::Stroke. If another caller does, first validate Brush::Create and that the shape render-group count equals the brush coat count; the inspected supported stock families are single-coat. Unsupported multi-coat data returns status.

Keep these details inside core/src/geometry/filled_region.h/.cpp. Add conformance tests for the explicit upstream conditions: non-null empty groups, interior holes, mask outline indices, concave/self-crossing contours, winding, singular transforms, more than one mesh partition, and two disconnected fragments with an interior hole that survive reopen and a second erase. Do not substitute unpatched ComputeTriangulation or public Stroke::Subtract because their simpler names look preferable. [Geometry implementation references][g-outlines] · [Tessellation][g-tessellation] · [Mesh factory][g-mesh] · [Segmentation][g-segmentation] · [Fragment outline omission][g-segmentation-impl]

## 6. Acceptance scenarios and release evidence

### Primary acceptance: ordinary day-to-day user journeys (J01–J20)

**These are NEW user stories, designed from the actual Math Notes product capabilities—not from the complaint list.** They are the primary, mandatory, replayable end-to-end usage corpus. Each is a *continuous human task*, with several screens and interacting features. Do not fragment the story into isolated feature tests, reset the app midway to make assertions easier, or replace any action with a model API or test-hosted SwiftUI view. Start with actual UI state, use ordinary in-app creation and navigation, and end with independently observed results. Data brought in from Files (a PDF or image) are legitimate *user inputs*; test code must not directly construct a notebook's internal state. Include these stories even if their features have never been mentioned in a bug report. [Product feature specification](https://github.com/dzackgarza/math-notes-app/blob/2da1707e1d4f28a609550268ef30459731985aaf/docs/FEATURES.md) · [L0/L1 everyday operations](https://github.com/dzackgarza/math-notes-app/blob/2da1707e1d4f28a609550268ef30459731985aaf/docs/specs/core-features.md) · [Tablet interaction model](https://github.com/dzackgarza/math-notes-app/blob/2da1707e1d4f28a609550268ef30459731985aaf/docs/specs/tablet-ui.md)

**Each story must have executable UI actions and user-visible assertions at meaningful intermediate checkpoints, not just at its end.** Look at screen recordings for the whole story, not only the moments already known to fail. The pen/stylus equivalent on the Simulator is a multi-point finger drawing gesture with **Draw with finger** switched on through Settings; actual Pencil behavior receives the same ordinary stories on a physical iPad before release. PDF and image inputs are supplied to the simulated Files app, imported via Math Notes' real picker, and exported products are opened in an independent user-visible viewer. Internal document paths and implementation events cannot stand in for a successfully completed story.

**J01 — Take a lecture's worth of notes.** Start from the library; create an *Algebraic Geometry* notebook and a *Lecture 04 — Divisors* note on dotted paper; write the date, a definition, a theorem and several lines of proof; switch between pen and highlighter; draw a small commutative square with arrows; make and erase an incorrect arrow; add a second and third page while continuing the proof; pan and zoom to read an earlier line; insert one typed reference; briefly leave the app and return; continue writing; exit to the library, close the app, relaunch and open the note again. **Observe:** every page has the intended handwriting and page order, earlier material survives additions and edits, tool effects match their visible selections, the sheet and pen remain operable throughout, and the reopened lecture matches what was saved.

**J02 — Work through a difficult proof and revise its layout.** Open a multi-page proof note; copy a useful calculation onto a new page; write a continuation below it; use the eraser to remove a mistaken term without deleting its neighbors; insert a block of vertical space in the middle of the argument; lasso a paragraph of handwritten algebra and move it below the new gap; resize a small sketch; add a page for a separate case; undo the last two actual edits, inspect the page, redo one, and make a different correction; move between the original and revised pages; close/reopen the note. **Observe:** neighboring expressions remain untouched, moved and resized ink retains its shape, the revised proof reads in its intended order, copied content remains independent, and the reopened version matches the final visible result rather than a stale intermediate edit.

**J03 — Read and annotate a full research PDF.** Through Files import a 20-page mathematical article with text, figures and distinct page sizes; navigate to page 7; highlight a hypothesis and write a marginal comment; pinch-zoom into a diagram and annotate it; jump to page 12 and insert a blank working page adjacent to it; calculate on that page; bookmark the relevant result; return to page 7; compare its notation with page 12; export the marked-up PDF via Share; open that exported PDF in an independent viewer, inspect pages 7, 12 and the inserted working page, then reopen the note in Math Notes. **Observe:** originals retain content and order, annotations stay attached to their intended pages, the blank calculation page has the correct position, bookmarks navigate correctly, and the exported/reopened documents faithfully display all work.

**J04 — Set up a semester's notes before class.** In a fresh library create three course notebooks with distinct cover colors and default paper styles; create a *Research* tag while assigning it to one notebook; start a *Seminar Notes* note template with graph paper and a title; enter text into another new-note form, cancel it, and verify it did not create a note; create a genuine note from the template; add a page and some ink; return to the library; search for the note; inspect all three notebook cards and reopen the created note. **Observe:** titles, covers, notebook location, tags and paper choice display consistently, canceled draft content does not leak into the library, searches open the right note, and the saved note preserves the selected template and ink.

**J05 — Review yesterday's lecture and extend it.** Open an existing lecture note through its notebook; scroll through several pages; use a bookmark to return to the proof of a lemma; read the definition on an earlier page; append a correction in a different ink color to the lemma; add a small example beneath the proof using insert-space rather than overwriting it; follow the original bookmark again; add a new page titled *Questions*; write two questions; return to the library, reopen and use the bookmark again. **Observe:** the bookmark still reaches the same mathematical material after edits and page insertion, earlier pages are unchanged, additions appear only where requested, and the note still opens at a usable navigation position.

**J06 — Find a result in a crowded library.** Begin with several real notebooks and many previously written notes, including similarly named ones; browse the library; search using a partial title such as *K3*; narrow to a tag or favorite; change sort order to most recently used; open one candidate, examine its contents, return and open another; favorite the correct note; clear the search; verify the favorite and recent-use ordering; exit and relaunch; search and reopen it again. **Observe:** filtering, sorting, search and favorite operate together on the same visible library, the correct note opens each time, no card menu is obscured, and the organization remains after relaunch.

**J07 — Organize notes accumulated over several weeks.** From the library rename a notebook; move two notes to another notebook; create a tag while assigning it to the moved notes; favorite the main reference note; move a discarded scratch note to Trash; inspect its absence from ordinary searches; restore it and open its existing ink; rename a different note; close/relaunch and examine the library in list and grid presentations where available. **Observe:** each action changes the intended visible item, the notes' contents survive moves and renames, metadata follows the correct note, Trash does not masquerade as permanent deletion, and no cover/menu overlay hides actions on crowded cards.

**J08 — Compare two mathematical notes in split view.** Open a reference theorem note, enable two-document split view, then open a second note containing an attempted proof; zoom the reference to the theorem while writing a counterexample in the scratch note; change pen settings, switch focus between panes, scroll the reference without moving the scratch page, copy an ink diagram from the reference to the scratch note using the visible copy/paste or clipping action; annotate the copied diagram; close the split view; reopen each note separately. **Observe:** active pane and target of every edit are unambiguous, each pane navigates independently, the copied diagram is editable without changing the source, and both saved documents remain correct.

**J09 — Reuse a frequently drawn diagram or calculation.** In a graph-paper note draw an exact sequence diagram or a 2×2 lattice diagram; lasso and save it to Clippings; switch to a different notebook; insert the clipping into a new note; move, resize and recolor it; write explanation around it; insert the same clipping a second time; modify only the second copy; navigate back to the original, then relaunch and reopen both notes. **Observe:** the clipping is visually selectable in its library, both inserted copies are independent, each has the intended position/color/size, and the original and both descendants remain intact after reopening.

**J10 — Turn a doodled diagram into a structured figure.** Draw a finite directed graph or commutative diagram as ordinary ink inside a proof note, including handwritten explanatory labels; lasso its diagram geometry; choose *Create structured figure from selection*; inspect and adjust its visual nodes and arrows in the full-screen editor; optionally open Show TikZ and copy the generated code; close the code panel; save the figure; return to the notebook, move it next to the relevant argument; reopen it and change one arrow; save, close/relaunch, and inspect the figure and original handwritten material. **Observe:** the diagram stays identifiable as a structured figure, its picture matches the accepted edits, its source remains associated with it, labels remain handwritten ink rather than being silently recognized, and the original drawing is recoverable through the visible Restore drawing action.

**J11 — Create and revise a structured figure entirely visually.** While explaining a proof, create a new blank Structured Figure; add multiple nodes and connections; adjust positions and line styles; briefly show and then hide Properties; rotate the iPad; continue editing; open Show TikZ, copy the source, and close it without saving; make another visual edit; Done; add ordinary pen annotations around the inserted figure; navigate to another page and back; edit the figure again; cancel an unwanted change; reopen the note. **Observe:** the full-screen canvas is always the editing surface, optional panels do not obstruct or commit work unexpectedly, canceled edits remain absent, the figure view and copied code correspond to completed changes, and ordinary ink stays independent.

**J12 — Combine image references with handwritten notes.** From Files insert a PNG diagram or photograph of a blackboard into a note; move and resize it to one side of the page; label its features by handwriting on the page; insert typed explanatory text; lasso-select a group of annotations and move them as a block; duplicate the image to a later page for a second calculation; erase a mistaken annotation near the image; undo/redo; export and reopen the note. **Observe:** imported imagery is displayed and selectable, the right object moves on each gesture, surrounding handwriting is not inadvertently erased or selected, later image copies remain independent, and the image, labels and text appear in the exported/reopened result.

**J13 — Mix typed mathematical commentary with ink.** In a working note draw a handwritten argument; insert a multiline typed paragraph containing mathematical symbols and a non-Latin name; resize the text box until it wraps into the intended margin; continue handwriting beside it; select and reposition the paragraph; edit one sentence and press Done; switch back to Pen; undo the text edit, redo it, then open a second page and insert another paragraph; exit and reopen. **Observe:** text is readable and correctly wrapped rather than arbitrarily scaled, the input/editor sheet closes when commanded, Pencil/finger drawing resumes, history changes the intended element only, and authored text survives exactly.

**J14 — Separate tentative work into layers.** Open an existing multi-page problem; add a layer named *Scratch* above the main ink; draw trial calculations on that layer; switch back to the main layer to add a final statement; hide Scratch to read the clean page; show it again; lock Scratch and attempt an edit there, observing that no locked content changes; select the editable layer, correct an equation; reorder the layers; save and reopen; export once with Scratch visible and once with it hidden. **Observe:** the visible and editable layer is always clear, the locked layer remains unchanged, layering affects the correct content, and reopening/exporting respects the selected visibility without discarding hidden work.

**J15 — Reorganize an untidy notebook before sharing.** Open a note containing six pages of mixed ink and figures; use Pages overview to find the page with an incorrectly placed lemma; duplicate that page for a different proof approach; move the duplicate after a later proposition; insert a blank page before a worked example; delete an actually empty surplus page and use Undo once to restore it; delete it again; add a bookmark; change the paper for newly created pages; open the reordered sequence by scrolling and by page overview; close/reopen. **Observe:** thumbnail previews match pages, insertion/reorder positions are the chosen ones, no unrelated page contents change, Undo restores exactly the deleted page, and the page sequence remains stable after relaunch.

**J16 — Customize tools during an actual writing session.** Begin a proof with the default pen; change size/color/opacity through the tool UI; write several lines; save that combination to favorites; switch to a highlighter and mark a statement; use the eraser and correct a term; select the saved favorite and add a related note elsewhere on the page; switch to a different note, use the same favorite again, return to the original; close/relaunch and select it once more. **Observe:** active tool and actual stroke properties match the user’s choice at every point, earlier ink does not change retrospectively, saved combinations are directly accessible and retain all properties across notes and relaunch.

**J17 — Read and write while changing viewport configuration.** Open a long notebook in portrait; write near the bottom of one page; pan and zoom to an earlier theorem; switch between fit width and fit height; rotate to landscape; switch to two-page arrangement; compare neighboring pages; use the page counter or thumbnails to navigate to a distant page; switch to vertical scroll; begin an ink edit and complete it; invoke the software keyboard in a text editor, dismiss it and return to the canvas; rotate back to portrait and reopen the note. **Observe:** the intended content remains visible and navigable, no layout overlays obscure controls, the app never draws while navigating or loses a stroke during layout changes, and the edited page reopens correctly.

**J18 — Continue work through ordinary interruptions.** Create a problem-solving note; write a first page; add an image and annotate it; wait until the app visibly indicates the work has been saved; open another app using the OS; resume Math Notes and append a second page; switch to another notebook to consult a result; return to the first note; let the iPad sleep/background the app; resume and write another correction; close or terminate the app using the OS; relaunch from its icon and open the note. **Observe:** app state recovers to an understandable location, all visibly saved pages and assets remain, no unsolicited duplicate save or modal occurs, and the user can continue writing after every return.

**J19 — Work with an externally managed notes folder.** Attach an ordinary notes folder using the real Files picker; create a notebook and annotate a page; leave Math Notes; in Files rename or move a note folder within the attached root; return to Math Notes and locate/open the moved note through the library; annotate it further; take the file provider offline, continue working locally where permitted by its visible availability; reconnect; reopen, and if an externally modified version conflicts, use the presented conflict-resolution UI rather than silently overwriting either edit. **Observe:** content remains associated with the right file/folder, external changes are not mistaken for deletions, errors are visible and recoverable, and the accepted local work is present afterward. Unsupported provider actions must produce understandable visible failure rather than invented success.

**J20 — Complete a long study/research session with many features.** Start with a library containing several filled notebooks; search/open an older result, copy a diagram into today's note, write a proof around it, annotate an imported PDF page, switch tools repeatedly, insert typed commentary, convert a sketch to a structured figure, move/resize the result, add three new pages, bookmark the conclusion, switch to a second note, return to the bookmarked page, reorganize the new pages, undo/redo several unrelated edits, export the current note, open the export, background/relaunch and revisit the work. **Observe:** each local step visibly affects exactly the intended note, page and element; no cumulative stall, state confusion, spontaneous dismissal, incorrect selection, corruption or content loss occurs; the finished document and exported file match the final visible session. This journey runs *without per-feature resets* or internal intervention and is extended with new natural variations over time.

**Cross-cutting expectations for all twenty journeys:** real navigation from the library into notes; actual UI actions; screenshots/checkpoints at significant transitions; a usable next action after every successful step; no surprise blocking modal, wrong-target edit or obscured actionable control; consistent behavior in portrait and landscape where appropriate; save/reopen verification after content edits; independent inspection of files a user would actually export. All outcomes are established from what the user can see and operate; no internal callbacks or serialized-model assertions are substitutes. For any currently unavailable or broken operation in these journeys, the failure is a real acceptance failure and points to the feature package that must fix it. Do not quietly shorten a journey or remove an action to obtain green CI.

**How these journeys are used:** They form the *first*, deterministic, real-use baseline at M0, with initial failures recorded against v343. The relevant journeys re-run on every implementation PR and all twenty must pass in a complete M6 candidate. They are not written from the complaints and must not be reduced to individually succeeding widgets. The separate C01–C21 suite targets known defects; stateful exploration continues beyond J01–J20 and C01–C21 so unknown failure classes are actively sought. A normal usage journey may itself discover an unreported failure at any intermediate step.

| Primary milestone dependency | Ordinary journeys requiring that capability | Complementary known-defect checks |
| --- | --- | --- |
| M1 command/input stability | J01, J02, J08, J10, J12, J13, J20 | C01–C04, C11 |
| M2 durability/recovery | J01–J04, J08–J15, J18–J20 | C17–C19 |
| M3 ordinary ink editing/tools | J01–J03, J05, J08–J09, J12–J14, J16–J17, J20 | C02–C09 |
| M4 Structured Figure | J10–J11, J20 | C10–C13, C21 |
| M5 library, page and editor UI | J04–J09, J13–J17, J19–J20 | C14–C16 |
| M6 complete real-world release | **All J01–J20 in uninterrupted end-to-end runs**, plus open-ended newly generated journeys | All C01–C21 as applicable; additional discovered failures |

### Known-issue replay seeds (not an exhaustive acceptance suite)

**C01–C21 below are a deliberately finite set of known-problem replay seeds, not the ordinary day-to-day user journeys J01–J20 just defined, and not a test plan exhaustive enough to certify the app.** Each must be executed externally against the independently installed app through actual user controls, with visible assertions and relaunch when persistence is at issue. Their success is necessary to fix the reported complaints but insufficient for the application's release. Primary qualification requires **all ordinary J01–J20 workflows and additional generated, ongoing, stateful exploration of interactions that nobody enumerated in advance**, under the same black-box acceptance standard (section 0 and Q1). Internal correctness tests may help developers debug failing UI traces, but they do not add user-acceptance evidence or replace any externally observed outcome. Hardware-only sensor behavior requires an actual device/Pencil; simulated finger strokes and internal samples are not proof of that experience. The generator, not this table, defines the broader search surface.

| ID | User story | Required observations and evidence |
| --- | --- | --- |
| C01 | Open note → Text → type multiline Unicode/IME → Done → Pen → draw → undo/redo → relaunch → edit text | Sheet actually closes; text is visible; next actions work without freezing; first-text fonts persist; exactly the entered text reopens and remains editable. Capture sheet, post-Done and reopened page. |
| C02 | Physically tap every tool and favorite in portrait, landscape, narrow window and keyboard-present layouts | Exactly one active drawing tool; screenshot highlight and accessibility agree with the actual effect. Include all three reported displaced highlights, visible eraser glyph/footprint and a proven nonempty selection before switching tools. |
| C03 | **Via actual UI:** turn on Draw with finger → draw beside imported/resized image → tap Lasso in rail → trace a closed multi-point lasso → save/relaunch → repeat | No crash, the correct visible object is selected, the app remains usable, and the selected content reopens. Use actual physical Apple Pencil to qualify angle/estimate-dependent behavior. Source-level angle cases may help developers debug but are not the behavioral pass condition. |
| C04 | Import PNG/JPEG and supported SVG → save clipping → close/reopen → insert → resize → actual lasso → move → undo/redo → reopen/export | App survives; image bytes and transforms persist; old and new positions render correctly; tiny diagonal lasso does not accidentally select a whole image. |
| C05 | Use Stroke/Partial eraser on pressure ink, broad marker and highlight at several zooms/rotations | Visible grazing hits work; interior holes stay empty; pixels outside footprint stay unchanged; cancel/undo restore exact geometry; linked/bookmarked ink and locked layers obey ownership. |
| C06 | Erase → save/relaunch → erase a remaining fragment → undo/export | No resurrection from original samples; fragments remain independent/editable; raw provenance retained; screen/SVG/PDF agree. |
| C07 | Cross the same highlighter several times, including across a Link/Bookmark → pen-up → undo one → recolor → reopen/export | Uniform same-style interior color; live/committed match; distinct styles have stable order; one stroke per undo; compatible old-reader round trip preserves content. |
| C08 | Change tool size/color/opacity → Add to favorites → tap favorite → switch notes → relaunch | Settings are simultaneously visible; preset immediately appears and selects the complete style; saved width is not reset by new defaults. |
| C09 | Insert short/long text → resize wrapping width visually → rotate with keyboard → undo/reopen; follow a link with a finger then draw with Pencil | Intrinsic sizing; reflow without font scaling; no unexplained 300; draft/IME survive; default link navigation does not disable drawing. |
| C10 | New Structured Figure → draw/edit geometry → Done → draw on notebook → reopen figure → relaunch | Fullscreen canvas-only entry; resulting notebook picture and exact source agree; page remains usable; stored badge opens the right object. |
| C11 | Continuous figure editing for 60 seconds → Done once while rendering is pending | The editor remains usable, closes when appropriate, and the displayed figure and exported source match the final visible edit; no duplicate figure, repeated visible save, random dismissal or blocked notebook action. |
| C12 | Two figures → edit each → duplicate → move/resize → undo/redo → reopen; interleave slow/pending rendering and switching notes | Both figures visibly remain independent; undo restores complete pictures/source together; late responses cannot change a figure that the user is no longer editing. |
| C13 | Open Properties/Show TikZ/Copy TikZ → rotate/resize → cold offline startup; terminate WebKit or fail a save → retry | Panels are optional; Copy does not save; local assets load offline; draft survives; explicit retry succeeds; no swipe/timer dismissal or silent save success. |
| C14 | Populate library with long titles, many tags and refreshed thumbnails → open each card menu → search/filter/sort → create note/notebook | No cover overlaps the menu; targets remain hittable; creation contrast is legible; one composable library query; screenshots of all dense/narrow states. |
| C15 | Read without editing → Most recently used; favorite/tag Notebook → own/external/offline/root rename → relaunch | Usage order changes only on accepted use; folder/note metadata persists; IDs do not churn; unknown identity and destination collisions preserve unmatched data; canceling tag assignment writes nothing. |
| C16 | Open Pages/Bookmarks/Layers inspector → insert Before/After/At end → reorder/clear/delete/undo → Share | Context matches target; page labels/position are clear; layer actions fit; existing data survives undo; one usable destination flow. |
| C17 | Externally slow/block a real provider write after edit A → edit B and continue drawing → resume provider → reopen | The app stays responsive, never falsely displays Saved while B is unpersisted, and the reopened notebook visibly contains both A and B without corruption or loss. Real Pencil estimate variations are qualified on device. |
| C18 | Terminate after a visible pending-save/recovery stage but before provider commit → relaunch; repeat with interrupted saving/backgrounding | The app visibly restores all acknowledged edits, presents a correct recovery or retry state, does not claim unsaved work is saved, and never loses a later committed edit to an older completion. |
| C19 | Modify a clean open document externally; then make concurrent dirty changes; close/switch with a pending command | Clean changes become visible; conflicts offer a usable resolution preserving both versions; a delayed action cannot visibly edit the wrong next note; reopening restores the correct view. |
| C20 | Trigger controlled test abort/hang → reopen diagnostics → export packet → symbolicate | Correct incident/build/UUID/load address; meaningful last actions/save stage; exact app frames resolve; normal reports omit document contents; export acknowledgment is truthful. |
| C21 | Open existing scene-v1 figure or original Pencil drawing → convert selection to structured figure → edit → Done → relaunch → Restore drawing → undo/redo; duplicate across notes and open in legacy version | The complete original ink visibly restores, the edited figure stays consistent after reopening, duplicated figures can be edited independently, old-reader round trip does not discard authored source, and retry never visibly creates a second figure. Verify Pencil-specific appearance on physical hardware. |

### Additional mandatory evidence: unseen workflow exploration

In addition to the primary J01–J20 everyday journeys and C01–C21 regression seeds, **every candidate must execute new sequences selected without consulting either list**. This is the work that addresses the sampling/survivorship problem. Build the next action from the actual visible state, not from an internal graph or prewritten script. Keep an on-screen event-flow record and replay seed. Exploration must combine at least the following classes of user actions, using many concrete values and orders:

| Interaction family | Unanticipated sequences the runner must be able to generate | External oracle |
| --- | --- | --- |
| Library ↔ editor ↔ library | Create, open, rename, favorite, tag, sort, trash/restore, switch several notes, reopen in different orders | The selected note and displayed contents correspond to the user action; metadata and visible content survive ordinary navigation and restart. |
| Tools ↔ mixed content | Draw/erase/select/highlight/text/image/figure in varying orders, including switching tools while a selection/sheet is present | Each control remains reachable; visible active tool and actual effect agree; other page objects remain intact. |
| Page/layer ↔ object edits | Duplicate/delete/reorder pages, show/hide/lock layers, add/bookmark pages, then edit objects and undo/redo | Changes affect only the selected visible target; reversibility and content survival are observable. |
| Sheets ↔ cancellation ↔ continued work | Open nested menus/sheets, edit inputs, cancel/confirm, rotate, background, resume, then continue drawing | No silent commit on cancel, spontaneous dismissal, obscured control, loss of input, or blocked next action. |
| Geometry ↔ viewport | Draw multi-point curves; lasso, move, resize, pan, zoom, rotate, erase and inspect across multiple view transforms | The visual object and gesture agree; no crash, hidden-object corruption, or changed unaffected strokes; reopen retains the same geometry. |
| Persistence ↔ lifecycle | Mix edits with rapid save/reopen, repeated note switching, app termination, offline files, and external document changes | The latest acknowledged visible edits remain available; conflicts are surfaced through actual UI; failure never masquerades as saved success. |
| Structured Figure ↔ notebook | Enter/leave figure editing among ink/text/images, reopen, edit, cancel, copy code, duplicate, undo, relaunch | The displayed figure corresponds to accepted edits; code export follows the visible figure; no ghost dialogs or stale results. |
| UI geometry/accessibility | Dense content, small/large windows, portrait/landscape, keyboard shown/hidden, scroll, menus and popovers | Controls remain visible, legible, actionable and consistently located, including during transitions. |

The cases above define **domains and externally checkable properties**, not fixed action scripts. Runs must vary the ordering and length of sequences, automatically discover transitions absent from this table, and preserve any failing new trace. Explicitly include long mixed-operation sessions and the next action after a purportedly successful operation. During release qualification, reviewers examine recordings and screenshots sampled across newly reached states, **not just screenshots from known issues**. No coverage percentage, assertion count, or green scripted replay by itself certifies user experience. GUI event-flow and model-based test generation are established methods: [Memon (2007)][gui-event-flow], [Arlt et al. (2012)][gui-trends] and [empirical comparison (2014)][gui-comparison].

### Visible-state inventory

The **installed-app daily-journey and exploratory session** gallery—not snapshots of individually constructed SwiftUI components—must include library empty/populated/filtered/trash states; notebook/note creation, dirty cancellation and keyboard layout; rail selections/popovers; favorites; text input and reflow; clipping import/selection; page/bookmark/layer management; links; document sharing/conflicts; figure creation/edit/code/error states; save/pending/recovery; and post-relaunch states. **This inventory is a floor, not the generator's allowed state list.** Newly observed states and interactions must be explored too.

Use real mathematical content, long notebook names, several pages/layers, many tags, mixed ink/images/text and more than one structured figure. An empty-note screenshot cannot close a populated-library or object-interaction defect.

### Numerical targets

These are proposed acceptance targets for defined ordinary fixtures, not measurements already achieved by v343:

- No externally observable UI freeze or missed response during ordinary editing/figure sessions; measure the interval from user action to displayed change and to readiness for the next action. OS traces/signposts may locate causes but are not acceptance evidence.
- Text Done produces a visible accepted result and a usable next interaction within one second on healthy local storage. Slow/unavailable external storage must not block the app.
- Figure Done closes within one second after the current render snapshot and local durable commit have completed. While either is pending, the editor remains responsive and reports its actual stage.
- One visibly accepted figure revision per Done: no duplicate object or repeated visible save effect, no further UI disruption from a dismissed editor, and correct visible content after relaunch.
- While slow, repeated and failed writes are imposed externally, the UI stays responsive and the correct visible note survives relaunch. Internal queue bounds remain engineering design requirements, not black-box acceptance tests.

Use synchronization gates for deliberately slow provider/render cases, not timing sleeps that can pass without reaching the intended condition. Include actual hardware Pencil qualification before closing M6; simulator synthesis does not establish hardware hover, estimation or frame behavior.

## 7. Complaint coverage and historical disposition

### Current interaction complaints

| Complaint in the supplied report | Identified cause or bounded evidence | Repair and acceptance |
| --- | --- | --- |
| Eraser icon disappears when selected | Rail has an eraser symbol; eraser hover explicitly hides the indicator; reported rail visibility also requires rendered-state repair | U1/C3; C02/C05 check both rail glyph and footprint |
| Eraser deletes seemingly random strokes | Raw-angle reconstruction differs from live input; invalid samples silently dropped; sample-based cuts and incorrect transformed broadphase | C1–C3; C03/C05/C06 |
| Autosave announces itself | Every save-state transition posts an accessibility announcement; visible label changes repeatedly | U3/N3; quiet reserved-width animation and truthful status |
| Paintbrush icon opens indistinguishable Marker | Misleading glyph/preview/default; underlying fixed-width Marker already exists | U1; C02/C08 |
| Opacity hidden in Advanced | Popover explicitly swaps size/opacity behind Advanced; test encodes that policy | U1; C08 |
| Save pen adds nothing to toolbar | Presets only appear inside palette; commit staged until onDisappear | U1; C08 |
| Highlight overlap darkens | Independent source-over alpha per stroke; self-overlap setting cannot affect other strokes | C4; C07 |
| Highlighter appears to select Lasso | No enum offset found; unsafe update feedback, accepted-state drift and duplicated rail layout are concrete repair boundaries | N1/U1; independent rendered/hit/action C02 oracle |
| Eraser appears to select Image | Image is hardcoded unselected; a guessed index patch would not explain the source | N1/U1; C02 |
| Lasso appears to select Figure | Same split-state/layout boundaries; exact observed pixel displacement not proven from source | N1/U1; C02 |
| Text has unexplained 300 and cannot be sized naturally | Default width 300, placeholder-only number; intrinsic width exists; generic transforms scale rather than reflow | U1; C01/C09 |
| Text Done leaves disabled sheet and freezes app | Source-confirmed Done→representable→command→Observation/save path; #93 confirms that command/save boundary | N1–N3; C01/C17 |
| GitHub failure report is unusable | Formatter omits load addresses and full context despite stored raw report/dSYMs | D1; C20 |
| Card menu misaligned/under cover | Bottom overlay + variable metadata + fixed whole-card aspect + insufficient reserved footer; nil-on-refresh flicker | U2; C14 visual/hit test |
| Search sidebar only focuses field | Explicit focus-only navigation action | U2; one search surface |
| Recent should be sort/filter on one screen | Separate scope and modified-time sort; no genuine usage history | U2; C14/C15 |
| New Tag should exist only while assigning | Global tag-creation row despite existing atomic folder assignment support | U2; C15 |
| New Notebook black on black | Inherited ink foreground/tint on prominent button; reported rendering consistent with missing on-accent token | U2/U3; C14 contrast screenshot |
| Show tab strip is incomprehensible | Technical control label | U3; Show open notes; existing single-note hiding retained |
| Follow links should default on | Coupled to exclusive Navigate tool, with Pen default | U1; C09 independent default-on preference |
| Diagram should be Structured Figure; code optional | Multiple names and implicit capture mode; automatic unclosable code overlay | F3; C10/C13 |
| Figure creation sometimes fails to add/update code | Unbounded native generator lifetime, raw-polyline-only path and missing full commit operation | F1/F2/F3; C10–C13 |
| Stored figures indistinguishable | Original children render as ordinary ink; no persistent object marker | F3; badge and C10/C12 |
| Figure mode alternates between canvas/code/popup; too small; inspector/code forced; closes itself | Two modes behind one toggle, sheet desktop layout, save-on-attempted-dismiss, uncorrelated saves | F1/F3; fullscreen canvas-first C10–C13 |
| Clipped image lasso crashes | #94 resolves empty ink-mesh lasso coverage; image context does not imply decoder fault | C1/C2; actual image-plus-ink C03/C04 |
| Figure saves too aggressively and hangs | Top-level postMessage feedback loop plus synchronous checkpoint/provider paths | F1/N2/N3; C11/C17 |
| Large test suite misses ordinary deadlocks/crashes; too much reinvention | Specific bypassed boundaries and duplicated ownership described in sections 2/3 | Q1 and all package gates; selected mature owners, real visible/durable stories |

The three displaced-highlight observations remain honestly bounded: the exact pixels were reported by the user; the source does not prove an integer-index bug. The plan still names the concrete state/layout corrections and an independent regression that must fail for the observed mismatch. It does not ask an implementer to investigate the toolbar before beginning work.

### Historical visual audit

| Historical category | Current disposition | Work still required |
| --- | --- | --- |
| Roboto fallback under Cupertino SF metrics | Superseded for native iPad: registered Alegreya/Alegreya Sans and named roles already exist | U3 role-relative scaling, UIFontMetrics and readability across real layouts |
| Mixed navy and warm-gray Flutter surfaces | Superseded for native iPad: explicit light theme/style now selected | Complete semantic contrast pairs, especially primary buttons and selected states |
| No cover/page depth or preview | Covers now have spine/preview/shadow; some loading changes already landed | Stable thumbnail replacement and unobscured page margins/rail insets |
| Small arbitrary labels, inconsistent hierarchy | Native type roles exist; fixed layouts and ambiguous wording remain | U3 scalable layouts, labels, keyboard/focus and contrast |
| Three stacked bars, horizontal 18-control pill, one browser tab | Native rail replaces pill; one-note tab hiding already exists | Rail footprint, one rendered layout, useful favorites and clear navigation hierarchy |
| Decorative accent and competing states | Native sidebar/toolbar have selected traits; not the old all-blue Flutter state | Semantic selected/on-accent/disabled tokens and rendered-state verification |
| 900-by-800 creation sheets with duplicate details | Native creation layout is adaptive and dirty-dismiss protected | Natural height, keyboard/narrow layout, remove redundant labels and complete contextual inspector |
| Menu organization and Goodnotes/Noteful comparisons | Page actions are already more consolidated; Pages/overview and duplicate sharing still fragment tasks | U3 contextual inspector/actions and one Share flow, preserving Math Notes' current visual identity |

Do not reuse the attachment's historic contrast ratios as measurements of current native screens. Measure the actual repaired palette and rendered states in the new evidence suite.

### Fixes already in the baseline that must survive

- dffc395: private serial file-presenter queue and excluding the writer's own presenter. This does not make its main-thread caller asynchronous.
- 9fa37b9: background assertion. Extend its lifetime to actual async completion.
- c7516be / ea1476b / 895ade5: portions of library/document reads moved off main. Remaining parsing/rendering/cache/writes still need N3.
- f1abbde: nested asset parent-directory creation and write ordering.
- 2c7f100: figure resource loading through WKURLSchemeHandler rather than the broken file-URL module path.
- 99cd21b: erasing descends Link/Bookmark containers.
- 76a90f9 / 7e30587: marked-text/direction/focus fixes in native text entry.
- Current native single-note strip hiding, creation dirty-discard protection, empty-state create action, conditional conflict entry and delete-page Undo feedback.

These historical changes are inspected context, not new backlog tasks.

## 8. Shipped-binary and CI evidence

### Symbolication method

The v343 release IPA and dSYM both match the UUID in #93/#94. The posted issues omit image load addresses, so slides were recovered from the exact Mach-O symbol tables and ARM64 call sites:

- **#94:** intersect the reported nearest-exported-symbol intervals for all app frames; the unique page-aligned slide is **0x00e1c000**. The runtime app base is **0x100e1c000**. The reported bottom app frame normalizes to main + 0x40, providing an independent cross-check.
- **#93:** enumerate aligned slides within the executable image. Only **0x0468c000** satisfies both independent direct call edges: frame 14 calls handlePageCommand's entry; frame 10 calls scheduleAutosave's entry. Runtime base is **0x10468c000**. DWARF confirms the representable call at InkEditorView.swift line 654, wrapper callback at line 2704, ContentView scheduling at line 2654 and the Observation-generated setter. The optimized handlePageCommand return location has compiler-generated line information.

| Issue/frame | Normalized address | Resolved function |
| --- | --- | --- |
| #93 / 9 | 0x1001da49c | OpenNotebookSession.scheduleAutosave + 0x154 |
| #93 / 10 | 0x100045c20 | ContentView editor-pane onEditCommitted closure + 0x144 |
| #93 / 11 | 0x100103750 | InkEditorView onEditCommitted wrapper + 0xac |
| #93 / 12 | 0x100116b6c | duringUpdateTraced closure + 0x1c |
| #93 / 13 | 0x1000f1c14 | InkEditorViewController.handlePageCommand + 0x1580 |
| #93 / 14 | 0x100100064 | InkEditorHost.updateUIViewController + 0x215c |
| #94 / 6 | 0x10038c2b4 | PartitionedMesh::Data::TotalAbsoluteArea + 0x138 |
| #94 / 7 | 0x10038c314 | PartitionedMesh::CoverageIsGreaterThan + 0x34 |
| #94 / 8 | 0x100359d74 | ink_engine::LassoSelects + 0x960 |
| #94 / 9 | 0x10033b0b8 | Editor::FinishSelect + 0xab0 |
| #94 / 10 | 0x10033a384 | Editor::SelectInput + 0xb44 |
| #94 / 11 | 0x10032183c | Editor::Input + 0xbc |
| #94 / 12 | 0x1002a44a8 | ink_input + 0x14c |
| #94 / 13 | 0x1000e6380 | InkCanvasView.sendPencilTouches + 0x1288 |
| #94 / 14 | 0x1000e6c98 | InkCanvasView.touchesEnded + 0x250 |

These replace the misleading nearest public SkPDF, formatting and exception symbols in the issue summaries. Future reports should record image base/UUID directly so this reconstruction is unnecessary. On macOS, use the matching dSYM with atos, arm64 architecture and the recorded image load address; reject UUID mismatches.

### What the green release actually checked

The native run is **38026399986**, job **114138045367**. It passed 220 Swift tests and 95 core cases. The shared-engine WASM run **38026400286** also passed. The native log records the figure save echo and 62 main-thread-stall log messages, including multi-second reports. Some occur around test setup/coordination; their count is not a measured user-device stall rate. The relevant conclusion is that this signal did not prevent a green result. [Native run][ci] · [Shared engine run][ci-wasm]

The project currently defines MathNotesTests as a unit-test bundle. It has some UIKit/Hammer interactions but no external user-action **exploration** against an independently installed application. `AppTests.xcresult` uploads only on app-test failure, and successful runs lack a comprehensive visual record. Q1 adds a **release-blocking black-box discovery runner** that actively searches for unknown interaction failures and retains the discovered action traces. The existing test counts cannot certify the user experience; Appium uses XCUITest via WebDriverAgent in a separate process. [Project][s-project] · [Workflow][s-workflow] · [Driver][appium-overview]

## 9. Completion and release rules

The remediation is complete only when the **independently installed app successfully executes all twenty ordinary day-to-day user journeys J01–J20 end-to-end, produces the expected observable results for known-defect replays C01–C21, and survives additional newly generated stateful multi-feature sessions** with no unresolved externally observed failure. Passing C01–C21 while everyday sessions still fail is insufficient. The discovery runner continues searching beyond known defects; unexplained crashes, hangs, incorrect visible effects or data loss found by it are release blockers. Hardware Pencil behavior is additionally observed on a physical device. Exact-candidate videos and screenshots, including new exploratory states, are reviewed. Core/format tests may aid debugging but do not discharge the black-box gate.

Each implementing pull request must demonstrate the real user-facing change at the candidate SHA and include the **affected ordinary J01–J20 journeys**, relevant known-defect replays and **unseen exploratory cross-feature traces** generated by the same black-box runner. A newly discovered failure is a defect to fix, not a test-coverage statistic or a reason to narrow the explorer. Do not close a task because a callback fired, an ABI returned OK, a unit suite was green or a scripted case passed while other externally explored workflows failed.

Migration gates are mandatory for existing SVG/InkML pages, scene-v1 figures, clipping assets, fonts, unknown/raw-error pages, recovery records, links/bookmarks, tags/favorites, external file changes and shared native/web format round trips. Preserve source and asset identity before cleanup. Any new format marker must have a demonstrated legacy-reader behavior; a version bump is ineffective against v343's reader, which ignores it.

Stop adding unrelated feature work until the stability packages **and broad independent exploration** pass. Keep the current platform minimum and established mathematical-data boundaries. The repair does not require OCR, full TeX compilation, a new drawing engine, a new native framework, a new cloud database or a replacement visual brand.

Use the CI system for the repository's supported native build workflow. Qualify actual Pencil hardware before the final release. Preserve IPA/version/tag/SHA/dSYM identity checks and shared-core build gates. Do not reduce test fidelity, suppress real failures or lengthen timeouts merely to restore a green badge.

## 10. Source map for implementers

All Math Notes file references below use the audited full commit. The work packages define the changes; these pointers locate the exact existing owners.

| Package | Primary implementation evidence |
| --- | --- |
| N1 | [applyHostState / handlePageCommand / updateUIViewController and callbacks][s-command]; [TextEditorSheet Done][s-text-sheet]; [observed autosave][s-autosave] |
| C1/C2/C3 | [live conversion, NearInk, erasure, estimates][s-editor]; [persisted conversion/sample cutting][s-erase]; [lasso meshes/coverage][s-selection]; [current lasso closure][s-hit-shapes]; [affine inversion][s-affine] |
| F1/F3 | [WKWebView host, requestSave and accept][s-figure-host]; [actual pinned bridge][embed-source]; [capture and automatic code overlay][s-command]; [native presentation/persistence callbacks][s-content] |
| N2/N3/N4 | [dirty extraction/MarkSaved][s-dirty]; [DocumentHistory][s-history]; [EngineDocument buffers][s-engine-document]; [recovery/provider implementation][s-storage]; [estimated-property callback][s-canvas] |
| C4 | [live/committed paint order][s-renderer]; [SVG writer/reader][s-svg]; [version-insensitive notebook reader][s-notebook-json]; [PDF renderer][s-pdf] |
| U1 | [rail, icons and accepted selection][s-tools]; [pen settings/preset staging][s-pen]; [saved palette][s-palette]; [text sheet][s-text-sheet]; [existing text-width operation][s-select-editor] |
| F2 | [current source-only draft mutation][s-figures]; [Figure model][s-model]; [core figure ABI][s-dirty]; [prior bounded SVG view][prior-figure-view]; [selected editor host][vte-host] |
| U2/U3 | [library cards/sidebar/creation][s-library]; [metadata, moves and presenter][s-storage]; [editor menus/status][s-content]; [theme][s-theme]; [layers][s-layers]; [creation layout][s-creation]; [editor settings][s-settings] |
| Q1/D1 | [Appium black-box driver][appium-overview]; [W3C gestures][appium-gestures]; [recording][appium-record]; [event-flow GUI testing][gui-event-flow]; [GUI exploratory test-generation study][gui-comparison]; [project targets][s-project]; [release workflow][s-workflow]; [crash reporting][s-crash] |

The most consequential history is the [partial angle-normalization fix][angle-fix], [removed source/view commit capability][figure-deletion], the native storage/presentation changes enumerated in section 7, and [the exact release CI result][ci].

### Primary platform and dependency references

- Apple [UIDocument][apple-document], [save queue semantics][apple-save], [incremental writing][apple-write], [file bookmarks][apple-bookmark], [UI automation][apple-ui-tests], [touch controls][apple-controls] and [contrast guidance][apple-contrast]. **For primary acceptance use [Appium XCUITest][appium-overview] to replay actual J01–J20 user journeys and to explore the independently launched app, [W3C gestures][appium-gestures], [screen recording][appium-record] and [event-flow-based test generation][gui-event-flow].** Scripts mirroring current bugs are only fixed regression seeds; in-process Hammer tests cannot substitute for user-observed outcomes.
- Google Ink at the actual pinned commit: [sample validation][g-input], [coverage checks][g-coverage], [boundary processing][g-outlines], [hole-dropping public subtraction path][g-subtraction], [multi-contour tessellator][g-tessellation], [mesh outline remapping][g-mesh] and [spatial segmentation][g-segmentation].
- Maintained Visual TikZ Editor at the inspected commit: [host contract][vte-host], [canvas provider][vte-provider], [owned upstream patch][vte-patch] and [asset provenance][vte-provenance]. These are the implementation owners; their required extensions are specified in F1/F2.

[baseline]: https://github.com/dzackgarza/math-notes-app/tree/2da1707e1d4f28a609550268ef30459731985aaf
[issue93]: https://github.com/dzackgarza/math-notes-app/issues/93
[issue94]: https://github.com/dzackgarza/math-notes-app/issues/94
[release]: https://github.com/dzackgarza/math-notes-app/releases/tag/v343
[ci]: https://github.com/dzackgarza/math-notes-app/actions/runs/38026399986/job/114138045367
[ci-wasm]: https://github.com/dzackgarza/math-notes-app/actions/runs/38026400286
[angle-fix]: https://github.com/dzackgarza/math-notes-app/commit/d1a0c7fb740f4946101c538d8f2f8d920f196266
[figure-deletion]: https://github.com/dzackgarza/math-notes-app/commit/5398b681d653fe25cf251cf4ff94600ebb3e3f22
[prior-figure-view]: https://github.com/dzackgarza/math-notes-app/blob/827fdf3e839ee722c621d25367252637b6091c31/core/src/render/figure_view.cpp
[embed-source]: https://github.com/TeXlyre/tikz-editor-embed-mirror/blob/b98714d3584ee849178f19cf44c7768ff9063f6e/embed/src/main.tsx
[gui-event-flow]: https://doi.org/10.1002/STVR.364
[gui-trends]: https://www.sciencedirect.com/science/article/pii/B9780123965356000065
[gui-comparison]: https://www.sciencedirect.com/science/article/pii/S0164121214001472
[appium-overview]: https://appium.github.io/appium-xcuitest-driver/latest/overview/
[appium-gestures]: https://appium.github.io/appium-xcuitest-driver/latest/guides/gestures/
[appium-record]: https://appium.github.io/appium-xcuitest-driver/12.16/reference/commands/#startrecordingscreen
[apple-document]: https://developer.apple.com/documentation/uikit/uidocument
[apple-save]: https://developer.apple.com/documentation/uikit/uidocument/save(to:for:completionhandler:)
[apple-write]: https://developer.apple.com/documentation/uikit/uidocument/writecontents(_:to:for:originalcontentsurl:)
[apple-ui-tests]: https://developer.apple.com/videos/play/wwdc2025/344/
[apple-controls]: https://developer.apple.com/design/tips/
[apple-contrast]: https://developer.apple.com/help/app-store-connect/manage-app-accessibility/sufficient-contrast-evaluation-criteria/
[apple-bookmark]: https://developer.apple.com/documentation/foundation/url/bookmarkdata(options:includingresourcevaluesforkeys:relativeto:)
[s-command]: https://github.com/dzackgarza/math-notes-app/blob/2da1707e1d4f28a609550268ef30459731985aaf/Sources/InkEditorView.swift
[s-callbacks]: https://github.com/dzackgarza/math-notes-app/blob/2da1707e1d4f28a609550268ef30459731985aaf/Sources/InkEditorView.swift#L2554-L2744
[s-autosave]: https://github.com/dzackgarza/math-notes-app/blob/2da1707e1d4f28a609550268ef30459731985aaf/Sources/OpenNotesState.swift#L99-L145
[s-editor]: https://github.com/dzackgarza/math-notes-app/blob/2da1707e1d4f28a609550268ef30459731985aaf/core/src/editor/editor.cpp
[s-erase]: https://github.com/dzackgarza/math-notes-app/blob/2da1707e1d4f28a609550268ef30459731985aaf/core/src/editor/erase.cpp
[s-selection]: https://github.com/dzackgarza/math-notes-app/blob/2da1707e1d4f28a609550268ef30459731985aaf/core/src/selection/selection.cpp
[s-hit-shapes]: https://github.com/dzackgarza/math-notes-app/blob/2da1707e1d4f28a609550268ef30459731985aaf/core/src/geometry/hit_shapes.cpp
[s-affine]: https://github.com/dzackgarza/math-notes-app/blob/2da1707e1d4f28a609550268ef30459731985aaf/core/src/geometry/affine.h
[s-figure-host]: https://github.com/dzackgarza/math-notes-app/blob/2da1707e1d4f28a609550268ef30459731985aaf/Sources/FigureEditorSheet.swift
[s-recovery]: https://github.com/dzackgarza/math-notes-app/blob/2da1707e1d4f28a609550268ef30459731985aaf/Sources/NotebookStorage.swift#L2300-L2344
[s-save]: https://github.com/dzackgarza/math-notes-app/blob/2da1707e1d4f28a609550268ef30459731985aaf/Sources/NotebookStorage.swift#L2815-L2903
[s-storage]: https://github.com/dzackgarza/math-notes-app/blob/2da1707e1d4f28a609550268ef30459731985aaf/Sources/NotebookStorage.swift
[s-dirty]: https://github.com/dzackgarza/math-notes-app/blob/2da1707e1d4f28a609550268ef30459731985aaf/core/src/ink.cpp
[s-history]: https://github.com/dzackgarza/math-notes-app/blob/2da1707e1d4f28a609550268ef30459731985aaf/core/src/editor/history.h
[s-renderer]: https://github.com/dzackgarza/math-notes-app/blob/2da1707e1d4f28a609550268ef30459731985aaf/core/src/render/renderer.cpp
[s-svg]: https://github.com/dzackgarza/math-notes-app/blob/2da1707e1d4f28a609550268ef30459731985aaf/core/src/format/page_svg.cpp
[s-figures]: https://github.com/dzackgarza/math-notes-app/blob/2da1707e1d4f28a609550268ef30459731985aaf/core/src/document/figures.cpp
[s-model]: https://github.com/dzackgarza/math-notes-app/blob/2da1707e1d4f28a609550268ef30459731985aaf/core/src/document/document.h
[s-project]: https://github.com/dzackgarza/math-notes-app/blob/2da1707e1d4f28a609550268ef30459731985aaf/project.yml
[s-cmake]: https://github.com/dzackgarza/math-notes-app/blob/2da1707e1d4f28a609550268ef30459731985aaf/core/CMakeLists.txt
[s-workflow]: https://github.com/dzackgarza/math-notes-app/blob/2da1707e1d4f28a609550268ef30459731985aaf/.github/workflows/ios.yml
[s-skia]: https://github.com/dzackgarza/math-notes-app/blob/2da1707e1d4f28a609550268ef30459731985aaf/core/scripts/build-skia-ios.sh#L8-L10
[skia-fill]: https://github.com/JetBrains/skia/blob/ab5932137bb327b627b44f15fbe34ba59d775d0e/include/core/SkPathUtils.h
[s-text-sheet]: https://github.com/dzackgarza/math-notes-app/blob/2da1707e1d4f28a609550268ef30459731985aaf/Sources/TextEditorSheet.swift
[s-content]: https://github.com/dzackgarza/math-notes-app/blob/2da1707e1d4f28a609550268ef30459731985aaf/Sources/ContentView.swift
[s-engine-document]: https://github.com/dzackgarza/math-notes-app/blob/2da1707e1d4f28a609550268ef30459731985aaf/Sources/EngineDocument.swift
[s-canvas]: https://github.com/dzackgarza/math-notes-app/blob/2da1707e1d4f28a609550268ef30459731985aaf/Sources/InkCanvasView.swift
[s-notebook-json]: https://github.com/dzackgarza/math-notes-app/blob/2da1707e1d4f28a609550268ef30459731985aaf/core/src/format/notebook.cpp
[s-pdf]: https://github.com/dzackgarza/math-notes-app/blob/2da1707e1d4f28a609550268ef30459731985aaf/core/src/export/pdf.cpp
[s-tools]: https://github.com/dzackgarza/math-notes-app/blob/2da1707e1d4f28a609550268ef30459731985aaf/Sources/EditorTools.swift
[s-pen]: https://github.com/dzackgarza/math-notes-app/blob/2da1707e1d4f28a609550268ef30459731985aaf/Sources/PenEditorPopover.swift
[s-palette]: https://github.com/dzackgarza/math-notes-app/blob/2da1707e1d4f28a609550268ef30459731985aaf/Sources/ColorPalettePopover.swift
[s-select-editor]: https://github.com/dzackgarza/math-notes-app/blob/2da1707e1d4f28a609550268ef30459731985aaf/core/src/editor/select.cpp#L819-L834
[s-library]: https://github.com/dzackgarza/math-notes-app/blob/2da1707e1d4f28a609550268ef30459731985aaf/Sources/NativeLibraryView.swift
[s-theme]: https://github.com/dzackgarza/math-notes-app/blob/2da1707e1d4f28a609550268ef30459731985aaf/Sources/NativeTheme.swift
[s-layers]: https://github.com/dzackgarza/math-notes-app/blob/2da1707e1d4f28a609550268ef30459731985aaf/Sources/LayersSheet.swift
[s-creation]: https://github.com/dzackgarza/math-notes-app/blob/2da1707e1d4f28a609550268ef30459731985aaf/Sources/CreationSheetLayout.swift
[s-settings]: https://github.com/dzackgarza/math-notes-app/blob/2da1707e1d4f28a609550268ef30459731985aaf/Sources/EditorSettingsSheet.swift
[s-crash]: https://github.com/dzackgarza/math-notes-app/blob/2da1707e1d4f28a609550268ef30459731985aaf/Sources/CrashReporting.swift
[s-failure]: https://github.com/dzackgarza/math-notes-app/blob/2da1707e1d4f28a609550268ef30459731985aaf/Sources/PreviousFailureSheet.swift
[s-trace]: https://github.com/dzackgarza/math-notes-app/blob/2da1707e1d4f28a609550268ef30459731985aaf/Sources/InputTrace.swift
[t-text]: https://github.com/dzackgarza/math-notes-app/blob/2da1707e1d4f28a609550268ef30459731985aaf/AppTests/TextPersistenceTests.swift
[t-clipping]: https://github.com/dzackgarza/math-notes-app/blob/2da1707e1d4f28a609550268ef30459731985aaf/AppTests/ClippingPersistenceTests.swift
[t-selection]: https://github.com/dzackgarza/math-notes-app/blob/2da1707e1d4f28a609550268ef30459731985aaf/core/tests/test_selection.cpp#L476-L542
[t-figure]: https://github.com/dzackgarza/math-notes-app/blob/2da1707e1d4f28a609550268ef30459731985aaf/AppTests/FigureEditorSheetWorkflowTests.swift
[t-pencil]: https://github.com/dzackgarza/math-notes-app/blob/2da1707e1d4f28a609550268ef30459731985aaf/AppTests/PencilStrokeWorkflowTests.swift
[t-library]: https://github.com/dzackgarza/math-notes-app/blob/2da1707e1d4f28a609550268ef30459731985aaf/AppTests/LibraryWorkflowTests.swift
[t-tools]: https://github.com/dzackgarza/math-notes-app/blob/2da1707e1d4f28a609550268ef30459731985aaf/AppTests/EditorToolsTests.swift
[g-coverage]: https://github.com/google/ink/blob/1b220eee5a05e9b67be9f20f49ae2d574c8667a7/ink/geometry/partitioned_mesh.cc#L557-L624
[g-input]: https://github.com/google/ink/blob/1b220eee5a05e9b67be9f20f49ae2d574c8667a7/ink/strokes/input/stroke_input_batch.cc#L159-L174
[g-outlines]: https://github.com/google/ink/blob/1b220eee5a05e9b67be9f20f49ae2d574c8667a7/ink/geometry/internal/outline_processing.cc
[g-subtraction]: https://github.com/google/ink/blob/1b220eee5a05e9b67be9f20f49ae2d574c8667a7/ink/strokes/internal/stroke_subtraction.cc
[g-tessellation]: https://github.com/google/ink/blob/1b220eee5a05e9b67be9f20f49ae2d574c8667a7/ink/geometry/internal/generic_tessellator.h
[g-mesh]: https://github.com/google/ink/blob/1b220eee5a05e9b67be9f20f49ae2d574c8667a7/ink/geometry/partitioned_mesh.cc#L63-L181
[g-segmentation]: https://github.com/google/ink/blob/1b220eee5a05e9b67be9f20f49ae2d574c8667a7/ink/strokes/internal/stroke_segmentation.h#L24-L37
[g-segmentation-impl]: https://github.com/google/ink/blob/1b220eee5a05e9b67be9f20f49ae2d574c8667a7/ink/strokes/internal/stroke_segmentation.cc
[vte-host]: https://github.com/dzackgarza/visual-tikz-editor/blob/60d007f0520777c4195079507d296bb79e086cd7/src/host.ts
[vte-provider]: https://github.com/dzackgarza/visual-tikz-editor/blob/60d007f0520777c4195079507d296bb79e086cd7/src/ui/TikzEditorPreview.vue
[vte-patch]: https://github.com/dzackgarza/visual-tikz-editor/blob/60d007f0520777c4195079507d296bb79e086cd7/vendor/tikz-editor/ZETTLR.patch
[vte-provenance]: https://github.com/dzackgarza/visual-tikz-editor/blob/60d007f0520777c4195079507d296bb79e086cd7/vendor/tikz-editor/PROVENANCE.toml
