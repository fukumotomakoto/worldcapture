import Testing
@testable import CaptureKit

@Test func shortTextIsReturnedWhole() {
    #expect(TextChunker.split("Hello world.", limit: 100) == ["Hello world."])
    #expect(TextChunker.split("   ", limit: 100).isEmpty)
}

@Test func longParagraphSplitsAtSentenceBoundariesUnderTheLimit() {
    let sentence = "Most faceless channels fail because creators lean on generic prompts. "
    let text = String(repeating: sentence, count: 20)
    let chunks = TextChunker.split(text, limit: 200)
    #expect(chunks.count >= 5)
    #expect(chunks.allSatisfy { $0.count <= 200 })
    #expect(chunks.allSatisfy { $0.hasSuffix(".") })
    #expect(chunks.joined(separator: " ") == text.trimmingCharacters(in: .whitespaces))
}

@Test func cjkSentencesSplitOnFullWidthPunctuationWithoutInsertingSpaces() {
    let text = String(repeating: "这是一句相当普通的中文句子，用来测试切分。", count: 12)
    let chunks = TextChunker.split(text, limit: 60)
    #expect(chunks.count >= 4)
    #expect(chunks.allSatisfy { $0.count <= 60 && !$0.contains(" ") })
    #expect(chunks.joined() == text)
}

@Test func aSingleOversizedSentenceIsHardSplitOnSpaces() {
    let words = (1...80).map { "word\($0)" }.joined(separator: " ")
    let chunks = TextChunker.split(words, limit: 50)
    #expect(chunks.count > 1)
    #expect(chunks.allSatisfy { $0.count <= 50 })
    #expect(chunks.joined(separator: " ") == words)
}
