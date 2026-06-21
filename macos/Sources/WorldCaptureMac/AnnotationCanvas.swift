import CaptureKit
import SwiftUI

struct AnnotationCanvas: View {
    let imageSize: CGSize
    @Binding var annotations: [CaptureAnnotation]
    let tool: AnnotationKind
    let textLabel: String
    let nextNumber: Int

    @State private var draft: CaptureAnnotation?

    var body: some View {
        GeometryReader { proxy in
            let imageRect = aspectFitRect(content: imageSize, container: proxy.size)
            Canvas { context, _ in
                for annotation in annotations {
                    draw(annotation, context: &context, imageRect: imageRect)
                }
                if let draft {
                    draw(draft, context: &context, imageRect: imageRect)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard imageRect.contains(value.startLocation) else { return }
                        draft = CaptureAnnotation(
                            kind: tool,
                            start: normalized(value.startLocation, in: imageRect),
                            end: normalized(clamped(value.location, to: imageRect), in: imageRect),
                            label: labelForCurrentTool
                        )
                    }
                    .onEnded { _ in
                        if let draft { annotations.append(draft) }
                        draft = nil
                    }
            )
        }
    }

    private func draw(_ annotation: CaptureAnnotation, context: inout GraphicsContext, imageRect: CGRect) {
        let start = screenPoint(annotation.start, in: imageRect)
        let end = screenPoint(annotation.end, in: imageRect)
        var path = Path()
        switch annotation.kind {
        case .rectangle:
            path.addRect(CGRect(
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
                Text(annotation.label ?? "说明")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.red),
                at: start,
                anchor: .topLeading
            )
        case .number:
            let circle = CGRect(x: start.x - 14, y: start.y - 14, width: 28, height: 28)
            context.fill(Path(ellipseIn: circle), with: .color(.red))
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
        }
        if annotation.kind == .rectangle || annotation.kind == .arrow {
            context.stroke(
                path,
                with: .color(.red),
                style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
            )
        }
    }

    private var labelForCurrentTool: String? {
        switch tool {
        case .text: textLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "说明" : textLabel
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
