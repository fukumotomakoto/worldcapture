import AppKit
import CoreGraphics
import CoreText

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

        for annotation in annotations where annotation.kind == .mosaic {
            drawMosaic(image: image, annotation: annotation, in: context)
        }

        context.setLineCap(.round)
        context.setLineJoin(.round)
        let baseLineWidth = max(3, CGFloat(min(image.width, image.height)) * 0.006)

        for annotation in annotations {
            let start = point(annotation.start, image: image)
            let end = point(annotation.end, image: image)
            let strokeColor = annotation.colorHex.map { RGBAColor(hex: $0).cgColor } ?? color.cgColor
            context.setStrokeColor(strokeColor)
            context.setLineWidth(baseLineWidth * CGFloat(annotation.resolvedLineWidth))
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
            case .text:
                drawText(
                    annotation.label?.isEmpty == false ? annotation.label! : "说明",
                    at: start,
                    in: context,
                    image: image,
                    color: strokeColor
                )
            case .number:
                drawNumber(annotation.label ?? "1", at: start, in: context, image: image, color: strokeColor)
            case .mosaic:
                break
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

    private static func drawMosaic(
        image: CGImage,
        annotation: CaptureAnnotation,
        in context: CGContext
    ) {
        let start = point(annotation.start, image: image)
        let end = point(annotation.end, image: image)
        let rect = CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        ).integral.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard rect.width >= 2, rect.height >= 2,
              let crop = image.cropping(to: rect) else { return }

        let blockSize: CGFloat = 14
        let lowWidth = max(1, Int((rect.width / blockSize).rounded(.up)))
        let lowHeight = max(1, Int((rect.height / blockSize).rounded(.up)))
        guard let lowContext = CGContext(
            data: nil,
            width: lowWidth,
            height: lowHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return }
        lowContext.interpolationQuality = .low
        lowContext.draw(crop, in: CGRect(x: 0, y: 0, width: lowWidth, height: lowHeight))
        guard let pixelated = lowContext.makeImage() else { return }
        context.saveGState()
        context.interpolationQuality = .none
        context.draw(pixelated, in: rect)
        context.restoreGState()
    }

    private static func drawText(
        _ text: String,
        at point: CGPoint,
        in context: CGContext,
        image: CGImage,
        color: CGColor
    ) {
        let fontSize = max(18, CGFloat(min(image.width, image.height)) * 0.04)
        let font = CTFontCreateWithName("Helvetica-Bold" as CFString, fontSize, nil)
        let attributed = NSAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: color,
            .strokeColor: NSColor.white.cgColor,
            .strokeWidth: -2.5,
        ])
        let line = CTLineCreateWithAttributedString(attributed)
        // `point` marks the top-leading corner (matching the editor preview). CTLine draws from
        // the baseline, so drop it by the font ascent to align the rendered text with the preview.
        context.textPosition = CGPoint(x: point.x, y: point.y - CTFontGetAscent(font))
        CTLineDraw(line, context)
    }

    private static func drawNumber(
        _ text: String,
        at point: CGPoint,
        in context: CGContext,
        image: CGImage,
        color: CGColor
    ) {
        let radius = max(14, CGFloat(min(image.width, image.height)) * 0.027)
        context.setFillColor(color)
        context.fillEllipse(in: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))

        let font = CTFontCreateWithName("Helvetica-Bold" as CFString, radius * 1.25, nil)
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: NSColor.white.cgColor,
        ]))
        let bounds = CTLineGetBoundsWithOptions(line, [.useGlyphPathBounds])
        context.textPosition = CGPoint(
            x: point.x - bounds.width / 2 - bounds.minX,
            y: point.y - bounds.height / 2 - bounds.minY
        )
        CTLineDraw(line, context)
    }
}
