import Foundation

public struct ComposedSeam: Codable, Sendable {
    public let firstIndex: Int
    public let secondIndex: Int
    public let outputY: Int
    public let sourceY: Int
    public let status: AlignmentStatus
    public let overlap: Int
}

public struct CompositionResult {
    public let image: RasterImage
    public let seams: [ComposedSeam]
    public let warnings: [String]
}

/// Shared composition intentionally keeps algorithm comparisons about alignment.
/// Original pixels are copied with a hard cut; no blending or hole synthesis.
public enum StitchCompositor {
    private struct Slice {
        let image: Int
        var from: Int
        var to: Int
        let originX: Int
    }

    public static func compose(_ images: [RasterImage], plan: StitchPlan,
                               maximumPixels: Int = 45_000_000) throws -> CompositionResult {
        guard !images.isEmpty, plan.bounds.count == images.count,
              plan.alignments.count == images.count - 1 else { throw StitchError.invalidPlan }
        for (image, bounds) in zip(images, plan.bounds) {
            guard bounds.top >= 0, bounds.bottom <= image.height, bounds.top < bounds.bottom else {
                throw StitchError.invalidPlan
            }
        }
        var slices = [Slice(image: 0, from: 0, to: images[0].height, originX: 0)]
        var seams: [ComposedSeam] = []
        var warnings: [String] = []
        // Position of the latest accepted frame within the current segment.
        var originX = 0
        var currentIndex = 0
        for index in 1..<images.count {
            try Task.checkCancellation()
            let alignment = plan.alignments[index - 1]
            let prior = images[currentIndex], next = images[index]
            if alignment.status == .duplicate {
                guard alignment.offsetX == 0, alignment.offsetY == 0,
                      prior.width == next.width, prior.height == next.height else { throw StitchError.invalidPlan }
                seams.append(ComposedSeam(firstIndex: index - 1, secondIndex: index,
                    outputY: slices.reduce(0) { $0 + $1.to - $1.from }, sourceY: 0,
                    status: .duplicate, overlap: next.height))
                // Matching of the next input still refers to this duplicate frame.
                currentIndex = index
                continue
            }
            let dy = alignment.offsetY, dx = alignment.offsetX
            let previousBounds = plan.bounds[currentIndex], nextBounds = plan.bounds[index]
            let lower = max(previousBounds.top, dy + nextBounds.top)
            let upper = min(previousBounds.bottom, dy + nextBounds.bottom)
            let horizontalOverlap = min(prior.width, dx + next.width) - max(0, dx)
            let valid = alignment.status == .matched && dy > 0 && dy < prior.height &&
                abs(dx) < min(prior.width, next.width) / 4 && lower < upper && horizontalOverlap > 0
            if valid, let last = slices.last {
                // Do not let a newly chosen seam erase an earlier committed seam.
                let minimumCut = max(lower, last.from)
                if minimumCut < upper {
                    let cut = bestCut(prior, next, dx: dx, dy: dy, lower: minimumCut, upper: upper)
                    slices[slices.count - 1].to = cut
                    let y = slices.reduce(0) { $0 + $1.to - $1.from }
                    originX += dx
                    slices.append(Slice(image: index, from: cut - dy, to: next.height, originX: originX))
                    seams.append(ComposedSeam(firstIndex: index - 1, secondIndex: index, outputY: y,
                        sourceY: cut - dy, status: .matched, overlap: upper - lower))
                    currentIndex = index
                    continue
                }
            }
            if alignment.status == .matched {
                warnings.append("Pair \(index - 1)-\(index): invalid or non-monotone geometry; preserved as a separate segment.")
            }
            let y = slices.reduce(0) { $0 + $1.to - $1.from }
            seams.append(ComposedSeam(firstIndex: index - 1, secondIndex: index, outputY: y,
                sourceY: 0, status: .unmatched, overlap: 0))
            slices.append(Slice(image: index, from: 0, to: next.height, originX: 0))
            originX = 0; currentIndex = index
        }
        let left = slices.map(\.originX).max() ?? 0
        let right = slices.map { $0.originX + images[$0.image].width }.min() ?? 0
        let width = right - left
        let height = slices.reduce(0) { $0 + $1.to - $1.from }
        guard width > 0, height > 0 else { throw StitchError.invalidPlan }
        guard width <= maximumPixels / height else { throw StitchError.outputTooLarge }
        if width < images[0].width { warnings.append("Horizontal registration cropped output to the common \(width)-pixel width.") }
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        var destinationY = 0
        for slice in slices {
            let source = images[slice.image]
            for y in slice.from..<slice.to {
                let start = (y * source.width + left - slice.originX) * 4
                let target = destinationY * width * 4
                pixels.replaceSubrange(target..<(target + width * 4), with: source.pixels[start..<(start + width * 4)])
                destinationY += 1
            }
        }
        return CompositionResult(image: try RasterImage(width: width, height: height, pixels: pixels),
                                 seams: seams, warnings: warnings)
    }

    /// Favor a low-residual horizontal cut near the overlap midpoint. The cut
    /// selects entire source rows so text is never alpha-blended.
    private static func bestCut(_ a: RasterImage, _ b: RasterImage, dx: Int, dy: Int,
                                lower: Int, upper: Int) -> Int {
        let midpoint = (lower + upper) / 2
        let margin = min(12, (upper - lower) / 5)
        let first = lower + margin, last = max(first, upper - margin - 1)
        let x0 = max(0, dx), x1 = min(a.width, dx + b.width)
        let step = max(1, (x1 - x0) / 180)
        var best = midpoint, bestScore = Double.infinity
        for y in stride(from: first, through: last, by: max(1, (last - first) / 160)) {
            var sum = 0.0, count = 0
            for row in max(lower, y - 2)...min(upper - 1, y + 2) {
                for x in stride(from: x0, to: x1, by: step) {
                    let i = (row * a.width + x) * 4, j = ((row - dy) * b.width + x - dx) * 4
                    for channel in 0..<3 { sum += Double(abs(Int(a.pixels[i + channel]) - Int(b.pixels[j + channel]))) }
                    count += 3
                }
            }
            let score = sum / Double(max(1, count)) + Double(abs(y - midpoint)) / Double(max(1, upper - lower)) * 2
            if score < bestScore { bestScore = score; best = y }
        }
        return best
    }
}
