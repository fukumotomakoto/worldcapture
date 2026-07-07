import SwiftUI

/// 工具栏按钮的标签样式：图标+文字，或纯图标（悬停显示文字提示）。
/// 纯图标可让界面布局不随语言长短变化，代价是需要悬停才知按钮含义。
enum ToolbarLabelStyle: String, CaseIterable, Identifiable {
    case iconAndText
    case iconOnly

    var id: String { rawValue }
    var displayName: String {
        Loc.s(self == .iconOnly ? "settings.labelStyle.iconOnly" : "settings.labelStyle.iconAndText")
    }

    static let storageKey = "WCToolbarLabelStyle"
}

/// 按偏好在「图标+文字」与「纯图标」间切换的标签样式。纯图标模式下务必给每个按钮配 `.help()` 提示。
struct AdaptiveLabelStyle: LabelStyle {
    let iconOnly: Bool

    func makeBody(configuration: Configuration) -> some View {
        if iconOnly {
            configuration.icon
        } else {
            HStack(spacing: 4) {
                configuration.icon
                configuration.title
            }
        }
    }
}

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
    @AppStorage(ToolbarLabelStyle.storageKey) private var toolbarLabelStyle: ToolbarLabelStyle = .iconAndText

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

                Picker(Loc.s("settings.labelStyle"), selection: $toolbarLabelStyle) {
                    ForEach(ToolbarLabelStyle.allCases) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                Text(Loc.s("settings.labelStyle.note"))
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
