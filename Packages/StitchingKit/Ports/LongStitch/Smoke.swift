import Foundation

@main struct Smoke {
    static func main() throws {
        let w = 120, h = 90
        func mix(_ a: UInt32, _ b: UInt32) -> UInt32 {
            var v = a &* 0x9E3779B1 ^ b &* 0x85EBCA77
            v ^= v >> 15; v = v &* 0xC2B2AE3D
            return v ^ (v >> 13)
        }
        func shot(_ top: Int, bars: Bool = false, seed: Int = 0) throws -> RasterImage {
            var bytes: [UInt8] = []
            for y in 0..<h { for x in 0..<w {
                let row = bars && y < 10 ? y : top+y+seed
                for k in [7,13,29] { bytes.append(UInt8(truncatingIfNeeded: mix(UInt32(row), UInt32(k))) ^ UInt8(x/40)) }
                bytes.append(255)
            } }
            return try RasterImage(width: w,height: h,pixels: bytes)
        }
        let engine = LongStitchEngine()
        for (name, frames, expected) in [
            ("down", try [shot(0),shot(30),shot(60)], [30,30]),
            ("up", try [shot(90),shot(60),shot(30)], [-30,-30]),
            ("duplicate", try [shot(30),shot(30)], [0]),
            ("fixed", try [shot(0,bars:true),shot(30,bars:true)], [30])
        ] {
            let plan = try engine.analyze(frames)
            precondition(plan.alignments.map(\.offsetY) == expected, name)
            precondition(plan.alignments.allSatisfy { $0.status != .unmatched }, name)
            print("PASS \(name): \(plan.alignments.map(\.offsetY))")
        }
        let gap = try engine.analyze([shot(0),shot(10000)])
        precondition(gap.alignments[0].status == .unmatched)
        print("PASS unrelated non-overlap")
        let still = try shot(0)
        var changedPixels = still.pixels
        for y in 35..<55 { for x in 0..<w { changedPixels[(y*w+x)*4] = 200 } }
        let changed = try RasterImage(width:w,height:h,pixels:changedPixels)
        let refresh = try engine.analyze([still,changed])
        precondition(refresh.alignments[0].status == .unmatched)
        precondition(refresh.alignments[0].diagnostic.contains("zero shift"))
        print("PASS changed zero-shift frame is not silently marked duplicate")
    }
}
