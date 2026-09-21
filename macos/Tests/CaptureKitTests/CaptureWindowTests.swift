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

@Test func dropsUntitledWindowsOfAppsThatHaveTitledWindows() {
    let frame = CGRect(x: 0, y: 0, width: 1080, height: 81)
    let windows = [
        CaptureWindow(id: 1, applicationName: "Google Chrome", title: "", frame: frame),
        CaptureWindow(id: 2, applicationName: "Google Chrome", title: "Dell - カート", frame: frame),
        CaptureWindow(id: 3, applicationName: "Google Chrome", title: "", frame: frame),
        CaptureWindow(id: 4, applicationName: "DesktopSprite", title: "", frame: frame),
        CaptureWindow(id: 5, applicationName: "iTerm2", title: "Claude Code", frame: frame),
    ]

    #expect(windows.droppingUntitledHelperWindows().map(\.id) == [2, 4, 5])
}

@Test func keepsUntitledWindowsWhenAppHasNoTitledWindow() {
    let frame = CGRect(x: 0, y: 0, width: 220, height: 220)
    let windows = [
        CaptureWindow(id: 4, applicationName: "DesktopSprite", title: "", frame: frame),
        CaptureWindow(id: 6, applicationName: "DesktopSprite", title: "", frame: frame),
    ]

    #expect(windows.droppingUntitledHelperWindows().map(\.id) == [4, 6])
}
