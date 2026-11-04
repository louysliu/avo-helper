// Port of JYAARU/jietuba longstitch (MIT); see Ports/LongStitch.
import Foundation
import StitchingCore

public struct LongStitchEngine: ScreenshotStitchingEngine {
    public let id = "longstitch"
    public init() {}

    public func analyze(_ images: [RasterImage]) throws -> StitchPlan {
        guard let first = images.first else { throw StitchError.invalidImage }
        guard images.allSatisfy({ $0.width == first.width && $0.height == first.height }) else {
            throw StitchError.incompatibleDimensions
        }
        var bounds = images.map { FrameBounds(top: 0, bottom: $0.height) }
        var pairs: [PairAlignment] = []
        var previous = Rows(first), heading = 0
        var settled: (Int, Int)?
        for index in 1..<images.count {
            let current = Rows(images[index])
            let unchanged = edges(previous.exact, current.exact)
            let bars = (unchanged.0 + unchanged.1) * 2 < first.height ? unchanged : (0, 0)
            var usedBars = bars
            var located = locate(previous, current, bars: bars, heading: heading)
            if located == nil, let settled {
                let reduced = (min(bars.0, settled.0), min(bars.1, settled.1))
                if reduced != bars {
                    located = locate(previous, current, bars: reduced, heading: heading)
                    usedBars = reduced
                }
            }
            let sample = Sample(previous, current, bars: usedBars, unchanged: unchanged)
            // Upstream retains a hash match if similarity cannot establish a better placement.
            if located == nil || (located!.0.top != 0 && !sample.alike(at: located!.0.top)) {
                if let similar = sample.locate() { located = (similar, "brightness") }
            }
            if let (placement, kind) = located {
                let dy = placement.top
                // A session can refresh pixels at the same position. A pair plan cannot
                // express that replacement, so zero shift does not establish duplication.
                // Otherwise a stationary header match can silently discard a new screen.
                if dy == 0 && images[index - 1].pixels != images[index].pixels {
                    pairs.append(PairAlignment(status: .unmatched,
                        diagnostic: "Upstream \(kind) matcher located zero shift (run=\(placement.length)), but pixels differ; session refresh is not representable by this pair plan"))
                    previous = current
                    continue
                }
                if dy != 0 { heading = dy > 0 ? 1 : -1; settled = usedBars }
                let trimming = dy == 0 ? (settled ?? usedBars) : usedBars
                for frame in [index - 1, index] {
                    bounds[frame] = FrameBounds(top: max(bounds[frame].top, trimming.0),
                                              bottom: min(bounds[frame].bottom, first.height - trimming.1))
                }
                pairs.append(PairAlignment(offsetY: dy, confidence: kind == "exact" ? 0.98 : kind == "coarse" ? 0.85 : 0.8,
                                           status: dy == 0 ? .duplicate : .matched,
                                           diagnostic: "\(kind); run=\(placement.length); fixed=\(usedBars.0),\(usedBars.1)"))
            } else {
                pairs.append(PairAlignment(status: .unmatched, diagnostic: "No credible row-run or unambiguous brightness overlap"))
            }
            previous = current
        }
        return StitchPlan(engineID: id, bounds: bounds, alignments: pairs,
                          notes: ["jietuba session matcher, adjacent-frame adapter; vertical translation only", "Confidence values label matching paths, not calibrated probabilities"])
    }
}

private struct Rows {
    var exact: [UInt64] = []
    var coarse: [UInt64] = []
    var profiles: [[Int]] = []
    let height: Int
    init(_ image: RasterImage) {
        height = image.height
        let width = image.width - image.width / 10
        let bins = width / 8
        for y in 0..<image.height {
            let start = y * image.width * 4
            var h: UInt64 = 0
            var offset = 0
            while offset + 8 <= width * 4 {
                var word: UInt64 = 0
                for byte in 0..<8 { word |= UInt64(image.pixels[start + offset + byte]) << (byte * 8) }
                h = ((h << 5 | h >> 59) ^ word) &* 0x517cc1b727220a95
                offset += 8
            }
            while offset < width * 4 {
                h = ((h << 5 | h >> 59) ^ UInt64(image.pixels[start + offset])) &* 0x517cc1b727220a95
                offset += 1
            }
            exact.append(h)
            var r = 0, g = 0, b = 0
            var profile = [Int](repeating: 0, count: bins)
            for x in 0..<width {
                let p = start + x * 4
                r += Int(image.pixels[p]); g += Int(image.pixels[p+1]); b += Int(image.pixels[p+2])
                if x / 8 < bins { profile[x/8] += Int(image.pixels[p]) + Int(image.pixels[p+1]) + Int(image.pixels[p+2]) }
            }
            coarse.append(UInt64(r / width / 8 * 8) &* 73856093 &+ UInt64(g / width / 8 * 8) &* 19349663 &+ UInt64(b / width / 8 * 8) &* 83492791)
            profiles.append(profile)
        }
    }
}

private struct Placement {
    let i: Int, j: Int, length: Int
    var top: Int { i - j }
}

private func edges(_ a: [UInt64], _ b: [UInt64]) -> (Int, Int) {
    if a == b { return (0, 0) }
    var top = 0, bottom = 0
    while top < a.count && a[top] == b[top] { top += 1 }
    while bottom < a.count && a[a.count - 1 - bottom] == b[b.count - 1 - bottom] { bottom += 1 }
    return (top, bottom)
}

