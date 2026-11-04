# LongStitch Swift port

Upstream: [1003129155/jietuba](https://github.com/1003129155/jietuba), branch `master2`, commit **5eb635bd88eab96c1a3bd4273478ce15e161541b** (2026-10-31). MIT © 2025 JYAARU; complete notice in LICENSE. Reference source retained in `upstream/{hash,lcs,session,stitch}.rs` and retrieved with the GitHub connector. Swift code is a translation/adaptation of the session matcher, not the simpler two-image coarse hash entry point.

## Retained decisions

* Exact 64-bit rotate/XOR/multiply row fingerprint over little-endian RGBA words, and quantized mean RGB hash with the original constants. Rightmost 10% excluded, original resolution preserved.
* Maximal common runs, 1% minimum run, deterministic ordering (length descending, previous start descending, next start ascending), over-half range suppression and 32 candidates.
* Eight unique-row credibility gate, adaptive exact-hash threshold, two-unique-row/quarter-frame weak-exact fallback; coarse matching never uses the weak fallback.
* Last nonzero scroll direction preference with the original five-times-length bound. Initial direction unknown.
* Exact unchanged edges, fixed-edge rejection when the edges occupy half the frame, settled-bar retry for content loading in place.
* Brightness profiles in eight-pixel bins; at most 256 informative sample rows; flatness 2/channel; mean channel difference 2; 75% verification; quarter-frame minimum overlap, eight matched rows and 50% agreement for fallback; distant rival and search boundary rejection.
* Upstream behavior retaining a hash candidate when similarity verification fails and no better similar placement exists is retained. Confidence numbers are path labels, not probability estimates.

## Explicit pair-contract adaptations

`LongStitchEngine.analyze` returns original-coordinate vertical offsets between adjacent source frames. It applies session matching to the previous source frame rather than a growing mosaic. Thus the session near/full-result search collapses to the preceding image. Long rollback with no adjacent overlap is **unmatched**, even if an earlier frame could locate it in the Rust session. No frame is silently omitted.

Fixed bars become per-frame bounds, accumulated from adjacent pair observations. The shared compositor decides seams and outer-header/footer retention. Rust `commit`'s edge replacement, lazy-load refresh, and local-hover-aware exact seam choice are not encoded by this contract. A zero displacement is reported as duplicate only when all input pixels are equal. Otherwise the adapter explicitly returns unmatched: upstream may refresh loaded/changed content at that position, but the pair contract cannot encode that replacement. This safety check avoids silently dropping different scrolling screens when an unchanged header produces the upstream zero-shift match; it does not claim to recover the correct offset. Horizontal motion is unsupported, as in this vertical matcher.

The source application's user-configurable ignore parameters are fixed here: no extra right/top pixel exclusion, right 10% floor, previous-frame top ratio 15% (5% after upward movement), bottom ratio 0%, minimum overlap ratio 1%. These are general defaults, never selected per test dataset. Rust's rayon parallelism is replaced by serial Swift loops. Arrays retain precomputed profiles for the two current images; there is no opaque imaging dependency.

## Validation

Validated with optimized macOS `swiftc`: all five cases PASS (down `[30,30]`, up `[-30,-30]`, duplicate `[0]`, fixed-header `[30]`, unrelated unmatched).

`Ports/LongStitch/Smoke.swift` is a standalone synthetic harness (compile alongside Contracts.swift and engine source, removing its StitchingCore import in a temporary copy). It checks distinct-row downward translation, upward translation, exact duplicates, fixed bars, and unrelated non-overlap. Real HEIC benchmark results are generated separately by the application's shared benchmark harness; synthetic passing is not evidence that all HEIC sets match.

## Real-data zero-shift parity audit

The initial HEIC group 2 run located all three pairs at zero displacement from unchanged header content. This was reproduced with the **unmodified pinned Rust session**, not just the Swift adapter: all four full-resolution 1206×2622 frames returned `top: 0`, and frames 2–4 returned `keep: 2622, skip: 2622`, so upstream also left the mosaic at one screen. The first acceptance is the exact run `(393,393,169)`. The detailed run trace is `parity/group2-session.txt`. Input hashes are recorded in the benchmark's group-2 JSON.

The adapter's previous `dy == 0 -> duplicate` classification was a separate integration bug and is fixed: differing RGBA input at a zero-shift match now returns **unmatched**. No thresholds were changed to force this dataset to succeed. Added synthetic regression: a stationary frame with a changed central region must not be silently discarded as a duplicate (all six smoke checks pass).

Reproduce exact Rust session behavior with the small `parity` Cargo binary (the four original modules are referenced directly, not rewritten). Arguments are width, height, then top-down opaque RGBA8 files:

```sh
cargo run --release --locked --manifest-path Packages/StitchingKit/Ports/LongStitch/parity/Cargo.toml -- 1206 2622 /tmp/2-1.rgba /tmp/2-2.rgba /tmp/2-3.rgba /tmp/2-4.rgba
```

The harness converts RGBA to upstream BGRA input, supplies no heading hint, top exclusion 0.15, bottom exclusion 0, right extra exclusion 0, and minimum overlap 0.01. The Rust library is a verification-only dependency, not shipped in the iOS application. Lockfile pins verification dependencies.
