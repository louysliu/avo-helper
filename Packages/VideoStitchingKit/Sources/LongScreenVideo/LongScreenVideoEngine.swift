import Foundation
import LongScreenBridge
import VideoStitchingCore

private final class Callbacks {
    var reader: VideoFrameReader?
    var pixels: UnsafeMutablePointer<UInt8>?
    var failure: Error?
    let url: URL
    let budget: Int
    deinit { pixels?.deallocate(); reader?.cancel() }
    let progress: @Sendable (VideoStitchProgress) -> Void
    let cancelled: @Sendable () -> Bool
    init(_ url: URL, _ budget: Int, _ progress: @escaping @Sendable (VideoStitchProgress) -> Void, _ cancelled: @escaping @Sendable () -> Bool) { self.url = url; self.budget = budget; self.progress = progress; self.cancelled = cancelled }
}
public struct LongScreenVideoEngine: VideoStitchEngine {
    public init() {}
    public func stitch(_ request: VideoStitchRequest, progress: @escaping @Sendable (VideoStitchProgress) -> Void, isCancelled: @escaping @Sendable () -> Bool) throws -> VideoStitchResult {
        let fm = FileManager.default
        try fm.createDirectory(at: request.outputDirectory, withIntermediateDirectories: true)
        let scratch = request.outputDirectory.appendingPathComponent("long-screen-work-" + UUID().uuidString)
        try fm.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: scratch) }
        let probe = try VideoFrameReader(url: request.inputURL)
        guard let first = try probe.next() else { throw VideoStitchError.invalidVideo }
        guard probe.duration <= 180 else { throw VideoStitchError.limitExceeded("Long Screen 当前支持最长 3 分钟视频") }
        let width = first.width; let height = first.height; let duration = probe.duration
        probe.cancel()
        let callbacks = Callbacks(request.inputURL, request.maximumWorkingBytes, progress, isCancelled)
        let context = Unmanaged.passRetained(callbacks).toOpaque()
        defer { Unmanaged<Callbacks>.fromOpaque(context).release() }
        let response = scratch.path.withCString { output in
            ls_run(width, height, duration, { context in
                guard let context else { return -1 }
                let c = Unmanaged<Callbacks>.fromOpaque(context).takeUnretainedValue()
                do { c.reader?.cancel(); c.reader = try VideoFrameReader(url: c.url); return 0 }
                catch { c.failure = error; return -1 }
            }, { context, frame, pixels, count in
                guard let context, let frame, let pixels, let count else { return -1 }
                let c = Unmanaged<Callbacks>.fromOpaque(context).takeUnretainedValue()
                if c.cancelled() { return -1 }
                do {
                    guard let value = try c.reader?.next() else { return 0 }
                    guard value.rgba.count <= c.budget / 8 else { throw VideoStitchError.limitExceeded("单帧超过 Long Screen 工作内存预算") }
                    c.pixels?.deallocate()
                    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: value.rgba.count)
                    value.rgba.withUnsafeBufferPointer { buffer.initialize(from: $0.baseAddress!, count: $0.count) }
                    c.pixels = buffer
                    frame.pointee = LSFrame(time: value.timestamp, duration: value.duration, width: value.width, height: value.height)
                    pixels.pointee = UnsafePointer(buffer); count.pointee = value.rgba.count
                    return 1
                } catch { c.failure = error; return -1 }
            }, output, request.maximumOutputPixels, request.maximumWorkingBytes, { context, fraction, message in
                guard let context else { return 1 }
                let c = Unmanaged<Callbacks>.fromOpaque(context).takeUnretainedValue()
                let raw = message.map { String(cString: $0) } ?? ""
                let phase = raw.split(separator: ":", maxSplits: 1).first.map(String.init) ?? ""
                let label = ["scanning": "分析视频", "solving": "对齐画面", "optimizing": "优化拼接", "rendering": "合成长图", "revealing": "补全可见内容", "framing": "整理画面", "pyramid": "生成预览", "complete": "处理完成", "partial": "保存可用结果"][phase] ?? "处理视频"
                c.progress(.init(fraction: fraction, message: "Long Screen · " + label))
                return c.cancelled() ? 1 : 0
            }, context)
        }
        guard let response else { throw VideoStitchError.processingFailed("Long Screen 没有返回结果") }
        defer { ls_string_free(response) }
        struct Reply: Decodable {
            struct Image: Decodable { let file: String; let width: Int; let height: Int }
            var images: [Image]?; var warnings: [String]?; var partial: Bool?; var error: String?
        }
        let reply = try JSONDecoder().decode(Reply.self, from: Data(String(cString: response).utf8))
        if let failure = callbacks.failure, (reply.images ?? []).isEmpty { throw failure }
        if let error = reply.error { if isCancelled() { throw VideoStitchError.cancelled }; throw VideoStitchError.processingFailed(error) }
        let images = try (reply.images ?? []).map { image -> VideoStitchImage in
            let destination = request.outputDirectory.appendingPathComponent(UUID().uuidString + ".png")
            try fm.moveItem(at: scratch.appendingPathComponent(image.file), to: destination)
            return .init(url: destination, width: image.width, height: image.height)
        }
        if images.isEmpty && isCancelled() { throw VideoStitchError.cancelled }
        if images.isEmpty && (reply.warnings ?? []).contains(where: { $0.contains("output pixel budget") || $0.contains("disk budget exceeded") }) { throw VideoStitchError.limitExceeded("Long Screen 输出超过像素预算") }
        guard !images.isEmpty else { throw VideoStitchError.processingFailed("Long Screen 未能重建可导出的图像") }
        var warnings = reply.warnings ?? []
        if let failure = callbacks.failure { warnings.append(failure.localizedDescription) }
        return .init(images: images, warnings: warnings, isPartial: (reply.partial ?? false) || callbacks.failure != nil || isCancelled())
    }
}
