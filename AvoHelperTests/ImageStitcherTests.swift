import XCTest
@testable import AvoHelper

final class ImageStitcherTests: XCTestCase {
    func testDetectsKnownVerticalOverlap() throws {
        let source = makePatternImage(size: CGSize(width: 160, height: 360))
        let first = try XCTUnwrap(crop(source, rect: CGRect(x: 0, y: 0, width: 160, height: 220)))
        let second = try XCTUnwrap(crop(source, rect: CGRect(x: 0, y: 140, width: 160, height: 220)))

        let match = ImageStitcher().detectOverlap(previous: first, next: second)

        XCTAssertFalse(match.isDuplicate)
        XCTAssertEqual(match.scrollDistancePixels, 140, accuracy: 3)
        XCTAssertGreaterThan(match.contentOverlapPixels, 35)
        XCTAssertGreaterThanOrEqual(match.confidence, 0.72)
    }

    func testDetectsExactDuplicate() {
        let image = makePatternImage(size: CGSize(width: 160, height: 240))

        let match = ImageStitcher().detectOverlap(previous: image, next: image)

        XCTAssertTrue(match.isDuplicate)
        XCTAssertEqual(match.scrollDistancePixels, 0)
        XCTAssertGreaterThan(match.contentOverlapPixels, 190)
    }

    func testUnrelatedImagesAreNotCropped() {
        let first = solidImage(color: .red)
        let second = solidImage(color: .blue)

        let match = ImageStitcher().detectOverlap(previous: first, next: second)

        XCTAssertEqual(match, .none)
    }

    func testStitchAppendsOnlyNewPixels() async throws {
        let source = makePatternImage(size: CGSize(width: 160, height: 360))
        let first = try XCTUnwrap(crop(source, rect: CGRect(x: 0, y: 0, width: 160, height: 220)))
        let second = try XCTUnwrap(crop(source, rect: CGRect(x: 0, y: 140, width: 160, height: 220)))

        let artifact = try await ImageStitcher().stitch(images: [first, second])
        defer { try? FileManager.default.removeItem(at: artifact.pngURL) }

        XCTAssertEqual(artifact.pixelSize.width, 160)
        XCTAssertEqual(artifact.pixelSize.height, 360, accuracy: 3)
        XCTAssertEqual(artifact.seams.first?.status, .matched)
    }

    func testOneDynamicBlockDoesNotBreakVoting() throws {
        let source = makePatternImage(size: CGSize(width: 160, height: 420))
        let first = try XCTUnwrap(crop(source, rect: CGRect(x: 0, y: 0, width: 160, height: 220)))
        let second = try XCTUnwrap(crop(source, rect: CGRect(x: 0, y: 140, width: 160, height: 220)))
        let secondWithBadge = addBadge(to: second)

        let configuration = StitchingConfiguration(topExclusionRatio: 0, bottomExclusionRatio: 0)
        let match = ImageStitcher(configuration: configuration)
            .detectOverlap(previous: first, next: secondWithBadge)

        XCTAssertFalse(match.isDuplicate)
        XCTAssertEqual(match.scrollDistancePixels, 140, accuracy: 4)
        XCTAssertGreaterThanOrEqual(match.confidence, 0.72)
    }

    func testAutomaticallyHandlesDifferentFixedChromeHeights() throws {
        let source = makePatternImage(size: CGSize(width: 160, height: 720))
        let cases: [(top: Int, bottom: Int, scroll: Int)] = [
            (top: 0, bottom: 0, scroll: 96),
            (top: 20, bottom: 34, scroll: 112),
            (top: 52, bottom: 18, scroll: 88),
            (top: 36, bottom: 48, scroll: 124)
        ]

        for item in cases {
            let first = try XCTUnwrap(
                makeScreenshot(
                    content: source,
                    offset: 0,
                    topHeight: item.top,
                    bottomHeight: item.bottom
                )
            )
            let second = try XCTUnwrap(
                makeScreenshot(
                    content: source,
                    offset: item.scroll,
                    topHeight: item.top,
                    bottomHeight: item.bottom
                )
            )

            let match = ImageStitcher().detectOverlap(previous: first, next: second)

            XCTAssertTrue(match.isMatched, "top=\(item.top), bottom=\(item.bottom)")
            XCTAssertEqual(
                match.scrollDistancePixels,
                item.scroll,
                accuracy: 4,
                "top=\(item.top), bottom=\(item.bottom)"
            )
        }
    }

    func testVariableFixedChromeIsPresentOnlyAtOutputEdges() async throws {
        let source = makePatternImage(size: CGSize(width: 160, height: 720))
        let scroll = 118
        let first = try XCTUnwrap(
            makeScreenshot(content: source, offset: 0, topHeight: 42, bottomHeight: 32)
        )
        let second = try XCTUnwrap(
            makeScreenshot(content: source, offset: scroll, topHeight: 42, bottomHeight: 32)
        )

        let artifact = try await ImageStitcher().stitch(images: [first, second])
        defer { try? FileManager.default.removeItem(at: artifact.pngURL) }

        XCTAssertEqual(artifact.pixelSize.width, 160)
        XCTAssertEqual(artifact.pixelSize.height, CGFloat(260 + scroll), accuracy: 4)
        XCTAssertEqual(artifact.seams.first?.status, .matched)
    }

