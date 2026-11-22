using WorldCapture.Core.Translation;

namespace WorldCapture.Core.Tests;

/// <summary>逐条移植自 macos/Tests/CaptureKitTests/TranslationGlossaryTests.swift（测试名保持对应）。</summary>
public class TranslationGlossaryTests
{
    [Fact]
    public void BuiltInGlossaryFixesCommonUILabels()
    {
        var g = TranslationGlossary.BuiltIn;
        Assert.Equal("账单", g.Lookup("Billing", "zh-Hans"));
        Assert.Equal("语音", g.Lookup("  voice: ", "zh-Hans"));
        Assert.Equal("偏好设置", g.Lookup("Preferences", "zh-Hans-CN"));
        Assert.Equal("請求", g.Lookup("Billing", "ja"));
        Assert.Null(g.Lookup("Some long sentence that is not a label", "zh-Hans"));
        Assert.Null(g.Lookup("Billing", "fr"));
    }

    [Fact]
    public void UserGlossaryOverridesBuiltInAndSupportsSections()
    {
        const string user = """
            # comment
            [zh-Hans]
            Billing = 计费
            Fiscal review log = 财务审阅日志
            [ja]
            Fiscal review log = 会計レビューログ
            """;
        var g = TranslationGlossary.Combined(user);
        Assert.Equal("计费", g.Lookup("Billing", "zh-Hans"));
        Assert.Equal("财务审阅日志", g.Lookup("fiscal review log", "zh-Hans"));
        Assert.Equal("会計レビューログ", g.Lookup("Fiscal review log", "ja"));
        Assert.Equal("语音", g.Lookup("Voice", "zh-Hans"));
    }

    [Fact]
    public void RelevantEntriesOnlyIncludeTermsPresentInTheBatch()
    {
        var entries = TranslationGlossary.BuiltIn.EntriesRelevantTo(["Open Billing settings", "Voice"], "zh-Hans");
        var sources = entries.Select(e => e.Source).ToList();
        Assert.Contains("billing", sources);
        Assert.Contains("voice", sources);
        Assert.Contains("settings", sources);
        Assert.DoesNotContain("password", sources);
    }

    // —— 以下为 Windows 侧补充（Swift 侧没有对应用例）——

    [Fact]
    public void BuiltInTablesCarryTheSameEntriesAsMacOS()
    {
        // macOS 的两张内置表各 144 条；这里少一条就说明两边的表不同步了。
        Assert.Equal(144, TranslationGlossary.EnglishToSimplifiedChinese.Length);
        Assert.Equal(144, TranslationGlossary.EnglishToJapanese.Length);
    }

    [Fact]
    public void MergingDoesNotChangeTheBuiltInGlossary()
    {
        _ = TranslationGlossary.Combined("Billing = 计费");
        Assert.Equal("账单", TranslationGlossary.BuiltIn.Lookup("Billing", "zh-Hans"));
    }

    [Fact]
    public void UserFileWithWindowsLineEndingsParses()
    {
        var g = TranslationGlossary.Parse("[ja]\r\nBilling = 課金\r\n\r\n[zh-Hans]\r\nBilling = 计费\r\n");
        Assert.Equal("課金", g.Lookup("billing", "ja"));
        Assert.Equal("计费", g.Lookup("BILLING:", "zh-Hans"));
    }

    [Fact]
    public void UserFileTemplateParsesIntoBothSections()
    {
        var g = TranslationGlossary.Parse(TranslationGlossary.UserFileTemplate);
        Assert.Equal("财务审阅日志", g.Lookup("Fiscal review log", "zh-Hans"));
        Assert.Equal("会計レビューログ", g.Lookup("Fiscal review log", "ja"));
        Assert.False(g.IsEmpty);
        Assert.True(new TranslationGlossary().IsEmpty);
    }

    /// <summary>审查报告 15：预组合「é」与「e + 组合重音」必须双向命中（与 Swift 版一致）。</summary>
    [Fact]
    public void GlossaryMatchesPrecomposedAndDecomposedForms()
    {
        const string precomposed = "Caf\u00E9";
        const string decomposed = "Cafe\u0301";
        Assert.Equal("咖啡馆", TranslationGlossary.Parse($"[zh-Hans]\n{precomposed} = 咖啡馆").Lookup(decomposed, "zh-Hans"));
        Assert.Equal("咖啡馆", TranslationGlossary.Parse($"[zh-Hans]\n{decomposed} = 咖啡馆").Lookup(precomposed, "zh-Hans"));
        Assert.Equal(TranslationGlossary.Key(precomposed), TranslationGlossary.Key(decomposed), StringComparer.Ordinal);

        // 用户词表覆盖内置 + 语言标识回退。
        var merged = TranslationGlossary.Combined($"[zh-Hans]\nBilling = 计费\n{decomposed} = 咖啡馆");
        Assert.Equal("计费", merged.Lookup("billing", "zh-Hans-CN"));
        Assert.Equal("咖啡馆", merged.Lookup(precomposed, "zh-Hans-CN"));
        var relevant = merged.EntriesRelevantTo([$"Visit the {precomposed} today"], "zh-Hans");
        Assert.Contains(relevant, e => e.Target == "咖啡馆");
    }
}
