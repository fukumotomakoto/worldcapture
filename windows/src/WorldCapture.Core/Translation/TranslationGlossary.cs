using System.Text;

namespace WorldCapture.Core.Translation;

/// <summary>
/// 术语表：界面常用词的固定译法，补机器翻译的短板（把 Billing 译成「开具发票」、Voice 译成「嗓音」那种）。
/// 移植自 macOS <c>TranslationGlossary.swift</c>。
/// <para>
/// 两层来源：① 内置表（英 → 简中 / 日）；② 用户词表文件（<c>glossary.txt</c>，<c>原文 = 译文</c> 一行一条，
/// 用 <c>[zh-Hans]</c> / <c>[ja]</c> 分节）。用户条目覆盖内置条目。词表文件格式两个平台通用。
/// </para>
/// <para>用法：① 短文本整体命中 → 直接用译法、不送引擎；② 送大模型引擎时把相关条目放进提示。</para>
/// </summary>
public sealed partial class TranslationGlossary
{
    /// <summary>目标语言标识（如 <c>zh-Hans</c>、<c>ja</c>）→ 小写原文 → 译文。</summary>
    private readonly Dictionary<string, Dictionary<string, string>> _tables;

    public TranslationGlossary(IReadOnlyDictionary<string, IReadOnlyDictionary<string, string>>? tables = null)
    {
        _tables = new Dictionary<string, Dictionary<string, string>>(StringComparer.Ordinal);
        if (tables is null) return;
        foreach (var (language, table) in tables)
            _tables[language] = new Dictionary<string, string>(table, StringComparer.Ordinal);
    }

    private TranslationGlossary(Dictionary<string, Dictionary<string, string>> tables) => _tables = tables;

    private static readonly Lazy<TranslationGlossary> BuiltInLazy = new(BuildBuiltIn);

    public static TranslationGlossary BuiltIn => BuiltInLazy.Value;

    private static TranslationGlossary BuildBuiltIn() => new(
        new Dictionary<string, Dictionary<string, string>>(StringComparer.Ordinal)
        {
            ["zh-Hans"] = Normalized(EnglishToSimplifiedChinese),
            ["zh"] = Normalized(EnglishToSimplifiedChinese),
            ["ja"] = Normalized(EnglishToJapanese),
        });

    /// <summary>内置表 + 用户词表；用户条目优先。</summary>
    public static TranslationGlossary Combined(string? userFileText) =>
        userFileText is null ? BuiltIn : BuiltIn.Merged(Parse(userFileText));

    public bool IsEmpty => _tables.Values.All(t => t.Count == 0);

    /// <summary>合并出一张新表；同一条原文以 <paramref name="other"/> 的译法为准。本对象不变。</summary>
    public TranslationGlossary Merged(TranslationGlossary other)
    {
        var merged = new Dictionary<string, Dictionary<string, string>>(StringComparer.Ordinal);
        foreach (var (language, table) in _tables)
            merged[language] = new Dictionary<string, string>(table, StringComparer.Ordinal);
        foreach (var (language, table) in other._tables)
        {
            if (!merged.TryGetValue(language, out var target))
                merged[language] = target = new Dictionary<string, string>(StringComparer.Ordinal);
            foreach (var (source, translation) in table) target[source] = translation;
        }
        return new TranslationGlossary(merged);
    }

    /// <summary>整段精确命中（忽略大小写、首尾空白与末尾的冒号/省略号）。</summary>
    public string? Lookup(string text, string target) =>
        TableFor(target) is { } table && table.TryGetValue(Key(text), out var translation) ? translation : null;

    /// <summary>与这批文本相关的条目（原文出现在任一文本里），供放进大模型提示。按原文排序。</summary>
    public IReadOnlyList<(string Source, string Target)> EntriesRelevantTo(IEnumerable<string> texts, string target)
    {
        if (TableFor(target) is not { } table) return [];
        var haystack = texts.Select(Fold).ToList();
        return table
            .Where(entry => haystack.Any(t => t.Contains(entry.Key, StringComparison.Ordinal)))
            .Select(entry => (Source: entry.Key, Target: entry.Value))
            .OrderBy(entry => entry.Source, StringComparer.Ordinal)
            .ToList();
    }

