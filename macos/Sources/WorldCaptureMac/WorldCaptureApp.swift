import SwiftUI

@main
struct WorldCaptureApp: App {
    var body: some Scene {
        WindowGroup {
            CaptureView()
                .frame(minWidth: 900, minHeight: 560)
        }
        .windowStyle(.hiddenTitleBar)
    }
}
