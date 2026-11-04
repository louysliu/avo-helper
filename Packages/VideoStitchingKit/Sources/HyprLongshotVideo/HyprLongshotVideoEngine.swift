import Foundation
import VideoStitchingCore
import HyprPhaseCorrelation

public struct HyprLongshotVideoEngine: VideoStitchEngine {
    public init() {}

    public func stitch(_ request: VideoStitchRequest,
                       progress: @escaping @Sendable (VideoStitchProgress) -> Void,
                       isCancelled: @escaping @Sendable () -> Bool) throws -> VideoStitchResult {
        let reader = try VideoFrameReader(url: request.inputURL, sampleFPS: 10)
        defer { reader.cancel() }
        try FileManager.default.createDirectory(at: request.outputDirectory, withIntermediateDirectories: true)
        var calibration: [HyprFrame] = []
        var workingReserve = 0
        while calibration.count < 6 {
            if isCancelled() { throw VideoStitchError.cancelled }
            guard let frame = try reader.next() else { break }
            if calibration.isEmpty {
                // Six retained RGBA+gray calibration frames plus reader, FFT scratch,
                // temporary copies and PNG encoding. Reject before retaining them.
                let (pixels, overflow) = frame.width.multipliedReportingOverflow(by: frame.height)
                let (reserve, reserveOverflow) = pixels.multipliedReportingOverflow(by: 96)
                guard !overflow, !reserveOverflow, pixels > 0,
                      reserve < request.maximumWorkingBytes else {
                    throw VideoStitchError.limitExceeded("视频帧超过 Hypr 工作内存预算")
                }
                workingReserve = reserve
            }
            let prepared = try HyprFrame(frame)
            if let first = calibration.first, first.width != prepared.width || first.height != prepared.height {
                throw VideoStitchError.processingFailed("视频帧尺寸发生变化")
            }
            calibration.append(prepared)
        }
        guard let first = calibration.first else { throw VideoStitchError.invalidVideo }
        let active = HyprAlgorithm.stickyRegion(calibration)
        let memoryPixels = (request.maximumWorkingBytes - workingReserve) / 12
        let maximumOutputBytes = min(request.maximumWorkingBytes, 256_000_000)
        let maximumPixels = min(request.maximumOutputPixels, memoryPixels, maximumOutputBytes / 8)
        guard maximumPixels >= first.width * first.height else {
            throw VideoStitchError.limitExceeded("输出尺寸或工作内存预算不足以容纳一帧")
        }
        var assembler = HyprAssembler(width: first.width, height: first.height, active: active,
                                      maximumPixels: maximumPixels, directory: request.outputDirectory,
                                      maximumTotalPixels: request.maximumOutputPixels,
                                      maximumOutputBytes: maximumOutputBytes)
        // Replay every calibration frame, including frame zero: upstream discarded their motion.
        for frame in calibration {
            if assembler.stopped { break }
            if isCancelled() { throw VideoStitchError.cancelled }
            try assembler.consume(frame)
        }
        calibration.removeAll(keepingCapacity: false)
        while !assembler.stopped, let frame = try reader.next() {
            if isCancelled() { throw VideoStitchError.cancelled }
            try assembler.consume(HyprFrame(frame))
            progress(VideoStitchProgress(fraction: min(0.99, frame.timestamp / max(reader.duration, 0.001)),
                                         message: "Hypr 相位相关拼接中（\(assembler.images.count + 1) 段）"))
        }
        if isCancelled() { throw VideoStitchError.cancelled }
        try assembler.finish()
        progress(VideoStitchProgress(fraction: 1, message: "Hypr 拼接完成"))
        return VideoStitchResult(images: assembler.images, warnings: assembler.warnings,
                                 isPartial: assembler.isPartial)
    }
}

struct HyprFrame {
    let width: Int
    let height: Int
    let rgba: [UInt8]
    let gray: [UInt8]

