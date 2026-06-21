import AppKit
import CoreGraphics
import ScreenCaptureKit

public protocol ScreenCapturing: Sendable {
    func captureMainDisplay(region: CaptureRegion?) async throws -> CGImage
    func availableWindows() async throws -> [CaptureWindow]
    func captureWindow(id: CGWindowID) async throws -> CGImage
}

public extension ScreenCapturing {
    func captureMainDisplay() async throws -> CGImage {
        try await captureMainDisplay(region: nil)
    }
}

public struct ScreenCapturer: ScreenCapturing {
    public init() {}

    public func captureMainDisplay(region: CaptureRegion? = nil) async throws -> CGImage {
        let content = try await shareableContent()

        guard let display = content.displays.first(where: { $0.displayID == CGMainDisplayID() })
                ?? content.displays.first else {
            throw CaptureError.noDisplayAvailable
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let configuration = SCStreamConfiguration()
        if let region {
            configuration.sourceRect = region.sourceRect
            configuration.width = region.pixelWidth
            configuration.height = region.pixelHeight
        } else {
            configuration.width = display.width
            configuration.height = display.height
        }
        configuration.showsCursor = true
        configuration.captureResolution = .best

        return try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: configuration
        )
    }

    public func availableWindows() async throws -> [CaptureWindow] {
        let content = try await shareableContent()
        let currentProcess = pid_t(ProcessInfo.processInfo.processIdentifier)

        return content.windows
            .filter { window in
                window.isOnScreen
                    && window.windowLayer == 0
                    && window.frame.width >= 100
                    && window.frame.height >= 80
                    && window.owningApplication?.processID != currentProcess
            }
            .map { window in
                CaptureWindow(
                    id: window.windowID,
                    applicationName: window.owningApplication?.applicationName ?? "未知应用",
                    title: window.title ?? "",
                    frame: window.frame
                )
            }
            .sorted {
                ($0.applicationName.localizedStandardCompare($1.applicationName) == .orderedAscending)
                    || ($0.applicationName == $1.applicationName
                        && $0.title.localizedStandardCompare($1.title) == .orderedAscending)
            }
    }

    public func captureWindow(id: CGWindowID) async throws -> CGImage {
        let content = try await shareableContent()
        guard let window = content.windows.first(where: { $0.windowID == id }) else {
            throw CaptureError.windowUnavailable
        }

        let filter = SCContentFilter(desktopIndependentWindow: window)
        let configuration = SCStreamConfiguration()
        configuration.width = max(1, Int((filter.contentRect.width * CGFloat(filter.pointPixelScale)).rounded()))
        configuration.height = max(1, Int((filter.contentRect.height * CGFloat(filter.pointPixelScale)).rounded()))
        configuration.showsCursor = false
        configuration.captureResolution = .best

        return try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: configuration
        )
    }

    private func shareableContent() async throws -> SCShareableContent {
        do {
            return try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: true
            )
        } catch {
            throw CaptureError.permissionDenied
        }
    }
}
