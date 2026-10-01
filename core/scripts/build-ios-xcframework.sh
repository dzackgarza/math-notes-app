#!/usr/bin/env bash
# Builds libInkEngine.a for iOS device and simulator (arm64, iOS 18.0) and
# bundles them as build/InkEngine.xcframework.
# Follows CMake cmake-toolchains(7) "Cross Compiling for iOS" and Apple
# "Creating a multiplatform binary framework bundle".
# Usage: build-ios-xcframework.sh <skia-dir> <vcpkg-root>
set -euo pipefail

skia_dir=$1
vcpkg_root=$2
root=$(cd "$(dirname "$0")/../.." && pwd)
out=$root/build

libraries=()
for target in device simulator; do
  case $target in
    device) sysroot=iphoneos; triplet=arm64-ios ;;
    simulator) sysroot=iphonesimulator; triplet=arm64-ios-simulator ;;
  esac
  dir=$out/ios-$target
  cmake -S "$root/core" -B "$dir" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_OSX_SYSROOT=$sysroot \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=18.0 \
    -DCMAKE_TOOLCHAIN_FILE="$vcpkg_root/scripts/buildsystems/vcpkg.cmake" \
    -DVCPKG_TARGET_TRIPLET=$triplet \
    -DSKIA_SOURCE_DIR="$skia_dir"
  cmake --build "$dir" --target ink

  skia_archives=("$skia_dir/out/$target"/*.a)
  archives=("$dir/libink.a" "$dir/vcpkg_installed/$triplet/lib/libpugixml.a" "${skia_archives[@]}")
  libtool -static -o "$dir/libInkEngine.a" "${archives[@]}"

  arch=$(lipo -info "$dir/libInkEngine.a")
  echo "$arch"
  [[ $arch == *"architecture: arm64" ]]
  # Every object must target iOS 18.0.
  minos=$(otool -l "$dir/libInkEngine.a" | awk '$1 == "minos" { print $2 }' | sort -u)
  echo "$target minos: $minos"
  test "$minos" = 18.0
  libraries+=(-library "$dir/libInkEngine.a" -headers "$out/headers")
done

mkdir -p "$out/headers/InkEngine"
cp "$root/core/include/ink.h" "$root/core/modulemap/module.modulemap" "$out/headers/InkEngine/"
xcodebuild -create-xcframework "${libraries[@]}" -output "$out/InkEngine.xcframework"
