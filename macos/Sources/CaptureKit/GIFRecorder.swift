import CoreImage
import CoreMedia
import CoreVideo
import Foundation
import ScreenCaptureKit

/// 区域 GIF 录制：以 `SCStreamOutput` 抓取选区内的视频帧（BGRA），逐帧转成 `CGImage` 累积在内存里，
/// 停止时交由 `GIFEncoder` 编码为动图。帧在流配置里已按 `maxDimension` 降采样，控制内存与最终体积。
public final class GIFRecorder: NSObject, SCStreamDelegate, SCStreamOutput, @unchecked Sendable {
    public struct CapturedFrame {
        public let image: CGImage
        public let timestamp: TimeInterval
    }

    private let lock = NSLock()
    private var stream: SCStream?
    private var frames: [(image: CGImage, timestamp: TimeInterval)] = []
    private var startTimestamp: TimeInterval?
    private var reachedCap = false

    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    private let sampleQueue = DispatchQueue(label: "io.worldcapture.gif.samples")

    /// 硬性上限，兜底内存（帧数）；时长上限由调用方计时驱动停止。
    private let maxFrames: Int
    /// 最长边像素上限（GIF 体积控制）。
    private let maxDimension: CGFloat

    public var isRecording: Bool { lock.withLock { stream != nil } }

    public init(maxFrames: Int = 600, maxDimension: CGFloat = 640) {
        self.maxFrames = maxFrames
        self.maxDimension = maxDimension
        super.init()
    }

    public func start(displayID: CGDirectDisplayID, region: CaptureRegion, fps: Int) async throws {
        guard !isRecording else { throw CaptureError.recordingAlreadyActive }

        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            throw CaptureError.permissionDenied
        }
        guard let display = content.displays.first(where: { $0.displayID == displayID }) ?? content.displays.first else {
            throw CaptureError.noDisplayAvailable
        }

        // 排除本应用窗口，避免把主窗口/浮窗拍进选区。
        let currentPID = pid_t(ProcessInfo.processInfo.processIdentifier)
        let filter: SCContentFilter
        if let app = content.applications.first(where: { $0.processID == currentPID }) {
            filter = SCContentFilter(display: display, excludingApplications: [app], exceptingWindows: [])
        } else {
            filter = SCContentFilter(display: display, excludingWindows: [])
        }

        // 目标像素尺寸 = 选区像素，最长边不超过 maxDimension。
        var width = CGFloat(region.pixelWidth)
        var height = CGFloat(region.pixelHeight)
        let longest = max(width, height)
        if longest > maxDimension {
            let factor = maxDimension / longest
            width = (width * factor).rounded()
            height = (height * factor).rounded()
        }

        let configuration = SCStreamConfiguration()
        configuration.sourceRect = region.sourceRect
        configuration.width = max(1, Int(width))
        configuration.height = max(1, Int(height))
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(max(1, fps)))
        configuration.queueDepth = 6
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.colorSpaceName = CGColorSpace.sRGB
        configuration.showsCursor = true
        configuration.capturesAudio = false

        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        do {
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: sampleQueue)
        } catch {
            throw CaptureError.recordingFailed(Self.errorDetails(error))
        }

        lock.withLock {
            self.stream = stream
            self.frames = []
            self.startTimestamp = nil
            self.reachedCap = false
        }

        do {
            try await stream.startCapture()
        } catch {
            lock.withLock { self.stream = nil }
            throw CaptureError.recordingFailed(Self.errorDetails(error))
        }
    }

    /// 停止并返回按时间戳排序的帧；调用方交给 `GIFEncoder`。
    public func stop() async throws -> [(image: CGImage, timestamp: TimeInterval)] {
        let activeStream = lock.withLock { stream }
        guard let activeStream else { throw CaptureError.recordingNotActive }

        try? await activeStream.stopCapture()

        return lock.withLock {
            let captured = frames
            stream = nil
            frames = []
            startTimestamp = nil
            reachedCap = false
            return captured
        }
    }

    // MARK: - SCStreamOutput

    public func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, CMSampleBufferIsValid(sampleBuffer) else { return }

        // 仅收完整帧；SCStream 内容无变化时会发 idle/blank 帧，需跳过。
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let info = attachments.first,
              let statusRaw = info[.status] as? Int,
              let status = SCFrameStatus(rawValue: statusRaw), status == .complete else {
            return
        }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else { return }

        lock.withLock {
            guard stream === self.stream, !reachedCap else { return }
            if frames.count >= maxFrames {
                reachedCap = true
                return
            }
            frames.append((image: cgImage, timestamp: timestamp))
        }
    }

    public func stream(_ stream: SCStream, didStopWithError error: Error) {
        lock.withLock { if stream === self.stream { self.stream = nil } }
    }

    private static func errorDetails(_ error: Error) -> String {
        let nsError = error as NSError
        return "\(nsError.domain) (\(nsError.code)): \(nsError.localizedDescription)"
    }
}
