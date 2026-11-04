# hypr-longshot Swift / OpenCV port

Source: https://github.com/Horizon0427/hypr-longshot
Pinned revision: `f0bcd63cca4e8309de78395bfa28262f012f5f6a` (MIT, see LICENSE).
`stitcher.py` is the unmodified source snapshot. Runtime code lives in
`Packages/VideoStitchingKit/Sources/HyprLongshotVideo` and `HyprPhaseCorrelation`.

The bridge calls the original `cv::createHanningWindow` and `cv::phaseCorrelate`
from OpenCV 4.13.0 (`https://github.com/yeatse/opencv-spm.git`, exact version).
It is not a hand-written phase-correlation substitute. Reader and PNG writer are
shared platform adapters supplied by VideoStitchingCore.

Preserved: approximately 10 fps sampling; six-frame calibration;
mean adjacent grayscale row difference threshold 1.5; minimum active height 30%;
central 50% matching crop; float32 Hanning window; dy = -rawDy; response >= .20;
minimum forward movement 5 px; only new bottom strips appended on valid matches;
fixed bottom chrome omitted and first top chrome retained.

Intentional corrections/deviations:
- Preserve full input dimensions: upstream's fixed 10 px crop assumes a Linux overlay border that iOS recordings do not guarantee. All four input edges are retained before sticky-region handling.
- Replay all six calibration frames. Upstream initializes output from frame zero
  but matching from frame five, silently losing initial scrolling content.
- AVAssetReader uses timestamps for ~10 fps sampling, honors preferredTransform,
  and yields RGBA. Integer RGB luminance approximation differs by at most about
  one gray level from OpenCV conversion.
- No aging refresh after 30 failures: each low-confidence, reverse, horizontal,
  or excessively large displacement produces a separate saved fragment and an
  explicit partial-result warning. Reverse content may repeat, but is preserved.
- Reject shifts at/above half the active height because FFT shifts wrap. Horizontal
  tolerance is max(3 px, 20% of vertical shift). Static identical frames are
  detected before correlation, including textureless frames.
- Small forward motion retains the reference so it accumulates to 5 px.
- Pixel/memory budget splits preserve the current viewport (overlap is explicit).
  The request pixel limit also bounds total emitted pixels across all images.
  At most 128 fragments and min(working-memory budget, 256 MB) encoded output
  are saved per run. A conservative pre-encode byte reserve plus actual file-size
  checks bound disk use; reaching a cap stops reading, returns saved images as
  partial, and explicitly reports unprocessed remaining video.
  Frame/FFT/encoder scratch is conservatively
  reserved before calibration; cancellation is checked between sampled frames.
- C++ exceptions are caught at the C ABI boundary and surfaced as errors.

Limits: a sampled-video stitcher cannot recover content never visible in sampled
frames. Repeating patterns and animated UI can produce plausible but incorrect
phase matches. A partial result explicitly does not claim continuous coverage.
Discarded detected fixed bottom chrome remains intentional; the fixed 10 px crop is removed.
