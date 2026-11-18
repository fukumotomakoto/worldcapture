using WorldCapture.Core.Imaging;
using WorldCapture.Core.Translation;

namespace WorldCapture.Core.Tests;

/// <summary>
/// 逐条移植自 macos/Tests/CaptureKitTests/TextBlockGrouperTests.swift（测试名保持对应）。
/// 那个文件里关于译文块排版的几条在 TranslationBlockLayoutTests.cs。
/// </summary>
public class TextBlockGrouperTests
{
    private static TextLine Line(string text, double x, double y, double w, double h = 20) =>
        new(text, new RectD(x, y, w, h));

    [Fact]
    public void ConsecutiveLinesOfAParagraphMergeIntoOneBlock()
    {
        var blocks = TextBlockGrouper.Group([
            Line("The quick brown fox", 10, 10, 200),
            Line("jumps over the", 10, 34, 150),
            Line("lazy dog.", 10, 58, 90),
        ]);
        Assert.Single(blocks);
        Assert.Equal("The quick brown fox jumps over the lazy dog.", blocks[0].Text);
        Assert.Equal(new RectD(10, 10, 200, 68), blocks[0].Rect);
    }

    [Fact]
    public void ALargeVerticalGapStartsANewBlock()
    {
        var blocks = TextBlockGrouper.Group([
            Line("Title", 10, 10, 80),
            Line("Body starts here", 10, 80, 160),
        ]);
        Assert.Equal(2, blocks.Count);
    }

    [Fact]
    public void SideBySideColumnsStaySeparate()
    {
        var blocks = TextBlockGrouper.Group([
            Line("Left column one", 10, 10, 120),
            Line("Right column one", 400, 10, 120),
            Line("Left column two", 10, 34, 120),
            Line("Right column two", 400, 34, 120),
        ]);
        Assert.Equal(2, blocks.Count);
        Assert.Equal(["Left column one", "Left column two"], blocks[0].Lines);
        Assert.Equal(["Right column one", "Right column two"], blocks[1].Lines);
    }

    [Fact]
    public void HeadingWithMuchLargerTypeIsNotMergedIntoBody()
    {
        var blocks = TextBlockGrouper.Group([
            Line("BIG HEADING", 10, 10, 300, 48),
            Line("small body text", 10, 62, 200, 16),
        ]);
        Assert.Equal(2, blocks.Count);
    }

    [Fact]
    public void CjkLinesJoinWithoutSpacesButLatinLinesJoinWithASpace()
    {
        Assert.Equal("这是第一行，这是第二行。", new TextBlock(RectD.Zero, ["这是第一行，", "这是第二行。"]).Text);
        Assert.Equal("first line second line", new TextBlock(RectD.Zero, ["first line", "second line"]).Text);
        Assert.Equal("版本 v2 已发布", new TextBlock(RectD.Zero, ["版本 v2", "已发布"]).Text);
    }

    [Fact]
    public void HeadingSlightlyLargerThanBodyIsKeptSeparate()
    {
        var blocks = TextBlockGrouper.Group([
            Line("Motion", 10, 10, 90, 26),
            Line("Reduce animation in streaming responses.", 10, 44, 400, 18),
        ]);
        Assert.Equal(2, blocks.Count);
    }

    [Fact]
    public void GroupedBlockRemembersItsMedianEstimatedFontSize()
    {
        var blocks = TextBlockGrouper.Group([
            Line("a", 10, 10, 100, 20),
            Line("b", 10, 34, 100, 22),
            Line("c", 10, 60, 100, 20),
        ]);
        Assert.Single(blocks);
        // 三行 → 用行距：(60 - 10) / 2 = 25 → 25 / 1.35
        Assert.Equal(25 / TextBlockGrouper.LineHeightOverFontSize, blocks[0].LineHeight, 0.01);
    }

    [Fact]
    public void WrappedLastLineWithASmallerBoxStaysInItsParagraph()
    {
        var blocks = TextBlockGrouper.Group([
            Line("Allow the app to capture windows and regions. You can revoke this permission at", 10, 10, 1000, 40),
            Line("any time in System Settings.", 10, 50, 300, 28),
        ]);
        Assert.Single(blocks);
    }

    [Fact]
    public void DescenderLettersDoNotInflateTheEstimatedFontSize()
    {
        // 同一字号：「General」无降部，框 15 高；「Appearance」有 p，框 19 高 → 估出的字号应接近。
        var general = TextBlock.EstimatedFontSize(15, "General");
        var appearance = TextBlock.EstimatedFontSize(19, "Appearance");
        Assert.True(Math.Abs(general - appearance) / general < 0.05);
        Assert.Equal(20, TextBlock.EstimatedFontSize(18, "设置"), 0.01);
    }

    [Fact]
    public void ASubheadingSlightlyLargerThanItsBodyStaysSeparate()
    {
        // 「Screen Recording」34pt 接 26pt 说明：字号比 0.76，在 ±25% 之内，但首行明显更大 → 分开。
        var blocks = TextBlockGrouper.Group([
            Line("Screen Recording", 10, 10, 260, 32),
            Line("Allow the app to capture windows and regions.", 10, 50, 600, 25),
            Line("You can revoke this permission at any time.", 10, 80, 560, 25),
        ]);
        Assert.Equal(2, blocks.Count);
        Assert.Equal(2, blocks[1].Lines.Count);
    }

    [Fact]
    public void ParagraphFontSizeComesFromLinePitchNotBoxHeight()
    {
        // 段落里的框高被行距撑到 40，但行距 36 → 字号 ≈ 36 / 1.35 ≈ 26.7，而不是按框高估的 42。
        var blocks = TextBlockGrouper.Group([
            Line("Everything is processed on this Mac and nothing", 10, 10, 900, 40),
            Line("ever leaves your device, no account required.", 10, 46, 860, 40),
        ]);
        Assert.Single(blocks);
        Assert.Equal(36 / TextBlockGrouper.LineHeightOverFontSize, blocks[0].LineHeight, 0.01);
    }

    [Fact]
    public void ShortHeadingFollowedByALongLineIsSplitEvenWhenHeightsLookSimilar()
    {
        var blocks = TextBlockGrouper.Group([
            Line("Screen Recording", 10, 10, 240, 33),
            Line("Allow the app to capture windows and regions on this Mac.", 10, 50, 980, 40),
        ]);
        Assert.Equal(2, blocks.Count);
    }

    // —— 以下为 Windows 侧补充（Swift 侧没有对应用例）——

    [Fact]
    public void LinesGivenOutOfOrderAreGroupedInReadingOrder()
    {
        var blocks = TextBlockGrouper.Group([
            Line("lazy dog.", 10, 58, 90),
            Line("Right column", 400, 10, 120),
            Line("jumps over the", 10, 34, 150),
            Line("   ", 10, 200, 50),
            Line("The quick brown fox", 10, 10, 200),
        ]);
        Assert.Equal(2, blocks.Count);
        Assert.Equal("The quick brown fox jumps over the lazy dog.", blocks[0].Text);
        Assert.Equal("Right column", blocks[1].Text);
    }

    [Fact]
    public void SingleLineBlockUsesItsEstimatedFontSizeAsLineHeight()
    {
        var blocks = TextBlockGrouper.Group([Line("设置", 10, 10, 60, 18)]);
        Assert.Equal(20, blocks[0].LineHeight, 0.01);
        // 不经分组直接构造时，行高默认取 框高 ÷ 行数。
        Assert.Equal(30, new TextBlock(new RectD(0, 0, 100, 60), ["a", "b"]).LineHeight);
    }
}
