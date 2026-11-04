#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
# Homebrew Rust includes rust-src; build-std makes iOS targets without installing another toolchain.
export RUSTC_BOOTSTRAP=1
for target in aarch64-apple-darwin aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios; do
 cargo build --locked --release -Z build-std=std,panic_unwind --target "$target"
done
mkdir -p target/simulator-universal
lipo -create target/aarch64-apple-ios-sim/release/liblong_screen_bridge.a target/x86_64-apple-ios/release/liblong_screen_bridge.a -output target/simulator-universal/liblong_screen_bridge.a
rm -rf LongScreenBridge.xcframework
xcodebuild -create-xcframework -library target/aarch64-apple-darwin/release/liblong_screen_bridge.a -headers include -library target/aarch64-apple-ios/release/liblong_screen_bridge.a -headers include -library target/simulator-universal/liblong_screen_bridge.a -headers include -output LongScreenBridge.xcframework
