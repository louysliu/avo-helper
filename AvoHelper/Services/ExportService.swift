import ImageIO
import Photos
import UIKit

final class ExportService {
    func savePNGToPhotos(_ url: URL) async throws {
        let status = await photoAuthorizationStatus()
        guard status == .authorized || status == .limited else {
            throw StitchingError.photoPermissionDenied
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, fileURL: url, options: nil)
            } completionHandler: { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume(returning: ())
                } else {
                    continuation.resume(throwing: StitchingError.couldNotWriteFile)
                }
            }
        }
    }

    func makeSinglePagePDF(fromPNG url: URL) throws -> URL {
        guard
            let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { throw StitchingError.invalidImage }

        let imageSize = CGSize(width: cgImage.width, height: cgImage.height)
        var pageSize = CGSize(width: 612, height: 612 * imageSize.height / imageSize.width)
        let maximumSide: CGFloat = 14_400
        if max(pageSize.width, pageSize.height) > maximumSide {
            let scale = maximumSide / max(pageSize.width, pageSize.height)
            pageSize = CGSize(width: pageSize.width * scale, height: pageSize.height * scale)
        }

        let bounds = CGRect(origin: .zero, size: pageSize)
        let renderer = UIGraphicsPDFRenderer(bounds: bounds)
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Avo-Helper-\(UUID().uuidString)")
            .appendingPathExtension("pdf")

        do {
            try renderer.writePDF(to: outputURL) { context in
                context.beginPage()
                UIImage(cgImage: cgImage).draw(in: bounds)
            }
        } catch {
            throw StitchingError.couldNotWriteFile
        }
        return outputURL
    }

    private func photoAuthorizationStatus() async -> PHAuthorizationStatus {
        let current = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        guard current == .notDetermined else { return current }
        return await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                continuation.resume(returning: status)
            }
        }
    }
}
