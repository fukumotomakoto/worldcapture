import CoreGraphics
import Foundation

public enum AnnotationKind: String, Codable, CaseIterable, Sendable {
    case rectangle
    case arrow
}

public struct NormalizedPoint: Codable, Equatable, Sendable {
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) {
        self.x = min(1, max(0, x))
        self.y = min(1, max(0, y))
    }
}

public struct CaptureAnnotation: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let kind: AnnotationKind
    public let start: NormalizedPoint
    public let end: NormalizedPoint

    public init(
        id: UUID = UUID(),
        kind: AnnotationKind,
        start: NormalizedPoint,
        end: NormalizedPoint
    ) {
        self.id = id
        self.kind = kind
        self.start = start
        self.end = end
    }
}
