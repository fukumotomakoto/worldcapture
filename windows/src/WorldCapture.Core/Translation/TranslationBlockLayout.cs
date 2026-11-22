using WorldCapture.Core.Annotations;
using WorldCapture.Core.Imaging;

namespace WorldCapture.Core.Translation;

/// <summary>
/// 文字测量。macOS 版直接调 CoreText；Core 不能依赖任何平台的排版引擎，所以抽成接口，
/// <b>待 Windows 端实现</b>（DirectWrite / Win2D 的 <c>CanvasTextLayout</c>）。
/// 实现必须和最终画译文的那套排版用同一个字体、同一种换行方式（按词换行），否则算出的字号和画出来的对不上。
/// </summary>
public interface ITextMeasurer
{
    /// <summary>不换行时文字的排印宽度（像素）。</summary>
    double SingleLineWidth(string text, double fontSize);

    /// <summary>在 <paramref name="width"/> 宽度内按词换行后所需的总高度；每行行高固定为 <paramref name="lineHeight"/>。</summary>
    double WrappedHeight(string text, double fontSize, double width, double lineHeight);
}

/// <summary>
/// 「译文块」的排版与着色：把译文塞进原文所在的矩形里。移植自 macOS <c>TranslationBlockLayout.swift</c>。
/// <para>
/// ① 采样矩形外圈像素的中位色当底色（盖住原文时和周围融为一体）；② 按底色明度选黑/白字；
/// ③ 算出「能装进矩形的字号与矩形」。渲染器和画布共用这里算出的结果，导出图和预览才一致。
/// </para>
/// </summary>
public static class TranslationBlockLayout
{
    /// <summary>文字与矩形边缘的留白（像素）。</summary>
    public const double Padding = 2;
    public const double MinimumFontSize = 6;

    /// <summary>译文字号相对原文行高的比例。1.0 时译文看起来与原文同大。</summary>
    public const double FontScaleOfLineHeight = 1.0;
    /// <summary>缩到基准的这个比例以下就不再缩字，改为把框向下加高。</summary>
    public const double MinimumFontScale = 0.6;
    /// <summary>框最多加高到原高的这个倍数（再高会盖住下面的内容）。</summary>
    public const double MaximumGrowth = 2.5;

    /// <summary>单行译文的行高倍数（紧凑，让它装进原文那一行的框）。</summary>
    public const double SingleLineHeightMultiple = 1.08;
    /// <summary>多行段落的行高倍数（可读性）。</summary>
    public const double ParagraphLineHeightMultiple = 1.3;

    /// <summary>排版结果：译文块最终的矩形和字号。</summary>
    /// <param name="Rect">译文块矩形。</param>
    /// <param name="FontSize">字号。</param>
    /// <param name="IsComplete">
    /// 译文是否在矩形里完整可见。缩到字号下限仍装不下时为 false——这时盖上去会截断译文、又遮住原文，
    /// 调用方应保留原文并提供完整译文的查看入口（与 macOS 版语义一致）。
    /// </param>
    /// <param name="RequiredHeight">需要的高度（含留白）。</param>
    public readonly record struct BlockLayout(RectD Rect, double FontSize, bool IsComplete = true, double RequiredHeight = 0);

    // —— 字号 ——

    /// <summary>
    /// 一个块周围可用的空间：向右能扩到最近的「同一行高范围内、位于右侧」的块（或图像右边）；
    /// 向下能扩到最近的「横向有重叠、位于下方」的块（或图像底边）。留 6px 间隙。
    /// </summary>
    public static (double MaxWidth, double MaxHeight) FreeSpace(RectD rect, IEnumerable<RectD> others, SizeD imageSize)
    {
        const double gap = 6;
        var rightLimit = imageSize.Width;
        var bottomLimit = imageSize.Height;
        foreach (var other in others)
        {
            if (other == rect) continue;
            var verticalOverlap = Math.Min(rect.MaxY, other.MaxY) - Math.Max(rect.MinY, other.MinY);
            if (verticalOverlap > 0 && other.MinX >= rect.MaxX - 1)
                rightLimit = Math.Min(rightLimit, other.MinX - gap);
            var horizontalOverlap = Math.Min(rect.MaxX, other.MaxX) - Math.Max(rect.MinX, other.MinX);
            if (horizontalOverlap > 0 && other.MinY >= rect.MaxY - 1)
                bottomLimit = Math.Min(bottomLimit, other.MinY - gap);
        }
        return (Math.Max(rect.Width, rightLimit - rect.MinX), Math.Max(rect.Height, bottomLimit - rect.MinY));
    }

