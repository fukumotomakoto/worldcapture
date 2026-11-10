import AppKit
import SwiftUI

/// 菜单栏常驻入口：无需主窗口聚焦即可发起截屏/录屏/取字。
/// 布局借鉴 iScreen Shoter「功能丰富但每模式一键直达 + 内联快捷键提示」，并补全已有但未暴露的能力
/// （OCR、滚动截屏、GIF、延时、最近截图）。
struct MenuBarCommands: View {
    @ObservedObject var model: CaptureViewModel
    @ObservedObject var updater: UpdaterController
    @ObservedObject private var pinned = PinnedImageController.shared
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Section(Loc.s("menu.section.capture")) {
            // 显示的快捷键 = 全局热键表（GlobalHotKey.swift 的 HotKeyAction），别再写死 ⌘⇧3/4/5/6——那是系统截图键。
            Button(Loc.s("menu.region")) { run { await model.captureRegion() } }
                .shortcut(.region)
            Button(Loc.s("menu.repeatRegion")) { run { await model.repeatLastRegion() } }
                .shortcut(.repeatRegion)
            // 截「当前正在用的窗口」（前台应用最前面那扇），不必先在主窗口里选。
            Button(Loc.s("menu.window")) { run { await model.captureFrontmostWindow() } }
                .shortcut(.window)
            Button(Loc.s("menu.main")) { activateThen { await model.capture() } }
                .shortcut(.fullScreen)
            Button(Loc.s("menu.scrolling")) { run { await model.captureScrolling() } }
                .shortcut(.scrolling)
            Button(Loc.s("menu.ocr")) { activateThen { await model.captureRegionAndExtractText() } }
                .shortcut(.ocr)
            Button(Loc.s("menu.mirror")) { run { await model.startTranslationMirror() } }
                .shortcut(.mirror)
            Menu(Loc.s("menu.delay")) {
                Button(Loc.s("menu.delay.seconds", Int32(3))) { run { await delayThenCapture(3) } }
                Button(Loc.s("menu.delay.seconds", Int32(5))) { run { await delayThenCapture(5) } }
                Button(Loc.s("menu.delay.seconds", Int32(10))) { run { await delayThenCapture(10) } }
            }
        }

        Section(Loc.s("menu.section.record")) {
            Button(model.isRecording ? Loc.s("record.stop") : Loc.s("record.screen")) {
                Task { await model.toggleRecording() }
            }
            .shortcut(.record)
            Button(model.isGIFRecording ? Loc.s("record.gif.stop") : Loc.s("record.gif")) {
                Task { await model.toggleGIFRecording() }
            }
            .shortcut(.gif)
        }

        Divider()

        Group {
            Menu(Loc.s("menu.recent")) { RecentCapturesMenu() }
            Button(Loc.s("library.open")) {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "history")
            }
            Button(Loc.s("pin.clickThrough.disableAll")) { pinned.disableAllClickThrough() }
                .disabled(pinned.clickThroughCount == 0)
        }

        Divider()

        Group {
            Button(Loc.s("menu.showMain")) { model.openMainWindow() }
            Button(Loc.s("menu.checkUpdates")) { updater.checkForUpdates() }
                .disabled(!updater.canCheckForUpdates)
            SettingsLink { Text(Loc.s("menu.settings")) }
                .keyboardShortcut(",", modifiers: .command)
            Button(Loc.s("menu.quit")) { NSApp.terminate(nil) }
                .keyboardShortcut("q", modifiers: .command)
        }
    }

    /// 直接执行（区域截屏自带全屏覆盖层，不需要先激活主窗口；延时截屏也刻意不激活，以免驱散悬停菜单）。
    private func run(_ action: @escaping () async -> Void) {
        Task { await action() }
    }

    /// 先把应用带到前台再执行，使结果显示在主窗口中。
    private func activateThen(_ action: @escaping () async -> Void) {
        NSApp.activate(ignoringOtherApps: true)
        Task { await action() }
    }

    /// 延时后再截全屏——用于截取悬停/下拉菜单等需要先手动展开的界面。
    private func delayThenCapture(_ seconds: UInt64) async {
        try? await Task.sleep(nanoseconds: seconds * 1_000_000_000)
        await model.capture()
    }
}

/// 「最近截图」子菜单：展示最近 5 条历史（带缩略图），点按用默认程序打开对应文件。
private struct RecentCapturesMenu: View {
    @ObservedObject private var store = HistoryStore.shared

    var body: some View {
        let recent = Array(store.entries.prefix(5))
        if recent.isEmpty {
            Button(Loc.s("menu.recent.empty")) {}.disabled(true)
        } else {
            ForEach(recent) { entry in
                RecentCaptureItem(entry: entry)
            }
        }
    }
}

private struct RecentCaptureItem: View {
    let entry: HistoryEntry
    @State private var thumb: NSImage?

    var body: some View {
        Button {
            NSWorkspace.shared.open(entry.url)
        } label: {
            if let thumb {
                Label {
                    Text(entry.fileName)
                } icon: {
                    Image(nsImage: thumb).renderingMode(.original)
                }
            } else {
                Text(entry.fileName)
            }
        }
        .task { thumb = await HistoryStore.shared.thumbnail(for: entry, maxDimension: 48) }
    }
}

private extension View {
    func shortcut(_ hotKey: HotKeyAction) -> some View {
        keyboardShortcut(hotKey.keyEquivalent, modifiers: hotKey.eventModifiers)
    }
}
