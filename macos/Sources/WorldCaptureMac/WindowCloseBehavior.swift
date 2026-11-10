import AppKit
import SwiftUI

/// 让主窗口的关闭按钮改为「最小化到 Dock」，而非销毁窗口。
/// 保留窗口与应用状态，可从 Dock 或菜单栏「显示主窗口」恢复；不影响真正的退出。
final class MinimizeOnCloseDelegate: NSObject, NSWindowDelegate {
    /// SwiftUI 原本的窗口委托——未处理的方法转发给它，避免破坏窗口管理。
    weak var previous: NSWindowDelegate?

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // 顶部工具条开着：关闭 = 收起编辑器，回到只有工具条；否则最小化到 Dock。
        if TopDockController.shared.isEnabled {
            sender.orderOut(nil)
        } else {
            sender.miniaturize(nil)
        }
        return false
    }

    override func responds(to aSelector: Selector!) -> Bool {
        super.responds(to: aSelector) || (previous?.responds(to: aSelector) ?? false)
    }

    override func forwardingTarget(for aSelector: Selector!) -> Any? {
        super.responds(to: aSelector) ? self : previous
    }
}

/// 把它 `.background(...)` 到主窗口内容上，即可把关闭改为最小化。
struct MinimizeOnClose: NSViewRepresentable {
    /// 已创建的主窗口（弱引用）：`openMainWindow` 靠它找回已有窗口，而不是再开一个。
    /// 不改写 `window.identifier`——那是 SwiftUI 认领场景窗口用的。
    @MainActor static weak var mainWindow: NSWindow?

    func makeCoordinator() -> MinimizeOnCloseDelegate { MinimizeOnCloseDelegate() }

    /// 多屏：把窗口搬到鼠标所在的屏（2026-11-11 师弟：截完图编辑器要出现在当前屏，
    /// 而不是上次拖放过的那块屏）。保持它在屏内的相对位置，放不下就缩到可见区域内。
    @MainActor
    static func moveToScreenUnderMouse(_ window: NSWindow) {
        guard let target = NSScreen.underMouse, window.screen != target else { return }
        let source = window.screen ?? NSScreen.screens.first ?? target
        let from = source.visibleFrame
        let to = target.visibleFrame
        var frame = window.frame
        frame.size.width = min(frame.width, to.width)
        frame.size.height = min(frame.height, to.height)
        // 窗口中心在原屏可见区域里的比例 → 新屏的同一比例处。
        let fx = from.width > 0 ? (window.frame.midX - from.minX) / from.width : 0.5
        let fy = from.height > 0 ? (window.frame.midY - from.minY) / from.height : 0.5
        frame.origin.x = to.minX + to.width * min(max(fx, 0), 1) - frame.width / 2
        frame.origin.y = to.minY + to.height * min(max(fy, 0), 1) - frame.height / 2
        frame.origin.x = min(max(frame.minX, to.minX), to.maxX - frame.width)
        frame.origin.y = min(max(frame.minY, to.minY), to.maxY - frame.height)
        window.setFrame(frame, display: false)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            // 第一次创建（openWindow）时也出现在鼠标所在的屏。
            if Self.mainWindow !== window { Self.moveToScreenUnderMouse(window) }
            Self.mainWindow = window
            // 已安装则不重复包裹（避免自引用循环）。
            if window.delegate is MinimizeOnCloseDelegate { return }
            context.coordinator.previous = window.delegate
            window.delegate = context.coordinator
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