    /// <summary>
    /// 统一字号的排版：字号由原文行高决定（不由框高决定）。译文装不下时按顺序：
    /// ① 向右借用空白（到 <paramref name="maxWidth"/>）② 向下加高（到 <paramref name="maxHeight"/>、原高 2.5 倍或图像底边）
    /// ③ 逐步缩字到下限。<paramref name="maxWidth"/>/<paramref name="maxHeight"/> 由 <see cref="FreeSpace"/> 给出，不传则只受图像边界限制。
    /// </summary>
    public static BlockLayout Layout(ITextMeasurer measurer, string text, RectD original, double lineHeight, SizeD imageSize,
                                     double? maxWidth = null, double? maxHeight = null)
    {
        // OCR 的框贴着字形，原文的上伸部/降部/字距会从译文块边缘漏出来：按字号外扩一圈再盖。
        var rect = original
            .Inset(-lineHeight * 0.12, -lineHeight * 0.14)
            .Intersection(new RectD(0, 0, imageSize.Width, imageSize.Height));
        var baseSize = Math.Max(MinimumFontSize, lineHeight * FontScaleOfLineHeight);
        var floor = Math.Max(MinimumFontSize, baseSize * MinimumFontScale);

        // ① 向右：单行放得下就拉成单行；放不下就用满可借的宽度减少换行。
        var widthLimit = Math.Min(imageSize.Width - rect.MinX, Math.Max(rect.Width, maxWidth ?? rect.Width));
        var boxWidth = rect.Width;
        var singleLine = measurer.SingleLineWidth(text, baseSize) * 1.02 + 2 + Padding * 2;
        if (singleLine > boxWidth) boxWidth = Math.Min(widthLimit, singleLine);
        var textWidth = Math.Max(1, boxWidth - Padding * 2);

        // ② 向下，③ 缩字。
        var growthCap = Math.Min(rect.Height * MaximumGrowth, imageSize.Height - rect.MinY);
        var heightLimit = Math.Max(rect.Height, Math.Min(growthCap, maxHeight ?? growthCap));
        var size = baseSize;
        var needed = LayoutHeight(measurer, text, size, textWidth) + Padding * 2;
        while (needed > heightLimit && size - 0.5 >= floor)
        {
            size -= 0.5;
            needed = LayoutHeight(measurer, text, size, textWidth) + Padding * 2;
        }
        var height = Math.Min(heightLimit, Math.Max(rect.Height, needed));
        return new BlockLayout(new RectD(rect.MinX, rect.MinY, boxWidth, height), size, needed <= heightLimit + 0.5, needed);
    }

    /// <summary>能让文字换行后装进 <paramref name="rect"/> 的最大字号；上限为矩形高度（单行即整块高）或 <paramref name="maxFontSize"/>。</summary>
    public static double FittingFontSize(ITextMeasurer measurer, string text, RectD rect, double? maxFontSize = null)
    {
        var availableWidth = Math.Max(1, rect.Width - Padding * 2);
        var availableHeight = Math.Max(1, rect.Height - Padding * 2);
        var low = MinimumFontSize;
        var high = Math.Max(MinimumFontSize, Math.Min(availableHeight, maxFontSize ?? availableHeight));
        if (!Fits(low)) return low;
        // 二分：精确到 0.5 就够了。
        while (high - low > 0.5)
        {
            var mid = (low + high) / 2;
            if (Fits(mid)) low = mid; else high = mid;
        }
        return low;

        bool Fits(double size) => LayoutHeight(measurer, text, size, availableWidth) <= availableHeight;
    }

    /// <summary>这段文字在给定宽度、字号下是否一行放得下。渲染器与排版都用它决定行高倍数，两边才一致。</summary>
    public static bool FitsOnOneLine(ITextMeasurer measurer, string text, double fontSize, double width) =>
        // 留 2% 余量：实际排版比排印宽度略宽时会意外换行，第二行装不下就整段消失。
        measurer.SingleLineWidth(text, fontSize) * 1.02 + 1 <= width;

    /// <summary>这段文字该用的行高（像素）：一行放得下用紧凑行高，否则用段落行高。</summary>
    public static double LineHeight(ITextMeasurer measurer, string text, double fontSize, double width) =>
        fontSize * (FitsOnOneLine(measurer, text, fontSize, width) ? SingleLineHeightMultiple : ParagraphLineHeightMultiple);

    /// <summary>排好版的文字所需高度（用于在矩形内垂直居中）。</summary>
    public static double LayoutHeight(ITextMeasurer measurer, string text, double fontSize, double width) =>
        measurer.WrappedHeight(text, fontSize, Math.Max(1, width), LineHeight(measurer, text, fontSize, width));

    // —— 颜色 ——

    /// <summary>
    /// 底色：取 <paramref name="rect"/>（像素坐标，左上角原点）外扩 2px 的一圈像素，各通道取中位数；采不到就回退白色。
    /// 取中位数而不是均值：环里偶尔混进相邻文字或边框的像素，均值会被拉偏，中位数不会。
    /// </summary>
    public static RgbaColor BackgroundColor(RgbaImage image, RectD rect)
    {
        const int ring = 2;
        var white = new RgbaColor(1, 1, 1);
        var outer = rect.Inset(-ring, -ring).Integral().Intersection(new RectD(0, 0, image.Width, image.Height));
        if (outer.Width < 3 || outer.Height < 3) return white;

        int x0 = (int)outer.MinX, y0 = (int)outer.MinY, w = (int)outer.Width, h = (int)outer.Height;
        var rs = new List<byte>();
        var gs = new List<byte>();
        var bs = new List<byte>();
        for (var y = 0; y < h; y++)
        for (var x = 0; x < w; x++)
        {
            var onRing = x < ring || y < ring || x >= w - ring || y >= h - ring;
            if (!onRing) continue;
            var o = image.Offset(x0 + x, y0 + y);
            rs.Add(image.Pixels[o]); gs.Add(image.Pixels[o + 1]); bs.Add(image.Pixels[o + 2]);
        }
        if (rs.Count == 0) return white;
        return new RgbaColor(Median(rs), Median(gs), Median(bs));

        static double Median(List<byte> values)
        {
            values.Sort();
            return values[values.Count / 2] / 255.0;
        }
    }

    /// <summary>字色：按底色相对明度选黑或白。</summary>
    public static RgbaColor TextColor(RgbaColor background) =>
        background.RelativeLuminance > 0.45
            ? new RgbaColor(0.08, 0.08, 0.08)
            : new RgbaColor(0.98, 0.98, 0.98);
}
