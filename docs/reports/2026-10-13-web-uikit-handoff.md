# Web and UIKit completion handoff — 2026-10-13

The ordered work remains: finish [web/shared core #113](https://github.com/dzackgarza/math-notes-app/issues/113) in draft [PR #114](https://github.com/dzackgarza/math-notes-app/pull/114), then complete [UIKit #7](https://github.com/dzackgarza/math-notes-app/issues/7). The standalone Visual TikZ Editor prerequisite is complete. Do not merge PR #114 or start the UIKit port on the strength of a narrow test result; #113's whole product and acceptance contract still applies.

## Immediate pickup

1. Inspect the two **Engine (wasm32)** runs for current code commit `6d5a5480b652681ab1528c04b3b153fa88e9dac8`: push run `38445080290`, PR run `38445087989`. Both were in progress when this handoff was written. Use `gh run watch 38445080290 --interval 60` and inspect failed job logs if either run fails. An older run for `ae6a123` (`38442513679`, PR run `38442525179`) still had its long exploratory shard running; its completed jobs were green. Keep results tied to their `headSha`.
2. The latest change corrects `core/src/format/page_svg.cpp` so Skia Paragraph's UTF-16 line indices select UTF-8 bytes correctly. The deployed baseline **failed** `hosts/web/e2e/text-composition.spec.ts`: saved SVG had `['नम', '��्ते']` instead of the composed Devanagari and Arabic lines, although the on-page renderer displayed them. The fixed revision has **not** passed a deployed replay yet. Its C++ regression is in `core/tests/test_document.cpp`. The first fix revision `2de10ad` failed compilation solely because it used `src/base/SkUTF.h`; the pinned Skia tree contains `src/core/SkUTF.h`, which current code uses.
3. Once the current exact-SHA CI run succeeds, run `just web-fetch`, then replay the composition workflow against that artifact. On this host `http://localhost/math-notes/` returned 404 while `http://localhost:8103/math-notes/` returned 200 through the local Python server; verify both before testing. Example from `hosts/web`: `MATH_NOTES_URL=http://localhost:8103/math-notes/ bunx playwright test e2e/text-composition.spec.ts --reporter=line`. Confirm the test reads the saved standalone SVG **and** succeeds after reload, rather than accepting the canvas view alone.
4. Inspect the old exploratory shard result and retain its original failure artifacts if it fails. `hosts/web/e2e/exploration.spec.ts` has a known local full-action execution that reached the genuine restart and matched SVG/pixels, but teardown failed while finalizing a large Playwright trace. The reduced trace settings in `ae6a123` have not yet passed CI. Another local replay observed a transient late-frame pixel poll failure; the source now waits up to 30 seconds for the visible frame. A failed full-task replay still needs a causal repair and a successful original-seed replay; do not weaken its screen or saved-file oracle.

## Remaining web acceptance

- Reconcile every acceptance item in #113 against **complete deployed workflows**, especially the ten-page real-folder restart and independently rendered PDF, ordinary L0/L1 task combinations, save/recovery/conflict and provider changes, ruled editing and overflow, selection/erasure geometry, highlight compositing, layers, bookmarks/links, text editing, mixed-size PDF import, and figure integration. Existing tests cover portions of these; a green internal/unit test or an isolated control demonstration cannot close the item. Use the issue's acceptance language as the checklist.
- Repair any failing CI or deployed workflow at its shared owner and replay the entire user task. Keep original failure evidence. The mixed-size PDF import workflow passed locally against a deployed prior revision, but its current CI result must be checked. The current branch has a save-order fix whose browser unit test passed locally; this does not by itself prove the full revision and recovery contract.
- Review PR #114's actual diff and any review feedback, update its currently stale “Current judgment” text with exact-revision evidence, and leave it draft until #113 is truly satisfied. Then obtain the required independent review, resolve feedback, merge, and only then begin #7. For Swift changes, use the iOS CI workflow because this Linux host cannot build Swift. Verify the exact CI SHA, release metadata invariants, and UIKit product workflows before closing #7.

## Native test environment

The local native chooser path uses `Xvfb`, `dbus-daemon`, `gdbus`, `openbox`, `xprop`, `xdotool`, `zenity`, ImageMagick `import`, Python 3 with GI/AT-SPI, and Chromium; PDF workflows also use `pdfinfo`, `pdftoppm`, and `qpdf`. `xdotool` and `zenity` are now in `/usr/bin`. `openbox` and `qpdf` were unavailable on the ordinary PATH at handoff but extracted binaries are under `/tmp/visual-tikz-test-tools/root/`; the previous local test used:

```sh
PATH=/tmp/visual-tikz-test-tools/root/usr/bin:$PATH \
LD_LIBRARY_PATH=/tmp/visual-tikz-test-tools/root/usr/lib/x86_64-linux-gnu \
XDG_DATA_DIRS=/tmp/visual-tikz-test-tools/root/usr/share:/usr/share \
MATH_NOTES_OPENBOX_CONFIG=/tmp/visual-tikz-test-tools/root/etc/xdg/openbox/rc.xml \
MATH_NOTES_URL=http://localhost:8103/math-notes/ \
bunx playwright test e2e/lifetime.spec.ts --reporter=line
```

Run that command from `hosts/web` after confirming the extracted files and deployed artifact still exist. CI's `web.yml` installs its own native test packages. Avoid further one-package-at-a-time requests to the user; inspect the whole toolchain first.

Read `README.md`, `TRAPS.md`, `docs/ARCHITECTURE.md#component-ownership`, and the issue body before changing behavior. Build through CI as `AGENTS.md` requires. Keep the handwritten-draft boundary and the standalone editor → web/shared core → UIKit order.
