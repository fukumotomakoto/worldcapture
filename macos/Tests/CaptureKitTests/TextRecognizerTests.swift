import CoreGraphics
import CoreText
import Foundation
import Testing
@testable import CaptureKit

/// 生成一张白底黑字的位图，供 OCR 识别。
private func makeTextImage(_ text: String, width: Int = 640, height: Int = 160) -> CGImage {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))

    let font = CTFontCreateWithName("Helvetica" as CFString, 48, nil)
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: CGColor(red: 0, green: 0, blue: 0, alpha: 1),
    ]
    let attributed = NSAttributedString(string: text, attributes: attributes)
    let line = CTLineCreateWithAttributedString(attributed)
    context.textPosition = CGPoint(x: 24, y: height / 2 - 20)
    CTLineDraw(line, context)

    return context.makeImage()!
}

@Test func recognizesPlainEnglishText() async throws {
    let image = makeTextImage("Hello World")
    let result = try await TextRecognizer.recognize(cgImage: image, languages: ["en-US"])
    let joined = result.text.lowercased()
    #expect(joined.contains("hello"))
    #expect(joined.contains("world"))
    #expect(!result.isEmpty)
}

@Test func returnsEmptyResultForBlankImage() async throws {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let context = CGContext(
        data: nil, width: 200, height: 200, bitsPerComponent: 8, bytesPerRow: 0,
        space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 200, height: 200))
    let blank = context.makeImage()!

    let result = try await TextRecognizer.recognize(cgImage: blank)
    #expect(result.isEmpty)
    #expect(result.text.isEmpty)
}
