// Standalone smoke test. See README.md for compilation command.
import Foundation
import StitchingCore
import EkibunStitch

func frame(shift: Int, seed: UInt64 = 17) throws -> RasterImage {
    let width = 128, height = 256
    var pixels = [UInt8](repeating: 255, count: width*height*4)
    for y in 0..<height {
        for x in 0..<width {
            var v = UInt64(bitPattern: Int64((y+shift)*width+x)) &+ seed
            v = (v ^ (v >> 30)) &* 0xbf58476d1ce4e5b9
            v = (v ^ (v >> 27)) &* 0x94d049bb133111eb
            v ^= v >> 31
            for c in 0..<3 { pixels[(y*width+x)*4+c] = UInt8(truncatingIfNeeded: v >> (c*8)) }
        }
    }
    return try RasterImage(width: width, height: height, pixels: pixels)
}
let engine = EkibunEngine()
let a = try frame(shift: 0)
for shift in [31, 90, 150, -50] {
    let p = try engine.analyze([a, frame(shift: shift)]).alignments[0]
    precondition(p.status == .matched && p.offsetX == 0 && p.offsetY == shift, "shift \(shift): \(p)")
    print("PASS translation \(shift)")
}
let empty = try engine.analyze([])
precondition(empty.bounds.isEmpty)
let duplicate = try engine.analyze([a,a]).alignments[0]
precondition(duplicate.status == .duplicate)
let unrelated = try engine.analyze([a,frame(shift: 0, seed: 999_999)]).alignments[0]
precondition(unrelated.status == .unmatched)
print("PASS empty, duplicate, unrelated")
