using WorldCapture.Core.Imaging;

namespace WorldCapture.Core.Tests;

/// <summary>
/// 逐条移植自 macos/Tests/CaptureKitTests/ContentRegionDetectorTests.swift（测试名保持对应）。
/// Swift 版用 CoreGraphics 画测试图（左下角原点）；这里直接按同样的数值填像素，行号已换算成左上角原点。
/// </summary>
public class ContentRegionDetectorTests
{
    /// <summary>
    /// 左右两侧为固定色块，中间列填入按 phase 逐行平移的灰度渐变（模拟真实滚动内容——每行都在变，且变化区域连续）。
    /// </summary>
    private static RgbaImage Framed(int width, int height, int midX0, int midX1, int phase)
    {
        var image = new RgbaImage(width, height);
        image.Fill(0, 0, width, height, 204, 204, 204);   // 0.8 的固定背景
        for (var cgY = 0; cgY < height; cgY++)
        {
            var v = (byte)((cgY * 3 + phase * 11) % 256);
            if (midX1 > midX0) image.Fill(midX0, height - 1 - cgY, midX1 - midX0, 1, v, v, v);
        }
        return image;
    }

    /// <summary>顶部/底部为固定背景带，中间整宽为随 phase 逐行变化的滚动内容带。</summary>
    private static RgbaImage RowBanded(int width, int height, int topFixed, int bottomFixed, int phase)
    {
        var image = new RgbaImage(width, height);
        image.Fill(0, 0, width, height, 191, 191, 191);   // 0.75 的固定背景
        for (var row = topFixed; row < height - bottomFixed; row++)
        {
            var v = (byte)((row + phase * 7) % 200 + 20);
            image.Fill(0, row, width, 1, v, v, v);
        }
        return image;
    }

    [Fact]
    public void DetectsScrollingMiddleColumn()
    {
        const int w = 240, h = 400;
        var a = Framed(w, h, 90, 150, 0);
        var b = Framed(w, h, 90, 150, 8);
        var rect = ContentRegionDetector.ChangedRect(a, b);
        Assert.NotNull(rect);
        // 变化区域应集中在中间列（左右固定不变）。
        Assert.InRange(rect.Value.X, 70, 100);
        Assert.InRange(rect.Value.MaxX, 140, 170);
        // 纵向应覆盖大部分高度。
        Assert.True(rect.Value.Height >= h * 0.6);
    }

    [Fact]
    public void ReturnsNilWhenWholeFrameChanges()
    {
        const int w = 200, h = 300;
        // 整帧都是变化的条纹 → 没有可裁的固定部分 → 回退 null。
        Assert.Null(ContentRegionDetector.ChangedRect(Framed(w, h, 0, w, 0), Framed(w, h, 0, w, 8)));
    }

    [Fact]
    public void ReturnsNilWhenIdentical()
    {
        var a = Framed(200, 300, 80, 120, 4);
        Assert.Null(ContentRegionDetector.ChangedRect(a, a));
    }

    [Fact]
    public void IsStableTrueForIdenticalFrames()
    {
        var a = Framed(200, 300, 80, 120, 4);
        Assert.True(ContentRegionDetector.IsStable(a, a));
    }

    [Fact]
    public void IsStableFalseWhileScrolling()
    {
        // 中间列在滚动（逐行平移）→ 大量像素在变 → 判为未稳定，应继续等待。
        Assert.False(ContentRegionDetector.IsStable(Framed(240, 400, 90, 150, 0), Framed(240, 400, 90, 150, 8)));
    }

    [Fact]
    public void ScrollingRowBandFindsMiddleBand()
    {
        const int w = 200, h = 400, top = 60, bottom = 50;
        var band = ContentRegionDetector.ScrollingRowBand(RowBanded(w, h, top, bottom, 0), RowBanded(w, h, top, bottom, 9));
        Assert.NotNull(band);
        Assert.InRange(band.Value.Y0, 40, 80);      // ≈ 固定顶带高
        Assert.InRange(band.Value.Y1, 330, 360);    // ≈ height − 固定底带（350）
    }

    [Fact]
    public void ScrollingRowBandNilWhenWholeHeightChanges()
    {
        // 无固定带（整高都在变）→ 回退整帧。
        Assert.Null(ContentRegionDetector.ScrollingRowBand(RowBanded(200, 400, 0, 0, 0), RowBanded(200, 400, 0, 0, 9)));
    }

    [Fact]
    public void ScrollingColumnRangeFindsMiddleColumn()
    {
        var range = ContentRegionDetector.ScrollingColumnRange(Framed(240, 400, 90, 150, 0), Framed(240, 400, 90, 150, 8));
        Assert.NotNull(range);
        Assert.InRange(range.Value.X0, 70, 100);    // ≈ 中列左界（左右固定被排除）
        Assert.InRange(range.Value.X1, 140, 170);   // ≈ 中列右界
    }

    [Fact]
    public void ScrollingColumnRangeNilWhenFullWidthScrolls()
    {
        // 整宽都在滚 → 回退，让拼接器用默认左右排除即可。
        Assert.Null(ContentRegionDetector.ScrollingColumnRange(Framed(200, 300, 0, 200, 0), Framed(200, 300, 0, 200, 8)));
    }

    // —— 以下为 Windows 侧补充（Swift 侧没有对应用例）——

    [Fact]
    public void ExactBoundsOfTheScrollingRegionAreReported()
    {
        // 小图不抽样（步长 1），边界应当精确：列 [90,150)、行 [60,350)。
        const int w = 240, h = 400;
        RgbaImage Frame(int phase)
        {
            var image = RowBanded(w, h, 60, 50, phase);
            image.Fill(0, 0, 90, h, 191, 191, 191);
            image.Fill(150, 0, w - 150, h, 191, 191, 191);
            return image;
        }
        var a = Frame(0);
        var b = Frame(9);
        Assert.Equal(new PixelRect(90, 60, 60, 290), ContentRegionDetector.ChangedRect(a, b));
        Assert.Equal((90, 150), ContentRegionDetector.ScrollingColumnRange(a, b));
    }

    [Fact]
    public void FramesOfDifferentSizesAreNeverComparable()
    {
        var a = Framed(200, 300, 80, 120, 0);
        var b = Framed(200, 301, 80, 120, 0);
        Assert.Null(ContentRegionDetector.ChangedRect(a, b));
        Assert.Null(ContentRegionDetector.ScrollingRowBand(a, b));
        Assert.Null(ContentRegionDetector.ScrollingColumnRange(a, b));
        Assert.False(ContentRegionDetector.IsStable(a, b));
    }

    [Fact]
    public void ASmallBlinkingSpotDoesNotCountAsUnstable()
    {
        // 300×300 里一个 4×4 的光标在闪：变化占比远低于 0.6% → 仍算稳定，也不算滚动区域。
        var a = Framed(300, 300, 0, 0, 0);
        var b = a.Clone();
        b.Fill(100, 100, 4, 4, 0, 0, 0);
        Assert.True(ContentRegionDetector.IsStable(a, b));
        Assert.Null(ContentRegionDetector.ChangedRect(a, b));
    }
}
