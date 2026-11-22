import SwiftUI

/// 图上翻译里「空间不足、没能完整贴回原位」的段落：原图上保留原文不覆盖，这里给出完整译文。
///
/// 为什么不硬塞：缩到字号下限仍装不下时，硬盖上去会截断译文（只显示前几十个字），
/// 底色又把原文遮住——用户两头都看不到。宁可不盖，也要让全文可读、可复制。
struct TranslationOverflowView: View {
    let items: [(source: String, translation: String)]
    let onCopy: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    private var allTranslations: String {
        items.map(\.translation).joined(separator: "\n\n")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Label(Loc.s("imageTranslate.overflow.title"), systemImage: "text.badge.exclamationmark")
                    .font(.headline)
                Text(Loc.s("imageTranslate.overflow.message", items.count))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.source)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                            Text(item.translation)
                                .textSelection(.enabled)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(20)
            }

            Divider()

            HStack {
                Spacer()
                Button(copied ? Loc.s("ocr.copied") : Loc.s("imageTranslate.overflow.copy")) {
                    onCopy(allTranslations)
                    copied = true
                }
                Button(Loc.s("ocr.close")) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(minWidth: 520, idealWidth: 560, minHeight: 360, idealHeight: 460)
    }
}
