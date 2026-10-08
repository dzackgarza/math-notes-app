# math-notes-app

Handwritten math notes: a C++ ink engine with a web app and an iPad app, all in this repo. Architecture: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md). Adopted web interface framework: [Flutter selection](docs/reports/Web%20interface%20framework%20selection.md). Roadmap: the issue tree under [#11](https://github.com/dzackgarza/math-notes-app/issues/11). The iPad app is developed on Linux, built by GitHub Actions, and installed with SideStore: no Mac, no App Store, free Apple Account.

```
push to main ──► GitHub Actions (macos-26) ──► release vN: MathNotes.ipa + source.json
                                                          │
iPad: SideStore source ◄── releases/latest/download/source.json
      signs with your Apple Account, installs, refreshes every 7 days
```

## Layout

| Path | Role |
| --- | --- |
| `project.yml` | [XcodeGen](https://github.com/yonaskolb/XcodeGen) spec. The `.xcodeproj` and `Sources/Info.plist` are generated in CI and not tracked. |
| `Sources/` | Swift sources. |
| `.github/workflows/ios.yml` | Builds an unsigned IPA, checks it, publishes release `v<run number>`. |
| `sidestore-source.jq` | Template for `source.json` ([AltStore source format](https://faq.altstore.io/developers/make-a-source)). |
| `docs/FEATURES.md` | Feature spec. |
| `docs/ARCHITECTURE.md` | Engine and host architecture, dependencies, reference implementations. |
| `docs/FORMAT.md` | Notebook storage and file format. |
| `core/` | The C++ engine; `core/include/ink.h` is its C ABI. |
| `hosts/web/` | The web host; `src/engine/` wraps the engine module (`just web-engine-test`). |
| `tests/fixtures/write/` | Traces and results recorded from Stylus Labs Write; see its README.md. |
| `justfile` | `test-commit` and `test-push`: YAML lint. Swift compiles only in CI. `write-fixtures`: regenerates `tests/fixtures/write/`. |

## Web app on this machine

CI builds the engine and the Flutter web app on every push (workflow "Engine (wasm32)", which uploads the artifacts `engine-module` and `web-app`). `just web-fetch` downloads the build of the checked-out commit and copies the web app to `/var/www/math-notes`; `gh run watch --interval 60 <run>` waits for a run. `just web-deploy` builds both on this machine instead, which loads the machine for minutes. nginx serves the deployment at `http://localhost/math-notes/` with `include <repo>/hosts/web/deploy/nginx-math-notes.conf;` inside the `server` block for `localhost`, then `sudo nginx -s reload`. Use `localhost`, not a LAN address: the folder picker and coalesced pen events need a secure context.

In Chrome, choose the notes folder once; after a restart, **Reconnect folder** grants access again (it needs a click).

`just web-test` runs the Vitest Browser Mode tests and the Playwright tests against the deployment.

Workbox caches the application, engine, renderer, and font assets for offline
restart. A new deployment activates at once; a reload shows it.

## Releasing

Push changes to a working branch first. Every branch revision runs "Engine (wasm32)"; `main` requires its `wasm` check to pass before accepting that revision, including administrator pushes. Local push checks only lint YAML; compilation and engine tests run in CI.

After the verified revision reaches `main`, a successful "Engine (wasm32)" workflow starts the iPad release. The iPad workflow checks the exact revision again before allocating a macOS runner, then runs Simulator tests and packages the IPA. It sets version `0.1.<run number>`, build `<run number>`. Manual runs (`gh workflow run ios.yml --ref <branch>`) require that branch revision's engine check to have passed too. Only runs on `main` publish to SideStore, and publication rejects a revision that has been superseded on `main`.

On the iPad, open SideStore; the update shows in My Apps. Tap Update (SideStore does not auto-install source updates).

## One-time iPad setup (from Linux)

1. `sudo pacman -S usbmuxd && sudo systemctl start usbmuxd`. Re-plug the iPad and tap Trust. `idevicepair validate` must succeed.
2. Install SideStore with [iloader](https://github.com/nab138/iloader). Use the binary from the `.deb` release asset (`usr/bin/iloader`, installed at `~/.local/bin/iloader`); see TRAPS.md for why not the AppImage.
3. iPad: Settings → General → VPN & Device Management → trust your Apple Account's developer certificate.
4. Open SideStore once; then Settings → Privacy & Security → Developer Mode → on, restart, Turn On.
5. Install **LocalDevVPN** from the App Store and connect it. SideStore needs it for every install and refresh.
6. SideStore → Settings → sign in with the same Apple Account.
7. SideStore → Sources → + → `https://github.com/dzackgarza/math-notes-app/releases/latest/download/source.json`, then install Math Notes.

For background signature refresh: Background App Refresh on for SideStore, LocalDevVPN connected.

## Free-account limits

App IDs and profiles expire after 7 days (SideStore refreshes them). At most 3 sideloaded apps per device, and SideStore counts as one. Some entitlements (iCloud, push, etc.) need the paid Developer Program.
