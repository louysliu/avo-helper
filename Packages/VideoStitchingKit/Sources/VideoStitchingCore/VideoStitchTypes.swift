import Foundation

public struct VideoStitchRequest: Sendable {
    public let inputURL: URL
    public let outputDirectory: URL
    public let maximumOutputPixels: Int
    public let maximumWorkingBytes: Int

    public init(inputURL: URL, outputDirectory: URL,
                maximumOutputPixels: Int = 45_000_000, maximumWorkingBytes: Int = 2_000_000_000) {
        self.inputURL = inputURL
        self.outputDirectory = outputDirectory
        self.maximumOutputPixels = maximumOutputPixels
        self.maximumWorkingBytes = maximumWorkingBytes
    }
}

public struct VideoStitchProgress: Sendable {
    public let fraction: Double
    public let message: String
    public init(fraction: Double, message: String) {
        self.fraction = fraction.isFinite ? min(1, max(0, fraction)) : 0
        self.message = message
    }
}

public struct VideoStitchImage: Sendable {
    public let url: URL
    public let width: Int
    public let height: Int
    public init(url: URL, width: Int, height: Int) {
        self.url = url; self.width = width; self.height = height
    }
}

public struct VideoStitchResult: Sendable {
    public let images: [VideoStitchImage]
    public let warnings: [String]
    public let isPartial: Bool
    public init(images: [VideoStitchImage], warnings: [String], isPartial: Bool) {
        self.images = images; self.warnings = warnings; self.isPartial = isPartial
    }
}

public protocol VideoStitchEngine: Sendable {
    func stitch(_ request: VideoStitchRequest,
                progress: @escaping @Sendable (VideoStitchProgress) -> Void,
                isCancelled: @escaping @Sendable () -> Bool) throws -> VideoStitchResult
}

public enum VideoStitchError: LocalizedError {
    case invalidVideo
    case cancelled
    case limitExceeded(String)
    case processingFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidVideo: return "无法读取这个视频，请选择有效的滚动录屏。"
        case .cancelled: return "已取消转换。"
        case .limitExceeded(let reason), .processingFailed(let reason): return reason
        }
    }
}

/// Shared between the UI task and a synchronous native engine worker.
public final class VideoCancellationToken: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    public init() {}
    public func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    public var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
}
