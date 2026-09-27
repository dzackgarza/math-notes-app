# Swift builds only on the macOS CI runner. The engine builds for wasm32 here.
# EMSDK must point at an activated emsdk 4.0.7; VCPKG_ROOT at a vcpkg clone.

emsdk := env("EMSDK", env("HOME") / ".cache/math-notes/emsdk")
vcpkg := env("VCPKG_ROOT", env("HOME") / ".cache/math-notes/vcpkg")
build := "core/build/wasm"

export EMSDK := emsdk
export PATH := emsdk / "upstream/emscripten" + ":" + env("PATH")

flutter := justfile_directory() / ".ci/flutter"
flutter_rev := "4cf24164269a5ebf0c16a028a00727d0e77bbb05"

[private]
_flutter-sdk:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ ! -d "{{flutter}}" ]; then
      git clone --depth 1 --branch 3.47.0 https://github.com/flutter/flutter.git "{{flutter}}"
    fi
    test "$(git -C '{{flutter}}' rev-parse HEAD)" = '{{flutter_rev}}'
    '{{flutter}}/bin/flutter' precache --web

# Builds the Cupertino host against the existing engine and storage services.
web-flutter-build: engine-module
    mkdir -p hosts/web/src/engine/wasm
    cp {{build}}/web/engine.* {{build}}/web/engine_test.* hosts/web/src/engine/wasm/
    just _flutter-host

