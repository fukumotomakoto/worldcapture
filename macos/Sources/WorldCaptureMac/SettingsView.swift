import SwiftUI

/// 录制相关偏好（持久化到 UserDefaults）。
enum RecordingPreferences {
    private static let micKey = "WCIncludeMicrophone"

    /// 录制时是否把麦克风声音一并录入（默认关）。
    static var includeMicrophone: Bool {
        get { UserDefaults.standard.bool(forKey: micKey) }
        set { UserDefaults.standard.set(newValue, forKey: micKey) }
    }
}

/// 偏好设置（⌘,）：界面语言、默认保存位置与快捷键说明。
struct SettingsView: View {
    @ObservedObject var updater: UpdaterController
    @State private var language = AppLanguage.current
    @State private var includeMicrophone = RecordingPreferences.includeMicrophone

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

            Section(Loc.s("settings.section.recording")) {
                Toggle(Loc.s("settings.mic"), isOn: $includeMicrophone)
                    .onChange(of: includeMicrophone) { _, newValue in
                        RecordingPreferences.includeMicrophone = newValue
                    }
                Text(Loc.s("settings.mic.note"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(Loc.s("settings.section.updates")) {
                Toggle(Loc.s("settings.autoUpdate"), isOn: Binding(
                    get: { updater.automaticallyChecksForUpdates },
                    set: { updater.automaticallyChecksForUpdates = $0 }
                ))
                Button(Loc.s("menu.checkUpdates")) { updater.checkForUpdates() }
                    .disabled(!updater.canCheckForUpdates)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 340)
    }
}
