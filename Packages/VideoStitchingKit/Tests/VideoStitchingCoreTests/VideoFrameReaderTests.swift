import AVFoundation
import XCTest
@testable import VideoStitchingCore

final class VideoFrameReaderTests: XCTestCase {
    func testReaderPreservesTopDownRowsAndReplaySampling() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mov")
        defer { try? FileManager.default.removeItem(at: url) }
        try writeVideo(to: url)
        let reader = try VideoFrameReader(url: url)
        let first = try XCTUnwrap(reader.next())
        XCTAssertEqual(first.width, 64)
        XCTAssertEqual(first.height, 96)
        // The encoded top half is red and bottom half blue. Verify orientation AND channel order.
        XCTAssertGreaterThan(Int(first.rgba[(10 * 64 + 32) * 4]), 180)
        XCTAssertGreaterThan(Int(first.rgba[(80 * 64 + 32) * 4 + 2]), 180)
        var count = 1
        while try reader.next() != nil { count += 1 }
        XCTAssertEqual(count, 12)
        let sampled = try VideoFrameReader(url: url, sampleFPS: 5)
        var sampledCount = 0
        while try sampled.next() != nil { sampledCount += 1 }
        XCTAssertEqual(sampledCount, 3)
        let cancelled = try VideoFrameReader(url: url)
        cancelled.cancel()
        XCTAssertThrowsError(try cancelled.next())
    }

    func testRotationMetadataIsApplied() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mov")
        defer { try? FileManager.default.removeItem(at: url) }
        try writeVideo(to: url, rotate: true)
        let frame = try XCTUnwrap(VideoFrameReader(url: url).next())
        XCTAssertEqual(frame.width, 96)
        XCTAssertEqual(frame.height, 64)
        // Clockwise rotation moves the original red top to the right.
        XCTAssertGreaterThan(Int(frame.rgba[(32 * 96 + 80) * 4]), 180)
        XCTAssertGreaterThan(Int(frame.rgba[(32 * 96 + 10) * 4 + 2]), 180)
    }

    private func writeVideo(to url: URL, rotate: Bool = false) throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 64, AVVideoHeightKey: 96
        ])
        if rotate { input.transform = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 96, ty: 0) }
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: 64, kCVPixelBufferHeightKey as String: 96
        ])
        writer.add(input)
        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        for frame in 0..<12 {
            let deadline = Date().addingTimeInterval(5)
            while !input.isReadyForMoreMediaData && Date() < deadline { Thread.sleep(forTimeInterval: 0.005) }
            guard input.isReadyForMoreMediaData else { throw VideoStitchError.invalidVideo }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, try XCTUnwrap(adaptor.pixelBufferPool), &buffer)
            let pixels = try XCTUnwrap(buffer)
            CVPixelBufferLockBaseAddress(pixels, [])
            let base = CVPixelBufferGetBaseAddress(pixels)!.assumingMemoryBound(to: UInt8.self)
            let stride = CVPixelBufferGetBytesPerRow(pixels)
            for y in 0..<96 { for x in 0..<64 {
                let p = y * stride + x * 4
                base[p] = y >= 48 ? 255 : 0; base[p + 1] = 0
                base[p + 2] = y < 48 ? 255 : 0; base[p + 3] = 255
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
