using WorldCapture.Core.Translation;

namespace WorldCapture.Core.Tests;

/// <summary>逐条移植自 macos/Tests/CaptureKitTests/TextChunkerTests.swift（测试名保持对应）。</summary>
public class TextChunkerTests
{
    private static string Repeat(string s, int count) => string.Concat(Enumerable.Repeat(s, count));

    [Fact]
    public void ShortTextIsReturnedWhole()
    {
        Assert.Equal(["Hello world."], TextChunker.Split("Hello world.", 100));
        Assert.Empty(TextChunker.Split("   ", 100));
    }

    [Fact]
    public void LongParagraphSplitsAtSentenceBoundariesUnderTheLimit()
    {
        var text = Repeat("Most faceless channels fail because creators lean on generic prompts. ", 20);
        var chunks = TextChunker.Split(text, 200);
        Assert.True(chunks.Count >= 5);
        Assert.All(chunks, c => Assert.True(c.Length <= 200));
        Assert.All(chunks, c => Assert.EndsWith(".", c));
        Assert.Equal(text.Trim(' '), string.Join(" ", chunks));
    }

    [Fact]
    public void CjkSentencesSplitOnFullWidthPunctuationWithoutInsertingSpaces()
    {
        var text = Repeat("这是一句相当普通的中文句子，用来测试切分。", 12);
        var chunks = TextChunker.Split(text, 60);
        Assert.True(chunks.Count >= 4);
        Assert.All(chunks, c => Assert.True(c.Length <= 60 && !c.Contains(' ')));
        Assert.Equal(text, string.Concat(chunks));
    }

    [Fact]
    public void ASingleOversizedSentenceIsHardSplitOnSpaces()
    {
        var words = string.Join(" ", Enumerable.Range(1, 80).Select(i => $"word{i}"));
        var chunks = TextChunker.Split(words, 50);
        Assert.True(chunks.Count > 1);
        Assert.All(chunks, c => Assert.True(c.Length <= 50));
        Assert.Equal(words, string.Join(" ", chunks));
    }

    // —— 以下为 Windows 侧补充（Swift 侧没有对应用例）——

    [Fact]
    public void LimitCountsGraphemeClustersLikeSwift()
    {
        // 一个家庭 emoji 是 1 个字素簇、11 个 UTF-16 码元；上限按字素算，才和 Swift 的 String.count 一致。
        const string family = "👨‍👩‍👧‍👦";
        var text = string.Join(" ", Enumerable.Repeat(family, 6));
        var chunks = TextChunker.Split(text, 3);
        Assert.Equal([$"{family} {family}", $"{family} {family}", $"{family} {family}"], chunks);
    }

    [Fact]
    public void AWordLongerThanTheLimitIsCutAtCharacterBoundaries()
    {
        Assert.Equal(["abcde", "fghij", "kl"], TextChunker.Split("abcdefghijkl", 5));
    }

    [Fact]
    public void PeriodInsideANumberIsNotASentenceEnd()
    {
        Assert.Equal(["Pi is 3.14 roughly.", "Next one."], TextChunker.Sentences("Pi is 3.14 roughly. Next one."));
    }

    [Fact]
    public void CrlfLineBreaksEndASentence()
    {
        Assert.Equal(["first line", "second line"], TextChunker.Sentences("first line\r\nsecond line"));
    }
}
