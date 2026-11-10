import AppKit
import Carbon
import Foundation
import SwiftUI

private let worldCaptureHotKeySignature: OSType = 0x57434350 // WCCP

/// 全局快捷键表（2026-11-11 师弟定）：单个 ⌥ + 英文首字母——两键、一只手按得到（⌃⌥ 三键师弟嫌难按）。
/// 代价：⌥A=å、⌥S=ß 这类特殊字符在这几个字母上打不出来（中日用户几乎不用）；避开了 ⌥E/U/I/N/` 这些重音死键。
/// 字母全在左手区（取字用 C = Copy text，而不是右手的 O），左拇指按 ⌥ 就能单手完成。
/// 避开系统截图 ⌘⇧3/4/5/6。一个功能只有一个键（老的 ⌘⇧2 已删，师弟 2026-11-11 定）。
enum HotKeyAction: UInt32, CaseIterable, Identifiable {
    case region = 1
    case window
    case fullScreen
    case scrolling
    case ocr
    case mirror
    case record
    case gif
    case repeatRegion

    var id: UInt32 { rawValue }

    var keyCode: Int {
        switch self {
        case .region: kVK_ANSI_A
        case .window: kVK_ANSI_W
        case .fullScreen: kVK_ANSI_F
        case .scrolling: kVK_ANSI_S
        case .ocr: kVK_ANSI_C
        case .mirror: kVK_ANSI_T
        case .record: kVK_ANSI_R
        case .gif: kVK_ANSI_G
        case .repeatRegion: kVK_ANSI_Z
        }
    }

    var carbonModifiers: Int {
        optionKey
    }

    /// 菜单里显示用（SwiftUI keyboardShortcut）。
    var keyEquivalent: KeyEquivalent {
        switch self {
        case .region: "a"
        case .window: "w"
        case .fullScreen: "f"
        case .scrolling: "s"
        case .ocr: "c"
        case .mirror: "t"
        case .record: "r"
        case .gif: "g"
        case .repeatRegion: "z"
        }
    }

    var eventModifiers: SwiftUI.EventModifiers {
        [.option]
    }

    /// 设置页里显示的组合键文字。
    var display: String {
        "⌥" + String(keyEquivalent.character).uppercased()
    }

    /// 功能名（复用菜单的文案）。
    var titleKey: String {
        switch self {
        case .region: "menu.region"
        case .window: "menu.window"
        case .fullScreen: "menu.main"
        case .scrolling: "menu.scrolling"
        case .ocr: "menu.ocr"
        case .mirror: "menu.mirror"
        case .record: "record.screen"
        case .gif: "record.gif"
        case .repeatRegion: "menu.repeatRegion"
        }
    }
}

/// 注册结果（设置页显示「被占用」用）。
@MainActor
enum HotKeyStatus {
    static var failed: Set<HotKeyAction> = []
}

private func worldCaptureHotKeyHandler(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }

    var identifier = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &identifier
    )
    guard status == noErr,
          identifier.signature == worldCaptureHotKeySignature,
          let action = HotKeyAction(rawValue: identifier.id) else {
        return OSStatus(eventNotHandledErr)
    }

    let hotKeys = Unmanaged<GlobalHotKeys>.fromOpaque(userData).takeUnretainedValue()
    hotKeys.invoke(action)
    return noErr
}

/// 注册整张 `HotKeyAction` 表为系统级热键（Carbon RegisterEventHotKey：无需辅助功能权限）。
/// 某个组合被别的程序先占了，注册会失败——记进 `failed`，其余照常生效。
final class GlobalHotKeys: @unchecked Sendable {
    private var hotKeyRefs: [EventHotKeyRef] = []
    private var eventHandlerRef: EventHandlerRef?
    private let action: @MainActor @Sendable (HotKeyAction) -> Void
    private(set) var failed: [HotKeyAction] = []

    init(action: @escaping @MainActor @Sendable (HotKeyAction) -> Void) {
        self.action = action

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            worldCaptureHotKeyHandler,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )

        for hotKey in HotKeyAction.allCases {
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(
                UInt32(hotKey.keyCode),
                UInt32(hotKey.carbonModifiers),
                EventHotKeyID(signature: worldCaptureHotKeySignature, id: hotKey.rawValue),
                GetApplicationEventTarget(),
                0,
                &ref
            )
            if status == noErr, let ref {
                hotKeyRefs.append(ref)
            } else {
                failed.append(hotKey)
            }
        }
    }

    deinit {
        hotKeyRefs.forEach { UnregisterEventHotKey($0) }
        if let eventHandlerRef { RemoveEventHandler(eventHandlerRef) }
    }

    fileprivate func invoke(_ hotKey: HotKeyAction) {
        let action = self.action
        Task { @MainActor in action(hotKey) }
    }
}

extension NSScreen {
    /// 鼠标当前所在的屏幕（多屏时「全屏截图 / 录屏 / 顶部工具条」都作用于这块屏）。
    static var underMouse: NSScreen? {
        let point = NSEvent.mouseLocation
        return screens.first { NSMouseInRect(point, $0.frame, false) } ?? main
    }

    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}
