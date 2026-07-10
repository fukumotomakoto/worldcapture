import AVFoundation
import CoreGraphics
import CoreMedia
import CoreVideo
import Foundation
import ScreenCaptureKit

public final class ScreenRecorder: NSObject, SCStreamDelegate, SCRecordingOutputDelegate, @unchecked Sendable {
    private let stateLock = NSLock()

    private var stream: SCStream?
    private var recordingOutput: SCRecordingOutput?
    private var terminalError: Error?
    private var didFinish = false
    private var finishContinuations: [CheckedContinuation<Void, Never>] = []

    // 暂停/继续采用「分段录制」：每次暂停结束当前段（一个正常的 SCRecordingOutput MP4），
    // 继续时开新段，停止时把所有段无损拼接（AVMutableComposition + Passthrough 导出）。
    private var recipe: (filter: SCContentFilter, configuration: SCStreamConfiguration)?
    private var finalOutputURL: URL?
    private var currentSegmentURL: URL?
    private var segments: [URL] = []
    private var paused = false

    /// 录制会话进行中（含暂停态）。
    public var isRecording: Bool {
        stateLock.withLock { stream != nil || paused }
    }

    /// 当前是否处于暂停态。
    public var isPaused: Bool {
        stateLock.withLock { paused }
    }

    public override init() {
        super.init()
    }

    /// 录制主显示器（兼容旧调用）。
    public func startMainDisplayRecording(to outputURL: URL) async throws {
        try await startRecording(displayID: CGMainDisplayID(), to: outputURL)
    }

    /// 录制指定显示器；找不到该 ID 时回退到主显示器或第一块可用显示器。
    /// - Parameters:
    ///   - region: 非 nil 时只录该选区（否则录整块显示器原生像素）。
    ///   - includeMicrophone: 是否把麦克风声音一并录入（需麦克风权限，macOS 15+）。
    public func startRecording(
        displayID: CGDirectDisplayID,
        region: CaptureRegion? = nil,
        includeMicrophone: Bool = false,
        to outputURL: URL
    ) async throws {
        guard !isRecording else { throw CaptureError.recordingAlreadyActive }
        try await Self.ensureMicrophoneAccess(includeMicrophone)

        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            throw CaptureError.permissionDenied
        }
        guard let display = content.displays.first(where: { $0.displayID == displayID })
                ?? content.displays.first(where: { $0.displayID == CGMainDisplayID() })
                ?? content.displays.first else {
            throw CaptureError.noDisplayAvailable
        }

        let currentPID = pid_t(ProcessInfo.processInfo.processIdentifier)
        let currentApplication = content.applications.first { $0.processID == currentPID }
        let filter: SCContentFilter
        if let currentApplication {
            filter = SCContentFilter(display: display, excludingApplications: [currentApplication], exceptingWindows: [])
        } else {
            filter = SCContentFilter(display: display, excludingWindows: [])
        }

        // 录制目标尺寸 = 显示器原生像素。优先取当前显示模式的真实像素尺寸（最可靠的“原尺寸”）；
        // 取不到时回退到 contentRect(点) × pointPixelScale。再用 captureResolution = .best 杜绝降采样。
        let scale = CGFloat(filter.pointPixelScale)
        var pixelWidth = Int((filter.contentRect.width * scale).rounded())
        var pixelHeight = Int((filter.contentRect.height * scale).rounded())
        if let mode = CGDisplayCopyDisplayMode(display.displayID), mode.pixelWidth > 0, mode.pixelHeight > 0 {
            pixelWidth = mode.pixelWidth
            pixelHeight = mode.pixelHeight
        }

