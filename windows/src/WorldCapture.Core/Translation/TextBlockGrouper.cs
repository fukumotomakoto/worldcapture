using WorldCapture.Core.Imaging;

namespace WorldCapture.Core.Translation;

/// <summary>
/// 一行识别出的文字及其位置，对应 macOS 的 <c>TextRecognizer.Line</c>。
/// <c>Box</c> 为图像像素坐标、<b>左上角原点</b>。Windows 端的 OCR（Windows.Media.Ocr）把结果转成它再交给 Core。
/// </summary>
public readonly record struct TextLine(string Text, RectD Box);

/// <summary>一段文字：若干 OCR 行合并而成，<c>Rect</c> 为图像像素坐标（左上角原点）的外接矩形。</summary>
public sealed record TextBlock
{
    public RectD Rect { get; init; }
    public IReadOnlyList<string> Lines { get; init; }
    /// <summary>原文一行的高度（各行框高的中位数）；译文字号以它为基准，不随译文长短忽大忽小。</summary>
    public double LineHeight { get; init; }

    public TextBlock(RectD rect, IReadOnlyList<string> lines, double? lineHeight = null)
    {
        Rect = rect;
        Lines = lines;
        LineHeight = lineHeight ?? rect.Height / Math.Max(1, lines.Count);
    }

    /// <summary>
    /// 由行框高度和文字内容反推原文字号（em）。行框贴着字形：有降部字母（g j p q y）的行约 0.95 em 高，
    /// 只有 x 高度和上伸部的行约 0.74 em，中日韩文字约 0.9 em。不做这个修正，
    /// 「General」和「Appearance」会因为一个 p 相差两成字号。
    /// <para>这三个系数是按 Apple Vision 的行框量出来的；Windows.Media.Ocr 的行框松紧不同，上机后要重新标定。</para>
    /// </summary>
    public static double EstimatedFontSize(double boxHeight, string text)
    {
        var elements = SwiftText.Elements(text);
        if (elements.Any(SwiftText.IsCjk)) return boxHeight / 0.9;
        var hasDescender = elements.Any(e => e is "g" or "j" or "p" or "q" or "y");
        return boxHeight / (hasDescender ? 0.95 : 0.74);
    }

    /// <summary>
    /// 合并后的整段文字：相邻两行若接缝两侧都是中日韩字符则直接相连，否则以空格相连。
    /// 按段送翻译，句子才不会在换行处被切成两半。
    /// </summary>
    public string Text
    {
        get
        {
            var joined = "";
            foreach (var line in Lines)
            {
                var trimmed = SwiftText.TrimWhitespaces(line);
                if (trimmed.Length == 0) continue;
                if (joined.Length == 0)
                    joined = trimmed;
                else if (SwiftText.IsCjk(SwiftText.LastElement(joined)) && SwiftText.IsCjk(SwiftText.FirstElement(trimmed)))
                    joined += trimmed;
                else
                    joined += " " + trimmed;
            }
            return joined;
        }
    }

    public bool Equals(TextBlock? other) =>
        other is not null && Rect == other.Rect && LineHeight == other.LineHeight && Lines.SequenceEqual(other.Lines);

    public override int GetHashCode() => HashCode.Combine(Rect, LineHeight, Lines.Count);
}

/// <summary>
/// 把 OCR 行按视觉排版合并成段落（纯逻辑，无框架依赖，可测试）。移植自 macOS <c>TextBlockGrouper.swift</c>。
/// <para>
/// 规则（都以行高为尺度）：候选行与段落最后一行 ①行高相近 ②竖向紧挨（行距小于 0.8 倍行高，允许少量重叠）
/// ③横向同一栏（x 范围有重叠，或左边缘相差不到 1.5 倍行高）。三条都满足才并入。
/// 段落按阅读顺序输出（先上后下，再左后右）。
/// </para>
/// </summary>
public static class TextBlockGrouper
{
    /// <summary>段落行距 ÷ 字号 的典型值。</summary>
    public const double LineHeightOverFontSize = 1.35;

    private sealed class Draft(TextLine line, double size)
    {
        public RectD Rect = line.Box;
        public RectD LastBox = line.Box;
        public double LastSize = size;
        public readonly List<string> Lines = [line.Text];
        public readonly List<double> Sizes = [size];
        public readonly List<double> Tops = [line.Box.MinY];
    }

