#!/bin/sh
set -eu
repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$repo_root"
export CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/avo-stitch-clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="${TMPDIR:-/tmp}/avo-stitch-swift-cache"
swift build --package-path Packages/StitchingKit -c release --scratch-path build/swift-stitch
exec build/swift-stitch/release/stitch-benchmark \
  --input LocalTestData/Screenshots --output build/stitch-benchmark "$@"
