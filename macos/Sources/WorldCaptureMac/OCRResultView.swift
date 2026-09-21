import SwiftUI
@preconcurrency import Translation  // TranslationSession 未标 Sendable，按编译器建议降级为警告

/// 「提取文字」结果面板：原文 + 端上翻译（Apple Translation 框架，macOS 15+）。
///
/// 翻译完全在本机进行：TranslationSession 由 `.translationTask` 提供，语言包由系统按需下载
/// （第一次会弹系统的下载确认）。译文渲染在我们自己的面板里，原文/译文并排，可分别复制。
struct OCRResultView: View {
    let text: String
    let onCopy: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var copied = false
    @State private var translationCopied = false

    @State private var translation: String?
    @State private var isTranslating = false
    @State private var translationError: String?
    @State private var configuration: TranslationSession.Configuration?

    @State private var supportedLanguages: [Locale.Language] = []
    @AppStorage(Self.targetLanguageKey) private var targetIdentifier: String = ""

    static let targetLanguageKey = "translation.target"

    private var isEmpty: Bool { text.isEmpty }
    private var showsTranslationColumn: Bool { translation != nil || isTranslating || translationError != nil }

    /// 目标语言：用户选过的优先，否则跟界面语言。
    private var targetLanguage: Locale.Language {
        if !targetIdentifier.isEmpty { return Locale.Language(identifier: targetIdentifier) }
        return Locale.current.language
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label(Loc.s("ocr.title"), systemImage: "text.viewfinder")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 12)

            Divider()

            if isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "text.badge.xmark")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                    Text(Loc.s("ocr.empty"))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(24)
            } else {
                HStack(spacing: 0) {
                    column(title: Loc.s("ocr.source.title")) {
                        TextEditor(text: .constant(text))
                    }
                    if showsTranslationColumn {
                        Divider()
                        column(title: Loc.s("ocr.translation.title")) {
                            translationBody
                        }
                    }
                }
            }

            Divider()

            footer
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
        }
        .frame(width: showsTranslationColumn ? 880 : 460, height: 440)
        .animation(.easeInOut(duration: 0.2), value: showsTranslationColumn)
        // 端上翻译会话：configuration 一变（或 invalidate）就重跑；语言包缺失时系统自己弹下载确认。
        .translationTask(configuration) { session in
            // session 不是 Sendable，只在这个闭包里用，不往外传。
            isTranslating = true
            translationError = nil
            defer { isTranslating = false }
            do {
                let response = try await session.translate(text)
                translation = response.targetText
            } catch {
                translation = nil
                translationError = error.localizedDescription
            }
        }
        .task { await loadSupportedLanguages() }
    }

    @ViewBuilder
    private func column<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 10)
            content()
                .font(.system(.body, design: .default))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var translationBody: some View {
        if isTranslating {
            VStack(spacing: 10) {
                ProgressView()
                Text(Loc.s("ocr.translating"))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let translationError {
            VStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 28))
                    .foregroundStyle(.orange)
                Text(Loc.s("ocr.translation.failed", translationError))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(16)
        } else {
            TextEditor(text: .constant(translation ?? ""))
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Picker(Loc.s("ocr.translate.target"), selection: Binding(
                get: { targetLanguage.minimalIdentifier },
                set: { targetIdentifier = $0 }
            )) {
                ForEach(languageChoices, id: \.identifier) { choice in
                    Text(choice.name).tag(choice.identifier)
                }
            }
            .labelsHidden()
            .frame(maxWidth: 170)
            .help(Loc.s("ocr.translate.target"))

            Button {
                translate()
            } label: {
                Label(Loc.s("ocr.translate"), systemImage: "character.book.closed")
            }
            .disabled(isEmpty || isTranslating)
            .help(Loc.s("ocr.translate.help"))

            if translation != nil {
                Button {
                    onCopy(translation ?? "")
                    translationCopied = true
                } label: {
                    Label(translationCopied ? Loc.s("ocr.copied") : Loc.s("ocr.copyTranslation"),
                          systemImage: translationCopied ? "checkmark" : "doc.on.doc")
                }
            }

            Spacer()

            Button(Loc.s("ocr.close")) { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button {
                onCopy(text)
                copied = true
            } label: {
                Label(copied ? Loc.s("ocr.copied") : Loc.s("ocr.copyAll"),
                      systemImage: copied ? "checkmark" : "doc.on.doc")
            }
            .buttonStyle(.borderedProminent)
            .disabled(isEmpty)
            .keyboardShortcut(.defaultAction)
        }
    }

    // MARK: - 语言列表

    private struct LanguageChoice: Identifiable {
        let identifier: String
        let name: String
        var id: String { identifier }
    }

    /// 系统翻译支持的目标语言，按本地化显示名排序；当前目标语言不在列表里时也保留一项，避免 Picker 无选中项。
    private var languageChoices: [LanguageChoice] {
        var languages = supportedLanguages
        let current = targetLanguage
        if !languages.contains(where: { $0.minimalIdentifier == current.minimalIdentifier }) {
            languages.append(current)
        }
        return languages
            .map { LanguageChoice(identifier: $0.minimalIdentifier, name: Self.displayName(of: $0)) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private static func displayName(of language: Locale.Language) -> String {
        Locale.current.localizedString(forIdentifier: language.minimalIdentifier) ?? language.minimalIdentifier
    }

    private func loadSupportedLanguages() async {
        // LanguageAvailability 不是 Sendable：整个创建 + 查询都放在主 actor 之外完成，只把结果拿回来。
        let languages = await Task.detached { await LanguageAvailability().supportedLanguages }.value
        supportedLanguages = languages
    }

    // MARK: - 翻译

    private func translate() {
        translationCopied = false
        let target = targetLanguage
        if var existing = configuration, existing.target == target {
            // 同一目标语言再点一次：显式失效让 translationTask 重跑。
            existing.invalidate()
            configuration = existing
        } else {
            configuration = TranslationSession.Configuration(source: nil, target: target)
        }
    }
}
