import Foundation

/// 把大模型一批译文对回输入条目。
///
/// 规则（宁可少配、绝不错配）：
/// 1. **以输入 ID（1 起的序号）为主绑定**。某个 ID 恰好出现一次、且回显原文与该条输入相容 → 绑定。
/// 2. 回显只用来**核验**：与 ID 指向的输入不相容，或同一 ID 出现多次 → 该 ID 作废，不猜。
/// 3. ID 缺失/作废的输入，才在「尚未被消费」的响应里按回显找——且回显必须**唯一**指向这一条输入
///    （同时与另一条未配输入相容就算含糊，放弃）。
/// 4. 任何一条响应最多被消费一次。配不上的输入返回 nil，由调用方单独重试或保留原文并标记未译。
///
/// 「相容」= 规范化后（小写、只留字母数字）完全相同，或回显是输入的前缀且长度足以区分
/// （模型常只回显前几个词）。
public enum TranslationResponseMatcher {
    public struct Item: Equatable, Sendable {
        public var index: Int
        public var source: String
        public var translation: String

        public init(index: Int, source: String, translation: String) {
            self.index = index
            self.source = source
            self.translation = translation
        }
    }

    /// 回显作为前缀核验时至少要这么长（规范化后的字符数），太短的前缀（如「按」）区分不了任何东西。
    static let minimumPrefixLength = 4

    static func normalize(_ s: String) -> String {
        String(s.precomposedStringWithCanonicalMapping.lowercased().filter { $0.isLetter || $0.isNumber })
    }

    /// 回显 `echo` 是否与输入 `input`（均已规范化）相容。
    static func compatible(echo: String, input: String) -> Bool {
        guard !echo.isEmpty, !input.isEmpty else { return false }
        if echo == input { return true }
        // 模型只回显前几个词：回显是输入的前缀；或输入很短、回显多带了点东西。
        if input.hasPrefix(echo) { return echo.count >= min(minimumPrefixLength, input.count) }
        if echo.hasPrefix(input) { return input.count >= minimumPrefixLength }
        return false
    }

    public static func match(_ inputs: [String], with items: [Item]) -> [String?] {
        let keys = inputs.map(normalize)
        let echoes = items.map { normalize($0.source) }
        var result: [String?] = Array(repeating: nil, count: inputs.count)
        var consumed = Set<Int>()

        // ① 按 ID 绑定（ID 唯一 + 回显核验通过）。
        var byIndex: [Int: [Int]] = [:]
        for (offset, item) in items.enumerated() { byIndex[item.index, default: []].append(offset) }
        for (inputOffset, key) in keys.enumerated() {
            guard let candidates = byIndex[inputOffset + 1], candidates.count == 1 else { continue }
            let itemOffset = candidates[0]
            guard compatible(echo: echoes[itemOffset], input: key) else { continue }
            // 回显必须不比「更像另一条输入」：若回显与另一条输入完全相同而与本条不同，视为错位。
            if echoes[itemOffset] != key,
               keys.enumerated().contains(where: { $0.offset != inputOffset && $0.element == echoes[itemOffset] }) {
                continue
            }
            result[inputOffset] = items[itemOffset].translation
            consumed.insert(itemOffset)
        }

        // ② 剩下的输入按回显找，要求双向唯一。
        let unresolved = keys.indices.filter { result[$0] == nil && !keys[$0].isEmpty }
        for inputOffset in unresolved {
            let key = keys[inputOffset]
            let candidates = items.indices.filter { !consumed.contains($0) && compatible(echo: echoes[$0], input: key) }
            guard candidates.count == 1 else { continue }
            let itemOffset = candidates[0]
            // 这条回显还能配上别的未解决输入 → 含糊，放弃。
            let rivals = unresolved.filter {
                $0 != inputOffset && result[$0] == nil && compatible(echo: echoes[itemOffset], input: keys[$0])
            }
            guard rivals.isEmpty else { continue }
            result[inputOffset] = items[itemOffset].translation
            consumed.insert(itemOffset)
        }
        return result
    }
}
