import AppKit
import AVFoundation
import ImageIO
import Foundation

/// 历史记录条目类型：截图或录像。
enum HistoryKind: String, Codable {
    case image
    case video
}

/// 一条历史记录：一个已保存到磁盘的截图或录像。
struct HistoryEntry: Codable, Identifiable, Hashable {
    let id: UUID
    let path: String
    let kind: HistoryKind
    let date: Date

    var url: URL { URL(fileURLWithPath: path) }
    var fileName: String { url.lastPathComponent }
    /// 文件当前是否仍存在于磁盘（可能已被移动或删除）。
    var exists: Bool { FileManager.default.fileExists(atPath: path) }

    init(url: URL, kind: HistoryKind, date: Date = Date()) {
        self.id = UUID()
        self.path = url.path
        self.kind = kind
        self.date = date
    }
}

/// 已保存截图/录像的持久化历史，跨启动保留；供历史库窗口浏览、重开、定位与删除。
///
/// 单一真相源（沿用 `PinnedImageController.shared` 等既有单例风格）：截图保存与录制完成都写入这里，
/// 数据持久化到 `~/Library/Application Support/WorldCapture/history.json`。
@MainActor
final class HistoryStore: ObservableObject {
    static let shared = HistoryStore()

    @Published private(set) var entries: [HistoryEntry] = []
    /// 最近一次失败（移入废纸篓失败、索引写不进磁盘……），供历史库界面提示；用户关闭提示后清空。
    @Published var lastError: String?

    private let fileURL: URL
    private let thumbnails = NSCache<NSString, NSImage>()

    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = support.appendingPathComponent("WorldCapture", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("history.json")
        load()
    }

    // MARK: - 读写

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            entries = try decoder.decode([HistoryEntry].self, from: data).sorted { $0.date > $1.date }
        } catch {
            // 索引损坏：先留一份副本再继续，别让下一次写入把唯一的旧记录覆盖掉。
            let backup = fileURL.deletingLastPathComponent()
                .appendingPathComponent("history.corrupt-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.copyItem(at: fileURL, to: backup)
            lastError = Loc.s("library.error.corrupt", backup.lastPathComponent)
        }
    }

    /// 把一份新列表写入磁盘；**写成功才替换内存中的列表**，界面、磁盘、重启后的记录始终一致。
    @discardableResult
    private func commit(_ next: [HistoryEntry]) -> Bool {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted]
        do {
            let data = try encoder.encode(next)
            try data.write(to: fileURL, options: .atomic)
            entries = next
            return true
        } catch {
            lastError = Loc.s("library.error.persist", error.localizedDescription)
            return false
        }
    }

    // MARK: - 变更

    /// 记录一次新保存（按路径去重，仅保留最新一条并置顶）。调用方须在文件写入成功之后才调用。
    func record(_ url: URL, kind: HistoryKind) {
        var next = entries
        next.removeAll { $0.path == url.path }
        next.insert(HistoryEntry(url: url, kind: kind), at: 0)
        commit(next)
    }

    /// 从历史列表中移除一条（不动磁盘文件）。
    func remove(_ entry: HistoryEntry) {
        var next = entries
        next.removeAll { $0.id == entry.id }
        if commit(next) {
            thumbnails.removeObject(forKey: entry.path as NSString)
        }
    }

    /// 把文件移入废纸篓，**成功后**才从历史移除；失败则记录保持不变并提示原因。
    /// 文件本来就不在了（已被移走/删除）视同成功，只清掉这条失效记录。
    func moveToTrash(_ entry: HistoryEntry) {
        if entry.exists {
            do {
                try FileManager.default.trashItem(at: entry.url, resultingItemURL: nil)
            } catch {
                lastError = Loc.s("library.error.trash", entry.fileName, error.localizedDescription)
                return
            }
        }
        remove(entry)
    }

    /// 清空历史列表（仅清记录，不删除磁盘文件）。
    func clearAll() {
        if commit([]) {
            thumbnails.removeAllObjects()
        }
    }

    /// 移除磁盘上已不存在的条目（打开历史库时调用）。
    func pruneMissing() {
        let next = entries.filter(\.exists)
        if next.count != entries.count { commit(next) }
    }

    // MARK: - 缩略图

    /// 包装非 Sendable 的 NSImage 以跨 actor 边界返回。
    private struct ThumbnailBox: @unchecked Sendable { let image: NSImage }

    /// 异步生成（并缓存）一条历史的缩略图；文件缺失或解码失败返回 nil。
    func thumbnail(for entry: HistoryEntry, maxDimension: CGFloat = 1024) async -> NSImage? {
        let key = entry.path as NSString
        if let cached = thumbnails.object(forKey: key) { return cached }
        guard entry.exists else { return nil }
        guard let boxed = await Self.makeThumbnail(url: entry.url, kind: entry.kind, maxDimension: maxDimension) else {
            return nil
        }
        thumbnails.setObject(boxed.image, forKey: key)
        return boxed.image
    }

    /// 在后台执行器上生成缩略图（`nonisolated async` 不会占用主线程）。
    private nonisolated static func makeThumbnail(url: URL, kind: HistoryKind, maxDimension: CGFloat) async -> ThumbnailBox? {
        switch kind {
        case .image:
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxDimension
            ]
            guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
            return ThumbnailBox(image: NSImage(cgImage: cg, size: .zero))
        case .video:
            let asset = AVURLAsset(url: url)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: maxDimension, height: maxDimension)
            guard let cg = try? await generator.image(at: .zero).image else { return nil }
            return ThumbnailBox(image: NSImage(cgImage: cg, size: .zero))
        }
    }
}