/// Maximal common runs, ordered and suppressed exactly like lcs::find_top_common_runs.
private func runs(_ a: [UInt64], _ b: [UInt64], aStart: Int, bStart: Int) -> [Placement] {
    guard !a.isEmpty, !b.isEmpty else { return [] }
    let minimum = max(1, Int(Float(min(a.count, b.count)) * 0.01))
    var positions: [UInt64: [Int]] = [:]
    for (j, hash) in b.enumerated() { positions[hash, default: []].append(j) }
    var candidates: [Placement] = []
    for (i, hash) in a.enumerated() {
        for j in positions[hash] ?? [] {
            if i > 0 && j > 0 && a[i-1] == b[j-1] { continue }
            var n = 1
            while i+n < a.count && j+n < b.count && a[i+n] == b[j+n] { n += 1 }
            if n >= minimum { candidates.append(Placement(i: i+aStart, j: j+bStart, length: n)) }
        }
    }
    candidates.sort {
        if $0.length != $1.length { return $0.length > $1.length }
        if $0.i != $1.i { return $0.i > $1.i }
        return $0.j < $1.j
    }
    var selected: [Placement] = []
    for p in candidates {
        if selected.contains(where: { min($0.i + $0.length, p.i+p.length) - max($0.i, p.i) > p.length/2 }) { continue }
        selected.append(p)
        if selected.count == 32 { break }
    }
    return selected
}

private func locate(_ a: Rows, _ b: Rows, bars: (Int, Int), heading: Int) -> (Placement, String)? {
    let start = bars.0, end = b.height - bars.1
    guard end > start else { return nil }
    // Source caller defaults: top exclusion 15%, 5% when moving upward; bottom 0%.
    let searchStart = min(a.height-1, Int(Float(a.height) * (heading < 0 ? 0.05 : 0.15)))
    for exact in [true, false] {
        let aa = exact ? a.exact : a.coarse, bb = exact ? b.exact : b.coarse
        let x = Array(aa[searchStart...]), y = Array(bb[start..<end])
        var ac: [UInt64: Int] = [:], bc: [UInt64: Int] = [:]
        for h in x { ac[h, default: 0] += 1 }; for h in y { bc[h, default: 0] += 1 }
        let needed = min(8, max(1, bc.values.filter { $0 == 1 }.count / 2))
        let found = runs(x, y, aStart: searchStart, bStart: start)
        let longest = found.first?.length ?? 0
        func preferred(_ p: Placement) -> Bool { (heading == 0 || p.top * heading >= 0) && longest <= p.length * 5 }
        for p in found.filter(preferred) + found.filter({ !preferred($0) }) {
            var unique = 0
            for k in 0..<p.length { if ac[aa[p.i+k]] == 1 && bc[bb[p.j+k]] == 1 { unique += 1 } }
            let enough = exact ? min(needed, max(1, p.length / 2)) : 8
            let overlap = max(0, min(end, a.height-p.top) - max(start, -p.top))
            if unique >= enough || (exact && p.length*2 >= overlap && (unique >= 2 || p.length*4 >= y.count)) {
                return (p, exact ? "exact" : "coarse")
            }
        }
    }
    return nil
}

private struct Similarity {
    var matched = 0, compared = 0, mean = 0.0
    var alike: Bool { matched * 4 >= compared * 3 }
}
private struct Sample {
    let a: Rows, b: Rows
    let start: Int, end: Int, bins: Int
    let sampled: [Int]
    init(_ a: Rows, _ b: Rows, bars: (Int, Int), unchanged: (Int, Int)) {
        self.a = a; self.b = b
        start = max(bars.0, unchanged.0)
        end = max(start, b.height - max(bars.1, unchanged.1))
        bins = b.profiles.first?.count ?? 0
        if start < end && bins > 0 {
            sampled = stride(from: start, to: end, by: max(1, (end-start+255)/256)).filter {
                let row = b.profiles[$0]
                return (row.max() ?? 0) - (row.min() ?? 0) > 48
            }
        } else { sampled = [] }
    }
    func similarity(at top: Int, minimum: Int) -> Similarity? {
        let first = max(start, -top), last = min(end, a.height-top)
        guard bins > 0, last-first >= minimum else { return nil }
        var score = Similarity()
        for j in sampled where j >= first && j < last {
            let lhs = a.profiles[j+top], rhs = b.profiles[j]
            var difference = 0
            for k in 0..<bins { difference += abs(lhs[k]-rhs[k]) }
            let value = Double(difference) / Double(bins*8*3)
            score.compared += 1; score.mean += value
            if value <= 2 { score.matched += 1 }
        }
        if score.compared > 0 { score.mean /= Double(score.compared) }
        return score
    }
    func alike(at top: Int) -> Bool { similarity(at: top, minimum: 1)?.alike ?? true }
    func locate() -> Placement? {
        guard start < end, bins > 0 else { return nil }
        let minimum = max(1, (end-start)/4)
        let first = -end+minimum, last = a.height-start-minimum
        guard first <= last else { return nil }
        var scores: [(Int, Similarity)] = []
        for top in first...last { if let s = similarity(at: top, minimum: minimum) { scores.append((top,s)) } }
        guard let best = scores.max(by: {
            $0.1.matched == $1.1.matched ? $0.1.mean > $1.1.mean : $0.1.matched < $1.1.matched
        }) else { return nil }
        let rival = scores.contains { abs($0.0-best.0) > 2 && ($0.1.matched*2 > best.1.matched || ($0.1.compared >= 8 && $0.1.alike)) }
        guard best.1.matched >= 8, best.1.matched*2 >= best.1.compared,
              best.0-first > 2, last-best.0 > 2, !rival else { return nil }
        let lo = max(start, -best.0), hi = min(end, a.height-best.0)
        return Placement(i: best.0+lo, j: lo, length: max(0,hi-lo))
    }
}
