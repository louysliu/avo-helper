@_exported import StitchingCore
import EkibunStitch
import LongStitch
import ZoomItStitch
import SeamlyStitch

public enum StitchEngineChoice: String, CaseIterable, Identifiable, Codable, Sendable {
    case ekibun, longstitch, zoomit, seamly
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .ekibun: return "Ekibun · 相位相关"
        case .longstitch: return "LongStitch"
        case .zoomit: return "ZoomIt"
        case .seamly: return "Seamly · 实验"
        }
    }
    public func makeEngine() -> any ScreenshotStitchingEngine {
        switch self {
        case .ekibun: return EkibunEngine()
        case .longstitch: return LongStitchEngine()
        case .zoomit: return ZoomItEngine()
        case .seamly: return SeamlyEngine()
        }
    }
}
