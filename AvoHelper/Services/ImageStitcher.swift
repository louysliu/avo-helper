import UIKit

struct StitchingConfiguration {
    var topExclusionRatio: CGFloat = 0
    var bottomExclusionRatio: CGFloat = 0
    var horizontalExclusionRatio: CGFloat = 0.12
    var minimumScrollRatio: CGFloat = 0.02
    var maximumScrollRatio: CGFloat = 1
    var nccThreshold: CGFloat = 0.72
    var ambiguityMargin: CGFloat = 0.015
}

struct OverlapMatch: Equatable {
    let contentOverlapPixels: Int
    let scrollDistancePixels: Int
    let confidence: CGFloat
    let isDuplicate: Bool

    var pixels: Int { contentOverlapPixels }
    var isMatched: Bool { isDuplicate || scrollDistancePixels > 0 }

    static let none = OverlapMatch(
        contentOverlapPixels: 0,
        scrollDistancePixels: 0,
        confidence: 0,
        isDuplicate: false
    )
}

final class ImageStitcher {
    private let maximumOutputPixels = 45_000_000
    private let analysisWidth = 320
    private let configuration: StitchingConfiguration

    init(configuration: StitchingConfiguration = StitchingConfiguration()) {
        self.configuration = configuration
    }

    func stitch(images: [UIImage]) async throws -> StitchArtifact {
        guard images.count >= 2 else { throw StitchingError.notEnoughImages }

        return try await Task.detached(priority: .userInitiated) { [self] in
            try Task.checkCancellation()
            return try performStitch(images: images)
        }.value
    }

    func detectOverlap(previous: UIImage, next: UIImage) -> OverlapMatch {
        guard
            let first = normalizedImage(previous),
            let second = normalizedImage(next)
        else { return .none }

        let commonWidth = min(first.size.width, second.size.width)
        guard
            let scaledFirst = scaled(first, toWidth: commonWidth),
            let scaledSecond = scaled(second, toWidth: commonWidth)
        else { return .none }

        return detectOverlapNormalized(
            previous: scaledFirst,
            next: scaledSecond,
            expectedScrollDistance: nil
        )
    }

