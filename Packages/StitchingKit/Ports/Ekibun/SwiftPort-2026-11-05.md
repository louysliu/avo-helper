# Ekibun phase correlation port

Upstream: https://github.com/ekibun/Stitch
Pinned commit: `07c61d250824cddcaa84af38042334efe2ad0070`.
Source: `app/src/main/jni/stitch.cpp`, specifically `phaseCorrelateNative`, and
`app/src/main/java/soko/ekibun/stitch/Stitch.kt`, `combine(homo=false, diff=true)`.
Exact source snapshots accompany this file. Upstream LICENSE is LGPL 2.1; the
license text is retained in LICENSE. Swift port modifications: 2026-11-05.

This implements one real, selectable upstream algorithm, **phase correlation
with difference masking**. It is not the SIFT/FLANN/RHO homography mode. The
source calls its SIFT variable `surf`, but the actual implementation is SIFT.

## Retained processing

1. The 3x3 eight-neighbor Laplacian with center -8, unsigned saturation,
   reflect-101 boundary behavior, separately on RGB channels.
2. Absolute difference of both filtered images, bitwise AND of that difference
   into each filtered image to suppress stationary screen elements.
3. RGB-to-gray coefficients, Fourier transforms, normalized cross-power
   spectrum, inverse transform and peak detection.
4. Translation maps next-image coordinates into previous-image coordinates.
   Input order is retained and no frame is silently removed.

## Explicit adaptations

- Native Swift radix-2 FFT avoids a large OpenCV binary dependency. Zero padding
  uses powers of two rather than OpenCV's optimal 2/3/5-factor DFT dimensions.
- For bounded memory and latency, images are sampled at an integer stride so the
  longest analysis side is at most 1024 pixels. Filtering is on that sampled
  RGB grid. This differs from upstream full-resolution filtering.
- OpenCV's 5x5 weighted subpixel centroid is replaced by the integer peak and a
  local original-resolution RGB-error refinement of +/- one sampling stride.
- Periodically equivalent FFT shifts are compared using overlap RGB error;
  this resolves the ambiguity when displacement exceeds half the FFT extent.
- Upstream accepts essentially any phase result. This port rejects weak peaks
  (<0.025), RGB error >=32, or overlap under 25% width / 5% height (minimum 8px).
  Confidence is a heuristic, not calibrated probability. Exact duplicates are
  detected before filtering; nonzero-error zero shifts are rejected.
- Same dimensions are required; differing inputs produce an explicit unmatched
  pair. No Android crop-padding emulation is needed with the current API.
- Bounds remain the full frame, as upstream has user-controlled cropping and no
  automatic sticky-header/footer detector. Difference masking suppresses static
  elements during alignment but does NOT remove them from exported imagery.
- Android interactive positioning, gradient blending, rotation, scale and map
  homographies are outside this translation-only engine. Composition belongs
  to the host. The UI should identify this as “Ekibun phase correlation”.

For the additional homography mode, a faithful integration would require an
OpenCV 4.x XCFramework with core, imgproc, features2d, flann and calib3d for both
iOS and macOS, a C ABI wrapper, and a transform-capable composition contract.
No OpenCV installation was available at `/opt/homebrew/opt/opencv` when ported.

## Verification

`verify.swift` tests exact translations +31, +90, +150 (periodic ambiguity),
-50, empty input, duplicates and unrelated input. All passed using an optimized
engine compiled with `swiftc` on macOS. Build the StitchingCore and EkibunStitch
modules and dynamic libraries into a temporary directory, then compile
verify.swift with `-I`, `-L`, `-lStitchingCore`, `-lEkibunStitch` and that directory
as linker rpath. Use `-module-cache-path /tmp/ekibun-verify/cache` if the default
Clang module cache is sandbox-restricted. Dataset performance and visual quality
are measured by the host's shared HEIC benchmark, not by these synthetic checks.

Expected limitations include very small overlap, large dynamic UI changes,
repeated patterns, scaling/rotation, and static bars in composition. This is a
scoped algorithm port with documented numerical differences, not a claim of
bit-for-bit equivalence to OpenCV or of upstream's complete feature set.

## Upstream default-mode verification

At the pinned commit, `app/src/main/res/layout/activity_edit.xml:107-113`
initializes `switch_diff` with `android:checked="true"`.
`activity_edit.xml:116-122` defines `switch_homography` without a checked
attribute (Android CheckBox defaults false). `EditActivity.kt:610-614` passes
these checkbox values directly to `stitch`, which calls `Stitch.combine` at
line 416. `EditActivity.kt:151` initializes the selected tab to AUTO.
Therefore **phase correlation with diff=true is the upstream initial automatic
mode**, not an arbitrary alternate algorithm. The optional homography toggle is
labelled “Feature match” (`res/values/strings.xml:26`); upstream does not name it
“map mode”, though README advertises map stitching among overall capabilities.

## Initial supplied-dataset audit

The shared benchmark's original `result.json` files and previews were reviewed
without parameter changes. Analysis times were approximately 460, 625, 103 and
211 ms for groups 1–4 respectively (single run, not statistical estimates).
All nine pair records are present: eight matched, one explicitly unmatched.
Translations: group 1 +1054/+1464/unmatched; group 2 +1225/+1462/+1083;
group 3 +1452; group 4 +1541/+928. All horizontal displacements are zero.
Output heights 7762/6392/4074/5091 equal first-frame height 2622 plus matched
vertical shifts, with one complete 2622px frame appended for the unmatched pair.

Visual review of all seam crops and all group previews found no obvious split
text or duplicated content at the eight matched seams. Groups 2–4 show a
coherent order page. Group 1's last join visibly repeats the fixed status/header
and bottom toolbar because it is an explicit full-frame append. The last two
input thumbnails have no identifiable shared scrolling content beyond partial
card edges, so a reliable content translation is not established by this audit.
It should remain reported as an incomplete stitch, not a successful seamless
output. Group 2's second match has low confidence (~0.070) despite a plausible
visible join; confidence is heuristic. This visual audit is not pixel-accurate
ground truth and does not prove every retained field or boundary correct.
