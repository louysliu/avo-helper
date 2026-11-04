import XCTest
import StitchingEngines

final class StitchingCoreTests: XCTestCase {
    private func image(offset: Int = 0, height: Int = 100, width: Int = 64) throws -> RasterImage {
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height { for x in 0..<width {
            let i = (y * width + x) * 4
            pixels[i] = UInt8((y + offset) % 256)
            pixels[i + 1] = UInt8((x * 17 + (y + offset) * 31) % 256)
            pixels[i + 2] = UInt8((x * 41 + (y + offset) * 11) % 256)
        } }
        return try RasterImage(width: width, height: height, pixels: pixels)
    }

    func testHardCutPreservesKnownDocumentPixels() throws {
        let images = try [image(), image(offset: 60), image(offset: 120)]
        let p = StitchPlan(engineID: "test", bounds: images.map { FrameBounds(top: 0, bottom: $0.height) },
            alignments: [PairAlignment(offsetY: 60, confidence: 1, status: .matched), PairAlignment(offsetY: 60, confidence: 1, status: .matched)])
        let result = try StitchCompositor.compose(images, plan: p)
        XCTAssertEqual(result.image.pixels, try image(height: 220).pixels)
        XCTAssertEqual(result.seams.map(\.status), [.matched, .matched])
    }

    func testFailedPairDoesNotUndoEarlierSuccessfulPair() throws {
        let images = try [image(), image(offset: 60), image(offset: 210)]
        let p = StitchPlan(engineID: "test", bounds: images.map { _ in FrameBounds(top: 8, bottom: 90) },
            alignments: [PairAlignment(offsetY: 60, confidence: 1, status: .matched), PairAlignment(status: .unmatched)])
        let result = try StitchCompositor.compose(images, plan: p)
        XCTAssertEqual(result.image.height, 260)
        XCTAssertEqual(result.image.pixels, try image(height: 160).pixels + images[2].pixels)
        XCTAssertEqual(result.seams.map(\.status), [.matched, .unmatched])
    }

    func testImpossibleMatchIsPreservedAsUnmatched() throws {
        let images = try [image(), image(offset: 210)]
        let p = StitchPlan(engineID: "test", bounds: images.map { FrameBounds(top: 0, bottom: $0.height) },
            alignments: [PairAlignment(offsetY: 150, status: .matched)])
        let result = try StitchCompositor.compose(images, plan: p)
        XCTAssertEqual(result.image.pixels, images[0].pixels + images[1].pixels)
        XCTAssertEqual(result.seams[0].status, .unmatched)
        XCTAssertEqual(result.warnings.count, 1)
    }

    func testImageIOKeepsOrientationAndChannels() throws {
        let source = try image(height: 117)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("stitch-roundtrip-\(UUID()).png")
        defer { try? FileManager.default.removeItem(at: url) }
        try RasterIO.writePNG(source, to: url)
        let decoded = try RasterIO.load(url)
        XCTAssertEqual(decoded.width, source.width)
        XCTAssertEqual(decoded.height, source.height)
        XCTAssertEqual(decoded.pixels, source.pixels)
    }

    func testPixelBudgetFailsBeforeAllocation() throws {
        let images = try [image(), image(offset: 60)]
        let p = StitchPlan(engineID: "test", bounds: images.map { FrameBounds(top: 0, bottom: $0.height) }, alignments: [PairAlignment(status: .unmatched)])
        XCTAssertThrowsError(try StitchCompositor.compose(images, plan: p, maximumPixels: 100))
    }

    func testAllEnginesRespectContractAndExactDuplicates() throws {
        let source = try image(height: 220, width: 160)
        for choice in StitchEngineChoice.allCases {
            let plan = try choice.makeEngine().analyze([source, source])
            XCTAssertEqual(plan.bounds.count, 2, choice.rawValue)
            XCTAssertEqual(plan.alignments.count, 1, choice.rawValue)
            XCTAssertEqual(plan.alignments[0].status, .duplicate, choice.rawValue)
            XCTAssertEqual(try StitchCompositor.compose([source, source], plan: plan).image.pixels, source.pixels, choice.rawValue)
        }
    }

    func testAllEnginesFindKnownVerticalTranslation() throws {
        // A nonperiodic texture provides a unique displacement. Periodic color
        // ramps can legitimately make the phase-correlation peak ambiguous.
        func texture(offset: Int) throws -> RasterImage {
            var pixels = [UInt8](repeating: 255, count: 160 * 240 * 4)
            for y in 0..<240 { for x in 0..<160 {
                var state = UInt64((y + offset) * 160 + x + 1)
                state = (state ^ (state >> 16)) &* 0x45d9f3b
                state = (state ^ (state >> 16)) &* 0x45d9f3b
                state ^= state >> 16
                let i = (y * 160 + x) * 4
                for c in 0..<3 { pixels[i + c] = UInt8(truncatingIfNeeded: state >> (c * 8)) }
            } }
            return try RasterImage(width: 160, height: 240, pixels: pixels)
        }
        let images = try [texture(offset: 0), texture(offset: 60)]
        for choice in StitchEngineChoice.allCases {
            let plan = try choice.makeEngine().analyze(images)
            XCTAssertEqual(plan.alignments[0].status, .matched, choice.rawValue)
            XCTAssertEqual(plan.alignments[0].offsetY, 60, accuracy: 1, choice.rawValue)
        }
    }

    func testChangedZeroShiftIsNotSilentlyDiscardedByLongStitch() throws {
        let source = try image(height: 240, width: 160)
        var changed = source.pixels
        for y in 100..<135 { for x in 30..<80 {
            let i = (y * source.width + x) * 4
            changed[i] = 255; changed[i + 1] = 0; changed[i + 2] = 0
        } }
        let next = try RasterImage(width: source.width, height: source.height, pixels: changed)
        let plan = try StitchEngineChoice.longstitch.makeEngine().analyze([source, next])
        XCTAssertNotEqual(plan.alignments[0].status, .duplicate)
    }
}
