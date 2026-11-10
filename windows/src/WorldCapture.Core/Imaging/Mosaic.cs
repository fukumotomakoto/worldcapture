using WorldCapture.Core.Annotations;

namespace WorldCapture.Core.Imaging;

/// <summary>
/// 马赛克（打码）。移植自 macOS <c>AnnotationRenderer.mosaicTile</c> 的规则：
/// 只取被盖住的那块像素 → 按格取平均色 → 不透明地填回原位。编辑器预览和导出必须共用这一份。
/// </summary>
public static class Mosaic
{
    /// <summary>块大小随图片放大：下限 16 px，约为短边的 1/45（Retina 截图上大致一块盖一个字）。</summary>
    public static int BlockSize(int imageWidth, int imageHeight) =>
        Math.Max(16, Math.Min(imageWidth, imageHeight) / 45);

    /// <summary>
    /// 归一化框 → 像素矩形：外扩到整像素（同 <c>CGRect.integral</c>）后裁到图内；小于 2×2 返回 null。
    /// </summary>
    public static PixelRect? PixelRectFor(int imageWidth, int imageHeight, NormalizedPoint start, NormalizedPoint end)
    {
        var minX = (int)Math.Floor(Math.Min(start.X, end.X) * imageWidth);
        var minY = (int)Math.Floor(Math.Min(start.Y, end.Y) * imageHeight);
        var maxX = (int)Math.Ceiling(Math.Max(start.X, end.X) * imageWidth);
        var maxY = (int)Math.Ceiling(Math.Max(start.Y, end.Y) * imageHeight);
        minX = Math.Clamp(minX, 0, imageWidth); maxX = Math.Clamp(maxX, 0, imageWidth);
        minY = Math.Clamp(minY, 0, imageHeight); maxY = Math.Clamp(maxY, 0, imageHeight);
        if (maxX - minX < 2 || maxY - minY < 2) return null;
        return new PixelRect(minX, minY, maxX - minX, maxY - minY);
    }

    /// <summary>
    /// 就地打码。格子数 = ceil(宽 / 块) × ceil(高 / 块)，格子在矩形内均分（与 macOS 版缩小再放大的结果一致），
    /// 每格填该格所有像素的平均色，alpha 强制 255——打码必须不透明。返回实际处理的像素矩形。
    /// </summary>
    public static PixelRect? Apply(RgbaImage image, NormalizedPoint start, NormalizedPoint end)
    {
        if (PixelRectFor(image.Width, image.Height, start, end) is not { } rect) return null;
        var block = BlockSize(image.Width, image.Height);
        var cols = Math.Max(1, (int)Math.Ceiling(rect.Width / (double)block));
        var rows = Math.Max(1, (int)Math.Ceiling(rect.Height / (double)block));

        for (var row = 0; row < rows; row++)
        {
            var y0 = rect.Y + (int)Math.Round(row * rect.Height / (double)rows);
            var y1 = rect.Y + (int)Math.Round((row + 1) * rect.Height / (double)rows);
            for (var col = 0; col < cols; col++)
            {
                var x0 = rect.X + (int)Math.Round(col * rect.Width / (double)cols);
                var x1 = rect.X + (int)Math.Round((col + 1) * rect.Width / (double)cols);
                if (x1 <= x0 || y1 <= y0) continue;

                long r = 0, g = 0, b = 0;
                var n = (x1 - x0) * (y1 - y0);
                for (var y = y0; y < y1; y++)
                for (var x = x0; x < x1; x++)
                {
                    var o = image.Offset(x, y);
                    r += image.Pixels[o]; g += image.Pixels[o + 1]; b += image.Pixels[o + 2];
                }
                image.Fill(x0, y0, x1 - x0, y1 - y0, (byte)(r / n), (byte)(g / n), (byte)(b / n));
            }
        }
        return rect;
    }
}
