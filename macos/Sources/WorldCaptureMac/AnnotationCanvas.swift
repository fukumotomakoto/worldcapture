import AppKit
import CaptureKit
import SwiftUI

struct AnnotationCanvas: View {
    let imageSize: CGSize
    @Binding var annotations: [CaptureAnnotation]
    @Binding var selectedIDs: Set<UUID>
    let tool: AnnotationKind
    let textLabel: String
    let nextNumber: Int
    let colorHex: String
    let lineWidth: Double
    /// 暂不显示、也不参与点选的标注类型（如「显示译文」关掉时的译文块）。
    var hiddenKinds: Set<AnnotationKind> = []

    /// 拖拽会话：新建、（组）移动、缩放或无操作（Shift 加选）。
    private enum Session {
        case create(CaptureAnnotation)
        case move(origins: [UUID: CaptureAnnotation], from: CGPoint)
        case resize(id: UUID, origin: CaptureAnnotation, handle: Int, from: CGPoint)
        case noop
    }

    @State private var session: Session?

    private let handleHitRadius: CGFloat = 12
    private let handleSize: CGFloat = 8

    var body: some View {
        GeometryReader { proxy in
            let imageRect = aspectFitRect(content: imageSize, container: proxy.size)
            Canvas { context, _ in
                for annotation in annotations where !hiddenKinds.contains(annotation.kind) {
                    draw(annotation, context: &context, imageRect: imageRect)
                }
                if case let .create(draft) = session {
                    draw(draft, context: &context, imageRect: imageRect)
                }
                let showHandles = selectedIDs.count == 1
                for annotation in annotations where selectedIDs.contains(annotation.id) && !hiddenKinds.contains(annotation.kind) {
                    drawSelection(annotation, context: &context, imageRect: imageRect, showHandles: showHandles)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if session == nil {
                            session = beginSession(at: value.startLocation, imageRect: imageRect)
                        }
                        update(with: value.location, imageRect: imageRect)
                    }
                    .onEnded { _ in
                        commit()
                        session = nil
                    }
            )
        }
    }

    // MARK: - 手势

    private func beginSession(at location: CGPoint, imageRect: CGRect) -> Session {
        let shift = NSEvent.modifierFlags.contains(.shift)

        // 1) 仅单选时，命中缩放手柄。
        if selectedIDs.count == 1, let id = selectedIDs.first,
           let selected = annotations.first(where: { $0.id == id }),
           let handle = handleIndex(at: location, for: selected, imageRect: imageRect) {
            return .resize(id: id, origin: selected, handle: handle, from: location)
        }

        // 2) 命中已有标注。
        if let hit = topmostHit(at: location, imageRect: imageRect) {
            if shift {
                if selectedIDs.contains(hit.id) { selectedIDs.remove(hit.id) } else { selectedIDs.insert(hit.id) }
                return .noop
            }
            if !selectedIDs.contains(hit.id) { selectedIDs = [hit.id] }
            let origins = annotations.filter { selectedIDs.contains($0.id) }
            return .move(origins: Dictionary(uniqueKeysWithValues: origins.map { ($0.id, $0) }), from: location)
        }

        // 3) 空白处。
        if shift { return .noop } // 保留当前多选（框选留待后续）
        selectedIDs = []
        guard imageRect.contains(location) else { return .noop }
        let point = normalized(location, in: imageRect)
        return .create(CaptureAnnotation(
            kind: tool, start: point, end: point,
            label: labelForCurrentTool, colorHex: colorHex, lineWidth: lineWidth,
            points: tool == .freehand ? [point] : nil
        ))
    }

    private func update(with location: CGPoint, imageRect: CGRect) {
        switch session {
        case let .create(draft):
            var updated = draft
            let point = normalized(clamped(location, to: imageRect), in: imageRect)
            updated.end = point
            if draft.kind == .freehand { updated.points = (draft.points ?? []) + [point] }
            session = .create(updated)
        case let .move(origins, from):
            let dx = (location.x - from.x) / imageRect.width
            let dy = (location.y - from.y) / imageRect.height
            for (id, origin) in origins {
                replace(id: id, with: origin.translated(by: (dx: dx, dy: dy)))
            }
        case let .resize(id, origin, handle, _):
            replace(id: id, with: resized(origin, handle: handle, to: clamped(location, to: imageRect), imageRect: imageRect))
        case .noop, .none:
            break
        }
    }

    private func commit() {
        guard case let .create(draft) = session else { return }
        guard shouldCommit(draft) else { return }
        annotations.append(draft)
        selectedIDs = [draft.id]
    }

    private func shouldCommit(_ annotation: CaptureAnnotation) -> Bool {
        switch annotation.kind {
        case .text, .number:
            return true
        case .freehand:
            return (annotation.points?.count ?? 0) >= 2
        case .rectangle, .ellipse, .arrow, .mosaic, .translation:
            let bounds = annotation.normalizedBounds
            return bounds.width >= 0.01 || bounds.height >= 0.01
        }
    }

