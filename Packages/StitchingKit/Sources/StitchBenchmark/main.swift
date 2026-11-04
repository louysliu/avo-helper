import Foundation
import StitchingEngines
import CryptoKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

struct InputRecord: Codable {
    let name: String
    let sha256: String
    let width: Int
    let height: Int
}
struct BenchmarkRecord: Codable {
    let group: String
    let engine: String
    let inputs: [InputRecord]
    let analysisMilliseconds: Double
    let compositionMilliseconds: Double
    let outputWidth: Int?
    let outputHeight: Int?
    let plan: StitchPlan?
    let seams: [ComposedSeam]
    let warnings: [String]
    let error: String?
}

func argument(_ flag: String, default value: String) -> String {
    guard let index = CommandLine.arguments.firstIndex(of: flag), index + 1 < CommandLine.arguments.count else { return value }
    return CommandLine.arguments[index + 1]
}
func writeJSON<T: Encodable>(_ value: T, _ url: URL) throws {
    let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(value).write(to: url, options: .atomic)
}
func preview(_ image: CGImage, _ url: URL) throws {
    let factor = min(1, min(480.0 / Double(image.width), 1800.0 / Double(image.height)))
    let w = max(1, Int(Double(image.width) * factor)), h = max(1, Int(Double(image.height) * factor))
    guard let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
        let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    if let result = context.makeImage() { CGImageDestinationAddImage(destination, result, nil); CGImageDestinationFinalize(destination) }
}
func escape(_ text: String) -> String {
    text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: "\"", with: "&quot;")
}

