import SwiftUI

@main
struct WorldCaptureApp: App {
    @StateObject private var model = CaptureViewModel()
    @StateObject private var history = HistoryStore.shared
    @StateObject private var updater = UpdaterController()

    var body: some Scene {
        WindowGroup {
            CaptureView(model: model)
                .frame(minWidth: 1160, minHeight: 560)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1160, height: 640)
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

        MenuBarExtra("WorldCapture", systemImage: "camera.viewfinder") {
            MenuBarCommands(model: model, updater: updater)
        }
    }
}