    private Dictionary<string, string>? TableFor(string target)
    {
        if (_tables.TryGetValue(target, out var exact)) return exact;
        // "zh-Hans-CN" → "zh-Hans" → "zh"
        var parts = target.Split('-', StringSplitOptions.RemoveEmptyEntries).ToList();
        while (parts.Count > 0)
        {
            parts.RemoveAt(parts.Count - 1);
            if (_tables.TryGetValue(string.Join('-', parts), out var table)) return table;
        }
        return null;
    }

    // —— 用户词表 ——

    /// <summary>词表文件模板（首次打开时写入）。内容与 macOS 版一致。</summary>
    public const string UserFileTemplate =
        "# WorldCapture 翻译词表 / Translation glossary\n" +
        "# 一行一条：原文 = 译文（忽略大小写；整条短文本命中时直接采用，送大模型翻译时作为术语提示）\n" +
        "# 用 [zh-Hans] / [ja] 分节指定目标语言；# 开头是注释。\n" +
        "#\n" +
        "# One entry per line: source = translation (case-insensitive). Sections select the\n" +
        "# target language; lines starting with # are comments.\n" +
        "\n" +
        "[zh-Hans]\n" +
        "Fiscal review log = 财务审阅日志\n" +
        "\n" +
        "[ja]\n" +
        "Fiscal review log = 会計レビューログ\n";

    /// <summary>同 Foundation 的 <c>CharacterSet.newlines</c>。</summary>
    private static readonly char[] LineSeparators = ['\n', '\r', (char)0x0B, (char)0x0C, (char)0x85, (char)0x2028, (char)0x2029];

    /// <summary>解析词表文件。没写分节的条目算 <c>zh-Hans</c>；LF / CRLF 换行都认。</summary>
    public static TranslationGlossary Parse(string text)
    {
        var tables = new Dictionary<string, Dictionary<string, string>>(StringComparer.Ordinal);
        var current = "zh-Hans";
        foreach (var rawLine in text.Split(LineSeparators))
        {
            var line = SwiftText.TrimWhitespaces(rawLine);
            if (line.Length == 0 || line.StartsWith('#')) continue;
            if (line.StartsWith('[') && line.EndsWith(']'))
            {
                current = SwiftText.TrimWhitespaces(line[1..^1]);
                continue;
            }
            var separator = line.IndexOf('=');
            if (separator < 0) continue;
            var source = Key(line[..separator]);
            var target = SwiftText.TrimWhitespaces(line[(separator + 1)..]);
            if (source.Length == 0 || target.Length == 0) continue;
            if (!tables.TryGetValue(current, out var table))
                tables[current] = table = new Dictionary<string, string>(StringComparer.Ordinal);
            table[source] = target;
        }
        return new TranslationGlossary(tables);
    }

    /// <summary>
    /// 统一的文本折叠：Unicode NFC 规范化 + 小写。键生成与查询都走它，预组合的「é」与
    /// 「e + 组合重音」才会落到同一个键（Swift 的 String 比较天生按规范等价，C# 的 Ordinal 不是）。
    /// </summary>
    internal static string Fold(string text) =>
        text.Normalize(NormalizationForm.FormC).ToLowerInvariant().Normalize(NormalizationForm.FormC);

    /// <summary>查表用的键：NFC 规范化、去首尾空白、转小写、去掉末尾的冒号/省略号。</summary>
    internal static string Key(string text)
    {
        var s = Fold(SwiftText.TrimWhitespacesAndNewlines(text));
        return s.TrimEnd(':', '：', '…');
    }

    private static Dictionary<string, string> Normalized((string Source, string Target)[] pairs)
    {
        var table = new Dictionary<string, string>(StringComparer.Ordinal);
        foreach (var (source, target) in pairs) table[Key(source)] = target;
        return table;
    }
}
