using System.Text.Json;
using System.Text.Json.Serialization;

namespace WorldCapture.Core.Annotations;

/// <summary>标注类型。JSON 里是小驼峰字符串，与 macOS 版 <c>AnnotationKind</c> 的 rawValue 一致。</summary>
[JsonConverter(typeof(JsonStringEnumConverter<AnnotationKind>))]
public enum AnnotationKind
{
    [JsonStringEnumMemberName("rectangle")] Rectangle,
    [JsonStringEnumMemberName("ellipse")] Ellipse,
    [JsonStringEnumMemberName("arrow")] Arrow,
    [JsonStringEnumMemberName("text")] Text,
    [JsonStringEnumMemberName("number")] Number,
    [JsonStringEnumMemberName("mosaic")] Mosaic,
    [JsonStringEnumMemberName("freehand")] Freehand,
    /// <summary>图上翻译生成的「译文块」：矩形区域盖底色、内填译文。由翻译流程创建，不是手绘工具。</summary>
    [JsonStringEnumMemberName("translation")] Translation,
}

/// <summary>归一化坐标（0…1，<b>左上角原点</b>）。构造时自动夹到 0…1。</summary>
public readonly record struct NormalizedPoint
{
    [JsonPropertyName("x")] public double X { get; }
    [JsonPropertyName("y")] public double Y { get; }

    [JsonConstructor]
    public NormalizedPoint(double x, double y)
    {
        X = Math.Clamp(x, 0, 1);
        Y = Math.Clamp(y, 0, 1);
    }
}

/// <summary>归一化空间里的矩形（左上角原点）。</summary>
public readonly record struct NormalizedRect(double X, double Y, double Width, double Height)
{
    public double MinX => X;
    public double MinY => Y;
    public double MaxX => X + Width;
    public double MaxY => Y + Height;

    public NormalizedRect Inflate(double d) => new(X - d, Y - d, Width + 2 * d, Height + 2 * d);

    public bool Contains(double px, double py) => px >= MinX && px <= MaxX && py >= MinY && py <= MaxY;

    /// <summary>与 CoreGraphics 的 <c>CGRect.intersects</c> 一致：只碰到边不算相交。</summary>
    public bool Intersects(NormalizedRect o) =>
        MinX < o.MaxX && o.MinX < MaxX && MinY < o.MaxY && o.MinY < MaxY;
}

/// <summary>
/// 一条标注。移植自 macOS <c>CaptureAnnotation.swift</c>；JSON 格式与之互通
/// （可选字段为 null 时不写出，旧工程文件缺字段也能读）。
/// </summary>
public sealed record CaptureAnnotation
{
    /// <summary>缺省颜色（系统红），用于未显式设置颜色或旧工程文件。</summary>
    public const string DefaultColorHex = "#FF3B30";

    [JsonPropertyName("id")] public Guid Id { get; init; } = Guid.NewGuid();
    [JsonPropertyName("kind")] public required AnnotationKind Kind { get; init; }
    [JsonPropertyName("start")] public required NormalizedPoint Start { get; init; }
    [JsonPropertyName("end")] public required NormalizedPoint End { get; init; }
    [JsonPropertyName("label")] public string? Label { get; init; }
    /// <summary><c>#RRGGBB</c>/<c>#RRGGBBAA</c>；null 表示用默认强调色。</summary>
    [JsonPropertyName("colorHex")] public string? ColorHex { get; init; }
    /// <summary>线宽倍率，null 表示 1.0。</summary>
    [JsonPropertyName("lineWidth")] public double? LineWidth { get; init; }
    /// <summary>自由笔的折线路径点；仅 <see cref="AnnotationKind.Freehand"/> 使用。</summary>
    [JsonPropertyName("points")] public IReadOnlyList<NormalizedPoint>? Points { get; init; }
    /// <summary>译文块底色；仅 <see cref="AnnotationKind.Translation"/> 使用。</summary>
    [JsonPropertyName("fillColorHex")] public string? FillColorHex { get; init; }
    /// <summary>译文块字号（图像像素）；仅 <see cref="AnnotationKind.Translation"/> 使用。</summary>
    [JsonPropertyName("fontSize")] public double? FontSize { get; init; }

    [JsonIgnore] public double ResolvedLineWidth => LineWidth ?? 1;
    [JsonIgnore] public string ResolvedColorHex => ColorHex ?? DefaultColorHex;
    [JsonIgnore] public RgbaColor Color => RgbaColor.FromHex(ResolvedColorHex);