    init(_ frame: VideoFrame) throws {
        guard frame.width >= 4, frame.height >= 4,
              frame.rgba.count == frame.width * frame.height * 4 else {
            throw VideoStitchError.processingFailed("Hypr 需要宽高均至少 4 像素的 RGBA 视频帧")
        }
        // iOS recordings have no guaranteed Linux overlay border. Preserve every edge.
        width = frame.width
        height = frame.height
        let pixels = frame.rgba
        rgba = pixels
        gray = stride(from: 0, to: pixels.count, by: 4).map {
            // OpenCV RGB -> gray coefficients; the reader already supplies RGBA.
            UInt8((77 * Int(pixels[$0]) + 150 * Int(pixels[$0 + 1]) + 29 * Int(pixels[$0 + 2]) + 128) >> 8)
        }
    }

    init(width: Int, height: Int, rgba: [UInt8], gray: [UInt8]) {
        self.width = width; self.height = height; self.rgba = rgba; self.gray = gray
    }

    func centralGray(_ active: Range<Int>) -> [UInt8] {
        let left = width / 4, right = width * 3 / 4
        var result = [UInt8]()
        result.reserveCapacity((right - left) * active.count)
        for y in active { result.append(contentsOf: gray[(y * width + left)..<(y * width + right)]) }
        return result
    }
}

enum HyprAlgorithm {
    struct Motion { let dx: Double; let dy: Double; let response: Double }

    static func correlate(_ previous: [UInt8], _ current: [UInt8], width: Int, height: Int) throws -> Motion {
        guard width >= 2, height >= 2, width <= Int(Int32.max), height <= Int(Int32.max),
              previous.count == width * height, current.count == previous.count else {
            throw VideoStitchError.processingFailed("相位相关输入尺寸无效")
        }
        var dx = 0.0, dy = 0.0, response = 0.0
        let status = previous.withUnsafeBufferPointer { a in
            current.withUnsafeBufferPointer { b in
                hypr_phase_correlate(a.baseAddress, b.baseAddress, Int32(width), Int32(height), &dx, &dy, &response)
            }
        }
        guard status == 0 else { throw VideoStitchError.processingFailed("OpenCV 相位相关失败（\(status)）") }
        return Motion(dx: dx, dy: dy, response: response)
    }

    static func stickyRegion(_ frames: [HyprFrame]) -> Range<Int> {
        guard let first = frames.first else { return 0..<0 }
        guard frames.count >= 2 else { return 0..<first.height }
        var differences = [Double](repeating: 0, count: first.height)
        for pair in zip(frames, frames.dropFirst()) {
            for y in 0..<first.height {
                var sum = 0
                for x in 0..<first.width {
                    let i = y * first.width + x
                    sum += abs(Int(pair.0.gray[i]) - Int(pair.1.gray[i]))
                }
                differences[y] += Double(sum) / Double(first.width * (frames.count - 1))
            }
        }
        var top = 0, bottom = first.height
        while top < bottom && differences[top] < 1.5 { top += 1 }
        while bottom > top && differences[bottom - 1] < 1.5 { bottom -= 1 }
        return Double(bottom - top) < Double(first.height) * 0.3 ? 0..<first.height : top..<bottom
    }
}

struct HyprAssembler {
    let width: Int
    let height: Int
    let active: Range<Int>
    let maximumPixels: Int
    let directory: URL
    let maximumTotalPixels: Int
    let maximumOutputBytes: Int
    let maximumFragments: Int
    private var emittedPixels = 0
    private var emittedBytes = 0
    private(set) var stopped = false
    private var previous: [UInt8]?
    private var canvas: [UInt8] = []
    private(set) var images: [VideoStitchImage] = []
    private(set) var warnings: [String] = []
    private(set) var isPartial = false

    init(width: Int, height: Int, active: Range<Int>, maximumPixels: Int, directory: URL,
         maximumTotalPixels: Int = Int.max, maximumOutputBytes: Int = 256_000_000,
         maximumFragments: Int = 128) {
        self.width = width; self.height = height; self.active = active
        self.maximumPixels = maximumPixels; self.directory = directory
        self.maximumTotalPixels = maximumTotalPixels
        self.maximumOutputBytes = maximumOutputBytes
        self.maximumFragments = maximumFragments
    }

