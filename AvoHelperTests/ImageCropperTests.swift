import XCTest
@testable import AvoHelper

final class ImageCropperTests: XCTestCase {
    func testNormalizedCropConvertsToPixelRect() {
        let crop = NormalizedCrop(x: 0.1, y: 0.2, width: 0.5, height: 0.6)

        let rect = ImageCropper.pixelRect(for: crop, imageSize: CGSize(width: 1000, height: 2000))

        XCTAssertEqual(rect, CGRect(x: 100, y: 400, width: 500, height: 1200))
    }

    func testCropClampsToImageBounds() {
        let crop = NormalizedCrop(x: 0.9, y: 0.95, width: 0.5, height: 0.5)

        let rect = ImageCropper.pixelRect(for: crop, imageSize: CGSize(width: 100, height: 200))

        XCTAssertEqual(rect.maxX, 100)
        XCTAssertEqual(rect.maxY, 200)
        XCTAssertGreaterThan(rect.width, 0)
        XCTAssertGreaterThan(rect.height, 0)
    }
}

