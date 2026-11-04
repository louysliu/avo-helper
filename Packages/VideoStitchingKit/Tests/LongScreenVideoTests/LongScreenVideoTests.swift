import AVFoundation
import XCTest
import ImageIO
import VideoStitchingCore
import LongScreenVideo

final class LongScreenVideoTests: XCTestCase {
    func testScrollingMOVThroughOriginalRustEngine() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appendingPathComponent("scroll.mov")
        try writeVideo(to: input)
        let result = try LongScreenVideoEngine().stitch(.init(inputURL: input, outputDirectory: directory), progress: { _ in }, isCancelled: { false })
        XCTAssertFalse(result.images.isEmpty)
        XCTAssertFalse(result.isPartial, result.warnings.joined(separator: "; "))
        XCTAssertEqual(result.images.count, 1)
        let output = try XCTUnwrap(result.images.first)
        XCTAssertEqual(output.width, 128)
        XCTAssertEqual(Double(output.height), 192 + 23 * 4, accuracy: 2,
                       "All 24 scrolling frames should contribute the complete observed height")
        for image in result.images {
            let source = try XCTUnwrap(CGImageSourceCreateWithURL(image.url as CFURL, nil))
            let decoded = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
            XCTAssertEqual(decoded.width, image.width)
            XCTAssertEqual(decoded.height, image.height)
        }
    }

    func testCancellationDuringRustProcessing() throws {
        final class Flag: @unchecked Sendable { var value = false }
        let flag = Flag()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appendingPathComponent("cancel.mov")
        try writeVideo(to: input)
        do {
            let result = try LongScreenVideoEngine().stitch(.init(inputURL: input, outputDirectory: directory), progress: { _ in flag.value = true }, isCancelled: { flag.value })
            XCTAssertTrue(result.isPartial)
        } catch VideoStitchError.cancelled { }
        XCTAssertTrue(flag.value, "Cancellation must happen inside Rust progress, not before decoding")
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: directory.path).contains { $0.hasPrefix("long-screen-work-") })
    }

    private func writeVideo(to url: URL, rotate: Bool = false) throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 128, AVVideoHeightKey: 192
        ])
        if rotate { input.transform = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 192, ty: 0) }
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: 128, kCVPixelBufferHeightKey as String: 192
        ])
        writer.add(input)
        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        for frame in 0..<24 {
            let deadline = Date().addingTimeInterval(5)
            while !input.isReadyForMoreMediaData && Date() < deadline { Thread.sleep(forTimeInterval: 0.005) }
            guard input.isReadyForMoreMediaData else { throw VideoStitchError.invalidVideo }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, try XCTUnwrap(adaptor.pixelBufferPool), &buffer)
            let pixels = try XCTUnwrap(buffer)
            CVPixelBufferLockBaseAddress(pixels, [])
            let base = CVPixelBufferGetBaseAddress(pixels)!.assumingMemoryBound(to: UInt8.self)
            let stride = CVPixelBufferGetBytesPerRow(pixels)
            for y in 0..<192 { for x in 0..<128 {
                let p = y * stride + x * 4
                let worldY = y + frame * 4
                let value = (x * 713 + worldY * 991 + x * worldY * 13) & 255
                base[p] = UInt8(value); base[p + 1] = UInt8((value * 3) & 255)
                base[p + 2] = UInt8((value * 7) & 255); base[p + 3] = 255
            } }
            CVPixelBufferUnlockBaseAddress(pixels, [])
            XCTAssertTrue(adaptor.append(pixels, withPresentationTime: CMTime(value: Int64(frame), timescale: 24)))
        }
        input.markAsFinished()
        let done = expectation(description: "video encoding")
        writer.finishWriting { done.fulfill() }
        wait(for: [done], timeout: 10)
        XCTAssertEqual(writer.status, .completed, String(describing: writer.error))
    }
}