    func testDetectsVerySmallLowTextureOverlap() throws {
        let source = makeLowTextureImage(size: CGSize(width: 160, height: 520))
        let first = try XCTUnwrap(
            makeScreenshot(content: source, offset: 0, topHeight: 35, bottomHeight: 35)
        )
        let second = try XCTUnwrap(
            makeScreenshot(content: source, offset: 180, topHeight: 35, bottomHeight: 35)
        )

        let match = ImageStitcher().detectOverlap(previous: first, next: second)

        XCTAssertTrue(match.isMatched)
        XCTAssertEqual(match.scrollDistancePixels, 180, accuracy: 4)
        XCTAssertLessThanOrEqual(match.contentOverlapPixels, 16)
    }

    func testUnmatchedStitchPreservesBothCompleteFrames() async throws {
        let red = solidImage(color: .red, size: CGSize(width: 160, height: 520))
        let blue = solidImage(color: .blue, size: CGSize(width: 160, height: 520))
        let first = try XCTUnwrap(
            makeScreenshot(content: red, offset: 0, topHeight: 42, bottomHeight: 32)
        )
        let second = try XCTUnwrap(
            makeScreenshot(content: blue, offset: 0, topHeight: 42, bottomHeight: 32)
        )

        let stitcher = ImageStitcher(
            configuration: StitchingConfiguration(
                maximumScrollRatio: 0.02,
                nccThreshold: 1.1
            )
        )
        let artifact = try await stitcher.stitch(images: [first, second])
        defer { try? FileManager.default.removeItem(at: artifact.pngURL) }

        XCTAssertEqual(artifact.seams.first?.status, .unmatched)
        XCTAssertEqual(artifact.pixelSize.height, 520, accuracy: 0.5)
    }

    private func makePatternImage(size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))

            for row in 0..<Int(size.height) {
                UIColor(
                    hue: CGFloat(row) / size.height,
                    saturation: 0.72,
                    brightness: 0.88,
                    alpha: 1
                ).setFill()
                context.fill(CGRect(x: 0, y: CGFloat(row), width: size.width, height: 1))
            }

            for index in 0..<12 {
                let y = CGFloat(index) * 30
                UIColor(
                    hue: CGFloat((index * 7) % 12) / 12,
                    saturation: 0.88,
                    brightness: 0.48,
                    alpha: 1
                ).setFill()
                let markerX = CGFloat(12 + (index * 43) % 118)
                context.fill(
                    CGRect(
                        x: markerX,
                        y: y + 18,
                        width: CGFloat(12 + (index % 3) * 6),
                        height: CGFloat(4 + index % 4)
                    )
                )
                "\(index)".draw(
                    at: CGPoint(x: 24 + CGFloat(index % 4) * 17, y: y + 3),
                    withAttributes: [
                        .font: UIFont.boldSystemFont(ofSize: 14),
                        .foregroundColor: UIColor.black
                    ]
                )
            }
        }
    }

    private func solidImage(
        color: UIColor,
        size: CGSize = CGSize(width: 120, height: 220)
    ) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    private func makeLowTextureImage(size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            UIColor(white: 0.96, alpha: 1).setFill()
            UIRectFill(CGRect(origin: .zero, size: size))
            UIColor(white: 0.72, alpha: 1).setStroke()
            let outline = UIBezierPath(
                roundedRect: CGRect(x: 12, y: 181, width: 136, height: 92),
                cornerRadius: 12
            )
            outline.lineWidth = 2
            outline.stroke()
        }
    }

    private func addBadge(to image: UIImage) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: image.size, format: format).image { context in
            image.draw(at: .zero)
            UIColor.magenta.setFill()
            context.fill(CGRect(x: 124, y: 72, width: 24, height: 24))
        }
    }

    private func makeScreenshot(
        content: UIImage,
        offset: Int,
        topHeight: Int,
        bottomHeight: Int
    ) -> UIImage? {
        let screenshotSize = CGSize(width: 160, height: 260)
        let viewportHeight = Int(screenshotSize.height) - topHeight - bottomHeight
        guard viewportHeight > 0 else { return nil }
        guard let body = crop(
            content,
            rect: CGRect(x: 0, y: offset, width: 160, height: viewportHeight)
        ) else { return nil }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: screenshotSize, format: format).image { context in
            if topHeight > 0 {
                UIColor(white: 0.93, alpha: 1).setFill()
                context.fill(CGRect(x: 0, y: 0, width: 160, height: topHeight))
                UIColor.black.setFill()
                context.fill(CGRect(x: 12, y: max(3, topHeight / 3), width: 34, height: 3))
                context.fill(CGRect(x: 112, y: max(3, topHeight / 3), width: 28, height: 3))
            }

            body.draw(at: CGPoint(x: 0, y: topHeight))

            if bottomHeight > 0 {
                let start = Int(screenshotSize.height) - bottomHeight
                UIColor(white: 0.96, alpha: 1).setFill()
                context.fill(CGRect(x: 0, y: start, width: 160, height: bottomHeight))
                UIColor.darkGray.setStroke()
                let button = UIBezierPath(
                    roundedRect: CGRect(x: 20, y: start + 5, width: 52, height: max(8, bottomHeight - 10)),
                    cornerRadius: 7
                )
                button.lineWidth = 2
                button.stroke()
            }
        }
    }

    private func crop(_ image: UIImage, rect: CGRect) -> UIImage? {
        guard let cgImage = image.cgImage?.cropping(to: rect) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
