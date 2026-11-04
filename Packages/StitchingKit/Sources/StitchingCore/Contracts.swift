import Foundation

/// Opaque RGBA8, row-major, top-down, unscaled source pixels.
public struct RasterImage: Sendable {
    public let width: Int
    public let height: Int
    public let pixels: [UInt8]

    public init(width: Int, height: Int, pixels: [UInt8]) throws {
        guard width > 0, height > 0, width <= 50_000, height <= 100_000,
              width * height <= 60_000_000, pixels.count == width * height * 4 else {
            throw StitchError.invalidImage
        }
        self.width = width
        self.height = height
        self.pixels = pixels
    }
}

public enum AlignmentStatus: String, Codable, Sendable {
    case matched, duplicate, unmatched
}

/// next(x,y) corresponds to previous(x + offsetX,y + offsetY).
/// Offsets are in ORIGINAL pixels, not cropped-content coordinates.
public struct PairAlignment: Codable, Sendable {
    public let offsetX: Int
    public let offsetY: Int
    public let confidence: Double
    public let status: AlignmentStatus
    public let diagnostic: String

    public init(offsetX: Int = 0, offsetY: Int = 0, confidence: Double = 0,
                status: AlignmentStatus, diagnostic: String = "") {
        self.offsetX = offsetX
        self.offsetY = offsetY
        self.confidence = confidence
        self.status = status
        self.diagnostic = diagnostic
    }
}

/// Source rows containing scrolling content; bottom is exclusive.
public struct FrameBounds: Codable, Sendable {
    public let top: Int
    public let bottom: Int
    public init(top: Int, bottom: Int) { self.top = top; self.bottom = bottom }
}

public struct StitchPlan: Codable, Sendable {
    public let engineID: String
    /// Exactly one bound per input and one alignment per adjacent pair.
    public let bounds: [FrameBounds]
    public let alignments: [PairAlignment]
    public let notes: [String]
    public init(engineID: String, bounds: [FrameBounds], alignments: [PairAlignment], notes: [String] = []) {
        self.engineID = engineID; self.bounds = bounds
        self.alignments = alignments; self.notes = notes
    }
}

public protocol ScreenshotStitchingEngine {
    var id: String { get }
    func analyze(_ images: [RasterImage]) throws -> StitchPlan
}

public enum StitchError: Error, LocalizedError {
    case invalidImage, incompatibleDimensions, invalidPlan, outputTooLarge
    public var errorDescription: String? {
        switch self {
        case .invalidImage: return "无法读取截图像素。"
        case .incompatibleDimensions: return "截图尺寸不一致。"
        case .invalidPlan: return "拼接算法返回了无效的对齐结果。"
        case .outputTooLarge: return "拼接结果过大，请减少截图数量。"
        }
    }
}
