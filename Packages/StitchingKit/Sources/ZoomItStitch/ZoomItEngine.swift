import Foundation
import StitchingCore

/// Adapter of Microsoft's Zoomit-Mac matcher for discrete ordered screenshots.
public struct ZoomItEngine: ScreenshotStitchingEngine {
    public let id = "zoomit"
    public init() {}

    public func analyze(_ images: [RasterImage]) throws -> StitchPlan {
        guard let first = images.first else {
            return StitchPlan(engineID: id, bounds: [], alignments: [])
        }
        guard images.allSatisfy({ $0.width == first.width && $0.height == first.height }) else {
            throw StitchError.incompatibleDimensions
        }
        let w = first.width, h = first.height
        let frames = images.map { PanoramaStitcher.Frame(width: $0.width, height: $0.height, pixels: $0.pixels) }
        var bounds = images.map { FrameBounds(top: 0, bottom: $0.height) }
        var alignments: [PairAlignment] = []
        guard frames.count > 1 else { return StitchPlan(engineID: id, bounds: bounds, alignments: []) }
        var previous = PanoramaStitcher.luma(frames[0])
        for i in 1..<frames.count {
            let current = PanoramaStitcher.luma(frames[i])
            defer { previous = current }
            if PanoramaStitcher.isNearDuplicate(frames[i - 1], frames[i]) {
                alignments.append(PairAlignment(confidence: 1, status: .duplicate,
                                                diagnostic: "ZoomIt near-duplicate and informative-motion guards"))
                continue
            }
            guard w >= 32, h >= 32 else {
                alignments.append(PairAlignment(status: .unmatched, diagnostic: "Insufficient image dimensions"))
                continue
            }
            let top = PanoramaStitcher.stationaryTopRows(previous, current, w, h)
            let bottom = PanoramaStitcher.stationaryBottomRows(previous, current, w, h)
            // Preserve the upstream search path and resolution. Sparse manual
            // screenshots can fail its capture-oriented range/overlap guards;
            // expose that failure instead of substituting another matcher.
            guard let shift = PanoramaStitcher.findShift(prevLuma: previous, curLuma: current,
                    w: w, h: h, expected: nil, axis: nil) else {
                alignments.append(PairAlignment(status: .unmatched,
                    diagnostic: "ZoomIt upstream original-resolution findShift returned nil"))
                continue
            }
            let residual = PanoramaStitcher.sad(prev: previous, cur: current, w: w, h: h,
                dx: shift.dx, dy: shift.dy, step: 2,
                ignoreTopRows: top, ignoreBottomRows: bottom).score
            let best = (dx: shift.dx, dy: shift.dy, score: residual)
            if best.dy != 0 {
                for j in [i - 1, i] {
                    bounds[j] = FrameBounds(top: max(bounds[j].top, top), bottom: min(bounds[j].bottom, h - bottom))
                }
            }
            alignments.append(PairAlignment(offsetX: best.dx, offsetY: best.dy,
                confidence: max(0, min(1, 1 - best.score / 32)), status: .matched,
                diagnostic: "ZoomIt upstream original-resolution findShift, SAD=\(String(format: "%.3f", best.score)), static=\(top)/\(bottom)"))
        }
        return StitchPlan(engineID: id, bounds: bounds, alignments: alignments,
            notes: ["Microsoft Zoomit-Mac design port; independent adjacent pairs, no capture-frame dropping or momentum assumptions.",
                    "Stationary header/footer row masks; Windows five-frame fixed-overlay mask is not ported."])
    }
}
