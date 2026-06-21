import SwiftUI

@main
struct WorldCaptureApp: App {
    var body: some Scene {
        WindowGroup {
            CaptureView()
                .frame(minWidth: 720, minHeight: 520)
        }
        .windowStyle(.hiddenTitleBar)
    }
}

