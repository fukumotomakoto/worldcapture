import AppKit
import SwiftUI

@main
struct WorldCaptureApp: App {
    @StateObject private var model = CaptureViewModel()
    @StateObject private var history = HistoryStore.shared
    @StateObject private var updater = UpdaterController()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        WindowGroup(id: "main") {
            CaptureView(model: model)
                .frame(minWidth: 900, minHeight: 580)
                .background(MinimizeOnClose())
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 960, height: 640)
        // 顶部工具条开着时，启动只显示工具条 + 菜单栏图标；主窗口（编辑器）截完图才打开。
        .defaultLaunchBehavior(TopDockController.isEnabledAtLaunch ? .suppressed : .automatic)
        .commands {
            CommandGroup(after: .appInfo) {
                Button(Loc.s("menu.checkUpdates")) { updater.checkForUpdates() }
                    .disabled(!updater.canCheckForUpdates)
            }
        }

        Window(Loc.s("library.title"), id: "history") {
            HistoryLibraryView(store: history)
        }
        .defaultSize(width: 820, height: 560)

        Settings {
            SettingsView(updater: updater)
        }

        MenuBarExtra {
            MenuBarCommands(model: model, updater: updater)
        } label: {
            Label("WorldCapture", systemImage: "camera.viewfinder")
                // 状态栏图标在启动时就会创建：借它把「打开主窗口」的能力交给模型，并挂起顶部工具条。
                .onAppear {
                    model.openMainWindow = {
                        openWindow(id: "main")
                        NSApp.activate(ignoringOtherApps: true)
                    }
                    TopDockController.shared.attach(model: model)
                }
        }
    }
}
