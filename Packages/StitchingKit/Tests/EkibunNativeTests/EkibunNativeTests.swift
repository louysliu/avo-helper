import XCTest
import EkibunNative
import EkibunStitch
import StitchingCore

final class EkibunNativeTests: XCTestCase {
    private func texture(offset: Int, width: Int = 160, height: Int = 240) throws -> RasterImage {
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height { for x in 0..<width {
            var value = UInt64((y + offset) * width + x + 1001)
            value = (value ^ (value >> 16)) &* 0x45d9f3b
            value = (value ^ (value >> 16)) &* 0x45d9f3b
            value ^= value >> 16
            for c in 0..<3 { pixels[(y * width + x) * 4 + c] = UInt8(truncatingIfNeeded: value >> (8 * c)) }
        } }
        return try RasterImage(width: width, height: height, pixels: pixels)
    }

    func testUsesPinnedOpenCV() {
        XCTAssertEqual(String(cString: ekibun_opencv_version()), "4.13.0")
    }

    func testRawCppTranslationDirectionAndImmutableBuffers() throws {
        let a = try texture(offset: 0), b = try texture(offset: 60)
        let beforeA = a.pixels.map { $0 }, beforeB = b.pixels.map { $0 }
        for diff in [Int32(0), Int32(1)] {
            var output = EkibunPhaseResult()
            let ok = a.pixels.withUnsafeBufferPointer { ap in b.pixels.withUnsafeBufferPointer { bp in
                ekibun_phase_correlate(ap.baseAddress, bp.baseAddress, 160, 240, diff, &output, nil, 0)
            } }
            XCTAssertEqual(ok, 1)
            XCTAssertEqual(output.x, 0, accuracy: 1)
            XCTAssertEqual(output.y, 60, accuracy: 1)
            XCTAssertTrue(output.response.isFinite)
        }
        XCTAssertEqual(a.pixels, beforeA)
        XCTAssertEqual(b.pixels, beforeB)
    }

    func testWrapperUnwrapsShiftBeyondHalfDFTPeriod() throws {
        let a = try texture(offset: 0), b = try texture(offset: 150)
        let plan = try EkibunEngine().analyze([a, b])
        XCTAssertEqual(plan.alignments[0].status, .matched)
        XCTAssertEqual(plan.alignments[0].offsetY, 150, accuracy: 1)
    }

    func testNativeRejectsInvalidPointers() {
        var output = EkibunPhaseResult()
        var error = [CChar](repeating: 0, count: 128)
        XCTAssertEqual(ekibun_phase_correlate(nil, nil, 160, 240, 1, &output, &error, error.count), 0)
        XCTAssertFalse(String(cString: error).isEmpty)
    }

    func testAnalysisScaleMapsBackToOriginalPixels() throws {
        let a = try texture(offset: 0, width: 320, height: 1440)
        let b = try texture(offset: 900, width: 320, height: 1440)
        for engine in [EkibunEngine(), EkibunEngine(maximumAnalysisDimension: 1024)] {
            let pair = try engine.analyze([a, b]).alignments[0]
            XCTAssertEqual(pair.status, .matched)
            XCTAssertEqual(pair.offsetX, 0)
            XCTAssertEqual(pair.offsetY, 900, accuracy: 1)
        }
    }

    func testDifferentFlatFramesAreNotDuplicates() throws {
        var pixels = [UInt8](repeating: 255, count: 160 * 240 * 4)
        let a = try RasterImage(width: 160, height: 240, pixels: pixels)
        for i in stride(from: 0, to: pixels.count, by: 4) { pixels[i] = 0; pixels[i + 1] = 0; pixels[i + 2] = 0 }
        let b = try RasterImage(width: 160, height: 240, pixels: pixels)
        XCTAssertEqual(try EkibunEngine().analyze([a, b]).alignments[0].status, .unmatched)
    }
}
