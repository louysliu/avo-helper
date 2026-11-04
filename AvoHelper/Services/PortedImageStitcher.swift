import UIKit
import StitchingEngines

enum AppStitchAlgorithm: String, CaseIterable, Identifiable {
    case original, ekibun, longstitch, zoomit, seamly
    var id: String { rawValue }
    var engineChoice: StitchEngineChoice? { StitchEngineChoice(rawValue: rawValue) }
    var title: String { engineChoice?.title ?? "原有算法 · 对照" }
}

/// UIKit/file lifecycle adapter. Algorithms operate only on shared pixel/plan types.
struct PortedImageStitcher {
    let choice: StitchEngineChoice

    func stitch(images: [UIImage]) async throws -> StitchArtifact {
        guard images.count >= 2 else { throw StitchingError.notEnoughImages }
        return try await Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let rasters = try images.map { image -> RasterImage in
                guard let cgImage = image.cgImage else { throw StitchingError.invalidImage }
                if image.imageOrientation == .up { return try RasterIO.raster(cgImage) }
                let format = UIGraphicsImageRendererFormat()
                format.scale = 1
                format.opaque = true
                let size = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
                let upright = UIGraphicsImageRenderer(size: size, format: format).image { _ in
                    image.draw(in: CGRect(origin: .zero, size: size))
                }
                guard let cg = upright.cgImage else { throw StitchingError.invalidImage }
                return try RasterIO.raster(cg)
            }
            let plan = try choice.makeEngine().analyze(rasters)
            let result = try StitchCompositor.compose(rasters, plan: plan)
            try Task.checkCancellation()
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("avo-\(choice.rawValue)-\(UUID().uuidString).png")
            do {
                try RasterIO.writePNG(result.image, to: url)
                let cg = try RasterIO.cgImage(result.image)
                let image = UIImage(cgImage: cg)
                let scale = min(1, min(900 / image.size.width, sqrt(16_000_000 / (image.size.width * image.size.height))))
                let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
                let previewSize = CGSize(width: max(1, (image.size.width * scale).rounded()),
                                         height: max(1, (image.size.height * scale).rounded()))
                let preview = UIGraphicsImageRenderer(size: previewSize, format: format).image { _ in
                    image.draw(in: CGRect(origin: .zero, size: previewSize))
                }
                return StitchArtifact(pngURL: url, preview: preview, pixelSize: image.size,
                    seams: result.seams.map {
                        SeamReport(firstIndex: $0.firstIndex, secondIndex: $0.secondIndex,
                            overlapPixels: $0.overlap,
                            status: $0.status == .matched ? .matched : $0.status == .duplicate ? .duplicate : .unmatched)
                    }, algorithmName: choice.title)
            } catch {
                try? FileManager.default.removeItem(at: url)
                throw error
            }
        }.value
    }
}
