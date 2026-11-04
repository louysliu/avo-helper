# Long Screen native bridge

Original MIT core vendored unchanged from https://github.com/t41372/long-screen,
commit f04d898426a4c7204b7dc9486d1e14e1fd6f59e2 (crate 0.1.2-dev).
Copyright and license: vendor/long-screen/LICENSE. Upstream agent guidance is
preserved as vendor/UPSTREAM-AGENTS.md. The bridge is integration code, not a
replacement reconstruction algorithm.

Build `./build.sh` with Xcode and Homebrew Rust 1.99.1 (rust-src included).
Cargo.lock pins bridge dependencies. Produces macOS arm64, iOS arm64 and iOS
Simulator arm64/x86_64 static XCFramework slices. Only the `driver` feature is enabled;
no FFmpeg, browser runtime, or upstream native decoder is linked.

Swift decodes orientation-applied RGBA with AVAssetReader, reopens the decoder for each pass through C reset/next callbacks, and supplies
original timestamps to a replayable FrameSource. The
original engine performs all scan/solve/render/reveal/framing stages. Prints and
unattached fragments are exported to PNG; partial status and diagnostics remain
visible. Scratch data is removed on exit. Cancellation calls original Control
between engine progress steps, retaining whatever canvases it can export.

Accepted recordings are limited to 3 minutes to bound per-frame metadata growth.
Resource limits: each decoded frame must fit one eighth of maximumWorkingBytes; cumulative exported
pixels are capped at maximumOutputPixels. Tile cache uses one quarter of working
bytes; encoded store keeps one eighth before spilling. These are NOT a strict
process RSS cap: original algorithm metadata and transient allocations may exceed
them. At every engine progress checkpoint, spill disk is measured against maximumWorkingBytes; crossing it stops processing and reports a partial-result warning (or limit error if no image exists). Writes within an engine step can temporarily exceed this checkpoint budget. Budget-skipped canvases emit
warnings and mark output partial. Input frames are not spooled. No sampling silently drops source frames.

Host smoke test (real engine, stationary textured 128×128 RGBA sequence):
```
mkdir -p /tmp/longscreen-smoke
clang tests/smoke.c -I include LongScreenBridge.xcframework/macos-arm64/liblong_screen_bridge.a -framework Security -framework Foundation -o /tmp/longscreen-smoke/run
/tmp/longscreen-smoke/run /tmp/longscreen-smoke
```
Validated output: 128×128 PNG, `partial=false`, original diagnostic messages.
This test proves the C ABI/engine/PNG route, not real recording reconstruction quality.
