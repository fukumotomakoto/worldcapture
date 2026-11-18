using WorldCapture.Core.Annotations;
using WorldCapture.Core.Imaging;
using WorldCapture.Core.Translation;

namespace WorldCapture.Core.Tests;

/// <summary>
/// 排版规则的测试，移植自 macos/Tests/CaptureKitTests/TextBlockGrouperTests.swift 里 TranslationBlockLayout 的那几条
/// （测试名保持对应）和 ImageTranslationPipelineTests.swift 里取色的断言。
/// <para>
/// macOS 那边用 CoreText 实测字宽；这里没有排版引擎，用 <see cref="FakeMeasurer"/> 代替（全角字 1 em、其余 0.5 em）。
/// 所以这些测试验的是「借宽 → 加高 → 缩字」的规则，<b>不是</b>与 CoreText 的数值一致；
/// 真实字宽要等 Windows 端的 DirectWrite 实现接上以后在实机上验。
/// </para>
/// </summary>
public class TranslationBlockLayoutTests
{
    /// <summary>确定性的假测量器：全角字宽 1 em，其余 0.5 em；装不下就按字换行。</summary>
    private sealed class FakeMeasurer : ITextMeasurer
    {
        private static double Advance(char c) => c >= 0x2E80 ? 1.0 : 0.5;

        public double SingleLineWidth(string text, double fontSize) => text.Sum(Advance) * fontSize;

        public double WrappedHeight(string text, double fontSize, double width, double lineHeight)
        {
            var lines = 1;
            var x = 0.0;
            foreach (var c in text)
            {
                var w = Advance(c) * fontSize;
                if (x > 0 && x + w > width) { lines++; x = 0; }
                x += w;
            }
            return lines * lineHeight;
        }
    }

    private static readonly FakeMeasurer Measurer = new();
    private static readonly SizeD Image900 = new(900, 400);

    [Fact]
    public void FittingFontSizeShrinksForLongerTextInTheSameBox()
    {
        var box = new RectD(0, 0, 200, 40);
        var small = TranslationBlockLayout.FittingFontSize(Measurer, "Hi", box);
        var large = TranslationBlockLayout.FittingFontSize(Measurer, "A considerably longer sentence that must wrap onto several lines", box);
        Assert.True(small > large);
        Assert.True(large >= TranslationBlockLayout.MinimumFontSize);
        Assert.True(small <= box.Height);
    }

    [Fact]
    public void TextColorContrastsWithBackground()
    {
        Assert.True(TranslationBlockLayout.TextColor(new RgbaColor(1, 1, 1)).RelativeLuminance < 0.2);
        Assert.True(TranslationBlockLayout.TextColor(new RgbaColor(0.1, 0.1, 0.12)).RelativeLuminance > 0.8);
        Assert.Equal("#FF0000", new RgbaColor(1, 0, 0).HexString);
    }

    [Fact]
    public void LayoutCapsFontAtTheOriginalLineHeightEvenWhenTheBoxIsTaller()
    {
        // 两行英文的框，译成一行短中文：字号应贴近原行高，而不是撑满两行高。
        var box = new RectD(0, 0, 600, 60);
        var layout = TranslationBlockLayout.Layout(Measurer, "设置已保存", box, 26, Image900);
        Assert.Equal(26 * TranslationBlockLayout.FontScaleOfLineHeight, layout.FontSize);
        Assert.True(layout.Rect.Contains(box) && layout.Rect.Height < box.Height + 26);
    }

    [Fact]
    public void SingleLineBlockKeepsTheOriginalFontSizeAndGrowsItsBoxIfNeeded()
    {
        // 一行英文的框只有 20px 高（比字号略小）：译文字号仍应等于行高，框按需要略微加高，而不是把字缩到六成。
        var box = new RectD(0, 0, 300, 20);
        var layout = TranslationBlockLayout.Layout(Measurer, "没有相机。", box, 20, Image900);
        Assert.Equal(20, layout.FontSize);
        Assert.InRange(layout.Rect.Height, 20, 40);
    }

    [Fact]
    public void LayoutGrowsTheBoxDownwardInsteadOfShrinkingBelowTheFloor()
    {
        var box = new RectD(0, 100, 120, 20);
        const string text = "这是一段稍长的译文，原文框放不下，应把框向下加高。";
        var layout = TranslationBlockLayout.Layout(Measurer, text, box, 20, Image900);
        Assert.True(layout.Rect.Height > box.Height + 10);
        Assert.Equal(box.MinY - 20 * 0.14, layout.Rect.MinY, 0.01);
        Assert.True(layout.FontSize >= 20 * TranslationBlockLayout.FontScaleOfLineHeight * TranslationBlockLayout.MinimumFontScale - 0.6);
    }

    [Fact]
    public void LayoutNeverGrowsPastTheImageBottom()
    {
        var box = new RectD(0, 380, 100, 16);
        var layout = TranslationBlockLayout.Layout(Measurer, "一二三四五六七八九十一二三四五六七八九十一二三四五六七八九十", box, 16, Image900);
        Assert.True(layout.Rect.MaxY <= 400);
    }

