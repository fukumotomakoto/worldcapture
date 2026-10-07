import CaptureKit
import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// 翻译引擎选择（设置页）。两种都在本机运行、不联网。
enum TranslationEngineChoice: String, CaseIterable, Identifiable {
    /// 优先 Apple 智能（Foundation Models，能吃术语提示、译得更自然），不可用时退回系统翻译。
    case automatic
    /// macOS 内置翻译（Translation 框架）。
    case system
    /// Apple 智能端上大模型。
    case appleIntelligence

    var id: String { rawValue }
    static let storageKey = "translation.engine"

    static var current: TranslationEngineChoice {
        TranslationEngineChoice(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .automatic
    }

    /// 这次翻译实际该走 Apple 智能吗。
    var usesAppleIntelligence: Bool {
        switch self {
        case .system: return false
        case .appleIntelligence: return AppleIntelligenceTranslator.isAvailable
        case .automatic: return AppleIntelligenceTranslator.isAvailable
        }
    }
}

/// 用户词表文件：`~/Documents/WorldCapture/glossary.txt`。
enum UserGlossary {
    static var fileURL: URL {
        OutputLocation.root.appendingPathComponent("glossary.txt", isDirectory: false)
    }

    /// 内置 + 用户词表。
    static func load() -> TranslationGlossary {
        TranslationGlossary.combined(userFileText: try? String(contentsOf: fileURL, encoding: .utf8))
    }

    /// 没有就先写模板，再返回路径（供「打开词表」按钮）。
    static func ensureFileExists() -> URL {
        let url = fileURL
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? TranslationGlossary.userFileTemplate.write(to: url, atomically: true, encoding: .utf8)
        }
        return url
    }
}

