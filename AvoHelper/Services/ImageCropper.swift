import CoreGraphics
import ImageIO
import UIKit
import UniformTypeIdentifiers

enum ImageCropper {
    static func pixelRect(for crop: NormalizedCrop, imageSize: CGSize) -> CGRect {
        let normalized = crop.clamped()
        let x = floor(normalized.x * imageSize.width)
        let y = floor(normalized.y * imageSize.height)
        let maxX = ceil((normalized.x + normalized.width) * imageSize.width)
        let maxY = ceil((normalized.y + normalized.height) * imageSize.height)
        return CGRect(
            x: x,
            y: y,
            width: max(1, min(imageSize.width, maxX) - x),
            height: max(1, min(imageSize.height, maxY) - y)
        ).integral
    }

    static func crop(_ image: UIImage, to crop: NormalizedCrop) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }
        let pixelRect = pixelRect(
            for: crop,
            imageSize: CGSize(width: cgImage.width, height: cgImage.height)
        )
        guard let cropped = cgImage.cropping(to: pixelRect) else { return nil }
        return UIImage(cgImage: cropped, scale: 1, orientation: .up)
    }

    static func writeCroppedPNG(sourceURL: URL, crop: NormalizedCrop) throws -> URL {
        if crop.isFull { return sourceURL }
        guard
            let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { throw StitchingError.invalidImage }

        let rect = pixelRect(
            for: crop,
            imageSize: CGSize(width: image.width, height: image.height)
        )
        guard let cropped = image.cropping(to: rect) else { throw StitchingError.invalidImage }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("avo-cropped-\(UUID().uuidString)")
            .appendingPathExtension("png")
        guard let destination = CGImageDestinationCreateWithURL(
            outputURL as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else { throw StitchingError.couldNotWriteFile }
        CGImageDestinationAddImage(destination, cropped, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw StitchingError.couldNotWriteFile
        }
        return outputURL
    }
}