    public static IReadOnlyList<TextBlock> Group(IEnumerable<TextLine> lines)
    {
        var ordered = lines
            .Where(l => SwiftText.TrimWhitespaces(l.Text).Length > 0 && l.Box.Height > 0)
            .ToList();
        SortInReadingOrder(ordered);

        var blocks = new List<Draft>();
        foreach (var line in ordered)
        {
            var size = TextBlock.EstimatedFontSize(line.Box.Height, line.Text);
            // 从最近的段落往前找，找到第一个能接上的；找不到就另起一段。
            Draft? target = null;
            for (var i = blocks.Count - 1; i >= 0; i--)
            {
                if (!CanAppend(line.Box, size, blocks[i].LastBox, blocks[i].LastSize, blocks[i].Lines.Count)) continue;
                target = blocks[i];
                break;
            }
            if (target is null)
            {
                blocks.Add(new Draft(line, size));
                continue;
            }
            target.Rect = target.Rect.Union(line.Box);
            target.LastBox = line.Box;
            target.LastSize = size;
            target.Lines.Add(line.Text);
            target.Sizes.Add(size);
            target.Tops.Add(line.Box.MinY);
        }

        return blocks.Select(block =>
        {
            // 多行段落：行距最可靠（OCR 对段落内行的框高会带上行距，不稳定）。界面/网页行距通常是字号的 1.25～1.45 倍。
            if (block.Tops.Count >= 2 && block.Tops[^1] > block.Tops[0])
            {
                var pitch = (block.Tops[^1] - block.Tops[0]) / (block.Tops.Count - 1);
                return new TextBlock(block.Rect, block.Lines, pitch / LineHeightOverFontSize);
            }
            var sorted = block.Sizes.Order().ToList();
            return new TextBlock(block.Rect, block.Lines, sorted[sorted.Count / 2]);
        }).ToList();
    }

    /// <summary>
    /// 阅读顺序：顶边相差超过半个行高的按上下排，否则按左右排。
    /// 这个比较带容差、不满足传递性，不能交给 <c>List.Sort</c>（.NET 的内省排序遇到这种比较器结果不确定，还可能抛异常），
    /// 所以用稳定的插入排序：结果只取决于输入顺序，可复现。
    /// </summary>
    private static void SortInReadingOrder(List<TextLine> lines)
    {
        for (var i = 1; i < lines.Count; i++)
        {
            var item = lines[i];
            var j = i - 1;
            while (j >= 0 && ComesBefore(item, lines[j]))
            {
                lines[j + 1] = lines[j];
                j--;
            }
            lines[j + 1] = item;
        }
    }

    private static bool ComesBefore(TextLine a, TextLine b)
    {
        if (Math.Abs(a.Box.MinY - b.Box.MinY) > Math.Min(a.Box.Height, b.Box.Height) * 0.5)
            return a.Box.MinY < b.Box.MinY;
        return a.Box.MinX < b.Box.MinX;
    }

    /// <summary><paramref name="size"/> 为按字形修正后的字号估计（见 <see cref="TextBlock.EstimatedFontSize"/>）。</summary>
    internal static bool CanAppend(RectD box, double size, RectD previous, double previousSize, int blockLineCount)
    {
        var height = (box.Height + previous.Height) / 2;
        if (height <= 0 || previousSize <= 0) return false;
        // 字号差超过 ±25% 多半是标题与正文，分开翻更准。
        // 例外：比前一行窄且左对齐的行多半是段落换行后的末行，OCR 对它的框高常偏小，下限放宽到 0.6。
        var sizeRatio = size / previousSize;
        var looksLikeWrappedTail = box.Width < previous.Width && Math.Abs(box.MinX - previous.MinX) < height * 1.5;
        if (sizeRatio < (looksLikeWrappedTail ? 0.6 : 0.75) || sizeRatio > 1.33) return false;
        // 段落首行比下一行大 12% 以上 = 小标题（「Screen Recording」接说明文字），也分开，标题才能保住自己的字号。
        // 但首行比候选行长得多时，它是段落的正文首行而不是标题（候选行是换行后的末行），不适用。
        if (blockLineCount == 1 && sizeRatio < 0.88 && previous.Width <= box.Width * 1.2) return false;
        // 首行很短、下一行很长 = 标题接说明（框高不可靠时的保险）：标题一般不到说明行宽的 60%，说明行至少 20 个字符。
        if (blockLineCount == 1 && previous.Width < box.Width * 0.6 && box.Width > height * 12) return false;

        var gap = box.MinY - previous.MaxY;
        if (gap <= -height * 0.35 || gap >= height * 0.8) return false;

        var horizontallyOverlapping = box.MaxX > previous.MinX && box.MinX < previous.MaxX;
        var leftAligned = Math.Abs(box.MinX - previous.MinX) < height * 1.5;
        return horizontallyOverlapping || leftAligned;
    }
}
