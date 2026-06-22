import ApplicationServices
import CoreGraphics

/// 辅助功能（Accessibility）权限：合成滚轮事件驱动其他应用滚动需要此权限。
enum AccessibilityPermission {
    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// 未授权时弹出系统提示，引导前往设置。返回当前是否已授权。
    @discardableResult
    static func requestPrompt() -> Bool {
        // 等价于 kAXTrustedCheckOptionPrompt，直接用字面量避开全局可变状态的并发告警。
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}

/// 在指定屏幕位置合成滚轮事件，用于滚动捕获时逐屏推进目标内容。
enum ScrollEventSender {
    /// 在 `point` 处向下滚动约 `pixels` 像素（内容上移，露出下方内容）。
    static func scrollDown(at point: CGPoint, pixels: Int) {
        let source = CGEventSource(stateID: .combinedSessionState)

        // 先移动指针到目标位置，使滚轮事件路由到该处的窗口/视图。
        CGEvent(
            mouseEventSource: source,
            mouseType: .mouseMoved,
            mouseCursorPosition: point,
            mouseButton: .left
        )?.post(tap: .cghidEventTap)

        // 负 wheel1 = 向下滚动；像素单位便于按视口比例精确控制重叠。
        if let event = CGEvent(
            scrollWheelEvent2Source: source,
            units: .pixel,
            wheelCount: 1,
            wheel1: Int32(-max(1, pixels)),
            wheel2: 0,
            wheel3: 0
        ) {
            event.location = point
            event.post(tap: .cghidEventTap)
        }
    }
}
