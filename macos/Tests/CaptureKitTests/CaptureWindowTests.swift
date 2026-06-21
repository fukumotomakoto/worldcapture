import CoreGraphics
import Testing
@testable import CaptureKit

@Test func windowDisplayNameIncludesApplicationAndTitle() {
    let window = CaptureWindow(
        id: 42,
        applicationName: "Safari",
        title: "Apple Developer",
        frame: CGRect(x: 0, y: 0, width: 800, height: 600)
    )

    #expect(window.displayName == "Safari — Apple Developer")
}

@Test func untitledWindowFallsBackToApplicationName() {
    let window = CaptureWindow(
        id: 42,
        applicationName: "Finder",
        title: "",
        frame: CGRect(x: 0, y: 0, width: 800, height: 600)
    )

    #expect(window.displayName == "Finder")
}