    mutating func consume(_ frame: HyprFrame) throws {
        guard !stopped else { return }
        guard frame.width == width, frame.height == height else {
            throw VideoStitchError.processingFailed("视频帧尺寸发生变化")
        }
        let current = frame.centralGray(active)
        guard let previous else {
            try start(frame, current: current)
            return
        }
        // A truly unchanged frame needs no phase estimate (constant frames have no signal).
        var absoluteDifference: Int64 = 0
        for i in current.indices { absoluteDifference += Int64(abs(Int(previous[i]) - Int(current[i]))) }
        if Double(absoluteDifference) / Double(current.count) < 0.1 { return }
        let motion = try HyprAlgorithm.correlate(previous, current, width: width * 3 / 4 - width / 4,
                                                 height: active.count)
        if motion.response < 0.20 {
            try split(frame, current: current, reason: "低置信度匹配，已保留独立片段；片段之间可能存在未采样内容")
            return
        }
        if abs(motion.dx) > max(3, abs(motion.dy) * 0.20) {
            try split(frame, current: current, reason: "检测到横向移动，已保留独立片段")
            return
        }
        if motion.dy <= -1 {
            try split(frame, current: current, reason: "检测到反向滚动，已保留独立片段；可能含重复内容")
            return
        }
        // Keep the reference until cumulative movement reaches the upstream 5 px threshold.
        if motion.dy < 5 { return }
        let rows = Int(motion.dy.rounded())
        // FFT correlation is circular; shifts near half the window are ambiguous.
        guard rows < active.count / 2 else {
            try split(frame, current: current, reason: "位移过大，无法确认连续重叠，已保留独立片段")
            return
        }
        let newRows = (active.upperBound - rows)..<active.upperBound
        if canvas.count / 4 + rows * width > maximumPixels {
            try flush()
            guard !stopped else { return }
            addWarning("长图达到像素或内存预算，已分段保存（相邻片段含重叠内容）", partial: false)
            try start(frame, current: current)
            return
        }
        canvas.append(contentsOf: frame.rgba[(newRows.lowerBound * width * 4)..<(newRows.upperBound * width * 4)])
        self.previous = current
    }

    mutating func finish() throws { try flush() }

    private mutating func start(_ frame: HyprFrame, current: [UInt8]) throws {
        canvas = Array(frame.rgba[..<(active.upperBound * width * 4)])
        previous = current
    }

    private mutating func split(_ frame: HyprFrame, current: [UInt8], reason: String) throws {
        try flush()
        guard !stopped else { return }
        addWarning(reason, partial: true)
        try start(frame, current: current)
    }

    private mutating func addWarning(_ text: String, partial: Bool) {
        if !warnings.contains(text) { warnings.append(text) }
        isPartial = isPartial || partial
    }

    private mutating func stopAtOutputLimit() {
        stopped = true
        canvas.removeAll(keepingCapacity: false)
        addWarning("已达到总输出像素、文件大小或片段数量上限，转换已停止；剩余视频未处理", partial: true)
    }

    private mutating func flush() throws {
        guard !canvas.isEmpty else { return }
        let pixels = canvas.count / 4
        // PNG's worst-case deflate overhead is small; a 2x raw-byte reserve is
        // deliberately generous. Check actual encoded bytes as a second boundary.
        guard images.count < maximumFragments,
              pixels <= maximumTotalPixels - emittedPixels,
              canvas.count <= (maximumOutputBytes - emittedBytes) / 2 else {
            stopAtOutputLimit()
            return
        }
        let output = directory.appendingPathComponent(String(format: "hypr-%04d.png", images.count + 1))
        let outputHeight = canvas.count / (width * 4)
        try VideoPNGWriter.write(rgba: canvas, width: width, height: outputHeight, to: output)
        let attributes = try FileManager.default.attributesOfItem(atPath: output.path)
        let bytes = (attributes[.size] as? NSNumber)?.intValue ?? maximumOutputBytes
        guard bytes <= maximumOutputBytes - emittedBytes else {
            try FileManager.default.removeItem(at: output)
            stopAtOutputLimit()
            return
        }
        emittedPixels += pixels
        emittedBytes += bytes
        images.append(VideoStitchImage(url: output, width: width, height: outputHeight))
        canvas.removeAll(keepingCapacity: false)
    }
}
