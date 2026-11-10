namespace WorldCapture.Core.Imaging;

/// <summary>
/// 平台无关的位图：RGBA8、<b>左上角原点</b>、行紧排（stride = width × 4）。
/// Windows 层把 SoftwareBitmap / Win2D 位图转成它交给 Core 处理，再转回去。
/// 统一用左上角原点——macOS 版马赛克的 bug 就出在两套原点混用（pit：cgimage-crop-vs-cgcontext-y-flip-mosaic）。
/// </summary>
public sealed class RgbaImage
{
    public int Width { get; }
    public int Height { get; }
    public byte[] Pixels { get; }
    public int Stride => Width * 4;

    public RgbaImage(int width, int height, byte[]? pixels = null)
    {
        ArgumentOutOfRangeException.ThrowIfNegativeOrZero(width);
        ArgumentOutOfRangeException.ThrowIfNegativeOrZero(height);
        Width = width;
        Height = height;
        Pixels = pixels ?? new byte[width * height * 4];
        if (Pixels.Length != width * height * 4)
            throw new ArgumentException("像素缓冲区大小与宽高不符", nameof(pixels));
    }

    public int Offset(int x, int y) => y * Stride + x * 4;

    public (byte R, byte G, byte B, byte A) GetPixel(int x, int y)
    {
        var o = Offset(x, y);
        return (Pixels[o], Pixels[o + 1], Pixels[o + 2], Pixels[o + 3]);
    }

    public void Fill(int x, int y, int width, int height, byte r, byte g, byte b, byte a = 255)
    {
        for (var yy = y; yy < y + height; yy++)
        for (var xx = x; xx < x + width; xx++)
        {
            var o = Offset(xx, yy);
            Pixels[o] = r; Pixels[o + 1] = g; Pixels[o + 2] = b; Pixels[o + 3] = a;
        }
    }

    public RgbaImage Clone() => new(Width, Height, (byte[])Pixels.Clone());
}

/// <summary>像素矩形（整数，左上角原点）。</summary>
public readonly record struct PixelRect(int X, int Y, int Width, int Height)
{
    public int MaxX => X + Width;
    public int MaxY => Y + Height;
}
