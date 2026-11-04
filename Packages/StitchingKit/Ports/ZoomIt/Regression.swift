import Foundation
import StitchingCore
import ZoomItStitch
func frame(_ origin: Int, header: Int = 0, salt: Int = 0, width: Int = 240, height: Int = 600) throws -> RasterImage {
 let w = width, h = height
 var pixels = [UInt8](repeating: 255, count: w*h*4)
 for y in 0..<h { for x in 0..<w {
  let row = y < header ? y : y + origin
  let block = row/13
  let value = ((x/7 + block*17 + salt*23) % 31 < 15 && row%13 < 8) ? UInt8((block*37+salt*51)%170) : 245
  let i = (y*w+x)*4
  pixels[i] = value; pixels[i+1] = value; pixels[i+2] = value
 }}
 return try RasterImage(width:w,height:h,pixels:pixels)
}
let engine = ZoomItEngine()
let a = try frame(0), b = try frame(147), c = try frame(298)
for (name, frames, expected) in [("forward",[a,b],[147]),("reverse",[b,a],[-147]),("three",[a,b,c],[147,151]),("duplicate",[a,a],[0]),("header",[try frame(0,header:60),try frame(147,header:60)],[147])] {
 let plan = try engine.analyze(frames)
 print(name,plan.alignments.map { "\($0.status):\($0.offsetY):\($0.diagnostic)" },plan.bounds)
 precondition(plan.alignments.map(\.offsetY)==expected)
}
func noise(_ seed: UInt64) throws -> RasterImage {
 var state = seed
 var pixels = [UInt8](repeating: 255, count: 240*600*4)
 for i in stride(from: 0, to: pixels.count, by: 4) {
  state = state &* 6364136223846793005 &+ 1
  let value = UInt8(truncatingIfNeeded: state >> 32)
  pixels[i] = value; pixels[i+1] = value; pixels[i+2] = value
 }
 return try RasterImage(width:240,height:600,pixels:pixels)
}
let noOverlap = try engine.analyze([try noise(42),try noise(98)])
// Reference matcher can accept unrelated noise; retain and expose its output.
print("Independent-noise probe", noOverlap.alignments)
precondition(noOverlap.alignments.count == 1)
let empty = try engine.analyze([])
precondition(empty.bounds.isEmpty)
let single = try engine.analyze([a])
precondition(single.alignments.isEmpty)
print("Noise probe cardinality, empty and single inputs passed")

let scaled = try engine.analyze([try frame(0, width:720, height:1800), try frame(443, width:720, height:1800)])
print("scaled", scaled.alignments)
precondition(scaled.alignments[0].offsetY == 443)