        let streamConfiguration = SCStreamConfiguration()
        // 区域录制：限定 sourceRect（点坐标），目标像素取选区像素，保持与显示器相同的清晰度。
        if let region {
            streamConfiguration.sourceRect = region.sourceRect
            pixelWidth = max(1, Int((region.sourceRect.width * scale).rounded()))
            pixelHeight = max(1, Int((region.sourceRect.height * scale).rounded()))
        }
        streamConfiguration.width = max(1, pixelWidth)
        streamConfiguration.height = max(1, pixelHeight)
        Self.applyCommonConfiguration(to: streamConfiguration, includeMicrophone: includeMicrophone)
        try await beginSession(filter: filter, configuration: streamConfiguration, to: outputURL)
    }

    /// 录制单个窗口（跟随该窗口，不含桌面其余部分）。
    public func startWindowRecording(
        windowID: CGWindowID,
        includeMicrophone: Bool = false,
        to outputURL: URL
    ) async throws {
        guard !isRecording else { throw CaptureError.recordingAlreadyActive }
        try await Self.ensureMicrophoneAccess(includeMicrophone)

        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            throw CaptureError.permissionDenied
        }
        guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
            throw CaptureError.windowUnavailable
        }

        let filter = SCContentFilter(desktopIndependentWindow: window)
        let scale = CGFloat(filter.pointPixelScale)
        let streamConfiguration = SCStreamConfiguration()
        streamConfiguration.width = max(1, Int((filter.contentRect.width * scale).rounded()))
        streamConfiguration.height = max(1, Int((filter.contentRect.height * scale).rounded()))
        Self.applyCommonConfiguration(to: streamConfiguration, includeMicrophone: includeMicrophone)
        try await beginSession(filter: filter, configuration: streamConfiguration, to: outputURL)
    }

    /// 开录前确认麦克风权限：尚未决定时弹窗申请，被拒则明确报错。
    /// 宁可让用户看见错误，也不要在无授权时静默录出一段没有讲解声的视频。
    private static func ensureMicrophoneAccess(_ includeMicrophone: Bool) async throws {
        guard includeMicrophone else { return }
        guard await MicrophonePermission.request() else {
            throw CaptureError.microphonePermissionDenied
        }
    }

    /// 录制流的公共配置（音频、像素格式、帧率、光标）。width/height/sourceRect 由调用方设定。
    ///
    /// SCRecordingOutput 把系统音频与麦克风混入同一条音轨：实测开启麦克风后输出仍只有
    /// 一条 audio track。因此 mergeSegments 取第一条音轨即可，不会漏掉讲解声。
    private static func applyCommonConfiguration(to configuration: SCStreamConfiguration, includeMicrophone: Bool) {
        configuration.captureResolution = .best
        configuration.captureMicrophone = includeMicrophone
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        configuration.queueDepth = 8
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.colorSpaceName = CGColorSpace.sRGB
        configuration.showsCursor = true
        configuration.capturesAudio = true
        configuration.excludesCurrentProcessAudio = true
        configuration.sampleRate = 48_000
        configuration.channelCount = 2
    }

    /// 开始一次录制会话：记录配方（过滤器+配置）与最终输出路径，然后开录第一段。
    private func beginSession(filter: SCContentFilter, configuration: SCStreamConfiguration, to outputURL: URL) async throws {
        guard !isRecording else { throw CaptureError.recordingAlreadyActive }
        stateLock.withLock {
            self.recipe = (filter, configuration)
            self.finalOutputURL = outputURL
            self.segments = []
            self.paused = false
        }
        do {
            try await startSegment()
        } catch {
            stateLock.withLock {
                self.recipe = nil
                self.finalOutputURL = nil
            }
            throw error
        }
    }

    /// 录制一个新分段到临时文件（每段是一个独立、正常的 SCRecordingOutput MP4）。
    private func startSegment() async throws {
        guard let recipe = stateLock.withLock({ self.recipe }) else {
            throw CaptureError.recordingNotActive
        }
        let segmentURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("wc-segment-\(UUID().uuidString).mp4")

        let outputConfiguration = SCRecordingOutputConfiguration()
        outputConfiguration.outputURL = segmentURL
        outputConfiguration.outputFileType = .mp4
        outputConfiguration.videoCodecType = .h264

        let recordingOutput = SCRecordingOutput(configuration: outputConfiguration, delegate: self)
        let stream = SCStream(filter: recipe.filter, configuration: recipe.configuration, delegate: self)
        do {
            try stream.addRecordingOutput(recordingOutput)
        } catch {
            throw CaptureError.recordingFailed(Self.errorDetails(error))
        }

        stateLock.withLock {
            self.stream = stream
            self.recordingOutput = recordingOutput
            self.currentSegmentURL = segmentURL
            self.terminalError = nil
            self.didFinish = false
            self.finishContinuations.removeAll()
        }

        do {
            try await stream.startCapture()
        } catch {
            stateLock.withLock {
                self.stream = nil
                self.recordingOutput = nil
                self.currentSegmentURL = nil
            }
            throw CaptureError.recordingFailed(Self.errorDetails(error))
        }
    }

    /// 结束当前分段：停止采集、等输出写完、把段文件收入 segments。
    private func finishCurrentSegment() async throws {
        let activeStream = stateLock.withLock { stream }
        guard let activeStream else { return }

        do {
            try await activeStream.stopCapture()
        } catch {
            throw CaptureError.recordingFailed(Self.errorDetails(error))
        }
        await waitForRecordingOutputToFinish()

        let error = stateLock.withLock {
            if let url = currentSegmentURL { segments.append(url) }
            let e = terminalError
            stream = nil
            recordingOutput = nil
            currentSegmentURL = nil
            return e
        }
        if let error {
            throw CaptureError.recordingFailed(Self.errorDetails(error))
        }
    }

    /// 暂停：结束当前分段，进入暂停态（不占用采集）。
    public func pause() async throws {
        let canPause = stateLock.withLock { stream != nil && !paused }
        guard canPause else { return }
        try await finishCurrentSegment()
        stateLock.withLock { paused = true }
    }

    /// 继续：从暂停态开一个新分段。
    public func resume() async throws {
        let canResume = stateLock.withLock { paused && stream == nil }
        guard canResume else { return }
        stateLock.withLock { paused = false }
        do {
            try await startSegment()
        } catch {
            stateLock.withLock { paused = true }
            throw error
        }
    }

    public func stopRecording() async throws {
        let (active, wasPaused) = stateLock.withLock { (stream != nil, paused) }
        guard active || wasPaused else { throw CaptureError.recordingNotActive }

        if active {
            try await finishCurrentSegment()
        }

        let (collected, output) = stateLock.withLock { (segments, finalOutputURL) }
        defer { resetState() }

        guard let output, !collected.isEmpty else {
            throw CaptureError.recordingFailed("no recorded segments")
        }

        try? FileManager.default.removeItem(at: output)
        if collected.count == 1 {
            try FileManager.default.moveItem(at: collected[0], to: output)
        } else {
            try await Self.mergeSegments(collected, to: output)
            collected.forEach { try? FileManager.default.removeItem(at: $0) }
        }
    }

    /// 把多个分段无损拼接为一个 MP4（编解码一致，用 Passthrough 不重编码）。
    private static func mergeSegments(_ segments: [URL], to outputURL: URL) async throws {
        let composition = AVMutableComposition()
        let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        let audioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)

        var cursor = CMTime.zero
        for url in segments {
            let asset = AVURLAsset(url: url)
            let duration = try await asset.load(.duration)
            guard duration.isValid, duration > .zero else { continue }
            let range = CMTimeRange(start: .zero, duration: duration)
            if let videoSource = try await asset.loadTracks(withMediaType: .video).first {
                try videoTrack?.insertTimeRange(range, of: videoSource, at: cursor)
            }
            if let audioSource = try await asset.loadTracks(withMediaType: .audio).first {
                // 按音轨自身的时间范围插入：它常比容器时长略短，硬套容器时长会越界失败。
                // 失败必须抛出——从前这里吞掉错误，用户会拿到一段莫名其妙没有声音的录像。
                let audioRange = try await audioSource.load(.timeRange)
                do {
                    try audioTrack?.insertTimeRange(audioRange, of: audioSource, at: cursor)
                } catch {
                    throw CaptureError.recordingFailed(
                        "合并分段音频失败（\(url.lastPathComponent)）：\(errorDetails(error))")
                }
            }
            // 光标按容器时长推进：音轨若短一点，末尾留静音，画面与声音仍对齐。
            cursor = CMTimeAdd(cursor, duration)
        }

        guard let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else {
            throw CaptureError.recordingFailed("could not create export session")
        }
        try await export.export(to: outputURL, as: .mp4)
    }

    public func stream(_ stream: SCStream, didStopWithError error: Error) {
        completeRecording(with: error)
    }

    public func recordingOutputDidStartRecording(_ recordingOutput: SCRecordingOutput) {}

    public func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        completeRecording(with: nil)
    }

    public func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: Error) {
        completeRecording(with: error)
    }

    private func waitForRecordingOutputToFinish() async {
        await withCheckedContinuation { continuation in
            let shouldResumeImmediately = stateLock.withLock {
                if didFinish || terminalError != nil { return true }
                finishContinuations.append(continuation)
                return false
            }
            if shouldResumeImmediately { continuation.resume() }
        }
    }

    private func completeRecording(with error: Error?) {
        let continuations = stateLock.withLock {
            if let error { terminalError = error }
            didFinish = true
            let pending = finishContinuations
            finishContinuations.removeAll()
            return pending
        }
        continuations.forEach { $0.resume() }
    }

    private func resetState() {
        stateLock.withLock {
            stream = nil
            recordingOutput = nil
            terminalError = nil
            didFinish = false
            finishContinuations.removeAll()
            recipe = nil
            finalOutputURL = nil
            currentSegmentURL = nil
            segments = []
            paused = false
        }
    }

    private static func errorDetails(_ error: Error) -> String {
        let nsError = error as NSError
        var parts = ["\(nsError.domain) (\(nsError.code)): \(nsError.localizedDescription)"]
        if let reason = nsError.localizedFailureReason, !reason.isEmpty {
            parts.append(reason)
        }
        if let suggestion = nsError.localizedRecoverySuggestion, !suggestion.isEmpty {
            parts.append(suggestion)
        }
        return parts.joined(separator: " — ")
    }
}