    private func replace(id: UUID, with annotation: CaptureAnnotation) {
        guard let index = annotations.firstIndex(where: { $0.id == id }) else { return }
        annotations[index] = annotation
    }

    // MARK: - 命中测试

    private func topmostHit(at location: CGPoint, imageRect: CGRect) -> CaptureAnnotation? {
        let point = normalized(location, in: imageRect)
        let tolerance = handleHitRadius / min(imageRect.width, imageRect.height)
        return annotations.last { !hiddenKinds.contains($0.kind) && $0.hitTest(point, tolerance: Double(tolerance)) }
    }

    /// 返回命中的手柄索引：箭头 0=起点 1=终点；矩形/马赛克 0=左上 1=右上 2=左下 3=右下。
    private func handleIndex(at location: CGPoint, for annotation: CaptureAnnotation, imageRect: CGRect) -> Int? {
        for (index, handle) in handlePoints(for: annotation, imageRect: imageRect) {
            if hypot(location.x - handle.x, location.y - handle.y) <= handleHitRadius {
                return index
            }
        }
        return nil
    }

    private func handlePoints(for annotation: CaptureAnnotation, imageRect: CGRect) -> [(Int, CGPoint)] {
        switch annotation.kind {
        case .arrow:
            return [
                (0, screenPoint(annotation.start, in: imageRect)),
                (1, screenPoint(annotation.end, in: imageRect)),
            ]
        case .rectangle, .ellipse, .mosaic, .translation:
            return corners(of: annotation, imageRect: imageRect).enumerated().map { ($0.offset, $0.element) }
        case .text, .number, .freehand:
            return []
        }
    }

    /// 顺序：左上、右上、左下、右下。
    private func corners(of annotation: CaptureAnnotation, imageRect: CGRect) -> [CGPoint] {
        let bounds = annotation.normalizedBounds
        return [
            screenPoint(NormalizedPoint(x: bounds.minX, y: bounds.minY), in: imageRect),
            screenPoint(NormalizedPoint(x: bounds.maxX, y: bounds.minY), in: imageRect),
            screenPoint(NormalizedPoint(x: bounds.minX, y: bounds.maxY), in: imageRect),
            screenPoint(NormalizedPoint(x: bounds.maxX, y: bounds.maxY), in: imageRect),
        ]
    }

    private func resized(_ origin: CaptureAnnotation, handle: Int, to location: CGPoint, imageRect: CGRect) -> CaptureAnnotation {
        var updated = origin
        let dragged = normalized(location, in: imageRect)
        switch origin.kind {
        case .arrow:
            if handle == 0 { updated.start = dragged } else { updated.end = dragged }
        case .rectangle, .ellipse, .mosaic, .translation:
            let bounds = origin.normalizedBounds
            // 锚定被拖角的对角，使矩形从固定角缩放。
            let anchor: NormalizedPoint
            switch handle {
            case 0: anchor = NormalizedPoint(x: bounds.maxX, y: bounds.maxY) // 左上 → 锚右下
            case 1: anchor = NormalizedPoint(x: bounds.minX, y: bounds.maxY) // 右上 → 锚左下
            case 2: anchor = NormalizedPoint(x: bounds.maxX, y: bounds.minY) // 左下 → 锚右上
            default: anchor = NormalizedPoint(x: bounds.minX, y: bounds.minY) // 右下 → 锚左上
            }
            updated.start = anchor
            updated.end = dragged
        case .text, .number, .freehand:
            break
        }
        return updated
    }

    // MARK: - 绘制

    private func swiftUIColor(_ annotation: CaptureAnnotation) -> Color {
        let c = annotation.color
        return Color(.sRGB, red: c.red, green: c.green, blue: c.blue, opacity: c.alpha)
    }

