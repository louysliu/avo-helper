import XCTest
import UIKit
import VideoStitchingCore
@testable import AvoHelper

@MainActor
final class VideoResultLifecycleTests: XCTestCase {
    func testFragmentsRemainSeparateAndCleanupOnlyOwnedOutputs() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")
        try Data("original input".utf8).write(to: outside)
        defer { try? FileManager.default.removeItem(at: outside) }
        let images = try [UIColor.red, .blue].enumerated().map { index, color -> VideoStitchImage in
            let url = directory.appendingPathComponent("\(index).png")
            let format = UIGraphicsImageRendererFormat(); format.scale = 1
            let image = UIGraphicsImageRenderer(size: CGSize(width: 64, height: 200), format: format).image { ctx in
                color.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 64, height: 200))
            }
            try XCTUnwrap(image.pngData()).write(to: url)
            return VideoStitchImage(url: url, width: 64, height: 200)
        }
        let session = StitchingSession()
        session.workflow = .video
        try session.showVideoResult(VideoStitchResult(images: images, warnings: ["未确认连续重叠"], isPartial: true),
                                    algorithm: "Long Screen", directory: directory)
        XCTAssertEqual(session.videoImages.count, 2)
        XCTAssertTrue(session.videoIsPartial)
        XCTAssertEqual(session.artifact?.pngURL, images[0].url)
        session.applyCrop(NormalizedCrop(x: 0, y: 0.2, width: 1, height: 0.6))
        session.selectVideoImage(1)
        XCTAssertEqual(session.artifact?.pngURL, images[1].url)
        XCTAssertTrue(session.crop.isFull)
        XCTAssertTrue(FileManager.default.fileExists(atPath: images[0].url.path))
        session.startOver()
        XCTAssertTrue(session.path.isEmpty)
        XCTAssertEqual(session.workflow, .video)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path))
    }
}
