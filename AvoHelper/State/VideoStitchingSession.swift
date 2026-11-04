import AVFoundation
import Observation
import PhotosUI
import SwiftUI
import VideoStitchingCore
import LongScreenVideo
import HyprLongshotVideo

@MainActor
@Observable
final class VideoStitchingSession {
    var pickerItem: PhotosPickerItem?
    var inputURL: URL?
    var inputName = ""
    var thumbnail: UIImage?
    var duration: Double = 0
    var algorithm: VideoAlgorithm = .longScreen
    var isImporting = false
    var isProcessing = false
    var isCancelling = false
    var progress = VideoStitchProgress(fraction: 0, message: "准备转换…")
    var status: String?
    var message: UserMessage?
    private var cancellation: VideoCancellationToken?
    var isBusy: Bool { isImporting || isProcessing }

    func importPhoto(_ item: PhotosPickerItem) async {
        guard !isBusy else { return }
        isImporting = true
        defer { isImporting = false }
        do {
            guard let imported = try await item.loadTransferable(type: ImportedVideo.self) else {
                throw VideoStitchError.invalidVideo
            }
            try await acceptCopiedVideo(imported.url, name: "相册录屏")
        } catch {
            message = UserMessage(title: "无法导入视频", message: error.localizedDescription)
        }
    }

    func importFile(_ url: URL) async {
        guard !isBusy else { return }
        isImporting = true
        defer { isImporting = false }
        let hasAccess = url.startAccessingSecurityScopedResource()
        defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }
        do {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= 2_000_000_000 else { throw VideoImportError.tooLarge }
            let destination = FileManager.default.temporaryDirectory
                .appendingPathComponent("avo-video-input-\(UUID().uuidString)")
                .appendingPathExtension(url.pathExtension.isEmpty ? "mov" : url.pathExtension)
            try await Task.detached(priority: .userInitiated) {
                try FileManager.default.copyItem(at: url, to: destination)
            }.value
            try await acceptCopiedVideo(destination, name: url.lastPathComponent)
        } catch {
            message = UserMessage(title: "无法导入视频", message: error.localizedDescription)
        }
    }

    private func acceptCopiedVideo(_ url: URL, name: String) async throws {
        do {
            let details = try await Task.detached(priority: .userInitiated) { () -> (Double, CGImage?) in
                let reader = try VideoFrameReader(url: url)
                guard try reader.next() != nil else { throw VideoStitchError.invalidVideo }
                reader.cancel()
                let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
                generator.appliesPreferredTrackTransform = true
                generator.maximumSize = CGSize(width: 480, height: 640)
                let image = try? generator.copyCGImage(at: .zero, actualTime: nil)
                return (reader.duration, image)
            }.value
            if let previous = inputURL { try? FileManager.default.removeItem(at: previous) }
            inputURL = url; inputName = name; duration = details.0
            thumbnail = details.1.map { UIImage(cgImage: $0) }
            status = nil
        } catch {
            try? FileManager.default.removeItem(at: url)
            throw error
        }
    }

    func convert(into session: StitchingSession) async {
        guard !isBusy, let inputURL else { return }
        let selectedAlgorithm = algorithm
        let token = VideoCancellationToken()
        cancellation = token
        isProcessing = true; isCancelling = false; status = nil
        progress = VideoStitchProgress(fraction: 0, message: "准备转换…")
        UIApplication.shared.isIdleTimerDisabled = true
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("avo-video-result-\(UUID().uuidString)")
        var transferredOutput = false
        defer {
            isProcessing = false; isCancelling = false; cancellation = nil
            UIApplication.shared.isIdleTimerDisabled = false
            if !transferredOutput { try? FileManager.default.removeItem(at: directory) }
        }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let request = VideoStitchRequest(inputURL: inputURL, outputDirectory: directory,
                maximumWorkingBytes: Int(min(512_000_000, ProcessInfo.processInfo.physicalMemory / 8)))
            let relay = VideoProgressRelay { [weak self] update in
                Task { @MainActor [weak self] in
                    guard let self, self.isProcessing, self.cancellation === token, !self.isCancelling else { return }
                    self.progress = update
                }
            }
            let result = try await withTaskCancellationHandler {
                try await Task.detached(priority: .userInitiated) {
                    let engine: any VideoStitchEngine = selectedAlgorithm == .longScreen
                        ? LongScreenVideoEngine() : HyprLongshotVideoEngine()
                    return try engine.stitch(request, progress: { relay.send($0) }, isCancelled: { token.isCancelled })
                }.value
            } onCancel: { token.cancel() }
            guard !token.isCancelled else { throw VideoStitchError.cancelled }
            try session.showVideoResult(result, algorithm: selectedAlgorithm.title, directory: directory)
            transferredOutput = true
        } catch {
            if token.isCancelled || error is CancellationError {
                status = "已取消转换，可以重新选择算法或视频。"
            } else {
                message = UserMessage(title: "转换失败", message: error.localizedDescription)
            }
        }
    }

    func cancel() {
        guard isProcessing else { return }
        isCancelling = true
        progress = VideoStitchProgress(fraction: progress.fraction, message: "正在取消并清理临时文件…")
        cancellation?.cancel()
    }

    func removeInput() {
        guard !isBusy else { return }
        if let inputURL { try? FileManager.default.removeItem(at: inputURL) }
        inputURL = nil; thumbnail = nil; inputName = ""; duration = 0; pickerItem = nil; status = nil
    }
}

private final class VideoProgressRelay: @unchecked Sendable {
    private let lock = NSLock()
    private var lastUpdate = Date.distantPast
    private let callback: @Sendable (VideoStitchProgress) -> Void
    init(callback: @escaping @Sendable (VideoStitchProgress) -> Void) { self.callback = callback }
    func send(_ update: VideoStitchProgress) {
        lock.lock()
        let now = Date()
        let emit = now.timeIntervalSince(lastUpdate) >= 0.12 || update.fraction >= 1
        if emit { lastUpdate = now }
        lock.unlock()
        if emit { callback(update) }
    }
}