/// Apple 智能端上大模型做翻译（macOS 26+，需在系统设置里开启 Apple 智能）。
///
/// 结构化输出（`@Generable`）保证译文条数与输入一一对应；术语表条目放进指令；
/// 超过上下文的批次自动切段。全部在 nonisolated 里跑，避免非 Sendable 类型跨 actor。
enum AppleIntelligenceTranslator {
    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            if case .available = SystemLanguageModel.default.availability { return true }
        }
        #endif
        return false
    }

    /// 不可用时的原因（给设置页显示）。
    static var unavailabilityNote: String? {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available: return nil
            case .unavailable(let reason): return String(describing: reason)
            }
        }
        #endif
        return Loc.s("settings.translation.engine.needsMacOS26")
    }

    /// 每批最多多少条 / 多少字符。模型上下文 4096 token：实测一段 6000 字符直接报
    /// exceededContextWindowSize（还要等 41 秒），16 条短句一批约 4 秒。所以段落先按句切到 ≤ 900 字符，
    /// 每批 ≤ 1000 字符，输出中文也留得下。
    static let batchItemLimit = 16
    static let batchCharacterLimit = 1000
    static let paragraphChunkLimit = 900

    /// 逐条翻译；某一批失败（超长、触发内容护栏……）只让那几条返回 nil，其余照常。
    /// `progress(done, total)` 按批回报，供界面显示进度。
    nonisolated static func translate(
        _ texts: [String],
        to target: Locale.Language,
        glossary: [(source: String, target: String)],
        progress: (@Sendable (Int, Int) -> Void)? = nil
    ) async throws -> [String?] {
        #if canImport(FoundationModels)
        guard #available(macOS 26.0, *) else { throw TranslationEngineError.unavailable }
        // 超长段落切块，翻完再拼回；chunkOwner[i] = 第 i 块属于第几条原文。
        var chunks: [String] = []
        var chunkOwner: [Int] = []
        for (index, text) in texts.enumerated() {
            for piece in TextChunker.split(text, limit: paragraphChunkLimit) {
                chunks.append(piece)
                chunkOwner.append(index)
            }
        }
        let batches = self.batches(of: chunks)
        var translatedChunks: [String?] = Array(repeating: nil, count: chunks.count)
        var cursor = 0
        for (batchIndex, batch) in batches.enumerated() {
            let range = cursor..<(cursor + batch.count)
            cursor += batch.count
            do {
                let session = LanguageModelSession(instructions: instructions(target: target, glossary: glossary))
                let numbered = batch.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
                let response = try await session.respond(to: numbered, generating: TranslatedBatch.self)
                // 回填：模型会把两条合并后重新编号（实测过），所以序号只是线索，以回显的原文为准匹配。
                let matched = Self.match(batch, with: response.content.items.map { ($0.index, $0.source, $0.translation) })
                for (offset, text) in matched.enumerated() {
                    translatedChunks[range.lowerBound + offset] = text ?? batch[offset]
                }
            } catch {
                // 这一批放弃（保留 nil），不影响其他批。
            }
            progress?(batchIndex + 1, batches.count)
        }
        // 拼回每条原文：任一块失败整条视为失败。
        let joinsWithoutSpace = ["zh", "ja", "ko"].contains(target.languageCode?.identifier ?? "")
        var results: [String?] = Array(repeating: nil, count: texts.count)
        var parts: [[String]?] = Array(repeating: [], count: texts.count)
        for (index, chunk) in translatedChunks.enumerated() {
            let owner = chunkOwner[index]
            if let chunk, parts[owner] != nil { parts[owner]!.append(chunk) } else { parts[owner] = nil }
        }
        for (index, list) in parts.enumerated() {
            if let list { results[index] = list.joined(separator: joinsWithoutSpace ? "" : " ") }
        }
        return results
        #else
        throw TranslationEngineError.unavailable
        #endif
    }

    /// 把模型输出对回输入：先看序号指向的条目回显原文是否对得上，对不上就在所有条目里找原文最像的；
    /// 都找不到返回 nil（调用方保留原文）。「像」= 规范化后的前 24 个字符相同，或一方是另一方的前缀。
    nonisolated static func match(_ inputs: [String], with items: [(index: Int, source: String, translation: String)]) -> [String?] {
        func norm(_ s: String) -> String {
            String(s.lowercased().filter { $0.isLetter || $0.isNumber }.prefix(24))
        }
        let normalized = items.map { (index: $0.index, source: norm($0.source), translation: $0.translation) }
        return inputs.enumerated().map { offset, input in
            let key = norm(input)
            guard !key.isEmpty else { return nil }
            if let byIndex = normalized.first(where: { $0.index == offset + 1 }),
               byIndex.source == key || (byIndex.source.count >= 8 && (key.hasPrefix(byIndex.source) || byIndex.source.hasPrefix(key))) {
                return byIndex.translation
            }
            if let best = normalized.first(where: { $0.source == key })
                ?? normalized.first(where: { $0.source.count >= 8 && (key.hasPrefix($0.source) || $0.source.hasPrefix(key)) }) {
                return best.translation
            }
            return nil
        }
    }

    static func batches(of texts: [String]) -> [[String]] {
        var batches: [[String]] = []
        var current: [String] = []
        var characters = 0
        for text in texts {
            if !current.isEmpty && (current.count >= batchItemLimit || characters + text.count > batchCharacterLimit) {
                batches.append(current)
                current = []
                characters = 0
            }
            current.append(text)
            characters += text.count
        }
        if !current.isEmpty { batches.append(current) }
        return batches
    }

    static func instructions(target: Locale.Language, glossary: [(source: String, target: String)]) -> String {
        let languageName = Locale.current.localizedString(forIdentifier: target.minimalIdentifier) ?? target.minimalIdentifier
        var text = """
        You are a software UI localizer. Translate each numbered line the user gives you into \(languageName).
        Rules: output exactly one entry per numbered input line, carrying that line's number; never merge or split lines; \
        translate every sentence of a line completely (never shorten or drop a sentence); \
        translate UI labels concisely as a native app would name them; keep product names, brand names, \
        file names, code, URLs, numbers and units unchanged; do not add explanations, quotes or numbering.
        """
        if !glossary.isEmpty {
            text += "\nUse these fixed translations (case-insensitive):\n"
            text += glossary.map { "- \($0.source) → \($0.target)" }.joined(separator: "\n")
        }
        return text
    }
}

enum TranslationEngineError: LocalizedError {
    case unavailable
    var errorDescription: String? { Loc.s("settings.translation.engine.unavailable") }
}

#if canImport(FoundationModels)
@available(macOS 26.0, *)
@Generable
private struct TranslatedItem {
    @Guide(description: "The number of the input line this translation belongs to (1-based).")
    var index: Int
    @Guide(description: "The first few words of that input line, copied exactly as given.")
    var source: String
    @Guide(description: "The translation of that line, without the number.")
    var translation: String
}

@available(macOS 26.0, *)
@Generable
private struct TranslatedBatch {
    @Guide(description: "One entry per numbered input line, each carrying the line's number.")
    var items: [TranslatedItem]
}
#endif
