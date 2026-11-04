import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum VideoPNGWriter {
    public static func write(rgba: [UInt8], width: Int, height: Int, to url: URL) throws {
        guard width > 0, height > 0, width <= 50_000, height <= 500_000,
              width <= Int.max / height / 4, rgba.count == width * height * 4,
              let provider = CGDataProvider(data: Data(rgba) as CFData),
              let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else {
            throw VideoStitchError.processingFailed("无法生成长图像素数据。")
        }
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw VideoStitchError.processingFailed("无法创建长图文件，请检查剩余存储空间。")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            try? FileManager.default.removeItem(at: url)
            throw VideoStitchError.processingFailed("无法保存长图文件。")
        }
    }
}
