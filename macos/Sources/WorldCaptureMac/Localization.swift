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
}
