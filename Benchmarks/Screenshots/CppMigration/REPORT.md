> Configuration update: the app now defaults to full-resolution C++ analysis, as requested. The sampled timing comparison below is historical and does not describe the current default. A fresh full-resolution run (`fullres-default.json`) verified analysisScale=1 for every pair and byte-identical PNG outputs across all four groups; 14 Release tests passed.

# Ekibun native C++ migration — 2026-11-05

The default Ekibun engine now calls the upstream phase+diff C++ computation through a C ABI and pinned OpenCV 4.13.0. Swift only adapts inputs/results. Other engines and the menu remain unchanged.

## Performance

One local macOS run per configuration, same 13 HEIC screenshots / four groups. Analysis only; excludes decoding, composition and PNG encoding. These are desktop measurements, not iPhone timings. Numbers are not a statistical benchmark.

| Group | Swift Debug ms | C++ Debug ms | Swift Release ms | C++ Release ms |
| --- | ---: | ---: | ---: | ---: |
| 1 | 19345.3 | 92.3 | 215.0 | 38.1 |
| 2 | 20651.1 | 105.6 | 228.6 | 39.8 |
| 3 | 6622.8 | 42.2 | 73.1 | 14.1 |
| 4 | 13177.2 | 93.5 | 158.3 | 26.3 |

Like-for-like Release analysis is approximately 5.2–6.0 times faster. Both production adapters use a 1024-pixel longest-side analysis budget. The original C++ core is unchanged: sampling happens separately in the host adapter, with offset refinement and overlap validation on original pixels. The common compositor still exports original resolution.

An initial full-resolution C++ experiment was slower than sampled Swift Release (358–1325 ms per group). Its measurements are retained as `cpp-fullres-*.json`; those are not the default path. `EkibunEngine(maximumAnalysisDimension: 0)` keeps that path available for comparison. No claim is made that merely changing language guarantees a speedup.

## Output parity and limits

All four final PNG files are byte-identical across Swift Debug/Release and C++ Debug/Release. Offsets and acceptance decisions are unchanged: 8 of 9 adjacent pairs accepted; group 1's final pair remains unmatched and is retained whole. This migration improves execution time, not the known unmatched case or universal tolerance to popups.

| Group | Output dimensions | Accepted vertical offsets | Output PNG SHA-256 |
| --- | --- | --- | --- |
| 1 | 1206×7762 | 1054, 1464, unmatched | b76eb7adfe216efc247c7ea4b5ccc154f700b15eb61b5bbadd187e2ec9249ed7 |
| 2 | 1206×6392 | 1225, 1462, 1083 | e6f3e9acaccf89646586e95938d5724fefd9a92a0458d17c568a064a6bdb5af6 |
| 3 | 1206×4074 | 1452 | 81e3a150d1428daf8e9dbda21de77b469d4d7d706b89c8b30e827665bca93b90 |
| 4 | 1206×5091 | 1541, 928 | 573e88cfb56f72065b29df7838b6962dc8b33deee6a442c040c51c96d81f924e |

## Validation and reproduction

- iPhone 17: signed Release build succeeded, installed and launched successfully. Local built app size approximately 3.7 MB; no on-device performance measurement was taken.
- SwiftPM Debug and Release: 8 shared tests and 6 native tests passed, including raw C++ translations, immutable inputs, invalid arguments, large wrapped shifts, sampled/original coordinate mapping, and nonduplicate flat frames.
- iOS Simulator: both `PortedImageStitcherTests` passed, covering all four engines' duplicate export and native Ekibun translation with exact original-pixel PNG export.
- Source: `Packages/StitchingKit/Sources/EkibunNative/stitch.cpp`; host policy in adjacent `ScreenshotAlignment.cpp`; dependency and license details in `Ports/Ekibun/README.md`.
- Build: `swift build -c release --package-path Packages/StitchingKit --scratch-path build/swift-native`.
- Run: `build/swift-native/release/stitch-benchmark --engine ekibun --input LocalTestData/Screenshots --output build/ekibun-migration/cpp-release`.

Detailed native results with input hashes and diagnostics accompany this report. Local PNGs and HTML are under `build/ekibun-migration/` and are not committed.
