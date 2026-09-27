#!/usr/bin/env bash
# Builds Skia for iOS arm64 at deployment target 18.0 from JetBrains/skia at the
# commit of the wasm prebuilt. Ports JetBrains/skia-pack script/checkout.py and
# script/build.py (iOS branch), with ios_min_target 18.0, no GL, PDF on.
# Usage: build-skia-ios.sh <skia-dir> <device|simulator>
set -euo pipefail

skia_dir=$1
target=$2
commit=ab5932137bb327b627b44f15fbe34ba59d775d0e

if [ ! -d "$skia_dir/.git" ]; then
  git init -q "$skia_dir"
  git -C "$skia_dir" remote add origin https://github.com/JetBrains/skia.git
fi
git -C "$skia_dir" fetch -q --depth 1 origin "$commit"
git -C "$skia_dir" -c advice.detachedHead=false checkout -q "$commit"
cd "$skia_dir"
python3 tools/git-sync-deps
python3 bin/fetch-ninja
python3 bin/fetch-gn

args=(
  is_official_build=true
  'target_cpu="arm64"'
  'target_os="ios"'
  skia_use_metal=true
  skia_use_gl=false
  skia_enable_pdf=true
  skia_pdf_subset_harfbuzz=true
  skia_use_system_expat=false
  skia_use_system_libjpeg_turbo=false
  skia_use_system_libpng=false
  skia_use_system_libwebp=false
  skia_use_system_zlib=false
  skia_use_system_freetype2=false
  skia_enable_fontmgr_custom_embedded=true
  skia_use_system_harfbuzz=false
  skia_use_system_icu=false
  skia_use_dng_sdk=false
  skia_use_piex=false
  skia_enable_tools=false
  skia_enable_skottie=false
)
case $target in
  device) args+=('ios_min_target="18.0"') ;;
  simulator) args+=(ios_use_simulator=true 'ios_min_target="18.0"' 'extra_cflags=["-mios-simulator-version-min=18.0"]') ;;
  *) echo "target must be device or simulator" >&2; exit 2 ;;
esac

bin/gn gen "out/$target" --args="${args[*]}"
third_party/ninja/ninja -C "out/$target" skia
