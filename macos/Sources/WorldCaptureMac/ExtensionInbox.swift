import AppKit

/// 接收 Safari 扩展经 App Group 收件箱投递的整页截图。
/// 扩展写入 PNG 后发 Darwin 通知；这里监听通知即时拉取，启动时也扫描一次（覆盖“主应用当时未运行”）。
@MainActor
final class ExtensionInbox {
    static let shared = ExtensionInbox()

    /// 须与 SafariWebExtensionHandler 侧常量一致（同一用户的 Application Support 共享路径）。
    private let notification = "io.worldcapture.extension.import"

    /// 收到新截图时回调（主线程）。由主界面接管载入编辑。
    var onImage: ((NSImage) -> Void)?

    private var started = false

    /// ~/Library/Application Support/WorldCapture/inbox
    private var inboxURL: URL? {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("WorldCapture/inbox", isDirectory: true)
    }

    func start() {
        guard !started else { return }
        started = true

        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let observer = Unmanaged.passUnretained(self).toOpaque()
        CFNotificationCenterAddObserver(
            center,
            observer,
            { _, _, _, _, _ in
                Task { @MainActor in ExtensionInbox.shared.drain() }
            },
            notification as CFString,
            nil,
            .deliverImmediately
        )

        drain() // 拉取“主应用未运行时”已排队的截图
    }

    /// 取出收件箱中所有 PNG，逐个回调后删除。
    func drain() {
        guard let inboxURL,
              let files = try? FileManager.default.contentsOfDirectory(
                  at: inboxURL,
                  includingPropertiesForKeys: nil
              ) else { return }

        // 文件名含毫秒时间戳，按名排序即时间序。
        let pngs = files.filter { $0.pathExtension.lowercased() == "png" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        for url in pngs {
            if let image = NSImage(contentsOf: url) {
                NSApp.activate(ignoringOtherApps: true)
                onImage?(image)
            }
            try? FileManager.default.removeItem(at: url)
        }
    }
}
