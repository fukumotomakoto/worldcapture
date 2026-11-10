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
            case .ellipse:
                context.strokeEllipse(in: CGRect(
                    x: min(start.x, end.x),
                    y: min(start.y, end.y),
                    width: abs(end.x - start.x),
                    height: abs(end.y - start.y)
                ))
            case .arrow:
                drawArrow(in: context, start: start, end: end)
            case .freehand:
                guard let pts = annotation.points, pts.count >= 2 else {
                    if let only = annotation.points?.first {
                        let p = point(only, image: image)
                        context.fillEllipse(in: CGRect(x: p.x - 1, y: p.y - 1, width: 2, height: 2))
                    }
                    break
                }
                context.move(to: point(pts[0], image: image))
                for p in pts.dropFirst() { context.addLine(to: point(p, image: image)) }
                context.strokePath()
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
            case .translation:
                drawTranslationBlock(annotation, start: start, end: end, in: context)
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
        guard let mosaic = mosaicTile(image: image, start: annotation.start, end: annotation.end) else { return }
        // tile.rect 是左上角原点（CGImage 的裁切坐标）；画进 CGContext 要换成左下角原点。
        let target = CGRect(
            x: mosaic.rect.minX,
            y: CGFloat(image.height) - mosaic.rect.maxY,
            width: mosaic.rect.width,
            height: mosaic.rect.height
        )
        context.saveGState()
        context.interpolationQuality = .none
        context.draw(mosaic.tile, in: target)
        context.restoreGState()
    }

    /// 马赛克块边长（图像像素）：随图片尺寸放大。
    ///
    /// 固定 14 px 在 Retina 截图上只有半个字高（正文字高约 28~32 px），大字号标题仍认得出。
    /// 取短边的 1/45、至少 16 px：1280 高的截图约 28 px，4K 约 48 px —— 一块盖住约一个字。
    public static func mosaicBlockSize(imageWidth: Int, imageHeight: Int) -> Int {
        max(16, min(imageWidth, imageHeight) / 45)
    }

    /// 马赛克的像素化小图：编辑器预览与导出共用，保证所见即所得。
    ///
    /// - Returns: `tile` 是低分辨率小图（每个像素 = 一个马赛克块，按最近邻放大到 `rect` 即可）；
    ///   `rect` 是马赛克在原图中的位置，**左上角原点**、图像像素。
    ///
    /// 之前的实现把左下角原点的矩形直接交给 `CGImage.cropping(to:)`（它是左上角原点），
    /// 结果从上下镜像的另一块区域取样——框选区被盖上了别处的像素。
    public static func mosaicTile(
        image: CGImage,
        start: NormalizedPoint,
        end: NormalizedPoint
    ) -> (tile: CGImage, rect: CGRect)? {
        let w = CGFloat(image.width), h = CGFloat(image.height)
        let rect = CGRect(
            x: CGFloat(min(start.x, end.x)) * w,
            y: CGFloat(min(start.y, end.y)) * h,
            width: CGFloat(abs(end.x - start.x)) * w,
            height: CGFloat(abs(end.y - start.y)) * h
        ).integral.intersection(CGRect(x: 0, y: 0, width: w, height: h))
        guard rect.width >= 2, rect.height >= 2, let crop = image.cropping(to: rect) else { return nil }

        let block = CGFloat(mosaicBlockSize(imageWidth: image.width, imageHeight: image.height))
        let lowWidth = max(1, Int((rect.width / block).rounded(.up)))
        let lowHeight = max(1, Int((rect.height / block).rounded(.up)))
        guard let lowContext = CGContext(
            data: nil,
            width: lowWidth,
            height: lowHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        // 高质量缩小 = 每块取整块的平均色，不会因为采样点恰好落在笔画上而留下可辨认的痕迹。
        lowContext.interpolationQuality = .high
        lowContext.draw(crop, in: CGRect(x: 0, y: 0, width: lowWidth, height: lowHeight))
        guard let tile = lowContext.makeImage() else { return nil }
        return (tile, rect)
    }

    /// 译文块：圆角矩形盖底色，译文按预先算好的字号排在矩形内、垂直居中。
    private static func drawTranslationBlock(
        _ annotation: CaptureAnnotation,
        start: CGPoint,
        end: CGPoint,
        in context: CGContext
    ) {
        let rect = CGRect(
            x: min(start.x, end.x), y: min(start.y, end.y),
            width: abs(end.x - start.x), height: abs(end.y - start.y)
        )
        guard rect.width > 2, rect.height > 2 else { return }
        let fill = RGBAColor(hex: annotation.fillColorHex ?? "#FFFFFF").cgColor
        let textColor = annotation.color.cgColor
        let text = annotation.label ?? ""
        let fontSize = CGFloat(annotation.fontSize ?? TranslationBlockLayout.fittingFontSize(for: text, in: rect))

        context.saveGState()
        let path = CGPath(roundedRect: rect, cornerWidth: 3, cornerHeight: 3, transform: nil)
        context.addPath(path)
        context.setFillColor(fill)
        context.fillPath()

        let padding = TranslationBlockLayout.padding
        let textWidth = max(1, rect.width - padding * 2)
        // 排版框给足高度（CoreText 装不下的行会整行丢弃，不是裁掉）；真正的裁切靠下面的 clip。
        let needed = TranslationBlockLayout.layoutHeight(for: text, fontSize: fontSize, width: textWidth) + 2
        // CoreText 从框顶往下排；CG 坐标 y 向上，所以「顶」是 maxY。垂直居中：上下各留一半余量。
        let frameRect = CGRect(
            x: rect.minX + padding,
            y: rect.midY - needed / 2,
            width: textWidth + 1,
            height: needed
        )
        let single = TranslationBlockLayout.fitsOnOneLine(text, fontSize: fontSize, width: textWidth)
        let attributed = TranslationBlockLayout.attributed(text, fontSize: fontSize, color: textColor, singleLine: single)
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), CGPath(rect: frameRect, transform: nil), nil)
        context.addPath(path)
        context.clip()
        CTFrameDraw(frame, context)
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
