using WorldCapture.Core.Annotations;
using WorldCapture.Core.Imaging;

namespace WorldCapture.Core.Tests;

/// <summary>逐条移植自 macos/Tests/CaptureKitTests/CaptureAnnotationTests.swift（测试名保持对应）。</summary>
public class CaptureAnnotationTests
{
    private static NormalizedPoint P(double x, double y) => new(x, y);

    private static CaptureAnnotation A(AnnotationKind kind, double x0, double y0, double x1, double y1) =>
        new() { Kind = kind, Start = P(x0, y0), End = P(x1, y1) };

    private static CaptureAnnotation RoundTrip(CaptureAnnotation a) =>
        AnnotationJson.Deserialize(AnnotationJson.Serialize(a))!;

    [Fact]
    public void AnnotationsRoundTripThroughJSON()
    {
        var a = A(AnnotationKind.Arrow, 0.1, 0.2, 0.8, 0.9) with { Id = Guid.Parse("B4347D55-A690-4B3C-990F-4CFCC45956F3") };
        Assert.Equal(a, RoundTrip(a));
    }

    [Fact]
    public void NormalizedPointsClampToImageBounds() => Assert.Equal(P(0, 1), P(-1, 2));

    [Fact]
    public void TextAnnotationPersistsItsLabel()
    {
        var decoded = RoundTrip(A(AnnotationKind.Text, 0.2, 0.3, 0.2, 0.3) with { Label = "重点" });
        Assert.Equal("重点", decoded.Label);
        Assert.Equal(AnnotationKind.Text, decoded.Kind);
    }

    [Fact]
    public void HitTestSelectsRectangleNearItsEdge()
    {
        var rect = A(AnnotationKind.Rectangle, 0.2, 0.2, 0.6, 0.6);
        Assert.True(rect.HitTest(P(0.21, 0.59), 0.02));
        Assert.False(rect.HitTest(P(0.9, 0.9), 0.02));
    }

    [Fact]
    public void HitTestSelectsArrowAlongItsLine()
    {
        var arrow = A(AnnotationKind.Arrow, 0.1, 0.1, 0.9, 0.9);
        Assert.True(arrow.HitTest(P(0.5, 0.5), 0.02));
        Assert.False(arrow.HitTest(P(0.1, 0.9), 0.02));
    }

    [Fact]
    public void HitTestSelectsEllipseWithinBounds()
    {
        var ellipse = A(AnnotationKind.Ellipse, 0.2, 0.2, 0.6, 0.6);
        Assert.True(ellipse.HitTest(P(0.4, 0.4), 0.02));
        Assert.False(ellipse.HitTest(P(0.9, 0.9), 0.02));
    }

    [Fact]
    public void EllipseRoundTripsThroughJSON()
    {
        var ellipse = A(AnnotationKind.Ellipse, 0.1, 0.2, 0.7, 0.5);
        Assert.Equal(ellipse, RoundTrip(ellipse));
    }

    [Fact]
    public void TranslatingAnnotationKeepsEndpointsInBounds()
    {
        var a = A(AnnotationKind.Rectangle, 0.8, 0.8, 0.95, 0.95);
        var moved = a.Translated(0.3, 0.3);
        Assert.Equal(P(1, 1), moved.Start);
        Assert.Equal(P(1, 1), moved.End);
        Assert.Equal(a.Id, moved.Id);
    }

    [Fact]
    public void ParsesSixDigitHexColor()
    {
        var c = RgbaColor.FromHex("#007AFF");
        Assert.InRange(c.Red, 0, 0.01);
        Assert.InRange(c.Green, 122.0 / 255 - 0.01, 122.0 / 255 + 0.01);
        Assert.InRange(c.Blue, 0.99, 1);
        Assert.Equal(1, c.Alpha);
    }

    [Fact]
    public void InvalidHexFallsBackToDefaultRed()
    {
        var c = RgbaColor.FromHex("not-a-color");
        Assert.InRange(c.Red, 0.99, 1);
        Assert.InRange(c.Green, 0.221, 0.241);
    }

