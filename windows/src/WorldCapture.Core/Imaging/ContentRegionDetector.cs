namespace WorldCapture.Core.Imaging;

/// <summary>
/// 从两帧滚动前后的画面中，找出「真正在滚动的内容区域」。移植自 macOS <c>ContentRegionDetector.swift</c>。
/// <para>
/// 全窗口滚动长图的老大难：整窗里有大量<b>固定</b>部分（浏览器标签栏/地址栏、左右侧栏、留白），
/// 只有中间一栏真正滚动。把整窗逐帧拼接会把固定部分重复叠加成一坨乱图。
/// 这里用「两帧差分」定位变化区域：固定部分两帧几乎相同 → 被排除；滚动列每行都变 → 被保留。
/// </para>
/// 所有坐标都是像素、<b>左上角原点</b>。两帧尺寸不同一律返回 null / false。
/// </summary>
public static class ContentRegionDetector
{
    /// <summary>
    /// 找出「滚动内容的纵向行带」<c>[y0, y1)</c>：中间随滚动逐行变化的区域。
    /// <c>y0</c> 之上是<b>固定顶带</b>（浏览器工具栏 / 吸顶导航），<c>y1</c> 之下是<b>固定底带</b>（固定页脚 / 广告）。
    /// <para>
    /// 只对「滚动行带」逐帧拼接（固定带不参与，避免被重复叠加），再由调用方把首帧的固定顶/底带各拼回一次——
    /// 得到「顶栏一次 + 全宽长内容 + 底栏一次」。按行分离、保留全宽，从而支持左/中/右多列同时滚动的页面。
    /// </para>
    /// 近乎整高都在变（无固定带可分离，如整窗滚动的原生视图）时返回 null，调用方回退为整帧拼接。
    /// </summary>
    public static (int Y0, int Y1)? ScrollingRowBand(GrayImage a, GrayImage b, int threshold = 22, double lineFraction = 0.05)
    {
        if (a.Width != b.Width || a.Height != b.Height) return null;
        int w = a.Width, h = a.Height;

        var stepX = Math.Max(1, w / 500);
        var stepY = Math.Max(1, h / 800);
        var rowChanged = new int[h];
        var sampledCols = (w + stepX - 1) / stepX;
        for (var y = 0; y < h; y += stepY)
        {
            var rowBase = y * w;
            for (var x = 0; x < w; x += stepX)
                if (Math.Abs(a.Pixels[rowBase + x] - b.Pixels[rowBase + x]) >= threshold) rowChanged[y]++;
        }

        // 某行「变化采样点」占比超过阈值才算滚动行（抗噪：固定带/零星变化不计）。
        var rowMin = (int)(sampledCols * lineFraction);
        // 取变化行的最长连续段 = 中间滚动带（跳过固定顶带/底带，且容忍带内的小静止行）。
        if (LongestRun(rowChanged, stepY, h, rowMin) is not var (y0, y1)) return null;
        // 滚动带太薄（误检）→ 回退。
        if (y1 - y0 < (int)(h * 0.25)) return null;
        // 几乎整高都在变（没有可分离的固定带）→ 回退整帧拼接。
        if (y0 <= (int)(h * 0.02) && y1 >= (int)(h * 0.98)) return null;
        return (y0, y1);
    }

    /// <summary>
    /// 找出「真正在滚动的那一列内容」的水平范围 <c>[x0, x1)</c>。用于把拼接<b>对齐</b>限制在滚动列上——
    /// 固定/吸顶侧栏在滚动时不动，若纳入整宽相关性会在 d=0 制造竞争峰、把位移估计带偏 → 误判「未滚动」提前结束。
    /// 变化列近乎整宽（整宽都滚）返回 null，调用方回退为默认排除（仅避滚动条）。
    /// </summary>
    public static (int X0, int X1)? ScrollingColumnRange(GrayImage a, GrayImage b, int threshold = 22, double lineFraction = 0.05)
    {
        if (a.Width != b.Width || a.Height != b.Height) return null;
        int w = a.Width, h = a.Height;

        var stepX = Math.Max(1, w / 800);
        var stepY = Math.Max(1, h / 500);
        var colChanged = new int[w];
        var sampledRows = 0;
        for (var y = 0; y < h; y += stepY)
        {
            sampledRows++;
            var rowBase = y * w;
            for (var x = 0; x < w; x += stepX)
                if (Math.Abs(a.Pixels[rowBase + x] - b.Pixels[rowBase + x]) >= threshold) colChanged[x]++;
        }

        var colMin = (int)(sampledRows * lineFraction);
        if (LongestRun(colChanged, stepX, w, colMin) is not var (x0, x1)) return null;
        // 太窄（误检）→ 回退。近乎整宽（整宽都滚）→ 回退让调用方用默认排除。
        if (x1 - x0 < (int)(w * 0.15)) return null;
        if (x0 <= (int)(w * 0.03) && x1 >= (int)(w * 0.97)) return null;
        return (x0, x1);
    }

