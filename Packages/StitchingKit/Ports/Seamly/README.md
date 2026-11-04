# Seamly StitchKit local port

Source: [LiLiKazine/Seamly.app](https://github.com/LiLiKazine/Seamly.app/tree/ed371adfc13151f95c95b6e3e8e3ff8790075d8d/Seamly/StitchKit), commit `ed371adfc13151f95c95b6e3e8e3ff8790075d8d`, fetched through the GitHub connector.

## License status

The upstream README's License section says **TBD** at this revision. No permissive license is assumed or granted by this port. This is a local experimental implementation requested for evaluation; distribution and publication require resolving upstream permission. Attribution remains with LiLiKazine / Seamly contributors. The added attribution headers do not replace or grant a license.

## Actual extracted implementation

`Sources/SeamlyStitch/Upstream` contains the upstream Swift sources for VerticalProfile, FrameProfile, OffsetMatcher, Match, ChromeStaticRowDetector, ChromeDomain, BatchStitcher, StitchSession and Compositor. Algorithm bodies and default constants are unchanged. Two unused imports (ImageIO and UniformTypeIdentifiers) were removed from Compositor; attribution headers were added. These files compile using Foundation, CoreGraphics and Accelerate on the package's iOS 17 / macOS 14 deployment floor; no upstream SwiftUI/iOS 26 interface was copied.

The adapter runs upstream BatchStitcher's input-order policy. Its 64-column BT.601 luminance signatures have at most 640 rows; matching includes the variance-weighted MAD and current offline tile-consensus scorer, independent plain/static-masked matches, directional edge gates, per-keyframe top/bottom chrome measurements (static baseline plus translation-residual evidence), and full-height ±16-pixel local seam refinement. The scorer and chrome constants remain the upstream defaults, with no local dataset-specific adjustment.

The contract preserves every input in its supplied order. Rejected edges become explicit unmatched pairs. Exact RGBA duplicates are identified by the adapter and retained as duplicate pairs. Dimension changes split independent same-dimension runs and are explicit unmatched boundaries. Vertical offsets remain original-image coordinates; chrome bounds do not get subtracted from offsets. Upstream horizontal displacement is diagnostic only, as in upstream composition; output offsetX stays zero. Reported confidence is the upstream provisional seam confidence, while the diagnostic flags failed/low-confidence refinement.

## Not activated by the adapter

Automatic order recovery and its component-chain joining remain in the extracted source but are not used because the shared contract requires adjacent input pairs. Upstream raster/PDF composition remains in its source to preserve BatchStitcher's dependencies, but the application uses the shared composer. ReplayKit capture, video selection, session file storage, repair/editor UI, export UI, and live keyframe selection were not ported. The adapter does not remove near-duplicate frames or infer an alternative order.

## Validation

The standalone `Smoke.swift` probes translated content, duplicate input, disconnected frames, mixed dimensions, and empty input. Build it together with the extracted files and a compiled StitchingCore module, or integrate it into the package's test harness. Synthetic correctness does not establish quality on real screenshots; benchmark and visually inspect all four local HEIC sets through the main package benchmark.

Local validation: isolated macOS Swift module compilation and arm64 iOS 17 deployment-target typechecking passed; the optimized standalone smoke executable passed all five scenarios and recovered the exact 117-pixel translation. `git diff --check` passed. Full package/HEIC benchmark integration is owned by the main harness.

### Real HEIC adapter parity check

`RealProbe.swift` was compiled against the extracted sources and run outside the sandbox (required for HEIC decoding in this environment) on all 13 local screenshots. Direct HEIC profiles and full-size RGBA round-trip profiles had exactly zero mean absolute difference on every image. Calling upstream planning/refinement independently reproduced the adapter's offsets and breaks:

| Group | Refined accepted offsets | Breaks after input index (zero-based) |
| --- | --- | --- |
| 1 | 1054, 1463, 1623 | none |
| 2 | 1225 | 1, 2 |
| 3 | none | 0 |
| 4 | none | 0, 1 |

Every rejected adjacent pair selected only one profile row of forward motion (and also one row in reverse). Upstream's `minEdgeDy = 2` rejects those candidates even when their confidence is high; their forward/reverse cost ratios were approximately 1. Group 1's second seam retains a low-confidence-refinement flag and provisional 1463-pixel offset. These checks establish adapter parity, not visual correctness of the upstream matches. No parameters were adjusted for these datasets.
