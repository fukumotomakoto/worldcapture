import CoreGraphics
import Foundation

public enum AnnotationKind: String, Codable, CaseIterable, Sendable {
    case rectangle
    case arrow
    case text
    case number
    case mosaic
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
    /// 缺省颜色（系统红 #FF3B30），用于未显式设置颜色或旧工程文件。
    public static let defaultColorHex = "#FF3B30"

    public let id: UUID
    public let kind: AnnotationKind
    public var start: NormalizedPoint
    public var end: NormalizedPoint
    public var label: String?
    /// `#RRGGBB`/`#RRGGBBAA`；nil 表示使用默认强调色。可选以兼容旧工程文件。
    public var colorHex: String?
    /// 线宽倍率（相对默认基准），nil 表示 1.0。仅作用于矩形与箭头描边。
    public var lineWidth: Double?

    public init(
        id: UUID = UUID(),
        kind: AnnotationKind,
        start: NormalizedPoint,
        end: NormalizedPoint,
        label: String? = nil,
        colorHex: String? = nil,
        lineWidth: Double? = nil
    ) {
        self.id = id
        self.kind = kind
        self.start = start
        self.end = end
        self.label = label
        self.colorHex = colorHex
        self.lineWidth = lineWidth
    }

    /// 实际线宽倍率，缺省 1.0。
    public var resolvedLineWidth: Double {
        lineWidth ?? 1
    }

    /// 实际使用的颜色十六进制，缺省回退到 `defaultColorHex`。
    public var resolvedColorHex: String {
        colorHex ?? Self.defaultColorHex
    }

    public var color: RGBAColor {
        RGBAColor(hex: resolvedColorHex)
    }
}

public extension CaptureAnnotation {
    /// 归一化空间中的包围盒（点状标注退化为零尺寸）。
    var normalizedBounds: CGRect {
        CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
    }

    /// 命中测试：归一化空间中，`point` 是否落在标注的可选中范围内（`tolerance` 为归一化容差）。
    func hitTest(_ point: NormalizedPoint, tolerance: Double) -> Bool {
        let p = CGPoint(x: point.x, y: point.y)
        switch kind {
        case .rectangle, .mosaic:
            return normalizedBounds.insetBy(dx: -tolerance, dy: -tolerance).contains(p)
        case .arrow:
            return Self.distance(from: p,
                                 toSegment: CGPoint(x: start.x, y: start.y),
                                 and: CGPoint(x: end.x, y: end.y)) <= tolerance
        case .text, .number:
            return hypot(p.x - start.x, p.y - start.y) <= max(tolerance, 0.04)
        }
    }

    /// 在归一化空间内整体平移，端点自动限制在 `0...1`。
    func translated(by delta: (dx: Double, dy: Double)) -> CaptureAnnotation {
        var moved = self
        moved.start = NormalizedPoint(x: start.x + delta.dx, y: start.y + delta.dy)
        moved.end = NormalizedPoint(x: end.x + delta.dx, y: end.y + delta.dy)
        return moved
    }

    private static func distance(from p: CGPoint, toSegment a: CGPoint, and b: CGPoint) -> Double {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return hypot(p.x - a.x, p.y - a.y) }
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSquared))
        let projection = CGPoint(x: a.x + t * dx, y: a.y + t * dy)
        return hypot(p.x - projection.x, p.y - projection.y)
    }
}
