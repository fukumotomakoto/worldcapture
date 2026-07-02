import SwiftUI

@main
struct WorldCaptureApp: App {
    @StateObject private var model = CaptureViewModel()
    @StateObject private var history = HistoryStore.shared
    @StateObject private var updater = UpdaterController()

    var body: some Scene {
        WindowGroup {
            CaptureView(model: model)
                .frame(minWidth: 900, minHeight: 580)
                .background(MinimizeOnClose())
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 960, height: 640)
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
