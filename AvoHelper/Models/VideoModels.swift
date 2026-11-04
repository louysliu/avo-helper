import CoreTransferable
import Foundation
import UniformTypeIdentifiers

enum AppWorkflow: String, CaseIterable, Identifiable {
    case screenshots, video
    var id: String { rawValue }
    var title: String { self == .screenshots ? "多张截图拼接" : "视频转长截图" }
    var symbol: String { self == .screenshots ? "photo.stack" : "video" }
}

enum VideoAlgorithm: String, CaseIterable, Identifiable {
    case longScreen, hyprLongshot
    var id: String { rawValue }
    var title: String { self == .longScreen ? "Long Screen" : "hypr-longshot" }
    var detail: String {
        self == .longScreen
            ? "分析完整滚动轨迹，支持回滚；无法连接的内容会分别保留。单段视频最长 3 分钟。"
            : "适合平稳向下滚动；遇到无法连接的内容会分段保留。"
    }
}

struct ImportedVideo: Transferable, Sendable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { received in
            let ext = received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension
            let destination = FileManager.default.temporaryDirectory
                .appendingPathComponent("avo-video-input-\(UUID().uuidString)").appendingPathExtension(ext)
            let size = try received.file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= 2_000_000_000 else { throw VideoImportError.tooLarge }
            try FileManager.default.copyItem(at: received.file, to: destination)
            return ImportedVideo(url: destination)
        }
    }
}

enum VideoImportError: LocalizedError {
    case tooLarge
    var errorDescription: String? { "视频文件超过 2 GB，请先截取需要拼接的片段。" }
}
