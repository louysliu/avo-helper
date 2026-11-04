import AVFoundation
import XCTest
import Foundation
import ImageIO
import VideoStitchingCore
@testable import HyprLongshotVideo

final class HyprLongshotVideoTests: XCTestCase {
    private func frame(offset: Int, top: Int = 0, bottom: Int = 0, seed: UInt32 = 17) -> HyprFrame {
        let width = 192, height = 200
        var gray = [UInt8](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                if y < top || y >= height - bottom { gray[y * width + x] = 90; continue }
                var value = UInt32(truncatingIfNeeded: (y + offset) * width + x) &+ seed &* 974_567
                value ^= value >> 16; value = value &* 0x45d9f3b; value ^= value >> 16
                gray[y * width + x] = UInt8(truncatingIfNeeded: value)
            }
        }
        return HyprFrame(width: width, height: height, rgba: gray.flatMap { [$0, $0, $0, 255] }, gray: gray)
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testVideoImportToPNGIncludesCalibrationMotion() throws {
        let directory = try temporaryDirectory()
        let video = directory.appendingPathComponent("scroll.mov")
        let writer = try AVAssetWriter(outputURL: video, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 212, AVVideoHeightKey: 220,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 8_000_000]
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: 212, kCVPixelBufferHeightKey as String: 220
        ])
        writer.add(input)
        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        for index in 0..<8 {
            let deadline = Date().addingTimeInterval(5)
            while !input.isReadyForMoreMediaData && Date() < deadline { Thread.sleep(forTimeInterval: 0.005) }
            guard input.isReadyForMoreMediaData else { throw VideoStitchError.invalidVideo }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, try XCTUnwrap(adaptor.pixelBufferPool), &buffer)
            let pixels = try XCTUnwrap(buffer)
            CVPixelBufferLockBaseAddress(pixels, [])
            let base = CVPixelBufferGetBaseAddress(pixels)!.assumingMemoryBound(to: UInt8.self)
            let stride = CVPixelBufferGetBytesPerRow(pixels)
            let content = frame(offset: index * 16)
            for y in 0..<220 { for x in 0..<212 {
                let p = y * stride + x * 4
                let value: UInt8 = (10..<210).contains(y) && (10..<202).contains(x)
                    ? content.gray[(y - 10) * 192 + x - 10] : 100
                base[p] = value; base[p + 1] = value; base[p + 2] = value; base[p + 3] = 255
            } }
            CVPixelBufferUnlockBaseAddress(pixels, [])
            XCTAssertTrue(adaptor.append(pixels, withPresentationTime: CMTime(value: Int64(index), timescale: 10)))
        }
        input.markAsFinished()
        let done = expectation(description: "encode scrolling video")
        writer.finishWriting { done.fulfill() }
        wait(for: [done], timeout: 15)
        XCTAssertEqual(writer.status, .completed, String(describing: writer.error))
        let result = try HyprLongshotVideoEngine().stitch(
            VideoStitchRequest(inputURL: video, outputDirectory: directory), progress: { _ in }, isCancelled: { false })
        XCTAssertFalse(result.isPartial, result.warnings.joined(separator: "; "))
        XCTAssertEqual(result.images.count, 1)
        XCTAssertEqual(result.images.first?.width, 212)
        XCTAssertEqual(result.images.first?.height, 322)
    }

    func testInputEdgesArePreservedThroughPNG() throws {
        let source = frame(offset: 0)
        let prepared = try HyprFrame(VideoFrame(width: 192, height: 200, rgba: source.rgba,
                                                timestamp: 0, duration: 0.1))
        XCTAssertEqual(prepared.width, 192)
        XCTAssertEqual(prepared.height, 200)
        XCTAssertEqual(prepared.rgba, source.rgba)
        var assembler = HyprAssembler(width: 192, height: 200, active: 0..<200, maximumPixels: 1_000_000,
                                      directory: try temporaryDirectory())
        try assembler.consume(prepared)
        try assembler.finish()
        let imageSource = try XCTUnwrap(CGImageSourceCreateWithURL(assembler.images[0].url as CFURL, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(imageSource, 0, nil))
        let data = try XCTUnwrap(image.dataProvider?.data) as Data
        // Writer encodes RGBA. Check all four edge corners, not just resulting dimensions.
        for (x, y) in [(0, 0), (191, 0), (0, 199), (191, 199)] {
            let offset = y * image.bytesPerRow + x * 4
            XCTAssertEqual(Array(data[offset..<(offset + 3)]), Array(source.rgba[(y * 192 + x) * 4..<(y * 192 + x) * 4 + 3]))
        }
    }

    func testFragmentCountLimitReturnsSavedPartialAndStops() throws {
        var assembler = HyprAssembler(width: 192, height: 200, active: 0..<200, maximumPixels: 1_000_000,
                                      directory: try temporaryDirectory(), maximumFragments: 2)
        for seed in 1...12 { try assembler.consume(frame(offset: seed * 8_000, seed: UInt32(seed))) }
        try assembler.finish()
        XCTAssertTrue(assembler.stopped)
        XCTAssertTrue(assembler.isPartial)
        XCTAssertEqual(assembler.images.count, 2)
        XCTAssertTrue(assembler.warnings.contains { $0.contains("剩余视频未处理") })
    }

    func testTotalPixelLimitBoundsAllFragments() throws {
        var assembler = HyprAssembler(width: 192, height: 200, active: 0..<200, maximumPixels: 1_000_000,
                                      directory: try temporaryDirectory(), maximumTotalPixels: 192 * 200)
        for seed in 1...6 { try assembler.consume(frame(offset: seed * 8_000, seed: UInt32(seed))) }
        try assembler.finish()
        XCTAssertTrue(assembler.stopped)
        XCTAssertTrue(assembler.isPartial)
        XCTAssertEqual(assembler.images.count, 1)
    }

    func testDiskBudgetReturnsPartialBeforeWritingOverBudget() throws {
        let directory = try temporaryDirectory()
        var assembler = HyprAssembler(width: 192, height: 200, active: 0..<200, maximumPixels: 1_000_000,
                                      directory: directory, maximumOutputBytes: 400_000)
        for seed in 1...20 { try assembler.consume(frame(offset: seed * 8_000, seed: UInt32(seed))) }
        try assembler.finish()
        XCTAssertTrue(assembler.stopped)
        XCTAssertTrue(assembler.isPartial)
        XCTAssertFalse(assembler.images.isEmpty)
        let bytes = try assembler.images.reduce(0) { total, image in
            total + ((try FileManager.default.attributesOfItem(atPath: image.url.path)[.size] as? NSNumber)?.intValue ?? 0)
        }
        XCTAssertLessThanOrEqual(bytes, 400_000)
    }

    func testUsesOpenCVPhaseCorrelationWithCorrectScrollSign() throws {
        let a = frame(offset: 0), b = frame(offset: 16)
        let motion = try HyprAlgorithm.correlate(a.centralGray(0..<200), b.centralGray(0..<200), width: 96, height: 200)
        XCTAssertEqual(motion.dy, 16, accuracy: 0.6)
        XCTAssertEqual(motion.dx, 0, accuracy: 0.6)
        XCTAssertGreaterThan(motion.response, 0.20)
    }

    func testSixFrameChromeCalibrationAndReplayRetainsAllMotion() throws {
        let frames = (0..<6).map { frame(offset: $0 * 16, top: 12, bottom: 18) }
        let active = HyprAlgorithm.stickyRegion(frames)
        XCTAssertEqual(active, 12..<182)
        var assembler = HyprAssembler(width: 192, height: 200, active: active, maximumPixels: 1_000_000,
                                      directory: try temporaryDirectory())
        for frame in frames { try assembler.consume(frame) }
        try assembler.finish()
        XCTAssertFalse(assembler.isPartial)
        XCTAssertEqual(assembler.images.count, 1)
        XCTAssertEqual(assembler.images[0].height, 182 + 5 * 16)
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(assembler.images[0].url as CFURL, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(image.height, 262)
    }

    func testConstantVideoKeepsOneFrameWithoutInventingMotion() throws {
        let gray = [UInt8](repeating: 80, count: 192 * 200)
        let still = HyprFrame(width: 192, height: 200, rgba: gray.flatMap { [$0, $0, $0, 255] }, gray: gray)
        XCTAssertEqual(HyprAlgorithm.stickyRegion(Array(repeating: still, count: 6)), 0..<200)
        var assembler = HyprAssembler(width: 192, height: 200, active: 0..<200, maximumPixels: 1_000_000,
                                      directory: try temporaryDirectory())
        for _ in 0..<10 { try assembler.consume(still) }
        try assembler.finish()
        XCTAssertEqual(assembler.images.map(\.height), [200])
        XCTAssertFalse(assembler.isPartial)
    }

    func testUnrelatedSceneStartsExplicitPartialFragment() throws {
        var assembler = HyprAssembler(width: 192, height: 200, active: 0..<200, maximumPixels: 1_000_000,
                                      directory: try temporaryDirectory())
        try assembler.consume(frame(offset: 0))
        try assembler.consume(frame(offset: 8_000, seed: 999))
        try assembler.finish()
        XCTAssertEqual(assembler.images.count, 2)
        XCTAssertTrue(assembler.isPartial)
        XCTAssertFalse(assembler.warnings.isEmpty)
    }

    func testRollbackRetainsCurrentFrameThenCanContinueForward() throws {
        var assembler = HyprAssembler(width: 192, height: 200, active: 0..<200, maximumPixels: 1_000_000,
                                      directory: try temporaryDirectory())
        for offset in [0, 16, 32, 16, 32, 48] { try assembler.consume(frame(offset: offset)) }
        try assembler.finish()
        XCTAssertTrue(assembler.isPartial)
        XCTAssertEqual(assembler.images.map(\.height), [232, 232])
    }

    func testPixelLimitSplitsWithoutDroppingNewContent() throws {
        var assembler = HyprAssembler(width: 192, height: 200, active: 0..<200, maximumPixels: 192 * 220,
                                      directory: try temporaryDirectory())
        for offset in [0, 16, 32, 48] { try assembler.consume(frame(offset: offset)) }
        try assembler.finish()
        XCTAssertEqual(assembler.images.map(\.height), [216, 216])
        XCTAssertFalse(assembler.isPartial)
        XCTAssertFalse(assembler.warnings.isEmpty)
    }
}
