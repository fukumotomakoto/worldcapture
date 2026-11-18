using System.Text;

namespace WorldCapture.Core.Translation;

/// <summary>
/// 把过长的段落按句子切成不超过 <c>limit</c> 个字符的块（送上下文有限的端上大模型前用）。
/// 优先在句末标点/换行处切；单句就超长时才在空格或字符边界硬切。
/// 移植自 macOS <c>TextChunker.swift</c>；「字符」按字素簇计数，与 Swift 的 <c>String.count</c> 一致。
/// </summary>
public static class TextChunker
{
    public static IReadOnlyList<string> Split(string text, int limit)
    {
        var trimmed = SwiftText.TrimWhitespacesAndNewlines(text);
        if (limit <= 0 || SwiftText.Count(trimmed) <= limit)
            return trimmed.Length == 0 ? [] : [trimmed];

        var chunks = new List<string>();
        var current = "";
        var currentCount = 0;
        foreach (var sentence in Sentences(trimmed))
        foreach (var piece in HardSplit(sentence, limit))
        {
            var pieceCount = SwiftText.Count(piece);
            if (current.Length == 0)
            {
                current = piece;
                currentCount = pieceCount;
            }
            else if (currentCount + 1 + pieceCount <= limit)
            {
                // 接缝两侧都是中日韩字符就直接相连，否则补一个空格。
                var joinDirectly = SwiftText.IsCjk(SwiftText.LastElement(current)) && SwiftText.IsCjk(SwiftText.FirstElement(piece));
                current += joinDirectly ? piece : " " + piece;
                currentCount = SwiftText.Count(current);
            }
            else
            {
                chunks.Add(current);
                current = piece;
                currentCount = pieceCount;
            }
        }
        if (current.Length > 0) chunks.Add(current);
        return chunks;
    }

    /// <summary>
    /// 按句末标点（。．！？!? 及换行）切句，标点留在句尾。英文句点只在后面是空白或文末时才算句末（不切 3.14）。
    /// 与 macOS 版的一处差别：Windows 文本常用 CRLF 换行，这里把 <c>\r\n</c> 也当换行；
    /// Swift 里 <c>\r\n</c> 是一个字符、不等于 <c>\n</c>，那边不会在 CRLF 处断句。
    /// </summary>
    internal static List<string> Sentences(string text)
    {
        var result = new List<string>();
        var current = new StringBuilder();
        var elements = SwiftText.Elements(text);
        for (var i = 0; i < elements.Count; i++)
        {
            var ch = elements[i];
            current.Append(ch);
            var isPeriod = ch == "." && (i + 1 == elements.Count || SwiftText.IsWhitespace(elements[i + 1]));
            if (ch is "。" or "．" or "！" or "？" or "!" or "?" or "\n" or "\r\n" || isPeriod)
            {
                var s = SwiftText.TrimWhitespacesAndNewlines(current.ToString());
                if (s.Length > 0) result.Add(s);
                current.Clear();
            }
        }
        var tail = SwiftText.TrimWhitespacesAndNewlines(current.ToString());
        if (tail.Length > 0) result.Add(tail);
        return result;
    }

    /// <summary>单句超长：先在空格处切，没有空格就按字符数切。</summary>
    internal static List<string> HardSplit(string sentence, int limit)
    {
        var elements = SwiftText.Elements(sentence);
        if (elements.Count <= limit) return [sentence];

        var pieces = new List<string>();
        var current = "";
        var currentCount = 0;
        foreach (var word in Words(elements))
        {
            if (word.Count > limit)
            {
                if (current.Length > 0) { pieces.Add(current); current = ""; }
                var offset = 0;
                while (word.Count - offset > limit)
                {
                    pieces.Add(string.Concat(word.GetRange(offset, limit)));
                    offset += limit;
                }
                current = string.Concat(word.GetRange(offset, word.Count - offset));
                currentCount = word.Count - offset;
            }
            else if (current.Length == 0)
            {
                current = string.Concat(word);
                currentCount = word.Count;
            }
            else if (currentCount + 1 + word.Count <= limit)
            {
                current += " " + string.Concat(word);
                currentCount += 1 + word.Count;
            }
            else
            {
                pieces.Add(current);
                current = string.Concat(word);
                currentCount = word.Count;
            }
        }
        if (current.Length > 0) pieces.Add(current);
        return pieces;
    }

    /// <summary>按半角空格切词，丢掉空词（同 Swift 的 <c>split(separator: " ")</c>）。</summary>
    private static IEnumerable<List<string>> Words(List<string> elements)
    {
        var word = new List<string>();
        foreach (var e in elements)
        {
            if (e == " ")
            {
                if (word.Count > 0) { yield return word; word = []; }
            }
            else word.Add(e);
        }
        if (word.Count > 0) yield return word;
    }
}
