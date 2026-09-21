import CoreGraphics
import Testing
@testable import CaptureKit

private func line(_ text: String, x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat = 20) -> TextRecognizer.Line {
    TextRecognizer.Line(text: text, box: CGRect(x: x, y: y, width: w, height: h))
}

@Test func consecutiveLinesOfAParagraphMergeIntoOneBlock() {
    let blocks = TextBlockGrouper.group([
        line("The quick brown fox", x: 10, y: 10, w: 200),
        line("jumps over the", x: 10, y: 34, w: 150),
        line("lazy dog.", x: 10, y: 58, w: 90),
    ])
    #expect(blocks.count == 1)
    #expect(blocks[0].text == "The quick brown fox jumps over the lazy dog.")
    #expect(blocks[0].rect == CGRect(x: 10, y: 10, width: 200, height: 68))
}

@Test func aLargeVerticalGapStartsANewBlock() {
    let blocks = TextBlockGrouper.group([
        line("Title", x: 10, y: 10, w: 80),
        line("Body starts here", x: 10, y: 80, w: 160),
    ])
    #expect(blocks.count == 2)
}

@Test func sideBySideColumnsStaySeparate() {
    let blocks = TextBlockGrouper.group([
        line("Left column one", x: 10, y: 10, w: 120),
        line("Right column one", x: 400, y: 10, w: 120),
        line("Left column two", x: 10, y: 34, w: 120),
        line("Right column two", x: 400, y: 34, w: 120),
    ])
    #expect(blocks.count == 2)
    #expect(blocks[0].lines == ["Left column one", "Left column two"])
    #expect(blocks[1].lines == ["Right column one", "Right column two"])
}

@Test func headingWithMuchLargerTypeIsNotMergedIntoBody() {
    let blocks = TextBlockGrouper.group([
        line("BIG HEADING", x: 10, y: 10, w: 300, h: 48),
        line("small body text", x: 10, y: 62, w: 200, h: 16),
    ])
    #expect(blocks.count == 2)
}

@Test func cjkLinesJoinWithoutSpacesButLatinLinesJoinWithASpace() {
    let cjk = TextBlock(rect: .zero, lines: ["这是第一行，", "这是第二行。"])
    #expect(cjk.text == "这是第一行，这是第二行。")
    let latin = TextBlock(rect: .zero, lines: ["first line", "second line"])
    #expect(latin.text == "first line second line")
    let mixed = TextBlock(rect: .zero, lines: ["版本 v2", "已发布"])
    #expect(mixed.text == "版本 v2 已发布")
}

@Test func fittingFontSizeShrinksForLongerTextInTheSameBox() {
    let box = CGRect(x: 0, y: 0, width: 200, height: 40)
    let short = TranslationBlockLayout.fittingFontSize(for: "Hi", in: box)
    let long = TranslationBlockLayout.fittingFontSize(for: "A considerably longer sentence that must wrap onto several lines", in: box)
    #expect(short > long)
    #expect(long >= TranslationBlockLayout.minimumFontSize)
    #expect(short <= box.height)
}

@Test func textColorContrastsWithBackground() {
    #expect(TranslationBlockLayout.textColor(on: RGBAColor(red: 1, green: 1, blue: 1)).relativeLuminance < 0.2)
    #expect(TranslationBlockLayout.textColor(on: RGBAColor(red: 0.1, green: 0.1, blue: 0.12)).relativeLuminance > 0.8)
    #expect(RGBAColor(red: 1, green: 0, blue: 0).hexString == "#FF0000")
}