    [Fact]
    public void LongTranslationBorrowsFreeSpaceToTheRightBeforeWrapping()
    {
        // 侧栏标签：右边是一大片空白 → 译文拉成单行，不向下压到下一项。
        var label = new RectD(40, 200, 180, 26);
        var below = new RectD(40, 260, 120, 26);
        var image = new SizeD(1600, 1000);
        var space = TranslationBlockLayout.FreeSpace(label, [label, below], image);
        Assert.True(space.MaxWidth > 1000);
        Assert.Equal(260 - 6 - 200, space.MaxHeight, 0.01);
        var layout = TranslationBlockLayout.Layout(Measurer, "プライバシーとセキュリティ", label, 26, image, space.MaxWidth, space.MaxHeight);
        Assert.True(layout.Rect.Width > label.Width);
        Assert.True(layout.Rect.MaxY < 260);
        Assert.Equal(26, layout.FontSize);
    }

    [Fact]
    public void FreeSpaceStopsAtTheNeighbourOnTheRightAndBelow()
    {
        var rect = new RectD(0, 0, 100, 20);
        var right = new RectD(300, 5, 50, 20);
        var below = new RectD(10, 80, 50, 20);
        var space = TranslationBlockLayout.FreeSpace(rect, [right, below], Image900);
        Assert.Equal(294, space.MaxWidth, 0.01);
        Assert.Equal(74, space.MaxHeight, 0.01);
    }

    /// <summary>
    /// 对应 imageTranslationPipelineProducesOverlayBlocks 里取色的断言（浅底段落 → 浅底黑字；深色横幅 → 深底白字）。
    /// OCR 和渲染那两段依赖 Vision / CoreGraphics，不在 Core 里，这里只验取色。
    /// </summary>
    [Fact]
    public void BackgroundAndTextColorsFollowTheSurroundingPixels()
    {
        // 900×420：上面 300 行浅底，下面 120 行深色横幅；各放一块深/白「文字」。
        var image = new RgbaImage(900, 420);
        image.Fill(0, 0, 900, 300, 245, 245, 240);
        image.Fill(0, 300, 900, 120, 31, 36, 51);
        var paragraph = new RectD(40, 50, 560, 95);
        var banner = new RectD(40, 335, 520, 44);
        image.Fill(40, 50, 560, 95, 26, 26, 26);
        image.Fill(40, 335, 520, 44, 255, 255, 255);

        var light = TranslationBlockLayout.BackgroundColor(image, paragraph);
        var dark = TranslationBlockLayout.BackgroundColor(image, banner);
        Assert.Equal("#F5F5F0", light.HexString);
        Assert.Equal("#1F2433", dark.HexString);
        Assert.True(RgbaColor.FromHex(light.HexString).RelativeLuminance > 0.7);
        Assert.True(TranslationBlockLayout.TextColor(light).RelativeLuminance < 0.2);
        Assert.True(RgbaColor.FromHex(dark.HexString).RelativeLuminance < 0.15);
        Assert.True(TranslationBlockLayout.TextColor(dark).RelativeLuminance > 0.8);
    }

    // —— 以下为 Windows 侧补充（Swift 侧没有对应用例）——

    [Fact]
    public void BackgroundColorUsesTheMedianSoStrayPixelsInTheRingAreIgnored()
    {
        var image = new RgbaImage(100, 60);
        image.Fill(0, 0, 100, 60, 200, 210, 220);
        image.Fill(20, 18, 30, 3, 255, 0, 0);   // 环上混进一小段红色边框
        Assert.Equal("#C8D2DC", TranslationBlockLayout.BackgroundColor(image, new RectD(20, 20, 60, 20)).HexString);
    }

    [Fact]
    public void BackgroundColorFallsBackToWhiteWhenThereIsNothingToSample()
    {
        var image = new RgbaImage(10, 10);
        Assert.Equal(new RgbaColor(1, 1, 1), TranslationBlockLayout.BackgroundColor(image, new RectD(50, 50, 20, 20)));
    }

    [Fact]
    public void HexStringAppendsAlphaOnlyWhenTranslucent()
    {
        Assert.Equal("#FF3B30", RgbaColor.FromHex("#FF3B30").HexString);
        Assert.Equal("#00000080", new RgbaColor(0, 0, 0, 0.5).HexString);
        Assert.Equal("#FFFFFF", new RgbaColor(2, 1, 1).HexString);
    }

    [Fact]
    public void LineHeightIsCompactForOneLineAndLooserForParagraphs()
    {
        Assert.Equal(20 * 1.08, TranslationBlockLayout.LineHeight(Measurer, "设置", 20, 200), 6);
        Assert.Equal(20 * 1.3, TranslationBlockLayout.LineHeight(Measurer, "设置已成功保存到本机", 20, 100), 6);
    }
}
