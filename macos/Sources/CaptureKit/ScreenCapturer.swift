import AppKit
import CoreGraphics
import ScreenCaptureKit

public protocol ScreenCapturing: Sendable {
    func captureMainDisplay(region: CaptureRegion?) async throws -> CGImage
}

public extension ScreenCapturing {
    func captureMainDisplay() async throws -> CGImage {
        try await captureMainDisplay(region: nil)
    }
}

public struct ScreenCapturer: ScreenCapturing {
    public init() {}

    public func captureMainDisplay(region: CaptureRegion? = nil) async throws -> CGImage {
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: true
            )
        } catch {
            throw CaptureError.permissionDenied
        }

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
}
