import SwiftUI

@main
struct WorldCaptureApp: App {
    @StateObject private var model = CaptureViewModel()

    var body: some Scene {
        WindowGroup {
            CaptureView(model: model)
                .frame(minWidth: 900, minHeight: 560)
        }
        .windowStyle(.hiddenTitleBar)

        MenuBarExtra("WorldCapture", systemImage: "camera.viewfinder") {
            MenuBarCommands(model: model)
        }
    }
}
