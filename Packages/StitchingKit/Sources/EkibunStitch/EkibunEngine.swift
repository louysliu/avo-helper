import Foundation
import StitchingCore
import EkibunNative

/// Swift owns only the application contract. Filtering, DFT, peak detection,
/// and pixel verification execute in C++ with the pinned OpenCV binary.
public struct EkibunEngine: ScreenshotStitchingEngine {
    public let id = "ekibun"
    private let maximumAnalysisDimension: Int32
    /// Defaults to full-resolution analysis. A positive limit is opt-in for benchmarks.
    public init(maximumAnalysisDimension: Int = 0) {
        self.maximumAnalysisDimension = maximumAnalysisDimension == 0 ? 0 : Int32(max(64, min(4096, maximumAnalysisDimension)))
    }

    public func analyze(_ images: [RasterImage]) throws -> StitchPlan {
        var pairs: [PairAlignment] = []
        for i in 1..<max(1, images.count) {
            try Task.checkCancellation()
            pairs.append(align(images[i - 1], images[i]))
        }
        return StitchPlan(engineID: id,
            bounds: images.map { FrameBounds(top: 0, bottom: $0.height) }, alignments: pairs,
            notes: ["Ekibun original C++ phase correlation + OpenCV \(String(cString: ekibun_opencv_version())); analysis limit=\(maximumAnalysisDimension), original-pixel verification.",
                    "Host overlap verification and periodic-shift disambiguation; full frame bounds. Homography mode is not included."])
    }

    private func align(_ a: RasterImage, _ b: RasterImage) -> PairAlignment {
        guard a.width == b.width, a.height == b.height else {
            return PairAlignment(status: .unmatched, diagnostic: "Phase correlation requires equal dimensions")
        }
        var result = EkibunAlignment()
        var message = [CChar](repeating: 0, count: 512)
        let ok = a.pixels.withUnsafeBufferPointer { previous in
            b.pixels.withUnsafeBufferPointer { next in
                ekibun_align_screenshots(previous.baseAddress, next.baseAddress,
                    Int32(a.width), Int32(a.height), maximumAnalysisDimension, &result, &message, message.count)
            }
        }
        guard ok != 0 else {
            return PairAlignment(status: .unmatched, diagnostic: "Native failure: \(String(cString: message))")
        }
        let status: AlignmentStatus = result.status == 2 ? .duplicate : result.status == 1 ? .matched : .unmatched
        return PairAlignment(offsetX: Int(result.x), offsetY: Int(result.y), confidence: result.confidence,
            status: status, diagnostic: "OpenCV \(String(cString: ekibun_opencv_version())) C++; analysisScale=\(result.analysis_scale); rawAnalysis=(\(result.phase.x),\(result.phase.y)); response=\(result.phase.response); RGB error=\(result.rgb_error)")
    }
}
