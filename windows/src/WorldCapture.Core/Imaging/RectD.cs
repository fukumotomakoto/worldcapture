namespace WorldCapture.Core.Imaging;

/// <summary>
/// 像素坐标里的浮点矩形（<b>左上角原点</b>），对应 macOS 版里用作像素框的 <c>CGRect</c>（OCR 行框、译文块）。
/// 运算规则照 CoreGraphics：<see cref="Inset"/> 负值即外扩，<see cref="Integral"/> 向外取整。
/// </summary>
public readonly record struct RectD(double X, double Y, double Width, double Height)
{
    public static readonly RectD Zero = new(0, 0, 0, 0);

    public double MinX => X;
    public double MinY => Y;
    public double MaxX => X + Width;
    public double MaxY => Y + Height;

    public RectD Union(RectD o)
    {
        var minX = Math.Min(MinX, o.MinX);
        var minY = Math.Min(MinY, o.MinY);
        return new RectD(minX, minY, Math.Max(MaxX, o.MaxX) - minX, Math.Max(MaxY, o.MaxY) - minY);
    }

    /// <summary>同 <c>CGRect.insetBy(dx:dy:)</c>：正值内缩，负值外扩。</summary>
    public RectD Inset(double dx, double dy) => new(X + dx, Y + dy, Width - 2 * dx, Height - 2 * dy);

    /// <summary>交集；完全不相交时返回 <see cref="Zero"/>（CoreGraphics 返回的是 null 矩形，调用方都不会走到这一支）。</summary>
    public RectD Intersection(RectD o)
    {
        var minX = Math.Max(MinX, o.MinX);
        var minY = Math.Max(MinY, o.MinY);
        var w = Math.Min(MaxX, o.MaxX) - minX;
        var h = Math.Min(MaxY, o.MaxY) - minY;
        return w < 0 || h < 0 ? Zero : new RectD(minX, minY, w, h);
    }

    /// <summary>同 <c>CGRect.integral</c>：外扩到整像素。</summary>
    public RectD Integral()
    {
        var minX = Math.Floor(MinX);
        var minY = Math.Floor(MinY);
        return new RectD(minX, minY, Math.Ceiling(MaxX) - minX, Math.Ceiling(MaxY) - minY);
    }

    /// <summary>同 <c>CGRect.contains(_: CGRect)</c>：<paramref name="o"/> 整个落在本矩形内（含贴边）。</summary>
    public bool Contains(RectD o) => o.MinX >= MinX && o.MinY >= MinY && o.MaxX <= MaxX && o.MaxY <= MaxY;
}

/// <summary>浮点尺寸（像素）。</summary>
public readonly record struct SizeD(double Width, double Height);
