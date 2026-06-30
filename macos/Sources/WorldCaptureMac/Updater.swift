import Combine
import Sparkle
import SwiftUI

/// 封装 Sparkle 更新器，供 SwiftUI 持有与调用。
///
/// 仅用于 Developer ID 直分发版（非 App Store）。更新源 `SUFeedURL` 与
/// 验签公钥 `SUPublicEDKey` 配置在 Info.plist（见 project.yml）。首次运行
/// 时 Sparkle 会询问用户是否开启自动检查，符合本地优先/隐私原则。
@MainActor
final class UpdaterController: ObservableObject {
    private let controller: SPUStandardUpdaterController

    /// 是否可以发起检查（更新进行中时为 false，用于禁用菜单项）。
    @Published var canCheckForUpdates = false

    init() {
        // startingUpdater: true → 自动按计划在后台检查；无自定义委托。
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        controller.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }

    /// 用户主动「检查更新…」。
    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }

    /// 是否自动后台检查更新（设置页开关绑定；直写 Sparkle，KVO 持久化）。
    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }
}
