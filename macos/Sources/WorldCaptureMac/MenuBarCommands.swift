import AppKit
import SwiftUI

/// 菜单栏常驻入口：无需主窗口聚焦即可发起截屏/录屏。
struct MenuBarCommands: View {
    @ObservedObject var model: CaptureViewModel

    var body: some View {
        Button(Loc.s("menu.region")) { run { await model.captureRegion() } }
            .keyboardShortcut("2", modifiers: [.command, .shift])
        Button(Loc.s("menu.main")) { activateThen { await model.capture() } }
        Button(Loc.s("menu.window")) { activateThen { await model.captureSelectedWindow() } }
            .disabled(model.selectedWindowID == nil)

        Divider()

        Button(model.isRecording ? Loc.s("record.stop") : Loc.s("record.screen")) {
            Task { await model.toggleRecording() }
        }

        Divider()

        Button(Loc.s("menu.showMain")) { NSApp.activate(ignoringOtherApps: true) }
        Button(Loc.s("menu.quit")) { NSApp.terminate(nil) }
            .keyboardShortcut("q", modifiers: .command)
    }

    /// 直接执行（区域截屏自带全屏覆盖层，不需要先激活主窗口）。
    private func run(_ action: @escaping () async -> Void) {
        Task { await action() }
    }

    /// 先把应用带到前台再执行，使结果显示在主窗口中。
    private func activateThen(_ action: @escaping () async -> Void) {
        NSApp.activate(ignoringOtherApps: true)
        Task { await action() }
    }
}
