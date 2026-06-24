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
        if let decoded = try? decoder.decode([HistoryEntry].self, from: data) {
            entries = decoded.sorted { $0.date > $1.date }
        }
    }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted]
        guard let data = try? encoder.encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    // MARK: - 变更

    /// 记录一次新保存（按路径去重，仅保留最新一条并置顶）。
    func record(_ url: URL, kind: HistoryKind) {
        entries.removeAll { $0.path == url.path }
        entries.insert(HistoryEntry(url: url, kind: kind), at: 0)
        persist()
    }

    /// 从历史列表中移除一条（不动磁盘文件）。
    func remove(_ entry: HistoryEntry) {
        entries.removeAll { $0.id == entry.id }
        thumbnails.removeObject(forKey: entry.path as NSString)
        persist()
    }

    /// 把文件移入废纸篓，并从历史移除。
    func moveToTrash(_ entry: HistoryEntry) {
        try? FileManager.default.trashItem(at: entry.url, resultingItemURL: nil)
        remove(entry)
    }

    /// 清空历史列表（仅清记录，不删除磁盘文件）。
    func clearAll() {
        entries.removeAll()
        thumbnails.removeAllObjects()
        persist()
    }

    /// 移除磁盘上已不存在的条目（打开历史库时调用）。
    func pruneMissing() {
        let before = entries.count
        entries.removeAll { !$0.exists }
        if entries.count != before { persist() }
    }

    // MARK: - 缩略图

    /// 包装非 Sendable 的 NSImage 以跨 actor 边界返回。
    private struct ThumbnailBox: @unchecked Sendable { let image: NSImage }

    /// 异步生成（并缓存）一条历史的缩略图；文件缺失或解码失败返回 nil。
    func thumbnail(for entry: HistoryEntry, maxDimension: CGFloat = 320) async -> NSImage? {
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
