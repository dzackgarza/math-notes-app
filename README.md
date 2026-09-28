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

`just web-deploy` builds the Solid site and the Flutter host and copies them to `/var/www/math-notes` and `/var/www/math-notes/flutter`. nginx serves it at `http://localhost/math-notes/` with `include <repo>/hosts/web/deploy/nginx-math-notes.conf;` inside the `server` block for `localhost`, then `sudo nginx -s reload`. Only `assets/` gets a long cache lifetime. Use `localhost`, not a LAN address: the folder picker and coalesced pen events need a secure context.

In Chrome, choose the notes folder once; after a restart, **Reconnect folder** grants access again (it needs a click).

`just web-test` runs the Vitest Browser Mode tests and the Playwright tests against the deployment.

`just web-flutter-build` builds the Cupertino host with the pinned Flutter SDK.
The web test deployment serves it at `http://localhost/math-notes/flutter/`.
The host transition is owned by [#56](https://github.com/dzackgarza/math-notes-app/issues/56).
Workbox caches its application, engine, renderer, and font assets for offline
restart. An updated worker waits until open app pages close before activation.

Figure compilation uses the pinned BusyTeX source build with TeX Live 2026,
LuaLaTeX, and the pictures collection. Set `MATH_NOTES_TEX_BUILD` to an absolute
build directory, then run `just web-figure-compiler`. The volume must hold the
6.8 GB ISO, its extracted contents, and native and WebAssembly build outputs.
The recipe verifies the ISO digest and places the browser assets in
`.ci/figure-compiler`. Run `just web-flutter-build` to bundle them for deployment
and offline use. The figure editor's **Preamble** control edits the shared
`.figure-preamble.tex` file in the notes root.

## Releasing

Push to `main` with a change under `Sources/`, `project.yml`, `sidestore-source.jq`, or the workflow. The run sets version `0.1.<run number>`, build `<run number>`. Other pushes do not build. Run manually with `gh workflow run ios.yml`.

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
