import XCTest
@testable import AvoHelper

final class CropGeometryTests: XCTestCase {
    func testTopLeftHandleKeepsBottomRightAnchorFixed() {
        let start = NormalizedCrop.full

        let result = CropGeometry.updatedCrop(
            startingAt: start,
            moving: .topLeft,
            to: CGPoint(x: 0.25, y: 0.35)
        )

        XCTAssertEqual(result.x, 0.25, accuracy: 0.0001)
        XCTAssertEqual(result.y, 0.35, accuracy: 0.0001)
        XCTAssertEqual(result.rect.maxX, 1, accuracy: 0.0001)
        XCTAssertEqual(result.rect.maxY, 1, accuracy: 0.0001)
    }

    func testTopRightHandleKeepsBottomLeftAnchorFixed() {
        let start = NormalizedCrop(x: 0.1, y: 0.1, width: 0.8, height: 0.8)

        let result = CropGeometry.updatedCrop(
            startingAt: start,
            moving: .topRight,
            to: CGPoint(x: 0.7, y: 0.3)
        )

        XCTAssertEqual(result.rect.minX, 0.1, accuracy: 0.0001)
        XCTAssertEqual(result.rect.minY, 0.3, accuracy: 0.0001)
        XCTAssertEqual(result.rect.maxX, 0.7, accuracy: 0.0001)
        XCTAssertEqual(result.rect.maxY, 0.9, accuracy: 0.0001)
    }

    func testTopHandleCannotCrossFixedBottomAnchor() {
        let start = NormalizedCrop.full

        let result = CropGeometry.updatedCrop(
            startingAt: start,
            moving: .topLeft,
            to: CGPoint(x: 0.99, y: 1)
        )

        XCTAssertEqual(result.width, 0.04, accuracy: 0.0001)
        XCTAssertEqual(result.height, 0.04, accuracy: 0.0001)
        XCTAssertEqual(result.rect.maxX, 1, accuracy: 0.0001)
        XCTAssertEqual(result.rect.maxY, 1, accuracy: 0.0001)
    }

    func testTopEdgeMovesInParallelAndKeepsOtherEdgesFixed() {
        let start = NormalizedCrop(x: 0.1, y: 0.1, width: 0.8, height: 0.8)

        let result = CropGeometry.updatedCrop(
            startingAt: start,
            moving: .top,
            to: CGPoint(x: 0.2, y: 0.3)
        )

        XCTAssertEqual(result.rect.minX, 0.1, accuracy: 0.0001)
        XCTAssertEqual(result.rect.maxX, 0.9, accuracy: 0.0001)
        XCTAssertEqual(result.rect.minY, 0.3, accuracy: 0.0001)
        XCTAssertEqual(result.rect.maxY, 0.9, accuracy: 0.0001)
    }

    func testRightEdgeMovesInParallelAndKeepsOtherEdgesFixed() {
        let start = NormalizedCrop(x: 0.1, y: 0.1, width: 0.8, height: 0.8)

        let result = CropGeometry.updatedCrop(
            startingAt: start,
            moving: .right,
            to: CGPoint(x: 0.65, y: 0.3)
        )

        XCTAssertEqual(result.rect.minX, 0.1, accuracy: 0.0001)
        XCTAssertEqual(result.rect.maxX, 0.65, accuracy: 0.0001)
        XCTAssertEqual(result.rect.minY, 0.1, accuracy: 0.0001)
        XCTAssertEqual(result.rect.maxY, 0.9, accuracy: 0.0001)
    }
}
