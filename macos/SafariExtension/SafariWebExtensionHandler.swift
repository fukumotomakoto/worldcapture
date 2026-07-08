import Foundation
import os.log

#if canImport(SafariServices)
import SafariServices
#endif

/// Safari 传入消息的固定键名。
private let messageKey = "message"

/// 落图收件箱与跨进程通知名。
/// 本扩展是沙盒进程（Safari Web Extension 强制沙盒），`.applicationSupportDirectory` 会被重定向到
/// 自身容器 Container/Data/Library/Application Support。非沙盒的主应用直接读该容器路径取图，
/// 免去 App Group 及其门户注册的签名负担。
private enum Shared {
    static let notification = "io.worldcapture.extension.import"

    /// 沙盒容器内的 .../WorldCapture/inbox
    static var inbox: URL? {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("WorldCapture/inbox", isDirectory: true)
    }
}

/// Safari Web Extension 的原生处理器：接收扩展拼好的整页 PNG（data URL），
/// 写入 App Group 收件箱并发跨进程通知，主应用据此载入编辑。
final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    private let log = OSLog(subsystem: "io.worldcapture.app.Extension", category: "handler")

    func beginRequest(with context: NSExtensionContext) {
        let item = context.inputItems.first as? NSExtensionItem
        let message = item?.userInfo?[messageKey] as? [String: Any]

        var response: [String: Any] = ["ok": false]
        if let message,
           message["type"] as? String == "import",
           let dataURL = message["image"] as? String {
            response["ok"] = saveImage(dataURL: dataURL)
        }

        let out = NSExtensionItem()
        out.userInfo = [messageKey: response]
        context.completeRequest(returningItems: [out], completionHandler: nil)
    }

    /// 解析 `data:image/png;base64,...`，写入 App Group 收件箱，并发 Darwin 通知。
    private func saveImage(dataURL: String) -> Bool {
        guard let comma = dataURL.firstIndex(of: ","),
              let data = Data(base64Encoded: String(dataURL[dataURL.index(after: comma)...])),
              !data.isEmpty else {
            os_log("bad data URL", log: log, type: .error)
            return false
        }
        guard let inbox = Shared.inbox else {
            os_log("no inbox path", log: log, type: .error)
            return false
        }
        try? FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        let url = inbox.appendingPathComponent("capture-\(Int(Date().timeIntervalSince1970 * 1000)).png")
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            os_log("write failed: %{public}@", log: log, type: .error, String(describing: error))
            return false
        }

        os_log("wrote %{public}@ (%d bytes), posting notify", log: log, type: .info, url.lastPathComponent, data.count)
        // 通知常驻的主应用（菜单栏）即时拉取；未运行时主应用启动时也会扫描收件箱。
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(Shared.notification as CFString),
            nil, nil, true
        )
        return true
    }
}
