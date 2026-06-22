import SwiftUI

/// 偏好设置（⌘,）：界面语言、默认保存位置与快捷键说明。
struct SettingsView: View {
    @State private var language = AppLanguage.current

    var body: some View {
        Form {
            Section(Loc.s("settings.section.general")) {
                Picker(Loc.s("settings.language"), selection: $language) {
                    ForEach(AppLanguage.allCases) { lang in
                        Text(lang.displayName).tag(lang)
                    }
                }
                .onChange(of: language) { _, newValue in
                    newValue.apply()
                }
                Text(Loc.s("settings.language.restartNote"))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                LabeledContent(Loc.s("settings.savePath")) {
                    Text(Loc.s("settings.savePath.ask"))
                        .foregroundStyle(.secondary)
                }

                LabeledContent(Loc.s("settings.shortcuts")) {
                    Text(Loc.s("settings.shortcuts.note"))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 300)
    }
}