    /// <summary>归一化空间中的包围盒（点状标注退化为零尺寸；自由笔取所有路径点的外接矩形）。</summary>
    [JsonIgnore]
    public NormalizedRect NormalizedBounds
    {
        get
        {
            if (Kind == AnnotationKind.Freehand && Points is { Count: > 0 } pts)
            {
                double minX = pts.Min(p => p.X), minY = pts.Min(p => p.Y);
                return new NormalizedRect(minX, minY, pts.Max(p => p.X) - minX, pts.Max(p => p.Y) - minY);
            }
            return new NormalizedRect(
                Math.Min(Start.X, End.X), Math.Min(Start.Y, End.Y),
                Math.Abs(End.X - Start.X), Math.Abs(End.Y - Start.Y));
        }
    }

    /// <summary>命中测试：<paramref name="point"/> 是否落在可选中范围内（<paramref name="tolerance"/> 为归一化容差）。</summary>
    public bool HitTest(NormalizedPoint point, double tolerance)
    {
        switch (Kind)
        {
            case AnnotationKind.Rectangle or AnnotationKind.Ellipse or AnnotationKind.Mosaic or AnnotationKind.Translation:
                return NormalizedBounds.Inflate(tolerance).Contains(point.X, point.Y);
            case AnnotationKind.Arrow:
                return DistanceToSegment(point.X, point.Y, Start.X, Start.Y, End.X, End.Y) <= tolerance;
            case AnnotationKind.Text or AnnotationKind.Number:
                return Hypot(point.X - Start.X, point.Y - Start.Y) <= Math.Max(tolerance, 0.04);
            case AnnotationKind.Freehand:
                if (Points is not { Count: >= 2 } pts)
                {
                    return Points is { Count: 1 } one && Hypot(point.X - one[0].X, point.Y - one[0].Y) <= tolerance;
                }
                for (var i = 0; i < pts.Count - 1; i++)
                {
                    if (DistanceToSegment(point.X, point.Y, pts[i].X, pts[i].Y, pts[i + 1].X, pts[i + 1].Y) <= tolerance)
                        return true;
                }
                return false;
            default:
                return false;
        }
    }

    /// <summary>整体平移，端点（及自由笔路径点）自动限制在 0…1。</summary>
    public CaptureAnnotation Translated(double dx, double dy) => this with
    {
        Start = new NormalizedPoint(Start.X + dx, Start.Y + dy),
        End = new NormalizedPoint(End.X + dx, End.Y + dy),
        Points = Points?.Select(p => new NormalizedPoint(p.X + dx, p.Y + dy)).ToArray(),
    };

    /// <summary>
    /// 重映射到裁切后的坐标系（<paramref name="region"/> 为原图归一化裁切框）。
    /// 整体落在裁切框外返回 null（应丢弃）；部分越界的端点被夹到边缘。
    /// </summary>
    public CaptureAnnotation? RemappedToCrop(NormalizedRect region)
    {
        if (region.Width <= 0 || region.Height <= 0) return null;
        if (!NormalizedBounds.Intersects(region)) return null;
        NormalizedPoint Map(NormalizedPoint p) =>
            new((p.X - region.MinX) / region.Width, (p.Y - region.MinY) / region.Height);
        return this with { Start = Map(Start), End = Map(End), Points = Points?.Select(Map).ToArray() };
    }

    public bool Equals(CaptureAnnotation? other) =>
        other is not null
        && Id == other.Id && Kind == other.Kind && Start == other.Start && End == other.End
        && Label == other.Label && ColorHex == other.ColorHex && LineWidth == other.LineWidth
        && FillColorHex == other.FillColorHex && FontSize == other.FontSize
        && (Points is null ? other.Points is null : other.Points is not null && Points.SequenceEqual(other.Points));

    public override int GetHashCode() => HashCode.Combine(Id, Kind, Start, End);

    private static double Hypot(double x, double y) => Math.Sqrt(x * x + y * y);

    private static double DistanceToSegment(double px, double py, double ax, double ay, double bx, double by)
    {
        double dx = bx - ax, dy = by - ay;
        var lengthSquared = dx * dx + dy * dy;
        if (lengthSquared <= 0) return Hypot(px - ax, py - ay);
        var t = Math.Clamp(((px - ax) * dx + (py - ay) * dy) / lengthSquared, 0, 1);
        return Hypot(px - (ax + t * dx), py - (ay + t * dy));
    }
}

/// <summary>标注 JSON 的统一读写设置（与 macOS JSONEncoder 输出互通）。</summary>
public static class AnnotationJson
{
    public static readonly JsonSerializerOptions Options = new()
    {
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
        PropertyNameCaseInsensitive = false,
    };

    public static string Serialize(CaptureAnnotation a) => JsonSerializer.Serialize(a, Options);

    public static CaptureAnnotation? Deserialize(string json) =>
        JsonSerializer.Deserialize<CaptureAnnotation>(json, Options);
}
