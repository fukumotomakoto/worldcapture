import AppKit

/// 接收 Safari 扩展经收件箱投递的整页截图。
/// 扩展写入 PNG 后发 Darwin 通知；这里监听通知即时拉取，启动时也扫描一次（覆盖“主应用当时未运行”）。
///
/// 由 App 级入口启动（不依赖主窗口出现过），并且**只有编辑器确认接收后才删除文件**：
/// 录屏中编辑器拒收时文件留在收件箱，录屏结束后再拉取——每张截图都有可恢复的去向。
/// 扩展侧以「文件是否被取走」判断结果页该显示「已打开」还是「已排队」。
@MainActor
final class ExtensionInbox {
    static let shared = ExtensionInbox()

    /// 须与 SafariWebExtensionHandler 侧常量一致（同一用户的 Application Support 共享路径）。
    private let notification = "io.worldcapture.extension.import"

    /// 收到新截图时回调（主线程）。返回 true 表示编辑器已接收（随后删除文件）；
    /// false 表示暂不能接收（如正在录屏），文件保留待下次拉取。
    var onImage: ((NSImage) -> Bool)?

    private var started = false

    /// 沙盒扩展把整页 PNG 写入自身容器；非沙盒的主应用直接读该容器路径（免 App Group）。
    /// 扩展侧用 `.applicationSupportDirectory`，沙盒会重定向到 Container/Data/Library/Application Support。
    private var inboxURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(
                "Library/Containers/io.worldcapture.app.Extension/Data/Library/Application Support/WorldCapture/inbox",
                isDirectory: true
            )
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

    /// 按时间顺序取出收件箱中的 PNG：编辑器接收一张删一张；遇到拒收就停（保持顺序，稍后再拉）。
    /// 解不开的文件移到 `failed/`，不阻塞后面的截图，也不直接删掉。
    func drain() {
        guard let onImage else { return }
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: inboxURL,
            includingPropertiesForKeys: nil
        ) else { return }

        // 文件名含毫秒时间戳，按名排序即时间序。
        let pngs = files.filter { $0.pathExtension.lowercased() == "png" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        for url in pngs {
            guard let image = NSImage(contentsOf: url), image.isValid else {
                quarantine(url)
                continue
            }
            NSApp.activate(ignoringOtherApps: true)
            guard onImage(image) else { return }
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func quarantine(_ url: URL) {
        let failed = inboxURL.appendingPathComponent("failed", isDirectory: true)
        try? FileManager.default.createDirectory(at: failed, withIntermediateDirectories: true)
        try? FileManager.default.moveItem(at: url, to: failed.appendingPathComponent(url.lastPathComponent))
    }
}