    [Fact]
    public void AnnotationColorRoundTripsAndDefaults()
    {
        var decoded = RoundTrip(A(AnnotationKind.Rectangle, 0, 0, 1, 1) with { ColorHex = "#34C759" });
        Assert.Equal("#34C759", decoded.ColorHex);
        Assert.Equal("#34C759", decoded.ResolvedColorHex);

        var plain = A(AnnotationKind.Arrow, 0, 0, 1, 1);
        Assert.Null(plain.ColorHex);
        Assert.Equal(CaptureAnnotation.DefaultColorHex, plain.ResolvedColorHex);
    }

    [Fact]
    public void DecodesLegacyAnnotationWithoutColorKey()
    {
        const string legacy = """{"id":"B4347D55-A690-4B3C-990F-4CFCC45956F3","kind":"text","start":{"x":0.1,"y":0.2},"end":{"x":0.3,"y":0.4}}""";
        var decoded = AnnotationJson.Deserialize(legacy)!;
        Assert.Null(decoded.ColorHex);
        Assert.Equal(CaptureAnnotation.DefaultColorHex, decoded.ResolvedColorHex);
    }

    [Fact]
    public void LineWidthRoundTripsAndDefaultsToOne()
    {
        var decoded = RoundTrip(A(AnnotationKind.Rectangle, 0, 0, 1, 1) with { LineWidth = 1.8 });
        Assert.Equal(1.8, decoded.LineWidth);
        Assert.Equal(1.8, decoded.ResolvedLineWidth);

        var plain = A(AnnotationKind.Arrow, 0, 0, 1, 1);
        Assert.Null(plain.LineWidth);
        Assert.Equal(1, plain.ResolvedLineWidth);
    }

    [Fact]
    public void FreehandBoundsCoverAllPathPoints()
    {
        var pen = A(AnnotationKind.Freehand, 0.2, 0.5, 0.7, 0.4) with { Points = [P(0.2, 0.5), P(0.5, 0.3), P(0.7, 0.4)] };
        var b = pen.NormalizedBounds;
        Assert.Equal(0.2, b.MinX, 4);
        Assert.Equal(0.3, b.MinY, 4);
        Assert.Equal(0.7, b.MaxX, 4);
        Assert.Equal(0.5, b.MaxY, 4);
    }

    [Fact]
    public void FreehandHitTestFollowsThePath()
    {
        var pen = A(AnnotationKind.Freehand, 0.1, 0.1, 0.9, 0.1) with { Points = [P(0.1, 0.1), P(0.9, 0.1)] };
        Assert.True(pen.HitTest(P(0.5, 0.105), 0.02));
        Assert.False(pen.HitTest(P(0.5, 0.4), 0.02));
    }

    [Fact]
    public void FreehandTranslatesEveryPoint()
    {
        var pen = A(AnnotationKind.Freehand, 0.2, 0.2, 0.4, 0.4) with { Points = [P(0.2, 0.2), P(0.4, 0.4)] };
        var pts = pen.Translated(0.1, 0.1).Points!;
        Assert.Equal(2, pts.Count);
        Assert.Equal(0.3, pts[0].X, 4); Assert.Equal(0.3, pts[0].Y, 4);
        Assert.Equal(0.5, pts[1].X, 4); Assert.Equal(0.5, pts[1].Y, 4);
    }

    [Fact]
    public void FreehandRoundTripsThroughJSON()
    {
        var pen = A(AnnotationKind.Freehand, 0.2, 0.2, 0.4, 0.4) with { Points = [P(0.2, 0.2), P(0.4, 0.4)] };
        Assert.Equal(pen, RoundTrip(pen));
    }

    [Fact]
    public void RemapScalesAnnotationIntoCropRegion()
    {
        var m = A(AnnotationKind.Rectangle, 0.6, 0.6, 0.9, 0.9).RemappedToCrop(new NormalizedRect(0.5, 0.5, 0.5, 0.5))!;
        Assert.Equal(0.2, m.Start.X, 4); Assert.Equal(0.2, m.Start.Y, 4);
        Assert.Equal(0.8, m.End.X, 4); Assert.Equal(0.8, m.End.Y, 4);
    }

