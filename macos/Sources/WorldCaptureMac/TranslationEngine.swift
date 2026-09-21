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

    /// 每批最多多少条 / 多少字符（模型上下文约 4k token，留足指令和输出的余量）。
    static let batchItemLimit = 16
    static let batchCharacterLimit = 1400

    nonisolated static func translate(
        _ texts: [String],
        to target: Locale.Language,
        glossary: [(source: String, target: String)]
    ) async throws -> [String] {
        #if canImport(FoundationModels)
        guard #available(macOS 26.0, *) else { throw TranslationEngineError.unavailable }
        var results: [String] = []
        for batch in batches(of: texts) {
            let session = LanguageModelSession(instructions: instructions(target: target, glossary: glossary))
            let numbered = batch.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
            let response = try await session.respond(to: numbered, generating: TranslatedBatch.self)
            var items = response.content.items
            // 条数对不上时以输入为准：多的截掉，少的用原文补位，绝不错位。
            if items.count > batch.count { items = Array(items.prefix(batch.count)) }
            while items.count < batch.count { items.append(batch[items.count]) }
            results.append(contentsOf: items)
        }
        return results
        #else
        throw TranslationEngineError.unavailable
        #endif
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
        Rules: keep the same number of items and the same order, one translation per input line; \
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
private struct TranslatedBatch {
    @Guide(description: "Translations in the same order as the numbered input lines, one per line, without the numbers.")
    var items: [String]
}
#endif
