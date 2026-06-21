import AppKit
import CoreGraphics

public enum AnnotationRenderer {
    public static func render(
        image: CGImage,
        annotations: [CaptureAnnotation],
        color: NSColor = .systemRed
    ) -> CGImage? {
        guard let context = CGContext(
            data: nil,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        let canvas = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.draw(image, in: canvas)
        context.setStrokeColor(color.cgColor)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setLineWidth(max(3, CGFloat(min(image.width, image.height)) * 0.006))

        for annotation in annotations {
            let start = point(annotation.start, image: image)
            let end = point(annotation.end, image: image)
            switch annotation.kind {
            case .rectangle:
                context.stroke(CGRect(
                    x: min(start.x, end.x),
                    y: min(start.y, end.y),
                    width: abs(end.x - start.x),
                    height: abs(end.y - start.y)
                ))
            case .arrow:
                drawArrow(in: context, start: start, end: end)
            }
        }
        return context.makeImage()
    }

    private static func point(_ point: NormalizedPoint, image: CGImage) -> CGPoint {
        CGPoint(
            x: CGFloat(point.x) * CGFloat(image.width),
            y: (1 - CGFloat(point.y)) * CGFloat(image.height)
        )
    }

    private static func drawArrow(in context: CGContext, start: CGPoint, end: CGPoint) {
        context.move(to: start)
        context.addLine(to: end)
        context.strokePath()

        let angle = atan2(end.y - start.y, end.x - start.x)
        let length = max(14, hypot(end.x - start.x, end.y - start.y) * 0.12)
        let spread = CGFloat.pi / 7
        context.move(to: end)
        context.addLine(to: CGPoint(
            x: end.x - length * cos(angle - spread),
            y: end.y - length * sin(angle - spread)
        ))
        context.move(to: end)
        context.addLine(to: CGPoint(
            x: end.x - length * cos(angle + spread),
            y: end.y - length * sin(angle + spread)
        ))
        context.strokePath()
    }
}

