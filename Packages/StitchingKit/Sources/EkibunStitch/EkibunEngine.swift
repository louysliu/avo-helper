// Swift port of ekibun/Stitch phaseCorrelateNative; LGPL-2.1.
// See ../../Ports/Ekibun/README.md for exact provenance and adaptations.
import Foundation
import StitchingCore

public struct EkibunEngine: ScreenshotStitchingEngine {
    public let id = "ekibun"
    public init() {}

    public func analyze(_ images: [RasterImage]) throws -> StitchPlan {
        var pairs: [PairAlignment] = []
        for i in 1..<max(1, images.count) { pairs.append(align(images[i - 1], images[i])) }
        return StitchPlan(engineID: id,
                          bounds: images.map { FrameBounds(top: 0, bottom: $0.height) },
                          alignments: pairs,
                          notes: ["Ekibun phase correlation with difference-masked Laplacian; full frame bounds as upstream. Homography mode is not ported."])
    }

    private func align(_ a: RasterImage, _ b: RasterImage) -> PairAlignment {
        guard a.width == b.width, a.height == b.height else {
            return PairAlignment(status: .unmatched, diagnostic: "Phase correlation requires equal dimensions")
        }
        if a.pixels == b.pixels { return PairAlignment(confidence: 1, status: .duplicate, diagnostic: "Identical RGBA pixels") }
        let step = max(1, Int(ceil(Double(max(a.width, a.height)) / 1024)))
        let w = (a.width + step - 1) / step, h = (a.height + step - 1) / step
        let fw = powerOfTwo(w), fh = powerOfTwo(h)
        let ga = gradients(a, width: w, height: h, step: step)
        let gb = gradients(b, width: w, height: h, step: step)
        var ar = [Double](repeating: 0, count: fw * fh), ai = ar
        var br = ar, bi = ar
        for y in 0..<h {
            for x in 0..<w {
                let p = (y * w + x) * 3
                var va = 0.0, vb = 0.0
                for c in 0..<3 {
                    let d = UInt8(abs(Int(ga[p+c]) - Int(gb[p+c])))
                    let weight = [0.299, 0.587, 0.114][c]
                    va += Double(ga[p+c] & d) * weight
                    vb += Double(gb[p+c] & d) * weight
                }
                ar[y*fw+x] = va; br[y*fw+x] = vb
            }
        }
        fft2(&ar, &ai, width: fw, height: fh, inverse: false)
        fft2(&br, &bi, width: fw, height: fh, inverse: false)
        for i in ar.indices {
            let r = ar[i]*br[i] + ai[i]*bi[i]
            let v = ai[i]*br[i] - ar[i]*bi[i]
            let magnitude = hypot(r, v)
            ar[i] = magnitude > 1e-12 ? r/magnitude : 0
            ai[i] = magnitude > 1e-12 ? v/magnitude : 0
        }
        fft2(&ar, &ai, width: fw, height: fh, inverse: true)
        guard let peakIndex = ar.indices.max(by: { ar[$0] < ar[$1] }), ar[peakIndex] > 0.015 else {
            return PairAlignment(status: .unmatched, diagnostic: "No phase-correlation peak")
        }
        let px = peakIndex % fw, py = peakIndex / fw
        let dx = (px > fw/2 ? px-fw : px) * step
        let dy = (py > fh/2 ? py-fh : py) * step
        // Local original-pixel refinement only: the FFT remains the sole displacement estimator.
        var best = (x: dx, y: dy, error: Double.infinity)
        // A phase peak is periodic. Validate its equivalent image-space shifts.
        for wrapY in -1...1 {
            for wrapX in -1...1 {
                let centerY = dy + wrapY*fh*step, centerX = dx + wrapX*fw*step
                guard abs(centerY) < a.height, abs(centerX) < a.width else { continue }
                for y in (centerY-step)...(centerY+step) {
                    for x in (centerX-step)...(centerX+step) {
                        let e = overlapError(a, b, x: x, y: y)
                        if e < best.error { best = (x, y, e) }
                    }
                }
            }
        }
        let peak = ar[peakIndex]
        guard best.error.isFinite, best.error < 32, abs(best.x) < a.width,
              abs(best.y) < a.height, peak > 0.025 else {
            return PairAlignment(status: .unmatched, diagnostic: "Rejected phase peak \(peak), RGB error \(best.error)")
        }
        // A zero displacement is only a duplicate when the *whole* image agrees.
        if best.x == 0 && best.y == 0 && best.error > 1 {
            return PairAlignment(status: .unmatched, diagnostic: "Zero phase shift but changed image")
        }
        return PairAlignment(offsetX: best.x, offsetY: best.y,
                             confidence: min(1, max(0, peak * 3)) * max(0, 1-best.error/64),
                             status: best.x == 0 && best.y == 0 ? .duplicate : .matched,
                             diagnostic: "Diff phase correlation peak=\(peak), RGB error=\(best.error), sampling=\(step)")
    }