# CI supplies the engine module as an artifact.
[private]
_flutter-host: _flutter-sdk
    cmake -P core/cmake/TextFonts.cmake
    mkdir -p hosts/web/flutter/generated_fonts
    cp .ci/fonts/*.ttf hosts/web/flutter/generated_fonts/
    cd hosts/web && bunx tsc -b && bunx --bun vite build --config vite.flutter.config.ts
    cd hosts/web/flutter && '{{flutter}}/bin/flutter' pub get --enforce-lockfile && '{{flutter}}/bin/flutter' build web --base-href /math-notes/flutter/ --no-web-resources-cdn
    cp -a hosts/web/flutter/build/bridge/. hosts/web/flutter/build/web/
    bun hosts/web/build-tikz.mjs
    cd hosts/web && bun flutter-cache.mjs

# Installs emsdk 4.0.7, vcpkg and the Playwright browsers where the recipes
# below look for them (the engine workflow's setup steps).
setup:
    [ -d {{emsdk}} ] || git clone -q https://github.com/emscripten-core/emsdk {{emsdk}}
    {{emsdk}}/emsdk install 4.0.7 && {{emsdk}}/emsdk activate 4.0.7
    [ -d {{vcpkg}} ] || git clone -q https://github.com/microsoft/vcpkg {{vcpkg}}
    [ -x {{vcpkg}}/vcpkg ] || {{vcpkg}}/bootstrap-vcpkg.sh -disableMetrics
    cd core/tests/webgl && bun install --frozen-lockfile && bunx playwright install chromium chromium-headless-shell
    cd hosts/web && bun install --frozen-lockfile && bunx playwright install chromium chromium-headless-shell

engine-wasm:
    cmake -S core -B {{build}} -G Ninja -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_TOOLCHAIN_FILE={{vcpkg}}/scripts/buildsystems/vcpkg.cmake \
      -DVCPKG_CHAINLOAD_TOOLCHAIN_FILE={{emsdk}}/upstream/emscripten/cmake/Modules/Platform/Emscripten.cmake \
      -DVCPKG_TARGET_TRIPLET=wasm32-emscripten -DVCPKG_MANIFEST_FEATURES=tests -DINK_BUILD_TESTS=ON
    cmake --build {{build}}

engine-test: engine-wasm
    cd {{build}} && ctest --output-on-failure
    qpdf --check {{build}}/tests/a4.pdf
    cd core/tests/webgl && bun install --frozen-lockfile && WEBGL_CHECK_DIR=$PWD/../../build/wasm/tests/webgl bunx playwright test -c playwright.config.mjs --project chromium

test-commit:
    uvx yamllint -s -d '{extends: relaxed, rules: {line-length: disable}}' project.yml .github/workflows/ios.yml .github/workflows/engine.yml .github/workflows/web.yml

test-push: test-commit

# Rewrites core/tests/fixtures/ink (traces and host outline goldens) on the Linux host.
ink-fixtures:
    cmake -S core/tools/ink-host -B core/build/ink-host -G Ninja -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_TOOLCHAIN_FILE={{vcpkg}}/scripts/buildsystems/vcpkg.cmake
    cmake --build core/build/ink-host
    core/build/ink-host/ink_host_fixtures core/build/ink-host/_deps/google_ink-src core/tests/fixtures/ink

# Rewrites core/tests/fixtures/documents: the engine's output for each notebook in tests/documents.
document-fixtures: engine-wasm
    node {{build}}/tests/write_documents.js tests/documents core/tests/fixtures/documents full custom-size

# Rewrites core/tests/fixtures/templates: the notebook of each built-in template.
template-fixtures: engine-wasm
    node {{build}}/tests/write_templates.js core/tests/fixtures/templates

# Rewrites core/tests/fixtures/render: Chromium's rendering of each listed page in
# core/tests/fixtures/documents and core/tests/fixtures/templates.
render-goldens:
    cd core/tests/webgl && bun install --frozen-lockfile && bun run render-goldens.mjs

# Zoom and input timings in Chromium on this machine's GPU (not run in CI, which has none).
frame-times: engine-wasm
    cd core/tests/webgl && bun install --frozen-lockfile && WEBGL_CHECK_DIR=$PWD/../../build/wasm/tests/webgl bunx playwright test frame.spec.mjs -c playwright.config.mjs --project chromium-gpu --reporter list

# The web engine module (core/build/wasm/web/engine.mjs, .wasm, .d.mts) and its Node test build.
# --emit-tsd runs the tsc that hosts/web installs.
engine-module: engine-wasm
    cd hosts/web && bun install --frozen-lockfile
    PATH="$PWD/hosts/web/node_modules/.bin:$PATH" cmake --build {{build}} --target engine engine_test

# The TypeScript wrapper: type check against the module's --emit-tsd types, then the Node tests.
web-engine-test: engine-module
    mkdir -p hosts/web/src/engine/wasm
    cp {{build}}/web/engine.* {{build}}/web/engine_test.* hosts/web/src/engine/wasm/
    cd hosts/web && bunx tsc -b && node --test src/engine/engine.test.ts

# The web app in hosts/web/dist, with the engine module.
web-build: engine-module
    mkdir -p hosts/web/src/engine/wasm
    cp {{build}}/web/engine.* {{build}}/web/engine_test.* hosts/web/src/engine/wasm/
    cd hosts/web && bunx tsc -b && bunx --bun vite build

# Builds the web app and copies it to /var/www/math-notes (served at http://localhost/math-notes/, README).
web-deploy: web-build
    rsync -a --delete hosts/web/dist/ /var/www/math-notes/

# Vitest Browser Mode in Chromium, then Playwright against the deployment.
web-test: web-deploy web-flutter-build
    mkdir -p /var/www/math-notes/flutter
    rsync -a --delete hosts/web/flutter/build/web/ /var/www/math-notes/flutter/
    cd hosts/web && bunx vitest run
    cd hosts/web && bunx playwright test

# Stylus Labs Write fork with the replay harness (dzackgarza/Write, branch replay-harness).
write_dir := env_var_or_default("WRITE_DIR", env_var("HOME") / ".cache/math-notes/Write")
write_rev := "876de97"

# Build the Write fork and regenerate every case in tests/fixtures/write (see its README.md).
write-fixtures:
    #!/usr/bin/env bash
    set -euo pipefail
    W="{{write_dir}}"
    F="{{justfile_directory()}}/tests/fixtures/write"
    if [ ! -d "$W" ]; then
      git clone --recurse-submodules -b replay-harness https://github.com/dzackgarza/Write "$W"
    fi
    if [ "$(git -C "$W" rev-parse --short=7 HEAD)" != "{{write_rev}}" ]; then
      echo "$W is not at write_rev {{write_rev}}; check it out or update write_rev" >&2
      exit 1
    fi
    # the build needs these submodules (not SDL: USE_SYSTEM_SDL)
    git -C "$W" submodule update --init miniz nanovgXC pugixml stb ugui ulib usvg
    # the justfile exports EMSDK, which makes Write's Makefile build for wasm
    env -u EMSDK make -C "$W/syncscribble" USE_SYSTEM_SDL=1 DEBUG=1 SANITIZE=0 -j"$(nproc)" >/dev/null
    cp "$W"/scribbleres/fonts/* "$W/syncscribble/Debug/"
    tmp=$(mktemp -d)
    trap 'trash "$tmp"' EXIT
    run() { env -u WAYLAND_DISPLAY SDL_VIDEODRIVER=x11 xvfb-run -a -s "-screen 0 1280x1024x24" "$W/syncscribble/Debug/Write" "$@"; }
    # convert the upstream tests: runAll records each test as a trace (and must still pass)
    mkdir "$tmp/rec" "$tmp/replay"
    out=$(cd "$W/syncscribble" && WRITE_RECORD_DIR="$tmp/rec" run --test 2>&1) || true
    # runAll leaves *_out.html and thumbnail PNGs next to the refs when thumbnails differ
    trash "$W"/scribbletest/test*_out.html "$W"/scribbletest/test*_{out,ref,diff}.png 2>/dev/null || true
    grep -q "with 0 failed tests" <<<"$out" || { echo "$out" >&2; exit 1; }
    for trace in "$tmp"/rec/test*.trace; do
      n=$(basename "$trace" .trace)
      mkdir -p "$F/upstream-$n"
      cp "$trace" "$F/upstream-$n/trace.txt"
      if [ -f "$W/scribbletest/${n}_in.html" ]; then cp "$W/scribbletest/${n}_in.html" "$F/upstream-$n/input.html"; fi
    done
    # replay every case; upstream-test<N> cases are also compared with Write's test<N>_ref.html
    (cd "$W/syncscribble" && WRITE_REPLAY_DIR="$F" WRITE_REPLAY_TMP="$tmp/replay" run --replaytest)

# Rewrites docs/specs/ui/screenshots: the library, New Notebook, New Note and editor
# screens of the deployment at 1366 × 1024, for review against the mockups.
screenshots: web-deploy
    cd hosts/web && bun e2e/screenshots.ts