    /// <summary>返回发生变化的内容区域。变化不足或近乎整帧时返回 null（调用方回退为整窗）。</summary>
    public static PixelRect? ChangedRect(GrayImage a, GrayImage b, int threshold = 22, double lineFraction = 0.08)
    {
        if (a.Width != b.Width || a.Height != b.Height) return null;
        int w = a.Width, h = a.Height;

        // 抽样控制开销（长图很高，无需逐像素）。
        var stepX = Math.Max(1, w / 500);
        var stepY = Math.Max(1, h / 800);

        var colChanged = new int[w];
        var rowChanged = new int[h];
        var sampledCols = (w + stepX - 1) / stepX;
        var sampledRows = 0;

        for (var y = 0; y < h; y += stepY)
        {
            sampledRows++;
            var rowBase = y * w;
            for (var x = 0; x < w; x += stepX)
            {
                if (Math.Abs(a.Pixels[rowBase + x] - b.Pixels[rowBase + x]) < threshold) continue;
                colChanged[x]++;
                rowChanged[y]++;
            }
        }

        // 某列/行「变化的抽样点」占比超过阈值，才算属于滚动区域（抗噪：忽略零星变化）。
        var colMin = (int)(sampledRows * lineFraction);
        var rowMin = (int)(sampledCols * lineFraction);

        // 取「变化列/行的最长连续段」而非简单首尾跨度：这样即使侧栏有个动态广告也在变，
        // 主滚动列（最长的连续变化块）仍能被正确挑出，不会把范围撑到整帧。
        if (LongestRun(colChanged, stepX, w, colMin) is not var (x0, x1)) return null;
        if (LongestRun(rowChanged, stepY, h, rowMin) is not var (y0, y1)) return null;

        var rect = new PixelRect(x0, y0, x1 - x0, y1 - y0);
        // 太小（误检）或近乎整帧（没有可裁的固定部分）都回退。
        if (rect.Width < w * 0.15 || rect.Height < h * 0.25) return null;
        if (rect.Width >= w * 0.92 && rect.Height >= h * 0.92) return null;
        return rect;
    }

    /// <summary>
    /// 两帧是否已「稳定」（近乎一致）。用于滚动后<b>自适应等待</b>：画面停稳（滚动惯性结束、
    /// 懒加载图片渲染完成）即可立即继续，不用固定死等。<paramref name="tolerance"/> 为「变化采样点占比」的上限（默认 0.6%）。
    /// </summary>
    public static bool IsStable(GrayImage a, GrayImage b, int threshold = 22, double tolerance = 0.006)
    {
        if (a.Width != b.Width || a.Height != b.Height) return false;
        int w = a.Width, h = a.Height;

        var stepX = Math.Max(1, w / 300);
        var stepY = Math.Max(1, h / 300);
        int changed = 0, total = 0;
        for (var y = 0; y < h; y += stepY)
        {
            var rowBase = y * w;
            for (var x = 0; x < w; x += stepX)
            {
                total++;
                if (Math.Abs(a.Pixels[rowBase + x] - b.Pixels[rowBase + x]) >= threshold) changed++;
            }
        }
        return total > 0 && (double)changed / total <= tolerance;
    }

    // RgbaImage 的便捷入口：先转灰度。连续多次检测同一帧时，调用方自己转一次 GrayImage 更省。

    public static (int Y0, int Y1)? ScrollingRowBand(RgbaImage a, RgbaImage b, int threshold = 22, double lineFraction = 0.05) =>
        SameSize(a, b) ? ScrollingRowBand(GrayImage.From(a), GrayImage.From(b), threshold, lineFraction) : null;

    public static (int X0, int X1)? ScrollingColumnRange(RgbaImage a, RgbaImage b, int threshold = 22, double lineFraction = 0.05) =>
        SameSize(a, b) ? ScrollingColumnRange(GrayImage.From(a), GrayImage.From(b), threshold, lineFraction) : null;

    public static PixelRect? ChangedRect(RgbaImage a, RgbaImage b, int threshold = 22, double lineFraction = 0.08) =>
        SameSize(a, b) ? ChangedRect(GrayImage.From(a), GrayImage.From(b), threshold, lineFraction) : null;

    public static bool IsStable(RgbaImage a, RgbaImage b, int threshold = 22, double tolerance = 0.006) =>
        SameSize(a, b) && IsStable(GrayImage.From(a), GrayImage.From(b), threshold, tolerance);

    private static bool SameSize(RgbaImage a, RgbaImage b) => a.Width == b.Width && a.Height == b.Height;

    /// <summary>
    /// 找出计数数组中「≥ minCount」的最长连续段（按 step 抽样，容忍 ≤ maxGap 个采样点的小间断），
    /// 返回 <c>[lo, hi)</c> 像素范围。
    /// </summary>
    private static (int Lo, int Hi)? LongestRun(int[] counts, int step, int limit, int minCount, int maxGap = 3)
    {
        int bestLo = -1, bestHi = -1, bestLen = -1;
        int curLo = -1, curHi = -1, gap = 0;
        for (var i = 0; i < limit; i += step)
        {
            if (counts[i] >= minCount)
            {
                if (curLo < 0) curLo = i;
                curHi = i;
                gap = 0;
            }
            else if (curLo >= 0)
            {
                gap++;
                if (gap > maxGap)
                {
                    if (curHi - curLo > bestLen) { bestLen = curHi - curLo; bestLo = curLo; bestHi = curHi; }
                    curLo = -1; curHi = -1; gap = 0;
                }
            }
        }
        if (curLo >= 0 && curHi - curLo > bestLen) { bestLo = curLo; bestHi = curHi; }
        if (bestLo < 0) return null;
        return (bestLo, Math.Min(limit, bestHi + step));
    }
}
