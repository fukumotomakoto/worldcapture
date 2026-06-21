import CoreGraphics

public struct CaptureWindow: Identifiable, Equatable, Sendable {
    public let id: CGWindowID
    public let applicationName: String
    public let title: String
    public let frame: CGRect

    public init(id: CGWindowID, applicationName: String, title: String, frame: CGRect) {
        self.id = id
        self.applicationName = applicationName
        self.title = title
        self.frame = frame
    }

    public var displayName: String {
        title.isEmpty ? applicationName : "\(applicationName) — \(title)"
    }
}