    private func draw(_ annotation: CaptureAnnotation, context: inout GraphicsContext, imageRect: CGRect) {
        let start = screenPoint(annotation.start, in: imageRect)
        let end = screenPoint(annotation.end, in: imageRect)
        let color = swiftUIColor(annotation)
        var path = Path()
        switch annotation.kind {
        case .rectangle:
            path.addRect(CGRect(
                x: min(start.x, end.x),
                y: min(start.y, end.y),
                width: abs(end.x - start.x),
                height: abs(end.y - start.y)
            ))
        case .ellipse:
            path.addEllipse(in: CGRect(
                x: min(start.x, end.x),
                y: min(start.y, end.y),
                width: abs(end.x - start.x),
                height: abs(end.y - start.y)
            ))
        case .arrow:
            path.move(to: start)
            path.addLine(to: end)
            let angle = atan2(end.y - start.y, end.x - start.x)
            let length = max(12, hypot(end.x - start.x, end.y - start.y) * 0.12)
            let spread = CGFloat.pi / 7
            path.move(to: end)
            path.addLine(to: CGPoint(
                x: end.x - length * cos(angle - spread),
                y: end.y - length * sin(angle - spread)
            ))
            path.move(to: end)
            path.addLine(to: CGPoint(
                x: end.x - length * cos(angle + spread),
                y: end.y - length * sin(angle + spread)
            ))
        case .text:
            context.draw(
                Text(annotation.label ?? Loc.s("anno.text.default"))
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(color),
                at: start,
                anchor: .topLeading
            )
        case .number:
            let circle = CGRect(x: start.x - 14, y: start.y - 14, width: 28, height: 28)
            context.fill(Path(ellipseIn: circle), with: .color(color))
            context.draw(
                Text(annotation.label ?? "1").font(.system(size: 15, weight: .bold)).foregroundStyle(.white),
                at: start,
                anchor: .center
            )
        case .mosaic:
            let rect = CGRect(
                x: min(start.x, end.x),
                y: min(start.y, end.y),
                width: abs(end.x - start.x),
                height: abs(end.y - start.y)
            )
            context.fill(Path(rect), with: .color(.gray.opacity(0.55)))
        case .translation:
            // 与导出渲染同一套字号（图像像素），按预览缩放比换算到屏幕。
            let rect = CGRect(
                x: min(start.x, end.x), y: min(start.y, end.y),
                width: abs(end.x - start.x), height: abs(end.y - start.y)
            )
            let scale = imageSize.width > 0 ? imageRect.width / imageSize.width : 1
            let fill = RGBAColor(hex: annotation.fillColorHex ?? "#FFFFFF")
            context.fill(
                Path(roundedRect: rect, cornerRadius: 3 * scale),
                with: .color(Color(.sRGB, red: fill.red, green: fill.green, blue: fill.blue, opacity: fill.alpha))
            )
            let fontSize = CGFloat(annotation.fontSize ?? 12) * scale
            let inset = TranslationBlockLayout.padding * scale
            context.draw(
                Text(annotation.label ?? "")
                    .font(.custom("PingFang SC", size: fontSize))
                    .foregroundStyle(color),
                in: rect.insetBy(dx: inset, dy: inset)
            )
        case .freehand:
            if let pts = annotation.points, let head = pts.first {
                path.move(to: screenPoint(head, in: imageRect))
                for p in pts.dropFirst() { path.addLine(to: screenPoint(p, in: imageRect)) }
            }
        }
        if annotation.kind == .rectangle || annotation.kind == .ellipse
            || annotation.kind == .arrow || annotation.kind == .freehand {
            context.stroke(
                path,
                with: .color(color),
                style: StrokeStyle(lineWidth: 3 * annotation.resolvedLineWidth, lineCap: .round, lineJoin: .round)
            )
        }
    }

    private func drawSelection(_ annotation: CaptureAnnotation, context: inout GraphicsContext, imageRect: CGRect, showHandles: Bool) {
        let bounds = annotation.normalizedBounds
        let rect = CGRect(
            x: screenPoint(NormalizedPoint(x: bounds.minX, y: bounds.minY), in: imageRect).x,
            y: screenPoint(NormalizedPoint(x: bounds.minX, y: bounds.minY), in: imageRect).y,
            width: bounds.width * imageRect.width,
            height: bounds.height * imageRect.height
        ).insetBy(dx: -4, dy: -4)
        context.stroke(
            Path(rect),
            with: .color(.accentColor),
            style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])
        )
        guard showHandles else { return }
        for (_, point) in handlePoints(for: annotation, imageRect: imageRect) {
            let handleRect = CGRect(
                x: point.x - handleSize / 2,
                y: point.y - handleSize / 2,
                width: handleSize,
                height: handleSize
            )
            context.fill(Path(ellipseIn: handleRect), with: .color(.white))
            context.stroke(Path(ellipseIn: handleRect), with: .color(.accentColor), lineWidth: 1.5)
        }
    }

    // MARK: - 坐标

    private var labelForCurrentTool: String? {
        switch tool {
        case .text: textLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Loc.s("anno.text.default") : textLabel
        case .number: String(nextNumber)
        default: nil
        }
    }

    private func aspectFitRect(content: CGSize, container: CGSize) -> CGRect {
        guard content.width > 0, content.height > 0 else { return .zero }
        let scale = min(container.width / content.width, container.height / content.height)
        let size = CGSize(width: content.width * scale, height: content.height * scale)
        return CGRect(
            x: (container.width - size.width) / 2,
            y: (container.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
    }

    private func normalized(_ point: CGPoint, in rect: CGRect) -> NormalizedPoint {
        NormalizedPoint(
            x: (point.x - rect.minX) / rect.width,
            y: (point.y - rect.minY) / rect.height
        )
    }

    private func screenPoint(_ point: NormalizedPoint, in rect: CGRect) -> CGPoint {
        CGPoint(
            x: rect.minX + CGFloat(point.x) * rect.width,
            y: rect.minY + CGFloat(point.y) * rect.height
        )
    }

    private func clamped(_ point: CGPoint, to rect: CGRect) -> CGPoint {
        CGPoint(
            x: min(rect.maxX, max(rect.minX, point.x)),
            y: min(rect.maxY, max(rect.minY, point.y))
        )
    }
}
