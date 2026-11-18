namespace WorldCapture.Core.Imaging;

/// <summary>
/// 灰度像素缓冲，行 0 为图像顶部，行主序，长度 = 宽 × 高。用于滚动截屏的纵向对齐和变化区域检测。
/// 移植自 macOS <c>ScrollStitcher.swift</c> 里的 <c>GrayImage</c>。
/// </summary>
public sealed class GrayImage
{
    public int Width { get; }
    public int Height { get; }
    public byte[] Pixels { get; }

    public GrayImage(int width, int height, byte[] pixels)
    {
        ArgumentOutOfRangeException.ThrowIfNegativeOrZero(width);
        ArgumentOutOfRangeException.ThrowIfNegativeOrZero(height);
        if (pixels.Length != width * height)
            throw new ArgumentException("像素缓冲区大小与宽高不符", nameof(pixels));
        Width = width;
        Height = height;
        Pixels = pixels;
    }

    /// <summary>
    /// RGBA → 灰度，用 Rec.601 亮度权重（整数运算，R=G=B 时原值不变）。
    /// macOS 版是让 CoreGraphics 把图画进灰度位图，带色彩管理，彩色像素的灰度值和这里会差几级；
    /// 对齐和差分只看相对差，阈值（22/255）留的余量足够，不要求两边逐像素相同。
    /// </summary>
    public static GrayImage From(RgbaImage image)
    {
        var gray = new byte[image.Width * image.Height];
        var src = image.Pixels;
        for (int i = 0, o = 0; i < gray.Length; i++, o += 4)
            gray[i] = (byte)((src[o] * 299 + src[o + 1] * 587 + src[o + 2] * 114 + 500) / 1000);
        return new GrayImage(image.Width, image.Height, gray);
    }
}
