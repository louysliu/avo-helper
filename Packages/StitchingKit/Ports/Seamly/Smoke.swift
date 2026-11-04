import Foundation
import StitchingCore

@main struct SeamlySmoke {
    static func frame(origin: Int, width: Int = 96, height: Int = 360, seed: Int = 0) throws -> RasterImage {
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                var value = UInt64((y + origin + 1) * 7907 + (x + 1) * 104729 + seed)
                value = (value ^ (value >> 13)) &* 1274126177
                let p = (y * width + x) * 4
                pixels[p] = UInt8(truncatingIfNeeded: value)
                pixels[p + 1] = UInt8(truncatingIfNeeded: value >> 8)
                pixels[p + 2] = UInt8(truncatingIfNeeded: value >> 16)
            }
        }
        return try RasterImage(width: width, height: height, pixels: pixels)
    }

    static func main() throws {
        let engine = SeamlyEngine()
        let a = try frame(origin: 0)
        let b = try frame(origin: 117)
        let translated = try engine.analyze([a, b])
        precondition(translated.bounds.count == 2 && translated.alignments.count == 1)
        precondition(translated.alignments[0].status == .matched)
        precondition(translated.alignments[0].offsetY == 117)
        let duplicate = try engine.analyze([a, a])
        precondition(duplicate.alignments[0].status == .duplicate)
        let disconnected = try engine.analyze([a, frame(origin: 1700, seed: 982)])
        precondition(disconnected.alignments[0].status == .unmatched)
        let changed = try engine.analyze([a, frame(origin: 0, width: 80)])
        precondition(changed.bounds.count == 2 && changed.alignments[0].status == .unmatched)
        let empty = try engine.analyze([])
        precondition(empty.bounds.isEmpty && empty.alignments.isEmpty)
        print("Seamly smoke: 5 scenarios passed; translated offset 117 px")
    }
}
