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

    /// 主应用取走收件箱文件 = 编辑器已接收。最多等这么久，超时就如实报「已排队」。
    private static let ackTimeout: TimeInterval = 3
    private static let ackPoll: TimeInterval = 0.15

    func beginRequest(with context: NSExtensionContext) {
        let item = context.inputItems.first as? NSExtensionItem
        let message = item?.userInfo?[messageKey] as? [String: Any]

        guard let message,
              message["type"] as? String == "import",
              let dataURL = message["image"] as? String else {
            Self.complete(context, ["ok": false, "status": "failed", "error": "bad request"])
            return
        }
        guard let url = saveImage(dataURL: dataURL) else {
            Self.complete(context, ["ok": false, "status": "failed", "error": "could not write to inbox"])
            return
        }
        // 不在 Safari 的调用线程里干等：后台轮询文件是否被主应用取走。
        // NSExtensionContext 不是 Sendable，但只在这一个后台块里用一次（completeRequest），没有并发访问。
        nonisolated(unsafe) let context = context
        let log = self.log
        DispatchQueue.global(qos: .userInitiated).async {
            let deadline = Date().addingTimeInterval(Self.ackTimeout)
            var opened = false
            while Date() < deadline {
                if !FileManager.default.fileExists(atPath: url.path) {
                    opened = true
                    break
                }
                Thread.sleep(forTimeInterval: Self.ackPoll)
            }
            // opened：编辑器已载入；queued：文件在收件箱等着（App 未运行、正在录屏……），之后会自动载入。
            os_log("hand-off %{public}@", log: log, type: .info, opened ? "opened" : "queued")
            Self.complete(context, ["ok": true, "status": opened ? "opened" : "queued"])
        }
    }

    private static func complete(_ context: NSExtensionContext, _ response: [String: Any]) {
        let out = NSExtensionItem()
        out.userInfo = [messageKey: response]
        context.completeRequest(returningItems: [out], completionHandler: nil)
    }

    /// 解析 `data:image/png;base64,...`，写入收件箱，并发 Darwin 通知。返回写入的文件路径。
    private func saveImage(dataURL: String) -> URL? {
        guard let comma = dataURL.firstIndex(of: ","),
              let data = Data(base64Encoded: String(dataURL[dataURL.index(after: comma)...])),
              !data.isEmpty else {
            os_log("bad data URL", log: log, type: .error)
            return nil
        }
        guard let inbox = Shared.inbox else {
            os_log("no inbox path", log: log, type: .error)
            return nil
        }
        try? FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        // 毫秒时间戳 + 随机后缀：同一毫秒两次投递也不会互相覆盖；名字仍按时间排序。
        let name = "capture-\(Int(Date().timeIntervalSince1970 * 1000))-\(UUID().uuidString.prefix(8)).png"
        let url = inbox.appendingPathComponent(name)
        // 先写 .part（主应用只拉 .png，不会读到半截文件），再改名到正式文件名（目标已存在则失败，不覆盖）。
        let partial = url.appendingPathExtension("part")
        do {
            try data.write(to: partial, options: .atomic)
            try FileManager.default.moveItem(at: partial, to: url)
        } catch {
            try? FileManager.default.removeItem(at: partial)
            os_log("write failed: %{public}@", log: log, type: .error, String(describing: error))
            return nil
        }

        os_log("wrote %{public}@ (%d bytes), posting notify", log: log, type: .info, url.lastPathComponent, data.count)
        // 通知常驻的主应用（菜单栏）即时拉取；未运行时主应用启动时也会扫描收件箱。
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(Shared.notification as CFString),
            nil, nil, true
        )
        return url
    }
}
