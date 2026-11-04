import XCTest
import StitchingEngines
@testable import AvoHelper

final class PortedImageStitcherTests: XCTestCase {
    func testEkibunNativeTranslationExportsOriginalPixels() async throws {
        let width = 160, height = 300
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height { for x in 0..<width {
            var value = UInt64(y * width + x + 1001)
            value = (value ^ (value >> 16)) &* 0x45d9f3b
            value = (value ^ (value >> 16)) &* 0x45d9f3b
            value ^= value >> 16
            for c in 0..<3 { pixels[(y * width + x) * 4 + c] = UInt8(truncatingIfNeeded: value >> (8 * c)) }
        } }
        let source = try RasterIO.cgImage(RasterImage(width: width, height: height, pixels: pixels))
        let first = try XCTUnwrap(source.cropping(to: CGRect(x: 0, y: 0, width: width, height: 240)))
        let next = try XCTUnwrap(source.cropping(to: CGRect(x: 0, y: 60, width: width, height: 240)))
        let result = try await PortedImageStitcher(choice: .ekibun).stitch(images: [UIImage(cgImage: first), UIImage(cgImage: next)])
        defer { try? FileManager.default.removeItem(at: result.pngURL) }
        XCTAssertEqual(result.seams.map(\.status), [.matched])
        XCTAssertEqual(result.pixelSize, CGSize(width: width, height: height))
        XCTAssertEqual(try RasterIO.load(result.pngURL).pixels, pixels)
    }

    func testAllFourEnginesExportDuplicateWithoutGrowingImage() async throws {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        let image = UIGraphicsImageRenderer(size: CGSize(width: 160, height: 240), format: format).image { context in
            UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 160, height: 240))
            for i in 0..<12 {
                UIColor(hue: CGFloat(i) / 12, saturation: 0.8, brightness: 0.6, alpha: 1).setFill()
                context.fill(CGRect(x: 9 + (i * 13) % 70, y: i * 20, width: 60, height: 12))
            }
        }
        for algorithm in AppStitchAlgorithm.allCases {
            guard let choice = algorithm.engineChoice else { continue }
            let result = try await PortedImageStitcher(choice: choice).stitch(images: [image, image])
            defer { try? FileManager.default.removeItem(at: result.pngURL) }
            XCTAssertEqual(result.pixelSize, image.size, algorithm.rawValue)
            XCTAssertEqual(result.seams.map(\.status), [.duplicate], algorithm.rawValue)
            XCTAssertNotNil(UIImage(contentsOfFile: result.pngURL.path))
            XCTAssertEqual(result.algorithmName, choice.title)
        }
    }
}