    private func performStitch(images: [UIImage]) throws -> StitchArtifact {
        let normalized = try images.map { image -> UIImage in
            guard let result = normalizedImage(image) else { throw StitchingError.invalidImage }
            return result
        }

        guard let commonWidth = normalized.map(\.size.width).min() else {
            throw StitchingError.invalidImage
        }

        let scaledImages = try normalized.map { image -> UIImage in
            guard let result = scaled(image, toWidth: commonWidth) else {
                throw StitchingError.invalidImage
            }
            return result
        }

        let detectedInsets = zip(scaledImages, scaledImages.dropFirst()).compactMap {
            estimateFixedInsets(previous: $0, next: $1)
        }
        let topExclusionRatio = max(
            configuration.topExclusionRatio,
            median(of: detectedInsets.map(\.topRatio)) ?? 0
        )
        let bottomExclusionRatio = max(
            configuration.bottomExclusionRatio,
            median(of: detectedInsets.map(\.bottomRatio)) ?? 0
        )

        var matches: [OverlapMatch] = []
        var seams: [SeamReport] = []
        var acceptedScrollDistances: [Int] = []

        for index in 1..<scaledImages.count {
            try Task.checkCancellation()
            let expected = median(of: Array(acceptedScrollDistances.suffix(3)))
            let match = detectOverlapNormalized(
                previous: scaledImages[index - 1],
                next: scaledImages[index],
                expectedScrollDistance: expected
            )
            matches.append(match)
            if match.scrollDistancePixels > 0 {
                acceptedScrollDistances.append(match.scrollDistancePixels)
            }
            seams.append(
                SeamReport(
                    firstIndex: index - 1,
                    secondIndex: index,
                    overlapPixels: match.contentOverlapPixels,
                    status: match.isDuplicate ? .duplicate : (match.isMatched ? .matched : .unmatched)
                )
            )
        }

        let geometries = scaledImages.map {
            contentGeometry(
                forHeight: Int($0.size.height),
                topExclusionRatio: topExclusionRatio,
                bottomExclusionRatio: bottomExclusionRatio
            )
        }
        let requiresLosslessFallback = matches.contains { !$0.isMatched }
        let appendedHeights = zip(matches, geometries.dropFirst()).map { match, geometry in
            if match.isDuplicate { return 0 }
            if match.isMatched { return min(geometry.height, match.scrollDistancePixels) }
            return geometry.height
        }
        let firstHeight = geometries[0].bottom
        let finalBottomChromeHeight = Int(scaledImages.last!.size.height) - geometries.last!.bottom
        let totalHeight = requiresLosslessFallback
            ? scaledImages.reduce(0) { $0 + Int($1.size.height) }
            : firstHeight + appendedHeights.reduce(0, +) + finalBottomChromeHeight
        let width = Int(commonWidth)

        guard width > 0, totalHeight > 0 else { throw StitchingError.invalidImage }
        guard width * totalHeight <= maximumOutputPixels else { throw StitchingError.outputTooLarge }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: width, height: totalHeight),
            format: format
        )

        let stitched = renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: totalHeight))

            if requiresLosslessFallback {
                var destinationY = 0
                for image in scaledImages {
                    drawSegment(
                        of: image,
                        fromY: 0,
                        toY: Int(image.size.height),
                        atY: destinationY
                    )
                    destinationY += Int(image.size.height)
                }
            } else {
                var destinationY = 0
                drawSegment(
                    of: scaledImages[0],
                    fromY: 0,
                    toY: geometries[0].bottom,
                    atY: destinationY
                )
                destinationY += geometries[0].bottom

                for index in 1..<scaledImages.count {
                    let appendHeight = appendedHeights[index - 1]
                    guard appendHeight > 0 else { continue }
                    let geometry = geometries[index]
                    drawSegment(
                        of: scaledImages[index],
                        fromY: geometry.bottom - appendHeight,
                        toY: geometry.bottom,
                        atY: destinationY
                    )
                    destinationY += appendHeight
                }

                if finalBottomChromeHeight > 0, let finalImage = scaledImages.last {
                    drawSegment(
                        of: finalImage,
                        fromY: geometries.last!.bottom,
                        toY: Int(finalImage.size.height),
                        atY: destinationY
                    )
                }
            }
        }

        try Task.checkCancellation()
        guard let pngData = stitched.pngData() else { throw StitchingError.couldNotWriteFile }
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("avo-stitched-\(UUID().uuidString)")
            .appendingPathExtension("png")
        do {
            try pngData.write(to: outputURL, options: .atomic)
        } catch {
            throw StitchingError.couldNotWriteFile
        }

        guard let preview = resizedPreview(stitched) else {
            try? FileManager.default.removeItem(at: outputURL)
            throw StitchingError.invalidImage
        }

        return StitchArtifact(
            pngURL: outputURL,
            preview: preview,
            pixelSize: stitched.size,
            seams: seams
        )
    }

    private func detectOverlapNormalized(
        previous: UIImage,
        next: UIImage,
        expectedScrollDistance: Int?
    ) -> OverlapMatch {
        guard
            let previousGray = GrayImage(image: previous, maximumWidth: analysisWidth),
            let nextGray = GrayImage(image: next, maximumWidth: analysisWidth)
        else { return .none }

        if isDuplicate(previousGray, nextGray) {
            let scale = next.size.width / CGFloat(nextGray.width)
            return OverlapMatch(
                contentOverlapPixels: Int((CGFloat(min(previousGray.height, nextGray.height)) * scale).rounded()),
                scrollDistancePixels: 0,
                confidence: 1,
                isDuplicate: true
            )
        }

        let fixedInsets = estimateFixedInsets(previous: previousGray, next: nextGray)
        return detectOverlap(
            previousGray: previousGray,
            nextGray: nextGray,
            nextImageWidth: next.size.width,
            expectedScrollDistance: expectedScrollDistance,
            topExclusionRatio: max(configuration.topExclusionRatio, fixedInsets.topRatio),
            bottomExclusionRatio: max(configuration.bottomExclusionRatio, fixedInsets.bottomRatio)
        )
    }

    private func detectOverlap(
        previousGray: GrayImage,
        nextGray: GrayImage,
        nextImageWidth: CGFloat,
        expectedScrollDistance: Int?,
        topExclusionRatio: CGFloat,
        bottomExclusionRatio: CGFloat
    ) -> OverlapMatch {

        let previousGeometry = contentGeometry(
            forHeight: previousGray.height,
            topExclusionRatio: topExclusionRatio,
            bottomExclusionRatio: bottomExclusionRatio
        )
        let nextGeometry = contentGeometry(
            forHeight: nextGray.height,
            topExclusionRatio: topExclusionRatio,
            bottomExclusionRatio: bottomExclusionRatio
        )
        let contentHeight = min(previousGeometry.height, nextGeometry.height)
        guard contentHeight >= 24 else { return .none }

        let bands = horizontalBands(forWidth: min(previousGray.width, nextGray.width))
        guard bands.count == 3 else { return .none }

        let duplicateScores = bands.map { band in
            blockScore(
                previousGray,
                nextGray,
                previousY: previousGeometry.top,
                nextY: nextGeometry.top,
                length: contentHeight,
                xRange: band
            )
        }
        let duplicateDifference = meanAbsoluteDifference(
            previousGray,
            nextGray,
            previousY: previousGeometry.top,
            nextY: nextGeometry.top,
            length: contentHeight,
            xRange: bands[0].lowerBound..<bands[2].upperBound
        )
        if duplicateScores.filter({ $0 >= 0.97 }).count >= 2, duplicateDifference <= 0.008 {
            let scale = nextImageWidth / CGFloat(nextGray.width)
            return OverlapMatch(
                contentOverlapPixels: Int((CGFloat(contentHeight) * scale).rounded()),
                scrollDistancePixels: 0,
                confidence: 1,
                isDuplicate: true
            )
        }

        let minimumShift = max(2, Int(CGFloat(contentHeight) * configuration.minimumScrollRatio))
        let minimumEvidenceHeight = max(8, min(24, contentHeight / 50))
        let ratioLimitedShift = Int(CGFloat(contentHeight) * configuration.maximumScrollRatio)
        let maximumShift = max(
            minimumShift,
            min(contentHeight - minimumEvidenceHeight, ratioLimitedShift)
        )
        let voteTolerance = max(3, Int(CGFloat(contentHeight) * 0.018))
        let supportingThreshold = max(0.6, configuration.nccThreshold - 0.05)
        let smallOverlapFallback = {
            self.detectSmallOverlap(
                previousGray: previousGray,
                nextGray: nextGray,
                nextImageWidth: nextImageWidth,
                previousGeometry: previousGeometry,
                nextGeometry: nextGeometry,
                contentHeight: contentHeight,
                bands: bands,
                minimumShift: minimumShift,
                maximumShift: maximumShift,
                voteTolerance: voteTolerance,
                expectedScrollDistance: expectedScrollDistance
            )
        }

        let bandCandidates = bands.compactMap { band in
            bestCandidate(
                previousGray,
                nextGray,
                previousGeometry: previousGeometry,
                nextGeometry: nextGeometry,
                contentHeight: contentHeight,
                shiftRange: minimumShift...maximumShift,
                xRange: band,
                separation: voteTolerance,
                minimumScore: supportingThreshold
            )
        }
        guard bandCandidates.count >= 2 else { return smallOverlapFallback() }

        let groups = bandCandidates.map { seed in
            bandCandidates.filter { abs($0.shift - seed.shift) <= voteTolerance }
        }
        guard let consensus = groups.max(by: { lhs, rhs in
            if lhs.count == rhs.count {
                return medianScore(lhs) < medianScore(rhs)
            }
            return lhs.count < rhs.count
        }), consensus.count >= 2 else { return smallOverlapFallback() }

        let consensusShift = Int(
            (CGFloat(consensus.reduce(0) { $0 + $1.shift }) / CGFloat(consensus.count)).rounded()
        )
        let overlap = contentHeight - consensusShift
        guard overlap > 0 else { return .none }

        let verificationScores = bands.map { band in
            blockScore(
                previousGray,
                nextGray,
                previousY: previousGeometry.top + consensusShift,
                nextY: nextGeometry.top,
                length: overlap,
                xRange: band
            )
        }
        let strongScores = verificationScores.filter { $0 >= configuration.nccThreshold }
        let supportingScores = verificationScores.filter { $0 >= supportingThreshold }
        guard strongScores.count >= 1, supportingScores.count >= 2 else {
            return smallOverlapFallback()
        }
        let confidence = median(of: strongScores) ?? 0

        let scale = nextImageWidth / CGFloat(nextGray.width)
        let fullScrollDistance = max(1, Int((CGFloat(consensusShift) * scale).rounded()))
        let fullContentOverlap = max(0, Int((CGFloat(overlap) * scale).rounded()))

        if let expectedScrollDistance, expectedScrollDistance > 0 {
            let allowedJump = max(
                Int(CGFloat(expectedScrollDistance) * 0.65),
                Int(CGFloat(nextGeometry.height) * scale * 0.28)
            )
            if abs(fullScrollDistance - expectedScrollDistance) > allowedJump, confidence < 0.94 {
                return .none
            }
        }

        return OverlapMatch(
            contentOverlapPixels: fullContentOverlap,
            scrollDistancePixels: fullScrollDistance,
            confidence: confidence,
            isDuplicate: false
        )
    }

    private func bestCandidate(
        _ previous: GrayImage,
        _ next: GrayImage,
        previousGeometry: ContentGeometry,
        nextGeometry: ContentGeometry,
        contentHeight: Int,
        shiftRange: ClosedRange<Int>,
        xRange: Range<Int>,
        separation: Int,
        minimumScore: CGFloat? = nil,
        minimumProminence: CGFloat? = nil
    ) -> ShiftCandidate? {
        var coarse: [ShiftCandidate] = []
        for shift in stride(from: shiftRange.lowerBound, through: shiftRange.upperBound, by: 2) {
            let overlap = contentHeight - shift
            guard overlap > 0 else { continue }
            let score = blockScore(
                previous,
                next,
                previousY: previousGeometry.top + shift,
                nextY: nextGeometry.top,
                length: overlap,
                xRange: xRange
            )
            coarse.append(ShiftCandidate(shift: shift, score: score))
        }
        guard let coarseBest = coarse.max(by: { $0.score < $1.score }) else { return nil }

        let fineLower = max(shiftRange.lowerBound, coarseBest.shift - 2)
        let fineUpper = min(shiftRange.upperBound, coarseBest.shift + 2)
        var best = coarseBest
        for shift in fineLower...fineUpper {
            let overlap = contentHeight - shift
            let score = blockScore(
                previous,
                next,
                previousY: previousGeometry.top + shift,
                nextY: nextGeometry.top,
                length: overlap,
                xRange: xRange
            )
            if score > best.score { best = ShiftCandidate(shift: shift, score: score) }
        }

        let secondScore = coarse
            .filter { abs($0.shift - best.shift) > separation }
            .map(\.score)
            .max() ?? -1
        guard
            best.score >= (minimumScore ?? configuration.nccThreshold),
            best.score - secondScore >= (minimumProminence ?? configuration.ambiguityMargin)
        else { return nil }
        return ShiftCandidate(
            shift: best.shift,
            score: best.score,
            prominence: best.score - secondScore
        )
    }

    private func detectSmallOverlap(
        previousGray: GrayImage,
        nextGray: GrayImage,
        nextImageWidth: CGFloat,
        previousGeometry: ContentGeometry,
        nextGeometry: ContentGeometry,
        contentHeight: Int,
        bands: [Range<Int>],
        minimumShift: Int,
        maximumShift: Int,
        voteTolerance: Int,
        expectedScrollDistance: Int?
    ) -> OverlapMatch {
        let maximumOverlap = max(16, Int(CGFloat(contentHeight) * 0.05))
        let smallRangeLower = max(minimumShift, contentHeight - maximumOverlap)
        guard smallRangeLower <= maximumShift else { return .none }

        let candidates = bands.compactMap { band in
            bestCandidate(
                previousGray,
                nextGray,
                previousGeometry: previousGeometry,
                nextGeometry: nextGeometry,
                contentHeight: contentHeight,
                shiftRange: smallRangeLower...maximumShift,
                xRange: band,
                separation: voteTolerance,
                minimumScore: 0.14,
                minimumProminence: configuration.ambiguityMargin
            )
        }
        let groups = candidates.map { seed in
            candidates.filter { abs($0.shift - seed.shift) <= voteTolerance }
        }
        guard let consensus = groups.max(by: { lhs, rhs in
            if lhs.count == rhs.count { return medianScore(lhs) < medianScore(rhs) }
            return lhs.count < rhs.count
        }), consensus.count >= 2, consensus.contains(where: { $0.prominence >= 0.05 }) else {
            return .none
        }

        let searchLower = max(smallRangeLower, consensus.map(\.shift).min()! - voteTolerance)
        let searchUpper = min(maximumShift, consensus.map(\.shift).max()! + voteTolerance)
        var consensusShift: Int?
        var bestCombinedScore = -CGFloat.infinity
        for shift in searchLower...searchUpper {
            let candidateOverlap = contentHeight - shift
            let eligibleScores = bands.compactMap { band -> CGFloat? in
                let informativePixels = informativePixelCount(
                    previousGray,
                    nextGray,
                    previousY: previousGeometry.top + shift,
                    nextY: nextGeometry.top,
                    length: candidateOverlap,
                    xRange: band
                )
                guard informativePixels >= max(12, band.count / 5) else { return nil }
                return blockScore(
                    previousGray,
                    nextGray,
                    previousY: previousGeometry.top + shift,
                    nextY: nextGeometry.top,
                    length: candidateOverlap,
                    xRange: band
                )
            }.sorted(by: >)
            guard eligibleScores.count >= 2, eligibleScores[1] >= 0.14 else { continue }
            let combinedScore = eligibleScores[0] + eligibleScores[1]
            if combinedScore > bestCombinedScore {
                bestCombinedScore = combinedScore
                consensusShift = shift
            }
        }
        guard let consensusShift else { return .none }
        let overlap = contentHeight - consensusShift
        guard overlap >= 8 else { return .none }

        let verifiedScores = bands.compactMap { band -> CGFloat? in
            let informativePixels = informativePixelCount(
                previousGray,
                nextGray,
                previousY: previousGeometry.top + consensusShift,
                nextY: nextGeometry.top,
                length: overlap,
                xRange: band
            )
            guard informativePixels >= max(12, band.count / 5) else { return nil }
            let score = blockScore(
                previousGray,
                nextGray,
                previousY: previousGeometry.top + consensusShift,
                nextY: nextGeometry.top,
                length: overlap,
                xRange: band
            )
            return score >= 0.14 ? score : nil
        }
        guard verifiedScores.count >= 2 else { return .none }
        let confidence = median(of: verifiedScores) ?? 0

        let scale = nextImageWidth / CGFloat(nextGray.width)
        let fullScrollDistance = max(1, Int((CGFloat(consensusShift) * scale).rounded()))
        let fullContentOverlap = max(0, Int((CGFloat(overlap) * scale).rounded()))
        if let expectedScrollDistance, expectedScrollDistance > 0 {
            let allowedJump = max(
                Int(CGFloat(expectedScrollDistance) * 0.65),
                Int(CGFloat(nextGeometry.height) * scale * 0.28)
            )
            if abs(fullScrollDistance - expectedScrollDistance) > allowedJump {
                return .none
            }
        }
        return OverlapMatch(
            contentOverlapPixels: fullContentOverlap,
            scrollDistancePixels: fullScrollDistance,
            confidence: confidence,
            isDuplicate: false
        )
    }

    private func informativePixelCount(
        _ previous: GrayImage,
        _ next: GrayImage,
        previousY: Int,
        nextY: Int,
        length: Int,
        xRange: Range<Int>
    ) -> Int {
        guard length > 0 else { return 0 }
        var count = 0
        for y in 0..<length {
            for x in xRange where max(previous.edge(x, previousY + y), next.edge(x, nextY + y)) >= 10 {
                count += 1
            }
        }
        return count
    }

    private func blockScore(
        _ previous: GrayImage,
        _ next: GrayImage,
        previousY: Int,
        nextY: Int,
        length: Int,
        xRange: Range<Int>
    ) -> CGFloat {
        let intensity = normalizedCrossCorrelation(
            previous,
            next,
            previousY: previousY,
            nextY: nextY,
            length: length,
            xRange: xRange,
            useEdges: false
        )
        let edges = normalizedCrossCorrelation(
            previous,
            next,
            previousY: previousY,
            nextY: nextY,
            length: length,
            xRange: xRange,
            useEdges: true
        )
        if edges < -0.5 { return intensity }
        if intensity < -0.5 { return edges }
        return intensity * 0.65 + edges * 0.35
    }

    private func normalizedCrossCorrelation(
        _ previous: GrayImage,
        _ next: GrayImage,
        previousY: Int,
        nextY: Int,
        length: Int,
        xRange: Range<Int>,
        useEdges: Bool
    ) -> CGFloat {
        guard length > 0, !xRange.isEmpty else { return -1 }
        let xStride = max(1, xRange.count / 64)
        let yStride = max(1, length / 110)
        var weightSum = 0.0
        var sumA = 0.0
        var sumB = 0.0
        var sumAA = 0.0
        var sumBB = 0.0
        var sumAB = 0.0

        for y in stride(from: 0, to: length, by: yStride) {
            for x in stride(from: xRange.lowerBound, to: xRange.upperBound, by: xStride) {
                let edgeA = previous.edge(x, previousY + y)
                let edgeB = next.edge(x, nextY + y)
                let texture = min(1, Double(max(edgeA, edgeB)) / 32)
                let weight = 0.08 + texture * 0.92
                let a = Double(useEdges ? edgeA : previous[x, previousY + y])
                let b = Double(useEdges ? edgeB : next[x, nextY + y])
                weightSum += weight
                sumA += weight * a
                sumB += weight * b
                sumAA += weight * a * a
                sumBB += weight * b * b
                sumAB += weight * a * b
            }
        }

        guard weightSum > 8 else { return -1 }
        let covariance = weightSum * sumAB - sumA * sumB
        let varianceA = weightSum * sumAA - sumA * sumA
        let varianceB = weightSum * sumBB - sumB * sumB
        let numericalVarianceFloor = weightSum * weightSum * 0.01
        guard varianceA > numericalVarianceFloor, varianceB > numericalVarianceFloor else {
            return -1
        }
        let denominator = sqrt(max(0, varianceA * varianceB))
        guard denominator > 0.0001 else { return -1 }
        return CGFloat(max(-1, min(1, covariance / denominator)))
    }

    private func meanAbsoluteDifference(
        _ previous: GrayImage,
        _ next: GrayImage,
        previousY: Int,
        nextY: Int,
        length: Int,
        xRange: Range<Int>
    ) -> CGFloat {
        let xStride = max(1, xRange.count / 80)
        let yStride = max(1, length / 120)
        var difference = 0.0
        var count = 0.0
        for y in stride(from: 0, to: length, by: yStride) {
            for x in stride(from: xRange.lowerBound, to: xRange.upperBound, by: xStride) {
                difference += abs(Double(previous[x, previousY + y]) - Double(next[x, nextY + y]))
                count += 1
            }
        }
        guard count > 0 else { return 1 }
        return CGFloat(difference / count / 255)
    }

    private func isDuplicate(_ previous: GrayImage, _ next: GrayImage) -> Bool {
        let width = min(previous.width, next.width)
        let height = min(previous.height, next.height)
        let bands = horizontalBands(forWidth: width)
        guard bands.count == 3, height > 0 else { return false }
        let scores = bands.map { band in
            blockScore(
                previous,
                next,
                previousY: 0,
                nextY: 0,
                length: height,
                xRange: band
            )
        }
        let difference = meanAbsoluteDifference(
            previous,
            next,
            previousY: 0,
            nextY: 0,
            length: height,
            xRange: bands[0].lowerBound..<bands[2].upperBound
        )
        return scores.filter { $0 >= 0.97 }.count >= 2 && difference <= 0.008
    }

    private func horizontalBands(forWidth width: Int) -> [Range<Int>] {
        let inset = max(1, Int(CGFloat(width) * configuration.horizontalExclusionRatio))
        let usableWidth = width - inset * 2
        guard usableWidth >= 12 else { return [] }
        let bandWidth = usableWidth / 3
        return (0..<3).map { index in
            let start = inset + index * bandWidth
            let end = index == 2 ? width - inset : start + bandWidth
            return start..<end
        }
    }

    private func estimateFixedInsets(previous: UIImage, next: UIImage) -> FixedInsets? {
        guard
            let previousGray = GrayImage(image: previous, maximumWidth: analysisWidth),
            let nextGray = GrayImage(image: next, maximumWidth: analysisWidth)
        else { return nil }
        return estimateFixedInsets(previous: previousGray, next: nextGray)
    }

    private func estimateFixedInsets(previous: GrayImage, next: GrayImage) -> FixedInsets {
        let width = min(previous.width, next.width)
        let height = min(previous.height, next.height)
        guard width >= 20, height >= 40 else { return .zero }

        let horizontalInset = max(1, Int(CGFloat(width) * 0.04))
        let xRange = horizontalInset..<(width - horizontalInset)
        let windowHeight = max(4, height / 90)

        func windowEvidence(startY: Int) -> FixedWindowEvidence {
            let endY = min(height, startY + windowHeight)
            guard startY >= 0, endY > startY else { return .changed }
            let xStride = max(1, xRange.count / 120)
            var intensityDifference = 0.0
            var edgeDifference = 0.0
            var changedSamples = 0.0
            var texturedSamples = 0.0
            var sampleCount = 0.0

            for y in startY..<endY {
                for x in stride(from: xRange.lowerBound, to: xRange.upperBound, by: xStride) {
                    let intensityDelta = abs(Int(previous[x, y]) - Int(next[x, y]))
                    let edgeDelta = abs(Int(previous.edge(x, y)) - Int(next.edge(x, y)))
                    intensityDifference += Double(intensityDelta)
                    edgeDifference += Double(edgeDelta)
                    if intensityDelta > 18 || edgeDelta > 28 { changedSamples += 1 }
                    if max(previous.edge(x, y), next.edge(x, y)) >= 10 {
                        texturedSamples += 1
                    }
                    sampleCount += 1
                }
            }

            guard sampleCount > 0 else { return .changed }
            let textureRatio = texturedSamples / sampleCount
            guard textureRatio >= 0.012 else { return .uninformative }
            let intensityMAE = intensityDifference / sampleCount / 255
            let edgeMAE = edgeDifference / sampleCount / 255
            let changedRatio = changedSamples / sampleCount
            if intensityMAE <= 0.022 && edgeMAE <= 0.035 && changedRatio <= 0.14 {
                return .stable
            }
            return .changed
        }

        func scanFromEdge(maximumRatio: CGFloat, fromTop: Bool) -> Int {
            let maximumDepth = Int((CGFloat(height) * maximumRatio).rounded())
            var confirmedStableDepth = 0
            var consecutiveStable = 0
            var disruptionsAfterConfirmation = 0

            scanLoop: for depth in stride(from: 0, to: maximumDepth, by: windowHeight) {
                let startY = fromTop ? depth : height - depth - windowHeight
                guard startY >= 0 else { break }
                let evidence = windowEvidence(startY: startY)
                switch evidence {
                case .stable:
                    consecutiveStable += 1
                    if consecutiveStable >= 2 {
                        confirmedStableDepth = min(maximumDepth, depth + windowHeight)
                        disruptionsAfterConfirmation = 0
                    }
                case .changed:
                    consecutiveStable = 0
                    if confirmedStableDepth > 0 {
                        disruptionsAfterConfirmation += 1
                        if disruptionsAfterConfirmation >= 2 { break scanLoop }
                    }
                case .uninformative:
                    consecutiveStable = 0
                }
            }
            guard confirmedStableDepth > 0 else { return 0 }
            // Dilate the detected mask by one analysis window so antialiased
            // separators at the chrome/content boundary cannot enter NCC.
            return min(maximumDepth, confirmedStableDepth + windowHeight)
        }

        let top = scanFromEdge(maximumRatio: 0.25, fromTop: true)
        let bottom = scanFromEdge(maximumRatio: 0.22, fromTop: false)
        return FixedInsets(
            topRatio: CGFloat(top) / CGFloat(height),
            bottomRatio: CGFloat(bottom) / CGFloat(height)
        )
    }

    private func contentGeometry(
        forHeight height: Int,
        topExclusionRatio: CGFloat,
        bottomExclusionRatio: CGFloat
    ) -> ContentGeometry {
        let top = min(height - 2, max(0, Int((CGFloat(height) * topExclusionRatio).rounded())))
        let bottomInset = min(height - top - 1, max(0, Int((CGFloat(height) * bottomExclusionRatio).rounded())))
        return ContentGeometry(top: top, bottom: height - bottomInset)
    }

    private func drawSegment(of image: UIImage, fromY: Int, toY: Int, atY destinationY: Int) {
        guard
            let cgImage = image.cgImage,
            toY > fromY,
            let segment = cgImage.cropping(
                to: CGRect(x: 0, y: fromY, width: cgImage.width, height: toY - fromY)
            )
        else { return }
        UIImage(cgImage: segment, scale: 1, orientation: .up)
            .draw(at: CGPoint(x: 0, y: destinationY))
    }

    private func normalizedImage(_ image: UIImage) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }
        guard image.imageOrientation != .up else {
            return UIImage(cgImage: cgImage, scale: 1, orientation: .up)
        }

        let swapsAxes: Bool = {
            switch image.imageOrientation {
            case .left, .leftMirrored, .right, .rightMirrored: return true
            default: return false
            }
        }()
        let size = CGSize(
            width: swapsAxes ? cgImage.height : cgImage.width,
            height: swapsAxes ? cgImage.width : cgImage.height
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    private func scaled(_ image: UIImage, toWidth width: CGFloat) -> UIImage? {
        guard image.size.width > 0, image.size.height > 0, width > 0 else { return nil }
        if abs(image.size.width - width) < 0.5 { return image }
        let height = (image.size.height * width / image.size.width).rounded()
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { _ in
            image.draw(in: CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    private func resizedPreview(_ image: UIImage) -> UIImage? {
        let maximumWidth: CGFloat = 900
        let maximumPixels: CGFloat = 16_000_000
        var scale = min(1, maximumWidth / image.size.width)
        let scaledPixels = image.size.width * image.size.height * scale * scale
        if scaledPixels > maximumPixels {
            scale *= sqrt(maximumPixels / scaledPixels)
        }
        guard scale < 0.999 else { return image }

        let size = CGSize(
            width: max(1, (image.size.width * scale).rounded()),
            height: max(1, (image.size.height * scale).rounded())
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    private func median<T: BinaryInteger>(of values: [T]) -> Int? {
        guard !values.isEmpty else { return nil }
        let sorted = values.map(Int.init).sorted()
        return sorted[sorted.count / 2]
    }

    private func median(of values: [CGFloat]) -> CGFloat? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        return sorted[sorted.count / 2]
    }

    private func medianScore(_ candidates: [ShiftCandidate]) -> CGFloat {
        median(of: candidates.map(\.score)) ?? -1
    }
}

private struct ContentGeometry {
    let top: Int
    let bottom: Int
    var height: Int { bottom - top }
}

private struct FixedInsets {
    let topRatio: CGFloat
    let bottomRatio: CGFloat

    static let zero = FixedInsets(topRatio: 0, bottomRatio: 0)
}

private enum FixedWindowEvidence: Equatable {
    case stable
    case changed
    case uninformative
}

private struct ShiftCandidate {
    let shift: Int
    let score: CGFloat
    var prominence: CGFloat = 0
}

private struct GrayImage {
    let width: Int
    let height: Int
    let pixels: [UInt8]
    let edges: [UInt8]

    init?(image: UIImage, maximumWidth: Int) {
        guard let cgImage = image.cgImage else { return nil }
        let targetWidth = max(1, min(maximumWidth, cgImage.width))
        let targetHeight = max(1, Int((CGFloat(cgImage.height) * CGFloat(targetWidth) / CGFloat(cgImage.width)).rounded()))
        var storage = [UInt8](repeating: 0, count: targetWidth * targetHeight)
        let created = storage.withUnsafeMutableBytes { buffer -> Bool in
            guard let baseAddress = buffer.baseAddress,
                  let context = CGContext(
                    data: baseAddress,
                    width: targetWidth,
                    height: targetHeight,
                    bitsPerComponent: 8,
                    bytesPerRow: targetWidth,
                    space: CGColorSpaceCreateDeviceGray(),
                    bitmapInfo: CGImageAlphaInfo.none.rawValue
                  ) else { return false }
            context.interpolationQuality = .medium
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
            return true
        }
        guard created else { return nil }

        var edgeStorage = [UInt8](repeating: 0, count: storage.count)
        if targetWidth > 2, targetHeight > 2 {
            for y in 1..<(targetHeight - 1) {
                for x in 1..<(targetWidth - 1) {
                    let horizontal = abs(Int(storage[y * targetWidth + x + 1]) - Int(storage[y * targetWidth + x - 1]))
                    let vertical = abs(Int(storage[(y + 1) * targetWidth + x]) - Int(storage[(y - 1) * targetWidth + x]))
                    edgeStorage[y * targetWidth + x] = UInt8(min(255, horizontal + vertical))
                }
            }
        }

        width = targetWidth
        height = targetHeight
        pixels = storage
        edges = edgeStorage
    }

    subscript(x: Int, y: Int) -> UInt8 {
        pixels[y * width + x]
    }

    func edge(_ x: Int, _ y: Int) -> UInt8 {
        edges[y * width + x]
    }
}
