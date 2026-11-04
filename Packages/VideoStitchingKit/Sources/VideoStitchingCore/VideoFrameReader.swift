import AVFoundation
import CoreImage
import Foundation

public struct VideoFrame: Sendable {
    public let width: Int
    public let height: Int
    public let rgba: [UInt8]
    public let timestamp: Double
    public let duration: Double
    public init(width: Int, height: Int, rgba: [UInt8], timestamp: Double, duration: Double) {
        self.width = width; self.height = height; self.rgba = rgba
        self.timestamp = timestamp; self.duration = duration
    }
}

/// Sequential, replayable by opening a fresh instance. Never retains previous frames.
/// The owning worker must call next/cancel serially. RGBA rows are top-down, sRGB, opaque.
public final class VideoFrameReader {
    public let duration: Double
    private let reader: AVAssetReader
    private let output: AVAssetReaderTrackOutput
    private let transform: CGAffineTransform
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    private let interval: Double?
    private var nextSampleTime = -Double.infinity
    private var cancelled = false

    public init(url: URL, sampleFPS: Double? = nil) throws {
        if let fps = sampleFPS, (!fps.isFinite || fps <= 0) { throw VideoStitchError.invalidVideo }
        let asset = AVURLAsset(url: url)
        guard let track = asset.tracks(withMediaType: .video).first else { throw VideoStitchError.invalidVideo }
        let seconds = asset.duration.seconds
        guard seconds.isFinite, seconds > 0 else { throw VideoStitchError.invalidVideo }
        duration = seconds
        transform = track.preferredTransform
        let size = track.naturalSize.applying(transform)
        guard size.width.isFinite, size.height.isFinite,
              abs(size.width) >= 1, abs(size.height) >= 1,
              abs(size.width * size.height) <= 16_777_216 else {
            throw VideoStitchError.limitExceeded("视频单帧尺寸过大，请使用较低分辨率的录屏。")
        }
        interval = sampleFPS.map { 1 / $0 }
        reader = try AVAssetReader(asset: asset)
        output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ])
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw VideoStitchError.invalidVideo }
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? VideoStitchError.invalidVideo }
    }

    deinit { reader.cancelReading() }
    public func cancel() { cancelled = true; reader.cancelReading() }

    public func next() throws -> VideoFrame? {
        if cancelled { throw VideoStitchError.cancelled }
        while let buffer = output.copyNextSampleBuffer() {
            let timestamp = CMSampleBufferGetPresentationTimeStamp(buffer).seconds
            guard timestamp.isFinite else { throw VideoStitchError.invalidVideo }
            if interval != nil, timestamp + 0.000001 < nextSampleTime { continue }
            if let interval { nextSampleTime = timestamp + interval }
            return try autoreleasepool {
                guard let pixels = CMSampleBufferGetImageBuffer(buffer) else { throw VideoStitchError.invalidVideo }
                // AV track transforms use top-left coordinates; Core Image uses bottom-left.
                let ciTransform = CGAffineTransform(a: transform.a, b: -transform.b,
                    c: -transform.c, d: transform.d, tx: transform.tx, ty: -transform.ty)
                let image = CIImage(cvPixelBuffer: pixels).transformed(by: ciTransform)
                let bounds = image.extent.integral
                guard bounds.width > 0, bounds.height > 0, bounds.width * bounds.height <= 16_777_216,
                      let cg = context.createCGImage(image, from: bounds, format: .RGBA8, colorSpace: colorSpace) else {
                    throw VideoStitchError.invalidVideo
                }
                let width = cg.width, height = cg.height
                var rgba = [UInt8](repeating: 0, count: width * height * 4)
                let rendered = rgba.withUnsafeMutableBytes { bytes -> Bool in
                    guard let bitmap = CGContext(data: bytes.baseAddress, width: width, height: height,
                        bitsPerComponent: 8, bytesPerRow: width * 4, space: colorSpace,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
                    bitmap.setBlendMode(.copy)
                    bitmap.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
                    return true
                }
                guard rendered else { throw VideoStitchError.invalidVideo }
                let frameDuration = CMSampleBufferGetDuration(buffer).seconds
                return VideoFrame(width: width, height: height, rgba: rgba, timestamp: timestamp,
                                  duration: frameDuration.isFinite && frameDuration > 0 ? frameDuration : 0)
            }
        }
        if reader.status == .failed { throw reader.error ?? VideoStitchError.invalidVideo }
        if reader.status == .cancelled { throw VideoStitchError.cancelled }
        return nil
    }
}
