import AppKit
import CoreGraphics
import ScreenCaptureKit

public protocol ScreenCapturing: Sendable {
    /// 截取指定显示器；找不到该 ID 时回退到第一块可用显示器。
    func captureDisplay(id displayID: CGDirectDisplayID, region: CaptureRegion?) async throws -> CGImage
    func availableWindows() async throws -> [CaptureWindow]
    func captureWindow(id: CGWindowID) async throws -> CGImage
}

public extension ScreenCapturing {
    func captureMainDisplay(region: CaptureRegion? = nil) async throws -> CGImage {
        try await captureDisplay(id: CGMainDisplayID(), region: region)
    }
}

public struct ScreenCapturer: ScreenCapturing {
    public init() {}

    public func captureDisplay(id displayID: CGDirectDisplayID, region: CaptureRegion? = nil) async throws -> CGImage {
        let content = try await shareableContent()

        guard let display = content.displays.first(where: { $0.displayID == displayID })
                ?? content.displays.first else {
            throw CaptureError.noDisplayAvailable
        }

        // 排除 WorldCapture 自身窗口（主窗口、区域选择遮罩、钉屏浮窗），
        // 否则区域/全屏截图会把暗色选择遮罩等自身界面一起拍进去。
        let currentPID = pid_t(ProcessInfo.processInfo.processIdentifier)
        let filter: SCContentFilter
        if let currentApplication = content.applications.first(where: { $0.processID == currentPID }) {
            filter = SCContentFilter(display: display, excludingApplications: [currentApplication], exceptingWindows: [])
        } else {
            filter = SCContentFilter(display: display, excludingWindows: [])
        }
        // 统一用 SCK 权威的 pointPixelScale 计算像素尺寸，确保与原生分辨率 1:1、不被重采样而发虚。
        let scale = CGFloat(filter.pointPixelScale)
        let configuration = SCStreamConfiguration()
        if let region {
            configuration.sourceRect = region.sourceRect
            configuration.width = max(1, Int((region.sourceRect.width * scale).rounded()))
            configuration.height = max(1, Int((region.sourceRect.height * scale).rounded()))
        } else {
            configuration.width = max(1, Int((filter.contentRect.width * scale).rounded()))
            configuration.height = max(1, Int((filter.contentRect.height * scale).rounded()))
        }
        // 静态截图（主屏/区域/滚动）不画鼠标光标，避免长图拼接时把箭头拍进画面。
        configuration.showsCursor = false
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

    /// 窗口缩略图（用于可视化窗口选择器）。失败返回 nil。
    public func windowThumbnail(id: CGWindowID, maxDimension: CGFloat = 360) async -> CGImage? {
        guard let content = try? await shareableContent(),
              let window = content.windows.first(where: { $0.windowID == id }) else { return nil }
        return try? await Self.captureThumbnail(filter: SCContentFilter(desktopIndependentWindow: window), maxDimension: maxDimension)
    }

    /// 显示器缩略图（排除本应用窗口）。失败返回 nil。
    public func displayThumbnail(id displayID: CGDirectDisplayID, maxDimension: CGFloat = 360) async -> CGImage? {
        guard let content = try? await shareableContent(),
              let display = content.displays.first(where: { $0.displayID == displayID }) ?? content.displays.first else { return nil }
        let currentPID = pid_t(ProcessInfo.processInfo.processIdentifier)
        let filter: SCContentFilter
        if let app = content.applications.first(where: { $0.processID == currentPID }) {
            filter = SCContentFilter(display: display, excludingApplications: [app], exceptingWindows: [])
        } else {
            filter = SCContentFilter(display: display, excludingWindows: [])
        }
        return try? await Self.captureThumbnail(filter: filter, maxDimension: maxDimension)
    }

    private static func captureThumbnail(filter: SCContentFilter, maxDimension: CGFloat) async throws -> CGImage {
        let scale = CGFloat(filter.pointPixelScale)
        let fullWidth = filter.contentRect.width * scale
        let fullHeight = filter.contentRect.height * scale
        let factor = min(1, maxDimension / max(fullWidth, fullHeight))
        let configuration = SCStreamConfiguration()
        configuration.width = max(1, Int((fullWidth * factor).rounded()))
        configuration.height = max(1, Int((fullHeight * factor).rounded()))
        configuration.showsCursor = false
        configuration.captureResolution = .best
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
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
