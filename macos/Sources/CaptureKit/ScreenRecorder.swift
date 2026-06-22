import AVFoundation
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

        // SCDisplay.width/height are in points; SCStreamConfiguration expects pixels.
        // Scale by pointPixelScale so the recording keeps native Retina resolution.
        let scale = CGFloat(filter.pointPixelScale)
        let streamConfiguration = SCStreamConfiguration()
        streamConfiguration.width = max(1, Int((filter.contentRect.width * scale).rounded()))
        streamConfiguration.height = max(1, Int((filter.contentRect.height * scale).rounded()))
        streamConfiguration.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        streamConfiguration.queueDepth = 6
        streamConfiguration.pixelFormat = kCVPixelFormatType_32BGRA
        streamConfiguration.showsCursor = true
        streamConfiguration.capturesAudio = true
        streamConfiguration.excludesCurrentProcessAudio = true
        streamConfiguration.sampleRate = 48_000
        streamConfiguration.channelCount = 2

        let outputConfiguration = SCRecordingOutputConfiguration()
        outputConfiguration.outputURL = outputURL
        outputConfiguration.outputFileType = .mp4
        outputConfiguration.videoCodecType = .h264

        let recordingOutput = SCRecordingOutput(configuration: outputConfiguration, delegate: self)
        let stream = SCStream(filter: filter, configuration: streamConfiguration, delegate: self)
        do {
            try stream.addRecordingOutput(recordingOutput)
        } catch {
            throw CaptureError.recordingFailed(Self.errorDetails(error))
        }

        stateLock.withLock {
            self.stream = stream
            self.recordingOutput = recordingOutput
            self.terminalError = nil
            self.didFinish = false
            self.finishContinuations.removeAll()
        }

        do {
            try await stream.startCapture()
        } catch {
            resetState()
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

        await waitForRecordingOutputToFinish()
        let error = stateLock.withLock { terminalError }
        resetState()

        if let error {
            throw CaptureError.recordingFailed(Self.errorDetails(error))
        }
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
