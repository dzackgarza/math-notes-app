**The archaeology is complete, and the implementation handoff is ready:** ipad-remediation-plan.md[ipad-remediation-plan.md](sandbox:/workspace/scratch/1837c3ca2329/ipad-remediation-plan.md).

The report contains **16 implementation packages, seven milestones, four agent lanes, 21 acceptance stories, and 77 source references**. Each package specifies the existing owners, concrete changes, dependencies, compatibility requirements, and completion evidence.

The audit is pinned to **v343 / 0.1.343 (343), commit `2da1707e1d4f28a609550268ef30459731985aaf`**. I inspected the native application, shared engine, relevant history, actual dependency pins, release CI, and shipped IPA/dSYM. I resolved both reported device stacks against that binary and reproduced the figure message loop using the pinned JavaScript. The repository remains unchanged. This was source and binary analysis; I did not run a new live iPad session. [Audited release](https://github.com/dzackgarza/math-notes-app/releases/tag/v343) · [Pinned source](https://github.com/dzackgarza/math-notes-app/tree/2da1707e1d4f28a609550268ef30459731985aaf)

## What is actually causing the failures

### 1. The native command boundary creates the reported hang

The resolved application frames in [issue #93](https://github.com/dzackgarza/math-notes-app/issues/93) show `updateUIViewController` executing `handlePageCommand`, which invokes `onEditCommitted` and then `scheduleAutosave`, followed by Observation mutation and SwiftUI transaction flushing.

The source explains the cycle. A representable update applies an editing command; that command changes observed document and save state before the update returns. The existing `duringUpdateTraced` helper detects and logs this boundary violation, then still performs the mutation. Text **Done** follows this path, including synchronous recovery work. [Command handling and callbacks](https://github.com/dzackgarza/math-notes-app/blob/2da1707e1d4f28a609550268ef30459731985aaf/Sources/InkEditorView.swift) · [Autosave scheduling](https://github.com/dzackgarza/math-notes-app/blob/2da1707e1d4f28a609550268ef30459731985aaf/Sources/OpenNotesState.swift#L99-L145)

**The prescribed repair is a command-boundary change.** A stable Coordinator/controller adapter must execute typed user commands outside representable updates. Representable updates become idempotent projections of accepted state. Commands carry session, document, page, element, and request identity so a delayed callback cannot edit a successor note or another pane.

Text Done closes when the model accepts the command. A rejected command retains the sheet and draft. A later persistence failure leaves accepted text dirty and retryable; it must not submit the text again.

The stack establishes the faulty command/save boundary in the device hang. Its optimized command frame does not identify the exact switch case, so the report does not pretend that #93 alone proves the user tapped Text Done. Text Done’s exposure is independently established by the source.

### 2. The image-adjacent lasso crash is an empty ink mesh reaching an abort

The resolved path in [issue #94](https://github.com/dzackgarza/math-notes-app/issues/94) is:

`PartitionedMesh::TotalAbsoluteArea` → coverage calculation → `LassoSelects` → selection completion → native Pencil `touchesEnded`.

Lasso accepts a non-null mesh object whose mesh list is empty. Google Ink then asserts that the list is nonempty and aborts. The C++ exception wrapper cannot catch that assertion. Whole-stroke erasing handles the same empty geometry as a miss, explaining why related defects can appear as inconsistent erasure instead of a crash. [Lasso implementation](https://github.com/dzackgarza/math-notes-app/blob/2da1707e1d4f28a609550268ef30459731985aaf/core/src/selection/selection.cpp) · [Pinned upstream assertion](https://github.com/google/ink/blob/1b220eee5a05e9b67be9f20f49ae2d574c8667a7/ink/geometry/partitioned_mesh.cc#L557-L624)

There is a concrete route to that state. Live Pencil input normalizes azimuth and roll; persisted-stroke reconstruction passes raw angles and ignores rejected sample statuses. Raw roll `−0.5`, with its capability present, can therefore draw through the live path and fail reconstruction. All rejected samples yield empty geometry; a valid prefix followed by rejected samples yields incomplete hit geometry. An earlier normalization change repaired only the live adapter. [Live conversion](https://github.com/dzackgarza/math-notes-app/blob/2da1707e1d4f28a609550268ef30459731985aaf/core/src/editor/editor.cpp) · [Persisted reconstruction](https://github.com/dzackgarza/math-notes-app/blob/2da1707e1d4f28a609550268ef30459731985aaf/core/src/editor/erase.cpp)

The initial repair therefore includes:

- One checked sample conversion path.
- Explicit rejection of invalid and empty geometry before coverage calls.
- A minimum adapter from persisted visible outlines to hit geometry, so guarding the crash does not make existing ink unselectable.
- Regression fixtures containing angle-bearing ink beside an actual resized image.

The exact negative-roll value is a proven route from the source, not an assertion about the contents of the user’s unexported page. The symbolicated failure does not implicate bitmap decoding.

### 3. Autosave still performs expensive work synchronously—and cannot safely be moved as-is

The one-second autosave delay occurs **after** recovery checkpointing. Before reaching that delay, the app serializes changed pages and assets, merges recovery state, encodes changed and base files into JSON, rewrites the recovery record, and marks the engine saved. Provider coordination and writes also remain on `MainActor`. Adding the first text can bring bundled font assets into this work. [Recovery checkpoint](https://github.com/dzackgarza/math-notes-app/blob/2da1707e1d4f28a609550268ef30459731985aaf/Sources/NotebookStorage.swift#L2300-L2344) · [Provider save](https://github.com/dzackgarza/math-notes-app/blob/2da1707e1d4f28a609550268ef30459731985aaf/Sources/NotebookStorage.swift#L2815-L2903)

A detached task around the existing functions would introduce a data-loss race. Dirty-file extraction mutates backing assets and exposes temporary buffers. `MarkSaved` acknowledges the current live state and clears new assets, rather than acknowledging precisely the revision written. A slow write of revision A could mark newer revision B as saved. [Current extraction and acknowledgment](https://github.com/dzackgarza/math-notes-app/blob/2da1707e1d4f28a609550268ef30459731985aaf/core/src/ink.cpp)

The plan defines the replacement contract:

- Capture an immutable document-and-assets snapshot with bounded work on main.
- Serialize and perform coordinated I/O through worker-owned state.
- Track **current**, **locally durable**, and **provider-persisted** generations separately.
- Permit one provider write in flight per document, with bounded pending work.
- Acknowledge only the generation actually completed.
- Store recovery generations using immutable payloads instead of rewriting the accumulated recovery JSON after every stroke.
- Preserve failed work for retry, including across backgrounding and relaunch.

`UIDocument` becomes the native lifecycle owner, with the existing notebook format adapter retained. Its adoption must respect the calling-queue behavior of `contents(forType:)`; putting full serialization there would preserve the problem. Apple’s document lifecycle and incremental-writing hooks support the selected design. [Apple Developer Documentation](https://developer.apple.com/documentation/uikit/uidocument?utm_source=chatgpt.com)

Late Pencil estimates join this same revision contract. They must use stable object identity, retain style and transforms, merge into the originating undo transaction, and become durable. Structural edits such as erasing must invalidate stale estimate records.

### 4. Figure saving has its own independent feedback loop

The pinned figure editor is loaded at the top level of `WKWebView`. It sends replies with `window.parent.postMessage`; at the top level, `parent` is the same window. Its receiver interprets either `message.action` or `message.event` as a command. A save reply consequently becomes another save command.

The source-extracted reproduction produced **25 save events from one request, with another event still queued at the diagnostic cap**. Giving the editor a distinct iframe parent produced one reply and an empty queue. The passing release CI independently contains **16 identical save notifications in about nine milliseconds**. [Native figure host](https://github.com/dzackgarza/math-notes-app/blob/2da1707e1d4f28a609550268ef30459731985aaf/Sources/FigureEditorSheet.swift) · [Pinned bridge](https://github.com/TeXlyre/tikz-editor-embed-mirror/blob/b98714d3584ee849178f19cf44c7768ff9063f6e/embed/src/main.tsx) · [Release CI](https://github.com/dzackgarza/math-notes-app/actions/runs/38026399986/job/114138045367)

The transport repair is explicit: distinct command/reply types, iframe isolation, correlated request and revision IDs, bounded requests, typed failures, and queue-drain assertions. A dismissed editor must leave no continuing message traffic.

The broader figure workflow uses the inspected, maintained **`dzackgarza/visual-tikz-editor`** owner. It already supplies relevant host, iframe, canvas-only, touch, and local-asset capabilities. The plan specifies the extensions it still needs; it does not treat the current package as a drop-in solution. [Selected host contract](https://github.com/dzackgarza/visual-tikz-editor/blob/60d007f0520777c4195079507d296bb79e086cd7/src/host.ts) · [Editor provider](https://github.com/dzackgarza/visual-tikz-editor/blob/60d007f0520777c4195079507d296bb79e086cd7/src/ui/TikzEditorPreview.vue)

### 5. Figure source, visible output, and persistence are disconnected

The native path currently saves a source draft while the notebook continues drawing the Figure’s original children. A historical removal deleted the complete source/view acceptance path along with the TeX compiler. Merely accepting the bridge’s SVG field would still be incorrect: that field can contain `lastKnownSvg` from an older source revision, and later rendering completion does not necessarily generate another source event. [Current figure mutation](https://github.com/dzackgarza/math-notes-app/blob/2da1707e1d4f28a609550268ef30459731985aaf/core/src/document/figures.cpp) · [Removal commit](https://github.com/dzackgarza/math-notes-app/commit/5398b681d653fe25cf251cf4ff94600ebb3e3f22) · [Provider behavior](https://github.com/dzackgarza/visual-tikz-editor/blob/60d007f0520777c4195079507d296bb79e086cd7/src/ui/TikzEditorPreview.vue)

The prescribed replacement is one **revision-matched snapshot** containing exact source, rendered SVG, bounds, and associated scene/original-ink information. One shared-core transaction accepts that complete revision, and undo restores all of it together.

The report resolves the storage and compatibility design as well:

- Use immutable revisions within the existing scene/TikZ asset references.
- Put the complete committed source/view pair and preserved original data in a self-contained scene envelope.
- Keep original Figure children available to old readers.
- Treat the page’s new SVG presentation as regenerable from the envelope.
- Resolve figure records after assets load, before establishing the saved baseline.
- Preserve preexisting pending source separately from the last complete committed picture.
- Remap live identity safely during duplication while preserving original ink provenance.

This matters because **v343 ignores format-version markers**. A version bump alone cannot protect new data from an old reader/writer. The handoff specifies what v343 displays and preserves, and how the updated reader restores the current figure view after an old-reader rewrite. [Page reader/writer](https://github.com/dzackgarza/math-notes-app/blob/2da1707e1d4f28a609550268ef30459731985aaf/core/src/format/page_svg.cpp) · [Notebook format and asset handling](https://github.com/dzackgarza/math-notes-app/blob/2da1707e1d4f28a609550268ef30459731985aaf/core/src/format/notebook.cpp)

Figure Done waits for the accepted revision’s **local durable acknowledgment**, not a remote provider write. Persistence Retry cannot create another model transaction.

### 6. Erasure, selection, and highlighting disagree with what is displayed

Several distinct geometry defects contribute to the apparently random behavior:

- Rendering uses persisted outlines, while hit testing reconstructs raw samples.
- Partial erasing cuts sample paths and remodels fragments, changing untouched caps and smoothing.
- Reconstructing a previously cut stroke from its original samples can resurrect erased ink.
- Rotated broadphase bounds use two opposite corners instead of all four.
- Image/text/figure coverage approximations can count both triangles of an object as covered when a small lasso crosses their diagonal. [Editing and bounds](https://github.com/dzackgarza/math-notes-app/blob/2da1707e1d4f28a609550268ef30459731985aaf/core/src/editor/editor.cpp) · [Erasure](https://github.com/dzackgarza/math-notes-app/blob/2da1707e1d4f28a609550268ef30459731985aaf/core/src/editor/erase.cpp) · [Selection](https://github.com/dzackgarza/math-notes-app/blob/2da1707e1d4f28a609550268ef30459731985aaf/core/src/selection/selection.cpp)

The plan makes **persisted visible geometry authoritative** for selection and erasing. Raw samples remain provenance. Partial erase subtracts the actual eraser footprint from filled geometry and persists the resulting contours.

I also checked the selected dependency APIs rather than leaving that choice to implementers. At the actual Google Ink pin, the public subtraction path drops holes during triangulation, and spatial segmentation can discard outline metadata. The report therefore specifies the multi-contour tessellation, boundary reconstruction, and persistence adapter required to preserve interior erasures and separated fragments. Native shape strokes use Skia’s own stroke expansion so their butt caps and miter joins agree with rendering. [Pinned subtraction implementation](https://github.com/google/ink/blob/1b220eee5a05e9b67be9f20f49ae2d574c8667a7/ink/strokes/internal/stroke_subtraction.cc) · [Boundary processing](https://github.com/google/ink/blob/1b220eee5a05e9b67be9f20f49ae2d574c8667a7/ink/geometry/internal/outline_processing.cc) · [Segmentation](https://github.com/google/ink/blob/1b220eee5a05e9b67be9f20f49ae2d574c8667a7/ink/strokes/internal/stroke_segmentation.cc)

Highlighter darkening is separate. Applying opacity `0.35` to each stroke produces combined opacity `0.5775` where two strokes overlap. The existing self-overlap setting operates within one stroke. Live and committed highlighter also use different paint ordering. [Renderer](https://github.com/dzackgarza/math-notes-app/blob/2da1707e1d4f28a609550268ef30459731985aaf/core/src/render/renderer.cpp)

The repair groups same-style coverage within each layer and applies authored opacity once, while retaining individual stroke identity and undo. The report specifies matching screen/SVG/PDF behavior and an old-reader-compatible SVG representation.

## Roadmap and agent ownership

The milestones are ordered by dependencies and completion evidence. Layout work can proceed in parallel, but storage, figure, and geometry work must consume the shared contracts.

| Milestone | Work | Exit condition |
|---|---|---|
| **M0 — Real acceptance and diagnostics** | Q1, D1; starts alongside M1 | Real application scenarios run; successful and failed runs retain evidence; incident packets can be symbolicated directly. |
| **M1 — Stop confirmed failures** | N1, C1, F1 transport containment | Commands do not mutate during representable updates; empty geometry cannot abort lasso; existing ink remains hittable; one figure request produces one reply. |
| **M2 — Correct persistence and input revisions** | N2 → N3, coordinated N4 | Slow storage cannot block input; revision A cannot acknowledge B; recovery, estimates, backgrounding, and external changes preserve the correct data. |
| **M3 — Correct ordinary editing** | C2 → C3/C4, U1 | Erasing follows visible geometry; lasso obeys the coverage rule; highlighting is uniform; tools, presets, and text resizing behave correctly. |
| **M4 — Complete Structured Figure** | F2 → F3, consuming F1, N2/N3, and C2 | One fullscreen visual editor; optional code; source and picture commit together; retry, reopen, undo, and existing figures work. |
| **M5 — Finish library and editor interaction** | U2, U3 | One composable library surface, usable cards, readable creation controls, contextual navigation, scalable layouts, and quiet save status. |
| **M6 — Qualify the complete release** | All packages and acceptance stories | Every complaint has behavioral, visual, and persistence evidence at the exact candidate SHA, including hardware Pencil qualification. |

An M1 build can be a limited stability repair. It cannot claim complete remediation while asynchronous persistence and figure transactions remain unfinished.

### Four implementation lanes

| Lane | Packages and responsibilities | Integration boundary |
|---|---|---|
| **A — Native state and storage** | N1–N4: commands, snapshots, lifecycle, recovery, estimates | Own native command/document APIs. Other lanes consume the same saver and accepted-state model. |
| **B — Core geometry and rendering** | C1–C4, shared-core portions of snapshots, estimates, and figures | Own document model, geometry, serialization, history, and ABI integration. |
| **C — Structured Figure** | F1–F3: maintained editor changes, transport, complete revisions, native presentation | Land dependency changes in the maintained editor, consume an immutable pin, and use A/B’s contracts. |
| **D — Interface and qualification** | Q1, D1, U1–U3, release evidence | Own native test target, visual layouts, interaction stories, and evidence review. |

**The immediate parallel queue is N1, C1, F1 containment, Q1, and D1.** N3 cannot begin background serialization against the current unsafe ABI. F2/F3 cannot introduce a separate persistence path.

## Product changes explicitly included

The report maps every current complaint to a work package. The interface changes are concrete:

- **Tool rail:** Use one adaptive layout and accepted tool state. A physical tap, rendered highlight, accessibility selection, and actual drawing effect must agree. Preserve a visible eraser glyph and footprint. The source does not establish a simple enum-offset explanation for the three displaced highlights, so the plan avoids a guessed index patch and repairs the state/layout boundaries with an independent regression. [Tool definitions](https://github.com/dzackgarza/math-notes-app/blob/2da1707e1d4f28a609550268ef30459731985aaf/Sources/EditorTools.swift)

- **Pens and presets:** Give Marker a recognizable nib and useful preview; show size, color, and opacity together; make **Add to favorites** immediately add a complete selectable preset to the rail. Existing customized widths must survive new defaults. The current implementation hides opacity behind Advanced and stages preset changes until dismissal. [Pen editor](https://github.com/dzackgarza/math-notes-app/blob/2da1707e1d4f28a609550268ef30459731985aaf/Sources/PenEditorPopover.swift)

- **Text and links:** Replace the unexplained width `300` with intrinsic sizing and visual wrapping-width controls. Resize text by reflowing it, preserving font size and IME state. Make **Follow links** an independent preference, on by default, with finger taps following links while Pencil remains usable for drawing. [Text sheet](https://github.com/dzackgarza/math-notes-app/blob/2da1707e1d4f28a609550268ef30459731985aaf/Sources/TextEditorSheet.swift) · [Existing width operation](https://github.com/dzackgarza/math-notes-app/blob/2da1707e1d4f28a609550268ef30459731985aaf/core/src/editor/select.cpp#L819-L834)

- **Structured Figure:** One fullscreen canvas-first editor, with optional **Properties** and independently closable **Show TikZ** panels. Copy TikZ does not save. New figures open a blank visual canvas; converting selected ink is a separately named operation. Stored figures receive an on-page badge and explicit Edit action. Done and Cancel have defined transaction semantics.

- **Library:** Combine search, favorites, tags, and sorting into one query surface. Replace the fixed whole-card aspect ratio and overlapping menu with a natural-height card and dedicated footer. Retain the previous thumbnail while its replacement loads. Add real usage history for **Most recently used**, rather than treating modification time as usage. Support Notebook favorites and contextual tag assignment, preserving metadata through moves and renames. [Current library layout](https://github.com/dzackgarza/math-notes-app/blob/2da1707e1d4f28a609550268ef30459731985aaf/Sources/NativeLibraryView.swift)

- **Editor organization:** Rename **Show tab strip** to **Show open notes**. Provide a collapsible Pages/Bookmarks/Layers panel, contextual insertion before/after/at end, compact layer actions, and one Share flow. Reserve canvas space for the rail so controls do not obscure usable page content. [Editor shell](https://github.com/dzackgarza/math-notes-app/blob/2da1707e1d4f28a609550268ef30459731985aaf/Sources/ContentView.swift) · [Layer controls](https://github.com/dzackgarza/math-notes-app/blob/2da1707e1d4f28a609550268ef30459731985aaf/Sources/LayersSheet.swift)

- **Theme and status:** Complete semantic foreground/background pairs, especially prominent creation buttons and selected controls. Use role-appropriate text scaling, keyboard-aware layouts, and adequate hit targets. Ordinary saving becomes quiet, stable-width feedback; failures and recovery remain visible and announced. The current native light palette and Alegreya families remain the visual starting point. [Native theme](https://github.com/dzackgarza/math-notes-app/blob/2da1707e1d4f28a609550268ef30459731985aaf/Sources/NativeTheme.swift)

The supplied historical Flutter/web audit is separately dispositioned in the report. Already-replaced Roboto, navy palette, horizontal-toolbar, and fixed-dialog code should not generate new work against the native host.

## Acceptance must establish the user outcome

The release passed **220 Swift tests and 95 core cases**, while its logs still contained the figure echo and stall reports. Existing tests bypass important boundaries: direct text mutation bypasses the actual sheet/Done path; clipping tests do not reproduce image-plus-Pencil lasso; the figure test substitutes persistence and deduplicates saves; several tool tests bypass physical rail interaction. [Release CI](https://github.com/dzackgarza/math-notes-app/actions/runs/38026399986/job/114138045367) · [Text tests](https://github.com/dzackgarza/math-notes-app/blob/2da1707e1d4f28a609550268ef30459731985aaf/AppTests/TextPersistenceTests.swift) · [Figure tests](https://github.com/dzackgarza/math-notes-app/blob/2da1707e1d4f28a609550268ef30459731985aaf/AppTests/FigureEditorSheetWorkflowTests.swift)

Q1 adds an independent application-level XCUI target and retains Hammer where actual Pencil channels require it. Apple’s automation guidance supports inspecting application behavior and retaining screenshots/video as test evidence. [Apple Developer](https://developer.apple.com/videos/play/wwdc2025/344/?utm_source=chatgpt.com)

The complete acceptance set is:

| Story | Required outcome |
|---|---|
| **C01 — Text Done** | Enter multiline Unicode/IME text, close the sheet, draw immediately afterward, undo/redo, relaunch, and edit the same persisted text. |
| **C02 — Every tool and favorite** | Physical taps, visible selection, accessibility state, and actual effect agree across orientation, narrow windows, and keyboard layouts. |
| **C03 — Lasso regression** | Angle-bearing ink beside a resized image survives lasso, save, reopen, and repeated selection without aborting. |
| **C04 — Clippings** | Import, save, reopen, insert, resize, lasso, move, undo, and export preserve bytes, placement, and app responsiveness. |
| **C05 — Eraser footprint** | Grazing hits and interior holes work; geometry outside the footprint remains unchanged; cancellation and undo restore exactly. |
| **C06 — Erased fragments** | Save/relaunch and erase again without resurrecting original ink; screen and exports agree. |
| **C07 — Highlighter** | Repeated same-style passes stay uniform, including semantic containers; live, committed, reopened, and exported results agree. |
| **C08 — Presets** | A complete favorite appears immediately, selects correctly, and survives note switching and relaunch. |
| **C09 — Text sizing and links** | Text reflows without font scaling; keyboard/IME state survives; finger navigation and Pencil drawing coexist. |
| **C10 — New figure** | Create visually, Done, continue notebook editing, reopen, and relaunch with matching source and picture. |
| **C11 — Figure traffic** | Edit continuously, press Done while rendering is pending, and receive one current commit with a drained message queue. |
| **C12 — Figure identity** | Two figures, duplication, transforms, undo, reopen, and stale replies preserve independent identity and complete revisions. |
| **C13 — Figure panels and failure** | Optional panels, offline startup, WebKit termination, save failure, and retry behave explicitly without losing drafts. |
| **C14 — Dense library** | Long titles, many tags, refreshed thumbnails, menus, search, and creation remain readable and hittable. |
| **C15 — Metadata and usage** | Reading affects recent-use order; favorites/tags survive owned, external, offline, and root renames. |
| **C16 — Page/layer/share actions** | Contextual targets, insertion positions, reorder/delete/undo, and sharing operate correctly. |
| **C17 — Slow storage race** | Hold write A, edit B, receive estimates, finish A then B; input remains responsive and A cannot acknowledge B. |
| **C18 — Recovery** | Terminate after local durability but before provider completion; recover exactly the acknowledged generation. |
| **C19 — External changes and switching** | Clean changes reload, dirty conflicts preserve both sides, and stale commands cannot edit the next note. |
| **C20 — Diagnostics** | A controlled incident exports the correct build, UUID, load address, and context and resolves against its dSYM. |
| **C21 — Existing figure migration** | Convert original ink, edit, relaunch, restore drawing, undo, duplicate, and round-trip through an old reader without losing source or provenance. |

Every candidate run must retain its `.xcresult`, screenshots, and relevant videos indexed by SHA, device/runtime, scenario, and state. An agent must inspect the visual evidence; artifact generation alone does not close a visual defect.

The report also proposes explicit performance gates for declared ordinary fixtures: no app-caused main-thread pause above 100 ms, usable Text Done within one second on healthy local storage, bounded save/message queues, and Figure Done completion within one second after rendering and local durability finish. These are **targets for the repair**, not claims about current measured performance. Deliberately slow-provider tests must synchronize on an actually blocked write.

**M6 closes only when the complete stories pass on the release candidate, the screenshots and videos have been reviewed, compatibility and recovery cases preserve existing data, and actual Pencil hardware has been qualified.** A green unit suite, a successful callback, or a view that merely renders is insufficient evidence for these reported failures.
Yes. There are mature frameworks for automating real iPad applications, including replaying complete user workflows against the running app. Testing by directly invoking core functions is not a substitute.

Apple's own XCUITest framework can launch an actual native iPad app in the iOS Simulator, tap its controls, enter text, perform gestures, navigate between screens, assert visible results, and capture screenshots and recordings. It runs in CI with `xcodebuild test`.

Two additional options are Maestro and Appium, both of which can automate native iOS interfaces.

The important distinction is between:

- Unit/integration testing: Calling model, controller, or engine functions directly.
- Actual UI testing: Driving the running application through its visible interface and verifying what a user sees and can do.

Math Notes needs both, but its reported failures demonstrate that the second category is insufficiently exercised.

## What I found in Math Notes itself

The repository has a specific architectural omission in its testing setup.

At the audited revision, [`project.yml`](https://github.com/dzackgarza/math-notes-app/blob/2da1707e1d4f28a609550268ef30459731985aaf/project.yml) defines `MathNotesTests` as a `bundle.unit-test` target. It does not define a separate UI-testing target. The [iPad CI workflow](https://github.com/dzackgarza/math-notes-app/blob/2da1707e1d4f28a609550268ef30459731985aaf/.github/workflows/ios.yml) boots an iPad Simulator and runs `xcodebuild test`, but executes that existing test target.

Some tests do inject real UIKit interactions using Lyft's Hammer library. That is more substantial than simply calling core functions, but the workflows still frequently construct their own application environment.

For example:

| Existing test                          | What it actually does                                                                                                               |
| -------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------- |
| `PencilStrokeWorkflowTests.swift`      | Constructs a new `UIWindow`, hosts an `EditorWorkflowHost`, injects stylus events, and sometimes changes `state.tool` directly.     |
| `LibraryWorkflowTests.swift`           | Mounts `ContentView` in a test-created window and injects touches, rather than launching the app as an independent UI-test process. |
| `FigureEditorSheetWorkflowTests.swift` | Hosts `FigureEditorSheet` directly, taps Save, and checks a supplied callback instead of the complete notebook workflow.            |
| `TextPersistenceTests.swift`           | Creates, saves, and reopens text through storage/model APIs without opening the editor or pressing Done.                            |

These are useful component and integration tests, but they do not establish that a user can complete the corresponding workflow in the independently launched application.

That distinction directly explains a major part of the discrepancy between the green simulator test suite and the unusable released application.

## Which framework should Math Notes use?

| Framework                | Runs against the live app   | Relevant capabilities                                                                                                                       | Limitations                                                                                        |
| ------------------------ | --------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------- |
| XCUITest                 | Simulator and physical iPad | Launch, tap, type, drag, navigate, assert UI state, capture screenshots; Xcode can record interactions and generate test code               | Programmatic complex drawing gestures are relatively awkward                                       |
| Maestro                  | iOS Simulator               | Readable YAML workflows, visual test authoring, screenshots, videos, visual regression testing                                              | Its built-in swipe action uses start/end points; physical iOS devices are not officially supported |
| Appium + XCUITest driver | Simulator and physical iPad | WebDriver automation from TypeScript/Python, complex multi-point gestures, screenshots, videos, app lifecycle, native controls and WebViews | More setup, particularly for signing the test runner on physical devices                           |
| Hammer                   | In-process test-hosted UI   | Synthetic Apple Pencil events with pressure, azimuth, and altitude                                                                          | Private APIs; not a standalone external application driver                                         |

Sources:&#x20;

[image](https://www.google.com/s2/favicons?domain=https://developer.apple.com\&sz=32)

Apple Developer Documentation

+6



For Math Notes, I would use Appium with its XCUITest driver as the primary black-box E2E framework. The decisive requirement is support for complex touch paths: drawing, lasso selection, erasing, resizing, and dragging images. Appium's W3C actions support sequences of pointer movements, not merely one straight swipe.&#x20;

[image](https://www.google.com/s2/favicons?domain=https://appium.github.io\&sz=32)

Appium XCUITest Driver

+1



Maestro is attractive for simpler workflows and agent-authored tests. It can construct flows interactively with Maestro Studio, capture videos and screenshots, and compare screenshots against references. However, I would not make it the sole test driver for a drawing application.&#x20;

[image](https://www.google.com/s2/favicons?domain=https://docs.maestro.dev\&sz=32)

Maestro Docs

+2



## What the corrected testing architecture should accomplish

The first mandatory remediation milestone should establish a suite that:

1. Builds and installs the real Math Notes application in the existing GitHub-hosted iPad Simulator.
2. Launches it through the OS, without substituting custom root windows, manually constructed editor sessions, or mock navigation callbacks.
3. Replays complete workflows by tapping visible controls, typing, dragging, drawing, changing tools, closing sheets, switching notes, and relaunching.
4. Asserts the actual visible results and independently checks persisted artifacts when necessary.
5. Records the screen throughout each workflow, captures screenshots at meaningful transitions, and uploads videos, screenshots, accessibility hierarchies, crashes, and diagnostics for successful as well as failed tests.

This needs to precede repairs to the reported UI defects. Each defect gets a test that fails against v343 for the intended reason, then passes against the corrected app.

Examples include the full Text → enter content → Done → continue drawing → relaunch interaction; insert image → resize → lasso around image → move selection → save; open Structured Figure → draw → Done → reopen and edit; and selecting every tool through actual rail taps rather than assigning enum values in test code.

The only special testing layer still required is for Apple Pencil-specific physical quantities. Public XCUITest/Appium touch gestures do not reproduce genuine Pencil pressure and tilt. The existing Hammer dependency can synthesize those properties through UIKit in a test-hosted application; it should remain for precise stylus regression tests, not replace black-box workflow testing.&#x20;

[image](https://www.google.com/s2/favicons?domain=https://github.com\&sz=32)

GitHub



## This can run in your existing CI

Your repository already uses a macOS runner, boots an iPad Simulator, and builds the app. Adding the external UI automation runner does not require you to own a Mac or purchase a device cloud.

Physical-device automation is also technically possible through Appium/XCUITest, but requires a connected Mac and appropriate signing/provisioning for WebDriverAgent. Maestro's documented iOS support is currently simulator-only.&#x20;

[image](https://www.google.com/s2/favicons?domain=https://github.com\&sz=32)

GitHub

+2



For visual evidence, Appium can record the device screen to MP4, and Apple's XCTest supports persistent screenshot attachments. These are established features, not functionality agents should reinvent.&#x20;

[image](https://www.google.com/s2/favicons?domain=https://github.com\&sz=32)

GitHub

+1



The testing failure in Math Notes is therefore not a limitation of iPad automation. The project chose an in-process unit-test architecture as its primary test suite, even where the intended acceptance criterion was a user completing a workflow in the actual application.

That is the architectural error to correct. No amount of additional direct core-function testing can discharge the missing live-application acceptance requirements.