    [Fact]
    public void RemapDropsAnnotationFullyOutsideCropRegion() =>
        Assert.Null(A(AnnotationKind.Rectangle, 0, 0, 0.2, 0.2).RemappedToCrop(new NormalizedRect(0.5, 0.5, 0.5, 0.5)));

    // —— 以下为 Windows 侧补充：跨平台互通 ——

    /// <summary>macOS JSONEncoder 的真实输出形状（UUID 大写、可选字段缺省）必须能读进来，写出的字段名也要一致。</summary>
    [Fact]
    public void ReadsAndWritesTheMacOSJsonShape()
    {
        const string fromMac = """{"id":"B4347D55-A690-4B3C-990F-4CFCC45956F3","kind":"freehand","start":{"x":0.2,"y":0.2},"end":{"x":0.4,"y":0.4},"points":[{"x":0.2,"y":0.2},{"x":0.4,"y":0.4}],"colorHex":"#34C759","lineWidth":1.5}""";
        var a = AnnotationJson.Deserialize(fromMac)!;
        Assert.Equal(AnnotationKind.Freehand, a.Kind);
        Assert.Equal(2, a.Points!.Count);
        Assert.Equal(1.5, a.LineWidth);

        var json = AnnotationJson.Serialize(a);
        Assert.Contains("\"kind\":\"freehand\"", json);
        Assert.Contains("\"colorHex\":\"#34C759\"", json);
        Assert.DoesNotContain("label", json);          // null 字段不写出
        Assert.DoesNotContain("resolved", json, StringComparison.OrdinalIgnoreCase);
    }
}

/// <summary>马赛克：移植自 Swift 的 mosaicSamplesTheRegionItCovers / mosaicBlockScalesWithImage，并补不透明性。</summary>
public class MosaicTests
{
    private static RgbaImage TopWhiteBottomBlack(int w = 200, int h = 200)
    {
        var img = new RgbaImage(w, h);
        img.Fill(0, 0, w, h / 2, 255, 255, 255);   // 左上角原点：上半白
        img.Fill(0, h / 2, w, h / 2, 0, 0, 0);     // 下半黑
        return img;
    }

    [Fact]
    public void MosaicSamplesTheRegionItCovers()
    {
        var img = TopWhiteBottomBlack();
        Mosaic.Apply(img, new NormalizedPoint(0.1, 0.05), new NormalizedPoint(0.9, 0.35));
        Assert.True(img.GetPixel(100, 40).R > 200);   // 框里仍是白（没取到镜像区域的黑）
        Assert.True(img.GetPixel(100, 150).R < 50);   // 框外不受影响
    }

    [Fact]
    public void MosaicBlockScalesWithImage()
    {
        Assert.Equal(16, Mosaic.BlockSize(300, 200));
        Assert.Equal(28, Mosaic.BlockSize(1920, 1280));
        Assert.Equal(48, Mosaic.BlockSize(3840, 2160));
    }

    /// <summary>打码后每一格是单一的不透明平均色——细节（文字笔画）不能留下任何痕迹。</summary>
    [Fact]
    public void MosaicCellsAreOpaqueUniformAverages()
    {
        var img = new RgbaImage(160, 160);
        img.Fill(0, 0, 160, 160, 255, 255, 255, 128);          // 半透明白底
        img.Fill(4, 4, 2, 8, 0, 0, 0);                          // 左上格里一道「笔画」
        Mosaic.Apply(img, new NormalizedPoint(0, 0), new NormalizedPoint(0.1, 0.1)); // 16×16 = 一格
        var first = img.GetPixel(0, 0);
        for (var y = 0; y < 16; y++)
        for (var x = 0; x < 16; x++)
            Assert.Equal(first, img.GetPixel(x, y));
        Assert.Equal(255, first.A);
        Assert.InRange(first.R, 230, 254);                      // 笔画被平均掉，只剩略灰
        Assert.Equal((byte)255, img.GetPixel(20, 20).R);        // 格外原样
    }

    [Fact]
    public void TinyOrEmptyRegionIsIgnored()
    {
        var img = TopWhiteBottomBlack();
        Assert.Null(Mosaic.Apply(img, new NormalizedPoint(0.5, 0.5), new NormalizedPoint(0.5, 0.5)));
    }
}
