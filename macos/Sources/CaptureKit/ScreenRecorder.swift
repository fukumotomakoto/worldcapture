import AVFoundation
import CoreMedia
import CoreVideo
import Foundation
import ScreenCaptureKit

public final class ScreenRecorder: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private let videoQueue = DispatchQueue(label: "worldcapture.recording.video", qos: .userInitiated)
    private let audioQueue = DispatchQueue(label: "worldcapture.recording.audio", qos: .userInitiated)
    private let stateLock = NSLock()

    private var stream: SCStream?
    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var sessionStarted = false
    private var terminalError: Error?

    public var isRecording: Bool {
        stateLock.withLock { stream != nil }
    }

    public override init() {
        super.init()
    }

    public func startMainDisplayRecording(to outputURL: URL) async throws {
        guard !isRecording else { throw CaptureError.recordingAlreadyActive }

        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            throw CaptureError.permissionDenied
        }
        guard let display = content.displays.first(where: { $0.displayID == CGMainDisplayID() })
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

        let configuration = SCStreamConfiguration()
        configuration.width = display.width
        configuration.height = display.height
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        configuration.queueDepth = 6
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.showsCursor = true
        configuration.capturesAudio = true
        configuration.excludesCurrentProcessAudio = true
        configuration.sampleRate = 48_000
        configuration.channelCount = 2

        let writer: AVAssetWriter
        do {
            writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        } catch {
            throw CaptureError.recordingFailed(Self.errorDetails(error))
        }

        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: configuration.width,
            AVVideoHeightKey: configuration.height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: max(6_000_000, configuration.width * configuration.height * 4),
                AVVideoExpectedSourceFrameRateKey: 60,
                AVVideoMaxKeyFrameIntervalKey: 120,
            ],
        ])
        videoInput.expectsMediaDataInRealTime = true

        let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 192_000,
        ])
        audioInput.expectsMediaDataInRealTime = true

        guard writer.canAdd(videoInput), writer.canAdd(audioInput) else {
            throw CaptureError.recordingFailed("编码器不支持当前音视频设置")
        }
        writer.add(videoInput)
        writer.add(audioInput)
        guard writer.startWriting() else {
            throw CaptureError.recordingFailed(writer.error?.localizedDescription ?? "无法启动 MP4 编码器")
        }

        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: videoQueue)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: audioQueue)

        stateLock.withLock {
            self.writer = writer
            self.videoInput = videoInput
            self.audioInput = audioInput
            self.stream = stream
            self.sessionStarted = false
            self.terminalError = nil
        }

        do {
            try await stream.startCapture()
        } catch {
            resetState()
            writer.cancelWriting()
            throw CaptureError.recordingFailed(Self.errorDetails(error))
        }
    }

    public func stopRecording() async throws {
        let activeStream = stateLock.withLock { stream }
        guard let activeStream else { throw CaptureError.recordingNotActive }

        do {
            try await activeStream.stopCapture()
        } catch {
            throw CaptureError.recordingFailed(Self.errorDetails(error))
        }

        let snapshot = stateLock.withLock { (writer, videoInput, audioInput, sessionStarted, terminalError) }
        snapshot.1?.markAsFinished()
        snapshot.2?.markAsFinished()

        if let writer = snapshot.0 {
            if snapshot.3 {
                await withCheckedContinuation { continuation in
                    writer.finishWriting { continuation.resume() }
                }
            } else {
                writer.cancelWriting()
            }
        }
        resetState()

        if let error = snapshot.4 {
            throw CaptureError.recordingFailed(Self.errorDetails(error))
        }
        if let error = snapshot.0?.error {
            throw CaptureError.recordingFailed(Self.errorDetails(error))
        }
    }

    public func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of outputType: SCStreamOutputType
    ) {
        guard sampleBuffer.isValid, CMSampleBufferDataIsReady(sampleBuffer) else { return }

        stateLock.withLock {
            guard let writer else { return }
            if !sessionStarted {
                guard outputType == .screen else { return }
                writer.startSession(atSourceTime: sampleBuffer.presentationTimeStamp)
                sessionStarted = true
            }

            switch outputType {
            case .screen:
                if videoInput?.isReadyForMoreMediaData == true {
                    videoInput?.append(sampleBuffer)
                }
            case .audio:
                if audioInput?.isReadyForMoreMediaData == true {
                    audioInput?.append(sampleBuffer)
                }
            case .microphone:
                break
            @unknown default:
                break
            }
        }
    }

    public func stream(_ stream: SCStream, didStopWithError error: Error) {
        stateLock.withLock { terminalError = error }
    }

    private func resetState() {
        stateLock.withLock {
            stream = nil
            writer = nil
            videoInput = nil
            audioInput = nil
            sessionStarted = false
            terminalError = nil
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
