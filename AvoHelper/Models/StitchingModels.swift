import CoreGraphics
import PhotosUI
import SwiftUI
import UIKit

struct SelectedScreenshot: Identifiable {
    let id: String
    let pickerItem: PhotosPickerItem
    let image: UIImage
}

struct SeamReport: Identifiable, Equatable {
    enum Status: Equatable {
        case matched
        case duplicate
        case unmatched
    }

    let id = UUID()
    let firstIndex: Int
    let secondIndex: Int
    let overlapPixels: Int
    let status: Status
}

struct NormalizedCrop: Equatable {
    var x: CGFloat
    var y: CGFloat
    var width: CGFloat
    var height: CGFloat

    static let full = NormalizedCrop(x: 0, y: 0, width: 1, height: 1)

    var rect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }

    var isFull: Bool {
        abs(x) < 0.0001 && abs(y) < 0.0001 &&
        abs(width - 1) < 0.0001 && abs(height - 1) < 0.0001
    }

    func clamped(minimumSize: CGFloat = 0.04) -> NormalizedCrop {
        let originX = min(max(x, 0), 1 - minimumSize)
        let originY = min(max(y, 0), 1 - minimumSize)
        let clampedWidth = min(max(width, minimumSize), 1 - originX)
        let clampedHeight = min(max(height, minimumSize), 1 - originY)
        return NormalizedCrop(x: originX, y: originY, width: clampedWidth, height: clampedHeight)
    }
}

struct StitchArtifact {
    let pngURL: URL
    let preview: UIImage
    let pixelSize: CGSize
    let seams: [SeamReport]
    var algorithmName: String? = nil
}

struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

struct UserMessage: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

enum AppRoute: Hashable {
    case result
    case crop
}

enum StitchingError: LocalizedError {
    case invalidImage
    case notEnoughImages
    case outputTooLarge
    case couldNotCreateContext
    case couldNotWriteFile
    case photoPermissionDenied

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "无法读取其中一张截图，请移除后重试。"
        case .notEnoughImages:
            return "请至少选择两张截图。"
        case .outputTooLarge:
            return "拼接结果过长，请减少截图数量后重试。"
        case .couldNotCreateContext:
            return "设备暂时无法处理这组截图，请减少截图数量。"
        case .couldNotWriteFile:
            return "无法生成导出文件，请稍后重试。"
        case .photoPermissionDenied:
            return "没有相册写入权限，请在系统设置中允许添加照片。"
        }
    }
}