    private func overlapError(_ a: RasterImage, _ b: RasterImage, x: Int, y: Int) -> Double {
        let left = max(0, -x), right = min(b.width, a.width-x)
        let top = max(0, -y), bottom = min(b.height, a.height-y)
        guard right-left >= max(8, a.width/4), bottom-top >= max(8, a.height/20) else { return .infinity }
        let sx = max(1, (right-left)/96), sy = max(1, (bottom-top)/192)
        var error = 0.0, count = 0
        for yy in stride(from: top, to: bottom, by: sy) {
            for xx in stride(from: left, to: right, by: sx) {
                let pa = ((yy+y)*a.width+xx+x)*4, pb = (yy*b.width+xx)*4
                for c in 0..<3 { error += Double(abs(Int(a.pixels[pa+c])-Int(b.pixels[pb+c]))); count += 1 }
            }
        }
        return error / Double(max(1, count))
    }

    private func gradients(_ image: RasterImage, width: Int, height: Int, step: Int) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: width*height*3)
        // OpenCV filter2D CV_8U, kernel [1,1,1;1,-8,1;1,1,1], BORDER_REFLECT_101.
        func reflect(_ value: Int, _ size: Int) -> Int {
            if size <= 1 { return 0 }
            if value < 0 { return -value }
            if value >= size { return size*2-value-2 }
            return value
        }
        for y in 0..<height {
            for x in 0..<width {
                for c in 0..<3 {
                    var sum = 0
                    for ky in -1...1 {
                        for kx in -1...1 {
                            let yy = min(image.height-1, reflect(y+ky, height)*step)
                            let xx = min(image.width-1, reflect(x+kx, width)*step)
                            sum += Int(image.pixels[(yy*image.width+xx)*4+c]) * (kx == 0 && ky == 0 ? -8 : 1)
                        }
                    }
                    out[(y*width+x)*3+c] = UInt8(clamping: sum)
                }
            }
        }
        return out
    }

    private func powerOfTwo(_ n: Int) -> Int { var p = 1; while p < n { p *= 2 }; return p }

    private func fft2(_ real: inout [Double], _ imaginary: inout [Double], width: Int, height: Int, inverse: Bool) {
        var r = [Double](repeating: 0, count: max(width, height)), i = r
        for y in 0..<height {
            for x in 0..<width { r[x] = real[y*width+x]; i[x] = imaginary[y*width+x] }
            fft(&r, &i, count: width, inverse: inverse)
            for x in 0..<width { real[y*width+x] = r[x]; imaginary[y*width+x] = i[x] }
        }
        for x in 0..<width {
            for y in 0..<height { r[y] = real[y*width+x]; i[y] = imaginary[y*width+x] }
            fft(&r, &i, count: height, inverse: inverse)
            for y in 0..<height { real[y*width+x] = r[y]; imaginary[y*width+x] = i[y] }
        }
    }

    private func fft(_ real: inout [Double], _ imaginary: inout [Double], count: Int, inverse: Bool) {
        guard count > 1 else { return }
        var j = 0
        for k in 1..<count {
            var bit = count >> 1
            while j & bit != 0 { j ^= bit; bit >>= 1 }
            j ^= bit
            if k < j { real.swapAt(k,j); imaginary.swapAt(k,j) }
        }
        var length = 2
        while length <= count {
            let angle = (inverse ? 2.0 : -2.0)*Double.pi/Double(length)
            let wr = cos(angle), wi = sin(angle)
            for start in stride(from: 0, to: count, by: length) {
                var ur = 1.0, ui = 0.0
                for k in 0..<(length/2) {
                    let p = start+k, q = p+length/2
                    let tr = real[q]*ur-imaginary[q]*ui, ti = real[q]*ui+imaginary[q]*ur
                    real[q] = real[p]-tr; imaginary[q] = imaginary[p]-ti
                    real[p] += tr; imaginary[p] += ti
                    let next = ur*wr-ui*wi; ui = ur*wi+ui*wr; ur = next
                }
            }
            length *= 2
        }
        if inverse { for k in 0..<count { real[k] /= Double(count); imaginary[k] /= Double(count) } }
    }
}
