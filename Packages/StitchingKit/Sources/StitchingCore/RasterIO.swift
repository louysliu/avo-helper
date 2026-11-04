import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Foundation

public enum RasterIO {
    public static func load(_ url: URL) throws -> RasterImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            throw StitchError.invalidImage
        }
        let width = properties[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = properties[kCGImagePropertyPixelHeight] as? Int ?? 0
        guard width > 0, height > 0, width <= 50_000, height <= 100_000,
              width * height <= 60_000_000 else { throw StitchError.invalidImage }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(width, height)
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw StitchError.invalidImage
        }
        return try raster(image)
    }

    public static func raster(_ image: CGImage) throws -> RasterImage {
        let w = image.width, h = image.height
        guard w > 0, h > 0, w <= 50_000, h <= 100_000, w * h <= 60_000_000 else {
            throw StitchError.invalidImage
        }
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        let ok = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: w, height: h,
                bitsPerComponent: 8, bytesPerRow: w * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
            context.setBlendMode(.copy)
            context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard ok else { throw StitchError.invalidImage }
        // HEIC decoding may be deferred until draw. An unavailable decoder can
        // leave the bitmap untouched even though ImageIO returned a CGImage.
        guard stride(from: 3, to: pixels.count, by: 4).contains(where: { pixels[$0] != 0 }) else {
            throw StitchError.invalidImage
        }
        // Flatten premultiplied alpha onto white for the opaque screenshot API.
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let white = 255 - Int(pixels[i + 3])
            for c in 0..<3 { pixels[i + c] = UInt8(clamping: Int(pixels[i + c]) + white) }
            pixels[i + 3] = 255
        }
        return try RasterImage(width: w, height: h, pixels: pixels)
    }

    public static func cgImage(_ image: RasterImage) throws -> CGImage {
        guard let provider = CGDataProvider(data: Data(image.pixels) as CFData),
              let cg = CGImage(width: image.width, height: image.height, bitsPerComponent: 8,
                bitsPerPixel: 32, bytesPerRow: image.width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else {
            throw StitchError.invalidImage
        }
        return cg
    }

    public static func writePNG(_ image: RasterImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw StitchError.invalidImage
        }
        CGImageDestinationAddImage(destination, try cgImage(image), nil)
        guard CGImageDestinationFinalize(destination) else { throw StitchError.invalidImage }
    }
}
