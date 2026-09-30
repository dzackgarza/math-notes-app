# Traps

## Build / release

- **The macOS runner's disk is case-insensitive.** Top-level `Tests/` and `tests/` were one directory there, and the iPad Simulator Catch2 run could not open `tests/documents/` ("cannot open …"). Keep top-level names distinct ignoring case; the Swift tests live in `AppTests/`.
- **XcodeGen writes fixed `1.0` / `1` into Info.plist** when `info.properties` is used, ignoring `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`. `project.yml` must map `CFBundleShortVersionString: $(MARKETING_VERSION)` and `CFBundleVersion: $(CURRENT_PROJECT_VERSION)`. Symptom: SideStore "does not match the build number specified by the source".
- **Never publish the IPA at a reused URL.** A rolling `latest` tag let the iPad install a cached older IPA (build mismatch). Deleting a tag breaks every cached `source.json` that points at it ("MathNotes.ipa doesn't exist"). Each build gets its own tag `v<run>`; old releases are kept.
- **Size in `source.json` must be the exact IPA byte count.** SideStore verifies it. macOS `stat` is `stat -f %z`, not `-c %s`.
- **Workflow re-runs reuse `github.run_number`,** so the release step uploads with `--clobber` when the tag exists.
- **`gh run watch` at its default 3-second interval trips GitHub's secondary rate limit** (`HTTP 403: API rate limit exceeded` while `gh api rate_limit` still shows thousands of core requests left), and the watch exits before the run ends. Watch with `--interval 60`.
- **`gh run list --commit` with an abbreviated SHA lists nothing,** with no error. Pass the full SHA (`git rev-parse HEAD`), as `just web-fetch` does.

## Linux host

