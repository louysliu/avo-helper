# Ekibun C++ / OpenCV integration

The production engine now calls the **original C++ phase-correlation algorithm**, not the former Swift FFT reimplementation.

## Compiled code

* `Sources/EkibunNative/stitch.cpp`: the upstream `phaseCorrelateNative` computational body; Android `JNIEnv`/`Bitmap` plumbing is replaced by a checked C ABI receiving borrowed RGBA8 buffers.
* `Sources/EkibunNative/ScreenshotAlignment.cpp`: host acceptance policy and periodic-shift disambiguation, kept separate from the upstream function.
* `Sources/EkibunNative/include/EkibunNative.h`: plain C interface; exceptions and OpenCV types do not cross into Swift.
* `Sources/EkibunStitch/EkibunEngine.swift`: only converts the C result to the shared `StitchPlan` contract.

The upstream `filter2D(CV_8U)` kernel, `absdiff`, `bitwise_and`, `COLOR_RGBA2GRAY`, `CV_64F` conversion, and `phaseCorrelate(next, previous)` execute unchanged in C++/OpenCV on the supplied analysis buffers. No Swift FFT, power-of-two replacement or rewritten peak detector remains. OpenCV supplies its own optimal DFT sizes and weighted subpixel peak. Asking for its correlation response adds diagnostics without changing the shift.

Input buffers remain owned by Swift for the duration of the synchronous call. The C++ matrices borrow them read-only; intermediate outputs are independent. Native exceptions are caught and returned as errors. Each adjacent pair releases its intermediate matrices before the next pair starts. No OpenCV global threading settings are mutated.

## App-level policy, separate from upstream

Upstream accepts essentially any finite phase result; the app retains a conservative wrapper:

* The app defaults to full-resolution analysis (`EkibunEngine()` / `maximumAnalysisDimension: 0`), with no downsampling. A positive analysis limit remains opt-in for benchmark comparisons only; the raw C phase function never resizes.
* Exact byte equality is the only duplicate shortcut.
* The phase response must be at least 0.025; this is an OpenCV response, not the former custom FFT peak score or a probability.
* Periodically equivalent shifts are checked using OpenCV's actual padded DFT dimensions. This is needed when manually selected screenshots scroll by more than half the image height.
* Candidate rounding is refined by ±analysis-scale original pixels and checked against sampled RGB overlap. Minimum overlap is 25% width and 5% height, at least 8 pixels, and mean RGB difference must be below 32. Changed zero-shift frames remain unmatched.
* Failure remains explicit and preserves the source frame through the common compositor. Full-frame bounds are retained; there is no automatic chrome detector in this branch.

The raw C function is independently callable and tested, so these host policies are not presented as upstream algorithm steps. The optional upstream SIFT/FLANN/homography mode is not enabled; phase+diff is the upstream default automatic mode.

## Pinned dependencies and license

* Ekibun: `ekibun/Stitch@07c61d250824cddcaa84af38042334efe2ad0070`, `app/src/main/jni/stitch.cpp`, LGPL-2.1. Full notice is `LICENSE`; original snapshots are retained for comparison.
* OpenCV: version **4.13.0**, compiled C++ XCFramework from `yeatse/opencv-spm` exact tag `4.13.0`, package revision `151a5374946aa867ff3892e0d69fd85e1ecdaf2e`. OpenCV is Apache-2.0. This is a third-party prebuilt distribution of OpenCV, not an Apple/system framework.
* Binary SHA-256: `41fc3bf0f2af1660e24694a3e05d5c56e5869a133cea7084a7e262d54dd5b675`; SwiftPM verifies it. Version and resolution are checked into the repository. iPhone, iOS Simulator, and native macOS use slices of the same XCFramework.

The dependency is fetched during build only. Image processing remains on-device. The archive is about 200 MB across all platforms; this is not the final app size. The repository does not vendor the downloaded binary.

## Verification

Run `swift test --package-path Packages/StitchingKit -c release` for shared tests and native boundary tests: pinned OpenCV version, known translation with both diff modes, analysis-to-original coordinate mapping, input immutability, invalid arguments, wrapped large shift, and different flat frames.

Run `sh Scripts/benchmark-stitching.sh --engine ekibun` for the four supplied HEIC groups. The diagnostics include raw native translation, response and host RGB error. The previous Swift implementation and its historical benchmark assumptions are documented in [SwiftPort-2026-11-05.md](SwiftPort-2026-11-05.md); those results are not claims about this new C++ version.
