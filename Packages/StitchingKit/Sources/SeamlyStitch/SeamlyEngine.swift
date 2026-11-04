import Foundation
import CoreGraphics
import StitchingCore

/// Input-order adapter for the pinned Seamly StitchKit offline pipeline.
public struct SeamlyEngine: ScreenshotStitchingEngine {
    public let id = "seamly"
    public init() {}

    public func analyze(_ images: [RasterImage]) throws -> StitchPlan {
        guard !images.isEmpty else { return StitchPlan(engineID: id, bounds: [], alignments: []) }
        // Upstream profile offsets assume equal source geometry. Keep every frame and
        // explicitly break at size changes instead of applying a misleading scale.
        if images.contains(where: { $0.width != images[0].width || $0.height != images[0].height }) {
            var bounds: [FrameBounds] = []
            var alignments: [PairAlignment] = []
            var start = 0
            while start < images.count {
                var end = start + 1
                while end < images.count, images[end].width == images[start].width,
                      images[end].height == images[start].height { end += 1 }
                let run = try analyze(Array(images[start..<end]))
                if start > 0 { alignments.append(PairAlignment(status: .unmatched, diagnostic: "Source dimensions changed")) }
                bounds += run.bounds
                alignments += run.alignments
                start = end
            }
            return StitchPlan(engineID: id, bounds: bounds, alignments: alignments)
        }
        let cgImages = try images.map(Self.cgImage)
        let plan = try BatchStitcher().plan(cgImages, strategy: .inputOrder)
        let session = plan.session
        let bounds = session.keyframes.map { keyframe -> FrameBounds in
            let chrome = session.resolvedChrome(for: keyframe).insets
            return FrameBounds(top: chrome.top, bottom: keyframe.pixelHeight - chrome.bottom)
        }
        // BatchStitcher uses ±16 source pixels for offline compositing refinement.
        let refined = try Compositor(refinementDelta: 16).refineSeams(session) { cgImages[$0.index] }
        let seams = Dictionary(uniqueKeysWithValues: refined.map { ($0.fromIndex, $0) })
        let alignments = (0..<max(0, images.count - 1)).map { index -> PairAlignment in
            if images[index].pixels == images[index + 1].pixels {
                return PairAlignment(confidence: 1, status: .duplicate, diagnostic: "Exact RGBA duplicate; input retained")
            }
            guard let seam = seams[index] else {
                return PairAlignment(status: .unmatched, diagnostic: "Seamly input-order edge gate rejected overlap")
            }
            // Upstream's horizontal component is monitoring only, not a geometry correction.
            return PairAlignment(offsetY: seam.provisionalDy, confidence: seam.confidence,
                                 status: .matched,
                                 diagnostic: "Seamly tile-consensus; full-height refinement; lowConfidence=\(seam.isLowConfidence); observedHorizontalDrift=\(seam.provisionalDx)")
        }
        return StitchPlan(engineID: id, bounds: bounds, alignments: alignments,
                          notes: ["Seamly offline defaults, input order, no frame selection; upstream license unresolved."])
    }

    private static func cgImage(_ raster: RasterImage) throws -> CGImage {
        let data = Data(raster.pixels) as CFData
        guard let provider = CGDataProvider(data: data),
              let image = CGImage(width: raster.width, height: raster.height,
                                  bitsPerComponent: 8, bitsPerPixel: 32,
                                  bytesPerRow: raster.width * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: false,
                                  intent: .defaultIntent) else { throw StitchingCore.StitchError.invalidImage }
        return image
    }
}