- **iloader AppImage aborts with `Could not create surfaceless EGL display: EGL_BAD_ALLOC`** on this machine. The AppImage bundles an old libwayland (upstream nab138/iloader#576); `WEBKIT_DISABLE_DMABUF_RENDERER`, `GDK_BACKEND=x11` do not help. Use the `.deb` asset's `usr/bin/iloader` against system `webkit2gtk-4.1`.
- **`usbmuxd` started after the iPad was plugged in does not see it.** Re-plug. `Pairing dialog response pending (-19)` means tap Trust on the iPad.

## SideStore on the iPad

- **Developer Mode switch is hidden** until a development-signed app (SideStore) is on the device and launched once.
- **"VPN connection error / no utun interface"**: LocalDevVPN is not connected.
- **Operation error 28** = `notAuthenticated` (Swift's implicit `CustomNSError` code for `OperationError`, payload cases first). Sign in inside SideStore's Settings; signing in to iloader is not enough.
- **A changed source is cached.** After changing download URLs, remove and re-add the source.

## Write replay harness (`just write-fixtures`)

- **Write's `--test` exits with status 16 although every test passes.** The exit status is `256·failed + failed thumbnails`, and all 16 thumbnails differ from the refs on this host, as upstream. Check the log line `with 0 failed tests` instead. The run also leaves `test*_out.html` and `test*_{out,ref,diff}.png` in `scribbletest/`; the recipe trashes them.
- **Stroke timestamps ignore the event time `t`.** `Page::addStroke` stamps each stroke with `mSecSinceEpoch()`, so `groupStrokes`' 2.5 s window depended on wall-clock speed. The fork adds `Page::clock`; replay sets it to the trace time.
- **A converted upstream test passed alone but failed after other cases.** `screenRect`, config, and clipboard persist in a `ScribbleTest`, and paste position depends on the screen. Replay builds a fresh `ScribbleTest` for each case.
- **Element ids changed between identical runs.** Ids keyed by `Element*` broke when freed elements' addresses were reused (reopen, undo history). The id now lives in `Element::uuid`.
- **The upstream tests start at view `(-10, -10)`, not `(0, 0)`.** Recorded traces begin with a `view` line that restores it.
- **The Write build is C++14 with `-fno-rtti`:** no `std::to_chars`, no `dynamic_cast`.
- **A Write mode other than 12 lasts one gesture** (`doubleTapSticky` off, `ScribbleMode::setMode`). A trace with one `mode 14` before three erase gestures erased on the first only; the others drew strokes, and the replay still reported 0 failures. Set the mode before each gesture.
- **`just write-fixtures` compiled Write for wasm** (`ulib/fileutil.h` not found under `EmDebug/`): the justfile exports `EMSDK`, and Write's Makefile picks `Makefile.wasm` when it is set. The recipe unsets it for the Write build.
- **Each `ie` line of an upstream trace has the time 0** (`ScribbleTest::ie`, `scribbletest.cpp:499`); Write makes a path from the positions alone. The engine, given those times, stored a two-point divider with the outline of its last point only, so `FindStops` saw no column and `upstream-test11` moved both columns. `ReplayWriteTrace` steps the clock 10 ms per event.

## Engine

- **The JetBrains/skia iOS prebuilts target iOS 12.0 and 14.0** (`otool -l` minos). The engine needs 18.0, so CI builds iOS Skia from source at the same commit (`core/scripts/build-skia-ios.sh`). The wasm prebuilt is used as shipped.
- **`SkPDF::MakeDocument` aborts the process** (`Must set both a jpegDecoder and jpegEncoder`) with a default `SkPDF::Metadata`. Start from `SkPDF::JPEG::MetadataWithCallbacks()` (`include/docs/SkPDFJpegHelpers.h`).
- **`wasm-objdump -x` dumps data segments,** whose strings (`shared_ptr`, SkSL `atomicStore`) match a thread check. Inspect only `-j Memory` and `-j target_features`.
- **`actions/cache` rejects paths containing `..`** ("Relative pathing . and .. is not allowed") and then saves nothing, with only a warning. CI keeps its tool directories under `$GITHUB_WORKSPACE/.ci/`.
- **google/ink keeps predicted-input smoothing in the finished stroke** unless the pen-up batch has no prediction. The sliding-window modeler smooths the last real inputs over the predicted ones. `FinishInputs()` does not re-model them, and `EnqueueInputs({}, {})` is a no-op (`sliding_window_input_modeler.cc:239`). The residue reaches 4 units (brush size 5) at the stroke end. Hosts send the final real samples with an empty prediction.
- **vcpkg's abseil port patches do not apply to abseil 20260526.0.** The overlay in `core/ports/abseil` drops `fix-heterogeneous_lookup_testing-target.patch` (upstream has `TESTONLY`) and the GCC 13 `constexpr` patch (both engine targets use Clang).
- **google/ink needs `absl::status_builder`** (for `ABSL_ASSIGN_OR_RETURN`), in addition to the targets its headers name.
- **Chromium snaps an SVG document's root box to whole CSS pixels.** A page opened as a document at `297mm` (1122.52 px) is laid out at 1123 px, which scales the drawing by 0.04% and moves edges near the bottom by 0.3 px. `render-goldens.mjs` draws the SVG as an image onto a canvas with an exact destination rectangle instead; an SVG image loads no external files, so it inlines the assets as data URIs.
- **Headless Chromium renders WebGL with SwiftShader** (CPU Vulkan), 10× slower than the GPU. Frame timings use the `chromium-gpu` Playwright project (`--use-angle=gl --ignore-gpu-blocklist`), which reaches the host GPU as desktop Chrome does.
- **A headless full-viewport screenshot can show the WebGL canvas displaced** while a DOM overlay over it changes size (the pull indicator): the page was drawn lower by the overlay's height, with desk above it. A 1 × 1 clipped capture of the same pixel, and a headed browser, show the correct frame. Check canvas pixels with clipped captures.
- **Chromium draws SVG `rect` and `ellipse` with `drawRect` and `drawOval`,** whose thin-stroke rasterization in Skia's CPU backend differs from `drawPath` of the same shape (full miter corners on a 1 px rect). The renderer draws those shapes with the same calls.
- **`--emit-tsd` needs `tsc`, and emsdk installs none** ("tsc executable not found in node_modules or in $PATH"). The build takes it from `hosts/web/node_modules/.bin`. **TypeScript 7 does not work there:** Emscripten 4.0.7 calls `tsc --outFile`, which TypeScript 7 removed; `hosts/web` pins TypeScript 5.9.
- **Chrome DevTools Protocol input has no pen eraser:** `Input.dispatchMouseEvent` maps `buttons` bits 1 to 16 only, so bit 32 never reaches the page. E2E tests dispatch the eraser end's `PointerEvent`s (button 5, buttons 32) on the canvas instead.
- **google/ink's modeled outline does not reach the input peaks.** The sliding-window modeler smooths the centerline, so a wave's outline box sat up to 1 Write unit inside the box of its samples padded by half the width. Write's selection bounds are the padded centerline (`SvgPainter::_bounds`); with the outline box, the selection rectangle's center moved by 0.3 units and a rotation drag differed by 0.2°. Selection bounds use the samples.
- **A comma in a Catch2 test name splits the command-line filter:** `ink_tests.js "Resize, select all"` matched nothing and reported "No tests ran". Keep commas out of test names.

## Web host

- **`FileSystemDirectoryHandle.move` is missing in Playwright's Chromium** (`knots.move is not a function`), even on the origin-private file system, and Chrome's local file system moves no directories. A test that moved a directory with it passed nowhere; the library renames and moves a directory by copying it and removing the original, and tests simulate `mv` the same way.
- **Save feedback distinguishes recovery from filesystem writes.** `Pending file save` means the edit journal committed to IndexedDB; reopening applies it before loading the note. `Saved` means the notebook file writes completed. Thumbnail and standalone-SVG checks must wait for `Saved`, because they read the files. Recovery entries identify OPFS directories by their path from the origin root and external directories by their filesystem handle.
- **Every rescan made the library covers show plain paper for a moment.** A rescan creates new note objects, so each cover's resource loaded again from empty, and the paper tile showed until the cache read ended. A screenshot taken after a rescan showed no ink in the covers, although the cached PNGs had ink. Covers now start from the last thumbnail loaded for their path.
- **Default headless Chromium renders WebGL with SwiftShader.** Flutter's CanvasKit then spends most of each frame in `createImageBitmap`: a 240-stroke page showed long tasks up to 518 ms while writing, and 16.7 ms frames on the GPU. Timing checks launch `/bin/chromium` with `--enable-gpu --use-gl=angle --use-angle=gl-egl --ignore-gpu-blocklist` and confirm the WebGL renderer names the Intel GPU.
- **`phosphor_flutter` 2.1.0 does not compile with Flutter 3.47:** `IconData` is a final class, and the package subclasses it (phosphor-flutter#61, #64). The host uses `lucide_icons_flutter`.
- **A click with no motion on `flex_color_picker`'s `ColorWheelPicker` changes nothing.** Its vertical-drag `onDown` never reaches `onStart` for a bare click, and its `onTapUp` only repeats the current color. A 3 px drag sets the color. Workflows drag the wheel; a mouse user must drag too.
- **After View > Toolbar at bottom, the toolbar buttons' accessibility bounds keep the top position** until a reload, although the ribbon draws at the bottom. Clicks through the semantics nodes still work. Workflows locate the ribbon from its pixels, not from `boundingBox()`.
- **A module worker drops each message that arrives before its top-level `await` ends.** The MuPDF worker awaits the WASM module before it sets `onmessage`, and the first `open` request got no reply: the PDF import stayed at "Importing" with no error. The worker posts `ready` after it sets the handler, and `importPdf` awaits that message before the first request.
- **The clear button of `CupertinoSearchTextField` ends the typing on web when semantics are on.** The suffix appears after the first character and splits the semantics node of the text field; the web engine then replaces the focused `<input>`, and the remaining keys go nowhere (flutter/flutter#151980). A query of one letter still filters, so a check of the results alone passes. `SearchField` in `notes_ui.dart` keeps the button outside the text field; workflows assert the field's value after they type.
- **A Flutter `BackdropFilter` does not blur a platform view on the web** (flutter/flutter#143747, open). The ink canvas is a DOM canvas under the Flutter scene, so a translucent surface (pull-down menu, alert, action sheet, popup surface) shows the ink behind it sharp. The editor therefore shows a Flutter image of the canvas over it while a route covers the editor (`still` in `hosts/web/flutter/lib/ui/editor/editor_screen.dart`).
- **Chromium 153 exits when IndexedDB reads a stored origin-private directory handle back after a reload.** Playwright's headless shell, its Chromium, and the system Chromium (153.0.8010.x) all end with `SIGTRAP` and no JavaScript error; Chromium 140 reads it back. A folder from the real picker reads back in the same Chromium, so the app's saved-folder start works for a user. A workflow that stores the picker stub's OPFS root in the app's IndexedDB must not reload with the app's own `startRoot`; the lifetime workflow replaces `startRoot` on restart.
- **A read of the WebGL ink canvas gives an empty image outside the task that drew the frame.** `preserveDrawingBuffer` is off, so the browser clears the drawing buffer when it presents the frame. Call `ink_canvas_invalidate`, then `ink_render`, then `createImageBitmap` in one task.
