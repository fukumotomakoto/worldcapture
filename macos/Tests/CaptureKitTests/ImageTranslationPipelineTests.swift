import CoreGraphics
import CoreText
import Foundation
import Testing
@testable import CaptureKit

/// 造一张「浅底两行段落 + 深色横幅白字」的图，走完 OCR 取框 → 合并段落 → 译文块 → 渲染 的整条管线
/// （只差真正的翻译会话，用固定译文代替）。设置 WC_DEBUG_OUT 时把结果 PNG 写出来供肉眼检查。
private func makeSampleImage() -> CGImage {
    let width = 900, height = 420
    let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.setFillColor(CGColor(red: 0.96, green: 0.96, blue: 0.94, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.setFillColor(CGColor(red: 0.12, green: 0.14, blue: 0.2, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: 120))

    func draw(_ text: String, x: CGFloat, y: CGFloat, size: CGFloat, white: Bool) {
        let font = CTFontCreateWithName("Helvetica" as CFString, size, nil)
        let color = white ? CGColor(red: 1, green: 1, blue: 1, alpha: 1) : CGColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1)
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color]))
        context.textPosition = CGPoint(x: x, y: y)
        CTLineDraw(line, context)
    }
    // CG 坐标 y 向上：段落在上半部（y 大），横幅在底部。
    draw("The quick brown fox jumps over", x: 40, y: 330, size: 40, white: false)
    draw("the lazy dog near the river.", x: 40, y: 275, size: 40, white: false)
    draw("Settings saved successfully", x: 40, y: 45, size: 44, white: true)
    return context.makeImage()!
}

@Test func imageTranslationPipelineProducesOverlayBlocks() async throws {
    let image = makeSampleImage()
    let result = try await TextRecognizer.recognize(cgImage: image, languages: ["en-US"])
    #expect(result.textLines.count >= 3)
    #expect(result.textLines.allSatisfy { $0.box.width > 0 && $0.box.height > 0 })

    let blocks = TextBlockGrouper.group(result.textLines)
    #expect(blocks.count == 2, "两行段落应合成一块，横幅另成一块，实际 \(blocks.map(\.lines))")
    guard let paragraph = blocks.first, let banner = blocks.last else { return }
    #expect(paragraph.lines.count == 2)
    #expect(paragraph.text.lowercased().contains("fox jumps over the lazy dog"))

    let fakeTranslations = ["敏捷的棕色狐狸跳过了河边那只懒狗。", "设置已成功保存"]
    let width = Double(image.width), height = Double(image.height)
    let annotations = zip(blocks, fakeTranslations).map { block, text in
        let background = TranslationBlockLayout.backgroundColor(around: block.rect, in: image)
        let foreground = TranslationBlockLayout.textColor(on: background)
        return CaptureAnnotation(
            kind: .translation,
            start: NormalizedPoint(x: block.rect.minX / width, y: block.rect.minY / height),
            end: NormalizedPoint(x: block.rect.maxX / width, y: block.rect.maxY / height),
            label: text,
            colorHex: foreground.hexString,
            fillColorHex: background.hexString,
            fontSize: Double(TranslationBlockLayout.fittingFontSize(for: text, in: block.rect))
        )
    }
    // 浅底段落 → 浅底黑字；深色横幅 → 深底白字。
    #expect(RGBAColor(hex: annotations[0].fillColorHex!).relativeLuminance > 0.7)
    #expect(RGBAColor(hex: annotations[0].colorHex!).relativeLuminance < 0.2)
    #expect(RGBAColor(hex: annotations[1].fillColorHex!).relativeLuminance < 0.15)
    #expect(RGBAColor(hex: annotations[1].colorHex!).relativeLuminance > 0.8)
    #expect(annotations.allSatisfy { ($0.fontSize ?? 0) > TranslationBlockLayout.minimumFontSize })

    let rendered = try #require(AnnotationRenderer.render(image: image, annotations: annotations))
    #expect(rendered.width == image.width && rendered.height == image.height)

    if let out = ProcessInfo.processInfo.environment["WC_DEBUG_OUT"] {
        try PNGEncoder.encode(image).write(to: URL(fileURLWithPath: out + "/translate-before.png"))
        try PNGEncoder.encode(rendered).write(to: URL(fileURLWithPath: out + "/translate-after.png"))
    }
}