do {
    let input = URL(fileURLWithPath: argument("--input", default: "LocalTestData/Screenshots"), isDirectory: true)
    let output = URL(fileURLWithPath: argument("--output", default: "build/stitch-benchmark"), isDirectory: true)
    let engineFilter = argument("--engine", default: "all")
    let groupFilter = argument("--group", default: "all")
    let choices = StitchEngineChoice.allCases.filter { engineFilter == "all" || $0.rawValue == engineFilter }
    guard !choices.isEmpty else { throw StitchError.invalidPlan }
    let fm = FileManager.default
    try fm.createDirectory(at: output, withIntermediateDirectories: true)
    let groups = try fm.contentsOfDirectory(at: input, includingPropertiesForKeys: [.isDirectoryKey])
        .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
        .filter { groupFilter == "all" || $0.lastPathComponent == groupFilter }
        .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    guard !groups.isEmpty else { throw StitchError.invalidImage }
    var records: [BenchmarkRecord] = []
    var html = """
    <!doctype html><html lang="zh"><meta charset="utf-8"><title>Screenshot stitching benchmark</title>
    <style>body{font:15px system-ui;background:#f3f4f6;color:#17202a;margin:24px}h1{font-size:24px}.grid{display:grid;grid-template-columns:repeat(4,minmax(240px,1fr));gap:16px}.card{background:white;padding:16px;border-radius:12px;overflow:auto}img{max-width:100%;height:auto}code{font-size:12px}a{color:#175caa}.inputs{display:flex;gap:12px}.inputs img{max-width:180px;max-height:420px}small{color:#555}pre{white-space:pre-wrap}.warning{color:#ad4a00}</style>
    <h1>四种拼接算法 · 本地原图评测</h1><p>相同解码、相同硬切合成器；只比较移植后的对齐与内容区检测。匹配成功不等于视觉正确。没有人工真值时不报告准确率。</p>
    """
    for group in groups {
        let files = try fm.contentsOfDirectory(at: group, includingPropertiesForKeys: nil)
            .filter { ["heic", "heif", "png", "jpg", "jpeg"].contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        guard files.count >= 2 else { continue }
        let images = try files.map { try RasterIO.load($0) }
        let inputRecords = try zip(files, images).map { file, image in
            InputRecord(name: file.lastPathComponent, sha256: SHA256.hash(data: try Data(contentsOf: file)).map { String(format: "%02x", $0) }.joined(), width: image.width, height: image.height)
        }
        let groupName = group.lastPathComponent
        html += "<h2>第 \(escape(groupName)) 组</h2><div class=inputs>"
        let sourceFolder = output.appendingPathComponent("group-\(groupName)/inputs", isDirectory: true)
        try fm.createDirectory(at: sourceFolder, withIntermediateDirectories: true)
        for (index, image) in images.enumerated() {
            try RasterIO.writePNG(image, to: sourceFolder.appendingPathComponent("\(index)-full.png"))
            try preview(RasterIO.cgImage(image), sourceFolder.appendingPathComponent("\(index).png"))
            html += "<figure><img src=\"group-\(groupName)/inputs/\(index).png\"><figcaption>\(escape(files[index].lastPathComponent))</figcaption></figure>"
        }
        html += "</div><div class=grid>"
        for choice in choices {
            let directory = output.appendingPathComponent("group-\(groupName)/\(choice.rawValue)", isDirectory: true)
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
            fputs("[group \(groupName)] \(choice.rawValue) analyzing…\n", stderr)
            let start = ProcessInfo.processInfo.systemUptime
            var plan: StitchPlan?
            var analysisTime = 0.0
            do {
                let p = try choice.makeEngine().analyze(images); plan = p
                analysisTime = (ProcessInfo.processInfo.systemUptime - start) * 1000
                let composeStart = ProcessInfo.processInfo.systemUptime
                let result = try StitchCompositor.compose(images, plan: p)
                let compositionTime = (ProcessInfo.processInfo.systemUptime - composeStart) * 1000
                try RasterIO.writePNG(result.image, to: directory.appendingPathComponent("output.png"))
                let cg = try RasterIO.cgImage(result.image)
                try preview(cg, directory.appendingPathComponent("preview.png"))
                for (i, seam) in result.seams.enumerated() {
                    let top = max(0, seam.outputY - 200), bottom = min(cg.height, seam.outputY + 200)
                    if bottom > top, let crop = cg.cropping(to: CGRect(x: 0, y: top, width: cg.width, height: bottom - top)) {
                        try RasterIO.writePNG(RasterIO.raster(crop), to: directory.appendingPathComponent("seam-\(i + 1).png"))
                    }
                }
                let record = BenchmarkRecord(group: groupName, engine: choice.rawValue, inputs: inputRecords,
                    analysisMilliseconds: analysisTime, compositionMilliseconds: compositionTime,
                    outputWidth: result.image.width, outputHeight: result.image.height, plan: p,
                    seams: result.seams, warnings: result.warnings, error: nil)
                records.append(record); try writeJSON(record, directory.appendingPathComponent("result.json"))
                let matched = result.seams.filter { $0.status == .matched || $0.status == .duplicate }.count
                html += "<article class=card><h3>\(escape(choice.title))</h3><p>\(result.image.width) × \(result.image.height) · \(Int(analysisTime)) ms</p><p>识别接缝 \(matched)/\(result.seams.count)</p><a href=\"group-\(groupName)/\(choice.rawValue)/output.png\"><img src=\"group-\(groupName)/\(choice.rawValue)/preview.png\"></a><pre>\(escape(p.alignments.map { "\($0.status.rawValue) dx=\($0.offsetX) dy=\($0.offsetY) confidence=\(String(format: "%.3f", $0.confidence))" }.joined(separator: "\n")))</pre><a href=\"group-\(groupName)/\(choice.rawValue)/result.json\">诊断 JSON</a></article>"
                fputs("  \(matched)/\(result.seams.count) seams, \(result.image.height) px, \(Int(analysisTime)) ms\n", stderr)
            } catch {
                let record = BenchmarkRecord(group: groupName, engine: choice.rawValue, inputs: inputRecords,
                    analysisMilliseconds: analysisTime == 0 ? (ProcessInfo.processInfo.systemUptime - start) * 1000 : analysisTime,
                    compositionMilliseconds: 0, outputWidth: nil, outputHeight: nil, plan: plan,
                    seams: [], warnings: [], error: String(describing: error))
                records.append(record); try writeJSON(record, directory.appendingPathComponent("result.json"))
                html += "<article class=card><h3>\(choice.title)</h3><p class=warning>\(escape(String(describing: error)))</p></article>"
                fputs("  FAILED: \(error)\n", stderr)
            }
            try writeJSON(records, output.appendingPathComponent("results.json"))
        }
        html += "</div>"
    }
    html += "</html>"
    try html.write(to: output.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
    print(output.appendingPathComponent("index.html").path)
} catch {
    fputs("Benchmark failed: \(error)\n", stderr); exit(1)
}
