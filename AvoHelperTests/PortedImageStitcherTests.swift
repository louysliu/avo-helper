import XCTest
@testable import AvoHelper

final class PortedImageStitcherTests: XCTestCase {
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
