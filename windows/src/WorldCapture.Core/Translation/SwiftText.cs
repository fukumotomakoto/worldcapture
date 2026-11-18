using System.Globalization;
using System.Text;

namespace WorldCapture.Core.Translation;

/// <summary>
/// 让 C# 的字符串运算与 Swift 对齐的小工具。Swift 的 <c>String.count</c>、<c>first</c>、<c>last</c>
/// 按「字素簇」算（一个 emoji、一个带声调的字母都算 1 个），而 C# 的 <c>Length</c> 按 UTF-16 码元算。
/// 切块上限、接缝判断都得按字素算，两边结果才一致。
/// </summary>
internal static class SwiftText
{
    /// <summary>拆成字素簇（对应 Swift 的 <c>Array(text)</c>）。</summary>
    public static List<string> Elements(string text)
    {
        var result = new List<string>(text.Length);
        var e = StringInfo.GetTextElementEnumerator(text);
        while (e.MoveNext()) result.Add((string)e.Current);
        return result;
    }

    /// <summary>字素簇个数（对应 Swift 的 <c>String.count</c>）。</summary>
    public static int Count(string text) => new StringInfo(text).LengthInTextElements;

    public static string? FirstElement(string text) =>
        text.Length == 0 ? null : StringInfo.GetNextTextElement(text, 0);

    public static string? LastElement(string text)
    {
        if (text.Length == 0) return null;
        var starts = StringInfo.ParseCombiningCharacters(text);
        return text[starts[^1]..];
    }

    /// <summary>
    /// 中日韩统一表意文字、假名、谚文、全角标点——这些文字之间不需要空格。
    /// 同 macOS 版 <c>Character.isCJK</c>：只看字素簇的第一个 Unicode 标量。
    /// </summary>
    public static bool IsCjk(string? element)
    {
        if (string.IsNullOrEmpty(element)) return false;
        Rune.DecodeFromUtf16(element, out var rune, out _);
        return rune.Value is
            (>= 0x3040 and <= 0x30FF) or   // 平假名、片假名
            (>= 0x3400 and <= 0x4DBF) or   // CJK 扩展 A
            (>= 0x4E00 and <= 0x9FFF) or   // CJK 统一表意
            (>= 0xAC00 and <= 0xD7AF) or   // 谚文音节
            (>= 0xF900 and <= 0xFAFF) or   // CJK 兼容表意
            (>= 0xFF00 and <= 0xFFEF) or   // 全角标点与字母
            (>= 0x3000 and <= 0x303F);     // CJK 标点
    }

    /// <summary>字素簇是否为空白（对应 Swift 的 <c>Character.isWhitespace</c>，含换行）。</summary>
    public static bool IsWhitespace(string element)
    {
        if (element.Length == 0) return false;
        Rune.DecodeFromUtf16(element, out var rune, out _);
        return Rune.IsWhiteSpace(rune);
    }

    /// <summary>同 Foundation 的 <c>CharacterSet.whitespaces</c>：Zs 类 + 制表符（不含换行）。</summary>
    public static bool IsInWhitespaces(Rune r) =>
        r.Value == 0x09 || Rune.GetUnicodeCategory(r) == UnicodeCategory.SpaceSeparator;

    /// <summary>同 Foundation 的 <c>CharacterSet.newlines</c>。</summary>
    public static bool IsInNewlines(Rune r) =>
        r.Value is (>= 0x0A and <= 0x0D) or 0x85 or 0x2028 or 0x2029;

    /// <summary>对应 <c>trimmingCharacters(in: .whitespaces)</c>。</summary>
    public static string TrimWhitespaces(string text) => Trim(text, IsInWhitespaces);

    /// <summary>对应 <c>trimmingCharacters(in: .whitespacesAndNewlines)</c>。</summary>
    public static string TrimWhitespacesAndNewlines(string text) =>
        Trim(text, static r => IsInWhitespaces(r) || IsInNewlines(r));

    private static string Trim(string text, Func<Rune, bool> isTrimmed)
    {
        var span = text.AsSpan();
        var start = 0;
        while (start < span.Length)
        {
            Rune.DecodeFromUtf16(span[start..], out var rune, out var consumed);
            if (!isTrimmed(rune)) break;
            start += consumed;
        }
        var end = span.Length;
        while (end > start)
        {
            Rune.DecodeLastFromUtf16(span[start..end], out var rune, out var consumed);
            if (!isTrimmed(rune)) break;
            end -= consumed;
        }
        return start == 0 && end == span.Length ? text : text[start..end];
    }
}
