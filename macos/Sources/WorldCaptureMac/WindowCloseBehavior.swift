import AppKit
import SwiftUI

/// 让主窗口的关闭按钮改为「最小化到 Dock」，而非销毁窗口。
/// 保留窗口与应用状态，可从 Dock 或菜单栏「显示主窗口」恢复；不影响真正的退出。
final class MinimizeOnCloseDelegate: NSObject, NSWindowDelegate {
    /// SwiftUI 原本的窗口委托——未处理的方法转发给它，避免破坏窗口管理。
    weak var previous: NSWindowDelegate?

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.miniaturize(nil)
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
    func makeCoordinator() -> MinimizeOnCloseDelegate { MinimizeOnCloseDelegate() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            // 已安装则不重复包裹（避免自引用循环）。
            if window.delegate is MinimizeOnCloseDelegate { return }
            context.coordinator.previous = window.delegate
            window.delegate = context.coordinator
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
