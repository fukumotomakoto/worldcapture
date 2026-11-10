import AppKit
import Foundation

/// 轻量本地化封装。
///
/// 双轨构建下解析正确的资源 bundle：SwiftPM 用 `Bundle.module`，
/// Xcode 应用用 `Bundle.main`。界面语言默认跟随系统；设置页可写入
/// `AppleLanguages` 覆盖，重启应用后生效（macOS 标准做法）。
enum Loc {
    static let bundle: Bundle = {
        #if SWIFT_PACKAGE
        return .module
        #else
        return .main
        #endif
    }()

    static func s(_ key: String, _ args: CVarArg...) -> String {
        let format = bundle.localizedString(forKey: key, value: key, table: nil)
        return args.isEmpty ? format : String(format: format, arguments: args)
    }
}

/// 界面语言偏好（持久化到 `AppleLanguages`，重启生效）。
enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case zhHans = "zh-Hans"
    case english = "en"
    case japanese = "ja"
    case korean = "ko"

    var id: String { rawValue }

    /// 选项显示名：语言名用本族名（不翻译），仅“跟随系统”随界面语言变化。
    var displayName: String {
        switch self {
        case .system: return Loc.s("settings.language.system")
        case .zhHans: return "简体中文"
        case .english: return "English"
        case .japanese: return "日本語"
        case .korean: return "한국어"
        }
    }

    private static let preferenceKey = "WCAppLanguage"

    /// 当前偏好（未设置时为跟随系统）。
    static var current: AppLanguage {
        guard let raw = UserDefaults.standard.string(forKey: preferenceKey),
              let value = AppLanguage(rawValue: raw) else { return .system }
        return value
    }

    /// 写入偏好。`.system` 时清除覆盖、跟随系统。需重启应用生效。
    func apply() {
        let defaults = UserDefaults.standard
        switch self {
        case .system:
            defaults.removeObject(forKey: Self.preferenceKey)
            defaults.removeObject(forKey: "AppleLanguages")
        default:
            defaults.set(rawValue, forKey: Self.preferenceKey)
            defaults.set([rawValue], forKey: "AppleLanguages")
        }
    }

    /// 切换后提示并自动重启生效（师弟 2026-11-11：改完语言要提示、自动退出重启）。
    /// 提示用**新语言**写：用户刚选了它，旧界面的语言可能正是他看不懂的。
    @MainActor
    func confirmRelaunch() {
        let alert = NSAlert()
        alert.messageText = localized("settings.language.relaunch.title")
        alert.informativeText = localized("settings.language.relaunch.message")
        alert.addButton(withTitle: localized("settings.language.relaunch.now"))
        alert.addButton(withTitle: localized("settings.language.relaunch.later"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Self.relaunch()
    }

    /// 起一个独立的 shell：等本进程退出后再 open，避免 open 时旧实例还在、只被激活不重开。
    @MainActor
    static func relaunch() {
        let path = Bundle.main.bundleURL.path
        let pid = ProcessInfo.processInfo.processIdentifier
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done; /usr/bin/open \"$0\"", path]
        do {
            try task.run()
        } catch {
            return
        }
        NSApp.terminate(nil)
    }

    /// 取这门语言的文案（跟随系统时用系统首选语言里第一个我们有的）。
    private func localized(_ key: String) -> String {
        let code: String
        if self == .system {
            code = Bundle.preferredLocalizations(from: Loc.bundle.localizations,
                                                 forPreferences: Locale.preferredLanguages).first ?? "en"
        } else {
            code = rawValue
        }
        guard let path = Loc.bundle.path(forResource: code, ofType: "lproj"),
              let bundle = Bundle(path: path) else { return Loc.s(key) }
        return bundle.localizedString(forKey: key, value: Loc.s(key), table: nil)
    }
}
