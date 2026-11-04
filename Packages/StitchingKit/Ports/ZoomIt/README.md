# ZoomIt screenshot matcher

## Provenance

This is a direct integration of Microsoft's Swift Zoomit-Mac matcher, not a
new matcher carrying the ZoomIt name:

- Repository: https://github.com/microsoft/Zoomit-Mac
- Pinned commit: `45e15ac00c578fa9b6ca68d5e474b01dbc5d50ef`
- Source Git blob: `465920bb7d522711c25199f1ad8e356cf171c8b7`
- Permanent source: https://github.com/microsoft/Zoomit-Mac/blob/45e15ac00c578fa9b6ca68d5e474b01dbc5d50ef/Sources/ZoomItMacCore/Capture/PanoramaStitcher.swift
- License: MIT, Copyright (c) 2026 Microsoft Corporation; see `LICENSE`.
- Exact reference source: `PanoramaStitcher.upstream.swift.txt`.

Upstream describes itself as a Swift port of the **design** of Windows ZoomIt's
`PanoramaCapture.cpp`. This integration represents that Microsoft Mac design
port, not a complete line-for-line port of the Windows C++ engine.

## Retained implementation

`PanoramaMatcher.swift` preserves upstream code through the end of `findShift`.
Only the enum's visibility and attribution header differ in this retained
section. Capture/composition functions are excluded from compilation.

Retained functionality includes integer Rec.601 luma (Accelerate with scalar
fallback), edge density, NCC1D primitives, pixel SAD, informative-edge scoring
for sparse text, duplicate/small-motion checks, global axis scanning to avoid
repetitive text harmonics, local refinement, and stationary top/bottom rows.
Foundation and Accelerate are the only platform imports.

**The pinned upstream retains NCC helpers but `findShift` actually uses global
informative-pixel SAD scanning.** The adapter follows that exact active path;
it does not activate dormant NCC helpers or substitute a fallback matcher.

## Adapter contract

`ZoomItEngine.analyze` returns N bounds and N-1 adjacent alignments. It does not
silently drop inputs. Near duplicates and unsupported pairs receive explicit
`.duplicate` / `.unmatched` statuses. Dimensions must agree. Every offset uses
original source pixels under the shared contract.

- Each adjacent pair independently invokes upstream `findShift` on original
  luma resolution, with `expected: nil` and `axis: nil`. There is no external
  downsampling, extra refinement, changed threshold, or extra acceptance gate.
- Capture-only warm-up dropping, cumulative-origin rebasing, direction locking,
  momentum, median-speed spike rejection, inferred skipped-frame displacement,
  and capture-progress filtering are outside the adjacent-pair adapter. They
  assume a continuous capture cadence unavailable for manually selected images.
- Stationary top/footer rows on matched vertical pairs become frame bounds.
  This is the Mac row-mask heuristic. The shared compositor owns presentation.
- Reported confidence is `clamp(1 - SAD / 32)` for display only; it does not
  accept/reject or modify upstream offsets. It is not calibrated probability.
- Negative or otherwise poor upstream shifts remain visible in the raw plan;
  shared composition is responsible for deciding whether it can use the plan.

## Explicit non-ports and limitations

The Windows dynamic five-composed-frame fixed-overlay mask, Win32 capture/UI,
capture scheduling, original Windows compositor, and upstream Mac gap-repair
and feather compositor are not integrated. We do **not** claim the Windows
five-frame mask is present. Multi-frame Mac header/footer helpers remain in the
reference-derived source, but the adapter uses pairwise stationary masks.

The original search is capture-oriented: without a detected top overlay,
`axisScan` searches up to three quarters of the smaller image dimension.
Stationary-row detection is sensitive to resolution and texture. Large gaps
between manually selected screenshots can therefore return no match. Original
SAD overlap guards are preserved, including their sampled-count versus area
comparison. No fixes or dataset-specific thresholds are applied to improve
benchmark acceptance. Blank/repetitive content remains ambiguous; an accepted
match is not proof of visually correct stitching. The independent-noise probe
can also return a match under unchanged upstream acceptance logic.

Offsets are axis-aligned. Perspective, zoom, arbitrary camera motion, animated
content, and large perpendicular drift are unsupported. No third-party binary
runtime or network call is required.

## Validation

`sh Packages/StitchingKit/Ports/ZoomIt/run-regressions.sh` runs optimized macOS
checks for forward/reverse offsets, unequal adjacent steps, duplicate status,
stationary header, unrelated-noise probe cardinality, empty/single inputs, and an
original-resolution 443-pixel displacement. The module also compiled for
arm64 iOS 17 simulator; this is compilation, not device runtime validation.

The nine real HEIC adjacent pairs were decoded to full-resolution PNGs and run
through an independently compiled, **unmodified reference source**. The final
adapter's upstream matcher agrees on all nine results:

| Group | Original upstream displacements | Final adapter displacements |
| --- | --- | --- |
| 1 | unmatched, unmatched, unmatched | unmatched, unmatched, unmatched |
| 2 | unmatched, unmatched, unmatched | unmatched, unmatched, unmatched |
| 3 | +382 | +382 |
| 4 | +695, +906 | +695, +906 |

These are alignment acceptance/parity results, not a claim of visual success.
The shared benchmark records rendering and visual review separately. The
source reference `.txt` and standalone regression sources are not part of the
shipping target.
