#!/bin/sh
set -eu
port_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
package_dir=$(CDPATH= cd -- "$port_dir/../.." && pwd)
build_dir=$(mktemp -d "${TMPDIR:-/tmp}/zoomit-regression.XXXXXX")
trap 'rm -rf "$build_dir"' EXIT
mkdir -p "$build_dir/cache"
xcrun swiftc -O -swift-version 5 -module-cache-path "$build_dir/cache" \
  -emit-module -emit-library -module-name StitchingCore \
  "$package_dir/Sources/StitchingCore/Contracts.swift" \
  -emit-module-path "$build_dir/StitchingCore.swiftmodule" -o "$build_dir/libStitchingCore.dylib"
xcrun swiftc -O -swift-version 5 -module-cache-path "$build_dir/cache" \
  -I "$build_dir" -L "$build_dir" -lStitchingCore \
  -emit-module -emit-library -module-name ZoomItStitch \
  "$package_dir/Sources/ZoomItStitch/"*.swift \
  -emit-module-path "$build_dir/ZoomItStitch.swiftmodule" -o "$build_dir/libZoomItStitch.dylib"
xcrun swiftc -O -swift-version 5 -module-cache-path "$build_dir/cache" \
  -I "$build_dir" -L "$build_dir" -lStitchingCore -lZoomItStitch \
  "$port_dir/Regression.swift" -o "$build_dir/regression"
DYLD_LIBRARY_PATH="$build_dir" "$build_dir/regression"
