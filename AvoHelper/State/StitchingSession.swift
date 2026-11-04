import Observation
import PhotosUI
import SwiftUI

@MainActor
@Observable
final class StitchingSession {
    var pickerItems: [PhotosPickerItem] = []
    var screenshots: [SelectedScreenshot] = []
    var path: [AppRoute] = []
    var artifact: StitchArtifact?
    var crop: NormalizedCrop = .full
    var croppedPreview: UIImage?
    var isLoadingSelection = false
    var isProcessing = false
    var isExporting = false
    var message: UserMessage?
    var shareItem: ShareItem?
    var algorithm: AppStitchAlgorithm = .ekibun

    private let stitcher: ImageStitcher
    private let exporter: ExportService

    init(
        stitcher: ImageStitcher = ImageStitcher(),
        exporter: ExportService = ExportService()
    ) {
        self.stitcher = stitcher
        self.exporter = exporter

        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--demo-result") {
            prepareDemoArtifact()
        }
        #endif
    }

    var canStitch: Bool {
        screenshots.count >= 2 && !isLoadingSelection && !isProcessing
    }

    var warningSeams: [SeamReport] {
        artifact?.seams.filter { $0.status == .unmatched } ?? []
    }

    func synchronizePickerItems(_ items: [PhotosPickerItem]) async {
        guard !isProcessing else { return }
        isLoadingSelection = true
        defer { isLoadingSelection = false }

        screenshots.removeAll { existing in
            !items.contains(existing.pickerItem)
        }

        for item in items where !screenshots.contains(where: { $0.pickerItem == item }) {
            do {
                guard
                    let data = try await item.loadTransferable(type: Data.self),
                    let image = UIImage(data: data)
                else { throw StitchingError.invalidImage }
                screenshots.append(
                    SelectedScreenshot(
                        id: item.itemIdentifier ?? UUID().uuidString,
                        pickerItem: item,
                        image: image
                    )
                )
            } catch {
                message = UserMessage(
                    title: "无法读取截图",
                    message: error.localizedDescription
                )
            }
        }

        pickerItems = screenshots.map(\.pickerItem)
    }

    func removeScreenshots(at offsets: IndexSet) {
        screenshots.remove(atOffsets: offsets)
        pickerItems = screenshots.map(\.pickerItem)
    }

    func moveScreenshots(from source: IndexSet, to destination: Int) {
        screenshots.move(fromOffsets: source, toOffset: destination)
        pickerItems = screenshots.map(\.pickerItem)
    }

    func stitch() async {
        guard canStitch else { return }
        isProcessing = true
        defer { isProcessing = false }

        do {
            let result: StitchArtifact
            if let choice = algorithm.engineChoice {
                result = try await PortedImageStitcher(choice: choice).stitch(images: screenshots.map(\.image))
            } else {
                result = try await stitcher.stitch(images: screenshots.map(\.image))
            }
            artifact = result
            crop = .full
            croppedPreview = result.preview
            path.append(.result)
        } catch is CancellationError {
            return
        } catch {
            message = UserMessage(title: "拼接失败", message: error.localizedDescription)
        }
    }

    func applyCrop(_ newCrop: NormalizedCrop) {
        guard let artifact else { return }
        let normalized = newCrop.clamped()
        crop = normalized
        croppedPreview = ImageCropper.crop(artifact.preview, to: normalized) ?? artifact.preview
    }

    func saveToPhotos() async {
        guard let artifact else { return }
        isExporting = true
        defer { isExporting = false }

        var temporaryURL: URL?
        do {
            let pngURL = try ImageCropper.writeCroppedPNG(sourceURL: artifact.pngURL, crop: crop)
            if pngURL != artifact.pngURL { temporaryURL = pngURL }
            try await exporter.savePNGToPhotos(pngURL)
            message = UserMessage(title: "已保存", message: "长图已保存到相册。")
        } catch {
            message = UserMessage(title: "保存失败", message: error.localizedDescription)
        }
        if let temporaryURL { try? FileManager.default.removeItem(at: temporaryURL) }
    }

    func preparePDFShare() async {
        guard let artifact else { return }
        isExporting = true
        defer { isExporting = false }

        var croppedURL: URL?
        do {
            let pngURL = try ImageCropper.writeCroppedPNG(sourceURL: artifact.pngURL, crop: crop)
            if pngURL != artifact.pngURL { croppedURL = pngURL }
            let pdfURL = try exporter.makeSinglePagePDF(fromPNG: pngURL)
            shareItem = ShareItem(url: pdfURL)
        } catch {
            message = UserMessage(title: "导出失败", message: error.localizedDescription)
        }
        if let croppedURL { try? FileManager.default.removeItem(at: croppedURL) }
    }

    func finishSharing(_ item: ShareItem) {
        try? FileManager.default.removeItem(at: item.url)
        if shareItem?.id == item.id { shareItem = nil }
    }

    func startOver() {
        if let artifact { try? FileManager.default.removeItem(at: artifact.pngURL) }
        artifact = nil
        crop = .full
        croppedPreview = nil
        pickerItems = []
        screenshots = []
        path = []
    }

    #if DEBUG
    private func prepareDemoArtifact() {
        let size = CGSize(width: 720, height: 2600)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.systemGroupedBackground.setFill()
            context.fill(CGRect(origin: .zero, size: size))

            let colors: [UIColor] = [.systemGreen, .systemBlue, .systemOrange, .systemPurple]
            for index in 0..<8 {
                let y = CGFloat(index) * 310 + 70
                let card = CGRect(x: 44, y: y, width: 632, height: 250)
                UIColor.secondarySystemGroupedBackground.setFill()
                UIBezierPath(roundedRect: card, cornerRadius: 28).fill()
                colors[index % colors.count].setFill()
                UIBezierPath(ovalIn: CGRect(x: 76, y: y + 40, width: 72, height: 72)).fill()

                let title = "示例内容 \(index + 1)"
                title.draw(
                    at: CGPoint(x: 176, y: y + 42),
                    withAttributes: [
                        .font: UIFont.boldSystemFont(ofSize: 28),
                        .foregroundColor: UIColor.label
                    ]
                )
                "拖动裁剪框的四个角，保留你需要的区域。".draw(
                    in: CGRect(x: 76, y: y + 135, width: 560, height: 70),
                    withAttributes: [
                        .font: UIFont.systemFont(ofSize: 22),
                        .foregroundColor: UIColor.secondaryLabel
                    ]
                )
            }
        }
        guard let data = image.pngData() else { return }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("avo-demo-\(UUID().uuidString).png")
        guard (try? data.write(to: url, options: .atomic)) != nil else { return }
        artifact = StitchArtifact(pngURL: url, preview: image, pixelSize: size, seams: [])
        croppedPreview = image
        path = [.result]
    }
    #endif
}
