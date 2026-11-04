import Foundation
import CoreGraphics
import ImageIO
import StitchingCore

/// Diagnostic parity check; compile with Seamly sources (instead of Smoke.swift).
@main struct RealProbe {
    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        for group in 1...4 {
            let urls = try FileManager.default.contentsOfDirectory(at: root.appendingPathComponent(String(group)), includingPropertiesForKeys: nil)
                .filter { $0.pathExtension.lowercased() == "heic" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
            let rasters = try urls.map(RasterIO.load)
            let images = try rasters.map(RasterIO.cgImage)
            let profiles = images.map { VerticalProfile().profile($0) }
            let stitcher = BatchStitcher()
            let upstream = try stitcher.plan(images, strategy: .inputOrder)
            let refined = try Compositor(refinementDelta: 16).refineSeams(upstream.session) { images[$0.index] }
            let adapter = try SeamlyEngine().analyze(rasters)
            for seam in refined {
                precondition(adapter.alignments[seam.fromIndex].offsetY == seam.provisionalDy)
            }
            print("GROUP \(group): upstream breaks \(upstream.session.segmentBreaks.map(\.afterKeyframeIndex)); refined \(refined.map(\.provisionalDy))")
            for index in 0..<max(0, images.count - 1) {
                let a = profiles[index], b = profiles[index + 1]
                let f = stitcher.downwardMatch(a, b), r = stitcher.downwardMatch(b, a)
                print("pair \(index): forward dy=\(f.dy) conf=\(f.confidence) cost=\(f.cost); reverse dy=\(r.dy) conf=\(r.confidence) cost=\(r.cost); ratio=\(f.cost/r.cost)")
            }
            // Compare the direct source profile to the RGBA round-trip profile. Tiny color
            // conversion differences are possible, but a reversal would radically change rows.
            for (index, url) in urls.enumerated() {
                let source = CGImageSourceCreateWithURL(url as CFURL, nil)!
                let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: max(images[index].width, images[index].height)]
                let direct = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)!
                let directProfile = VerticalProfile().profile(direct)
                let roundtrip = profiles[index]
                var difference: Float = 0
                for row in 0..<directProfile.rowCount {
                    for col in directProfile.rows[row].indices {
                        difference += abs(directProfile.rows[row][col] - roundtrip.rows[row][col])
                    }
                }
                print("frame \(index): direct/roundtrip profile MAD=\(difference / Float(directProfile.rowCount * directProfile.rows[0].count))")
            }
        }
    }
}
