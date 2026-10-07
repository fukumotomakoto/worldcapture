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

@Test func layoutCapsFontAtTheOriginalLineHeightEvenWhenTheBoxIsTaller() {
    // 两行英文的框，译成一行短中文：字号应贴近原行高，而不是撑满两行高。
    let box = CGRect(x: 0, y: 0, width: 600, height: 60)
    let layout = TranslationBlockLayout.layout(text: "设置已保存", in: box, lineHeight: 26, imageSize: CGSize(width: 900, height: 400))
    #expect(layout.fontSize == 26 * TranslationBlockLayout.fontScaleOfLineHeight)
    #expect(layout.rect.contains(box) && layout.rect.height < box.height + 26)
}

@Test func singleLineBlockKeepsTheOriginalFontSizeAndGrowsItsBoxIfNeeded() {
    // 一行英文的框只有 20px 高（比字号略小）：译文字号仍应等于行高，框按需要略微加高，而不是把字缩到六成。
    let box = CGRect(x: 0, y: 0, width: 300, height: 20)
    let layout = TranslationBlockLayout.layout(text: "没有相机。", in: box, lineHeight: 20, imageSize: CGSize(width: 900, height: 400))
    #expect(layout.fontSize == 20)
    #expect(layout.rect.height >= 20 && layout.rect.height <= 40)
}

@Test func layoutGrowsTheBoxDownwardInsteadOfShrinkingBelowTheFloor() {
    let box = CGRect(x: 0, y: 100, width: 120, height: 20)
    let long = "这是一段稍长的译文，原文框放不下，应把框向下加高。"
    let layout = TranslationBlockLayout.layout(text: long, in: box, lineHeight: 20, imageSize: CGSize(width: 900, height: 400))
    #expect(layout.rect.height > box.height + 10)
    #expect(abs(layout.rect.minY - (box.minY - 20 * 0.14)) < 0.01)
    #expect(layout.fontSize >= 20 * TranslationBlockLayout.fontScaleOfLineHeight * TranslationBlockLayout.minimumFontScale - 0.6)
}

@Test func layoutNeverGrowsPastTheImageBottom() {
    let box = CGRect(x: 0, y: 380, width: 100, height: 16)
    let layout = TranslationBlockLayout.layout(text: "一二三四五六七八九十一二三四五六七八九十一二三四五六七八九十", in: box, lineHeight: 16, imageSize: CGSize(width: 900, height: 400))
    #expect(layout.rect.maxY <= 400)
}

@Test func headingSlightlyLargerThanBodyIsKeptSeparate() {
    let blocks = TextBlockGrouper.group([
        line("Motion", x: 10, y: 10, w: 90, h: 26),
        line("Reduce animation in streaming responses.", x: 10, y: 44, w: 400, h: 18),
    ])
    #expect(blocks.count == 2)
}

@Test func groupedBlockRemembersItsMedianEstimatedFontSize() {
    let blocks = TextBlockGrouper.group([
        line("a", x: 10, y: 10, w: 100, h: 20),
        line("b", x: 10, y: 34, w: 100, h: 22),
        line("c", x: 10, y: 60, w: 100, h: 20),
    ])
    #expect(blocks.count == 1)
    // 三行 → 用行距：(60 - 10) / 2 = 25 → 25 / 1.35
    #expect(abs(blocks[0].lineHeight - 25 / TextBlockGrouper.lineHeightOverFontSize) < 0.01)
}

@Test func wrappedLastLineWithASmallerBoxStaysInItsParagraph() {
    let blocks = TextBlockGrouper.group([
        line("Allow the app to capture windows and regions. You can revoke this permission at", x: 10, y: 10, w: 1000, h: 40),
        line("any time in System Settings.", x: 10, y: 50, w: 300, h: 28),
    ])
    #expect(blocks.count == 1)
}

@Test func descenderLettersDoNotInflateTheEstimatedFontSize() {
    // 同一字号：「General」无降部，框 15 高；「Appearance」有 p，框 19 高 → 估出的字号应接近。
    let general = TextBlock.estimatedFontSize(boxHeight: 15, text: "General")
    let appearance = TextBlock.estimatedFontSize(boxHeight: 19, text: "Appearance")
    #expect(abs(general - appearance) / general < 0.05)
    #expect(abs(TextBlock.estimatedFontSize(boxHeight: 18, text: "设置") - 20) < 0.01)
}

@Test func aSubheadingSlightlyLargerThanItsBodyStaysSeparate() {
    // 「Screen Recording」34pt 接 26pt 说明：字号比 0.76，在 ±25% 之内，但首行明显更大 → 分开。
    let blocks = TextBlockGrouper.group([
        line("Screen Recording", x: 10, y: 10, w: 260, h: 32),
        line("Allow the app to capture windows and regions.", x: 10, y: 50, w: 600, h: 25),
        line("You can revoke this permission at any time.", x: 10, y: 80, w: 560, h: 25),
    ])
    #expect(blocks.count == 2)
    #expect(blocks[1].lines.count == 2)
}

@Test func paragraphFontSizeComesFromLinePitchNotBoxHeight() {
    // 段落里的框高被行距撑到 40，但行距 36 → 字号 ≈ 36 / 1.35 ≈ 26.7，而不是按框高估的 42。
    let blocks = TextBlockGrouper.group([
        line("Everything is processed on this Mac and nothing", x: 10, y: 10, w: 900, h: 40),
        line("ever leaves your device, no account required.", x: 10, y: 46, w: 860, h: 40),
    ])
    #expect(blocks.count == 1)
    #expect(abs(blocks[0].lineHeight - 36 / TextBlockGrouper.lineHeightOverFontSize) < 0.01)
}

@Test func shortHeadingFollowedByALongLineIsSplitEvenWhenHeightsLookSimilar() {
    let blocks = TextBlockGrouper.group([
        line("Screen Recording", x: 10, y: 10, w: 240, h: 33),
        line("Allow the app to capture windows and regions on this Mac.", x: 10, y: 50, w: 980, h: 40),
    ])
    #expect(blocks.count == 2)
}
