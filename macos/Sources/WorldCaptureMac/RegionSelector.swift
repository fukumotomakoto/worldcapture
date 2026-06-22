import AppKit
import CaptureKit

/// 一次区域选择的结果：截图所需的 `CaptureRegion`、选区所在显示器及其全局矩形。
struct RegionSelection {
    let region: CaptureRegion
    let displayID: CGDirectDisplayID
    let globalRect: CGRect
    let screenFrame: CGRect
}

@MainActor
final class RegionSelector {
    private var panels: [SelectionPanel] = []
    private var keyMonitor: Any?
    private var continuation: CheckedContinuation<RegionSelection?, Never>?

    /// 每块显示器各一个选择遮罩（兼容“显示器使用单独空间”），支持跨屏：在任意屏框选，按该屏截图。
    func selectRegion() async -> RegionSelection? {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return nil }

        return await withCheckedContinuation { continuation in
            self.continuation = continuation

            for screen in screens {
                guard let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
                    continue
                }
                let pixelSize = Self.pixelSize(of: displayID)

                // 关键：不传 screen: 参数（避免 contentRect 被相对该屏二次偏移到屏外），
                // 用全局坐标的 contentRect，再显式 setFrame 落到对应屏。
                let panel = SelectionPanel(
                    contentRect: screen.frame,
                    styleMask: .borderless,
                    backing: .buffered,
                    defer: false
                )
                panel.setFrame(screen.frame, display: false)
                panel.level = .screenSaver
                panel.backgroundColor = .clear
                panel.isOpaque = false
                panel.hasShadow = false
                panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

                let selectionView = SelectionView(frame: CGRect(origin: .zero, size: screen.frame.size))
                selectionView.onFinish = { [weak self] localRect in
                    let globalRect = localRect.map {
                        $0.offsetBy(dx: screen.frame.minX, dy: screen.frame.minY)
                    }
                    let selection = globalRect.flatMap { rect -> RegionSelection? in
                        guard let region = CaptureRegion(selection: rect, displayFrame: screen.frame, pixelSize: pixelSize) else {
                            return nil
                        }
                        return RegionSelection(region: region, displayID: displayID, globalRect: rect, screenFrame: screen.frame)
                    }
                    self?.finish(with: selection)
                }
                panel.contentView = selectionView
                panels.append(panel)
                panel.orderFrontRegardless()
            }

            // 全局 Esc 监听：任意屏（含非 key 遮罩）按 Esc 都能取消。
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                if event.keyCode == 53 {
                    self?.finish(with: nil)
                    return nil
                }
                return event
            }

            NSApp.activate(ignoringOtherApps: true)
            (panels.first { $0.screen == NSScreen.main } ?? panels.first)?.makeKeyAndOrderFront(nil)
            NSCursor.crosshair.push()
        }
    }

    private func finish(with selection: RegionSelection?) {
        // 防止任一屏的 onFinish 多次触发导致续体重复 resume：先取出并清空。
        guard let continuation else { return }
        self.continuation = nil

        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        NSCursor.pop()
        for panel in panels {
            panel.orderOut(nil)
            panel.close()
        }
        panels.removeAll()
        continuation.resume(returning: selection)
    }

    /// 取显示器原生像素尺寸（避免 HiDPI 缩放模式下逻辑尺寸导致区域非 Retina）。
    private static func pixelSize(of displayID: CGDirectDisplayID) -> CGSize {
        if let mode = CGDisplayCopyDisplayMode(displayID) {
            return CGSize(width: mode.pixelWidth, height: mode.pixelHeight)
        }
        return CGSize(width: CGDisplayPixelsWide(displayID), height: CGDisplayPixelsHigh(displayID))
    }
}

private final class SelectionPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

private final class SelectionView: NSView {
    var onFinish: ((CGRect?) -> Void)?
    private var startPoint: CGPoint?
    private var selection: CGRect?

    override var acceptsFirstResponder: Bool { true }

    // 允许在非 key 的副屏遮罩上首次点击即开始框选，而不是先消耗一次点击去激活窗口。
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        startPoint = event.locationInWindow
        selection = nil
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let startPoint else { return }
        selection = CGRect(from: startPoint, to: event.locationInWindow)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let startPoint else {
            onFinish?(nil)
            return
        }
        let result = CGRect(from: startPoint, to: event.locationInWindow)
        onFinish?(result.width >= 2 && result.height >= 2 ? result : nil)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onFinish?(nil)
        } else {
            super.keyDown(with: event)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.34).setFill()
        let mask = NSBezierPath(rect: bounds)
        if let selection {
            mask.appendRect(selection)
            mask.windingRule = .evenOdd
        }
        mask.fill()

        guard let selection else { return }
        NSColor.white.setStroke()
        let border = NSBezierPath(rect: selection.insetBy(dx: 0.5, dy: 0.5))
        border.lineWidth = 1
        border.stroke()
    }
}

private extension CGRect {
    init(from start: CGPoint, to end: CGPoint) {
        self.init(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
    }
}

