import AppKit
import CaptureKit
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
    @State private var microphoneDenied = false
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
                Toggle(Loc.s("settings.mic"), isOn: Binding(
                    get: { includeMicrophone },
                    set: { setMicrophone($0) }
                ))
                if microphoneDenied {
                    HStack(spacing: 6) {
                        Text(Loc.s("settings.mic.denied"))
                            .font(.caption)
                            .foregroundStyle(.red)
                        Button(Loc.s("settings.mic.openSettings")) { openMicrophoneSettings() }
                            .buttonStyle(.link)
                            .font(.caption)
                    }
                } else {
                    Text(Loc.s("settings.mic.note"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
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
        .onAppear { reconcileMicrophoneState() }
    }

    /// 开关打开时先申请麦克风权限，授权成功才真正开启；被拒则保持关闭并引导去系统设置。
    /// 这样开关状态始终等于「真能录到声音」，而不是等录完才发现是段静音视频。
    private func setMicrophone(_ enabled: Bool) {
        guard enabled else {
            includeMicrophone = false
            RecordingPreferences.includeMicrophone = false
            microphoneDenied = false
            return
        }
        Task { @MainActor in
            let granted = await MicrophonePermission.request()
            includeMicrophone = granted
            RecordingPreferences.includeMicrophone = granted
            microphoneDenied = !granted
        }
    }

    /// 偏好记着「开」，但用户后来在系统设置里收回了麦克风权限——把开关拨回去，别撒谎。
    /// 只处理已明确拒绝的情况；尚未决定的留到打开开关或开录时再弹窗，不在进设置页时打扰。
    private func reconcileMicrophoneState() {
        guard includeMicrophone, MicrophonePermission.isDenied else { return }
        includeMicrophone = false
        RecordingPreferences.includeMicrophone = false
        microphoneDenied = true
    }

    private func openMicrophoneSettings() {
        guard let url = URL(string:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") else { return }
        NSWorkspace.shared.open(url)
    }
}
