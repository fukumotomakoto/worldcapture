import AVFoundation
import Darwin
import Foundation

/// 录像收尾与恢复。
///
/// 每次录制会话在 `rootDirectory/<会话 ID>/` 下落分段（暂停/继续 = 多段）和一份 `manifest.json`。
/// 停止时：合并（单段直接用该段）→ 写进会话目录里的临时文件 → **校验**容器、视频轨与预期音轨 →
/// 以无覆盖语义提交到最终目录（撞名自动加后缀）→ 成功才删会话目录。
/// 任何一步失败，分段与清单都原样留着：下次可以重试合并，或把各段单独导出，录下的内容不会丢。
public struct RecordingRecovery: Identifiable, Sendable, Equatable {
    public let directory: URL
    public let preferredOutput: URL
    public let segments: [URL]
    public let createdAt: Date

    public var id: String { directory.lastPathComponent }

    struct Manifest: Codable {
        var preferredOutput: String
        var segments: [String]
        var createdAt: Date
    }

    static let manifestName = "manifest.json"

    /// 恢复目录根：`~/Library/Application Support/WorldCapture/RecordingRecovery`。
    public static let rootDirectory: URL = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return support.appendingPathComponent("WorldCapture/RecordingRecovery", isDirectory: true)
    }()

    // MARK: - 会话目录与清单

    static func createSession(preferredOutput: URL, root: URL = rootDirectory, date: Date = Date()) throws -> URL {
        let directory = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        writeManifest(in: directory, preferredOutput: preferredOutput, segments: [], createdAt: date)
        return directory
    }

    static func writeManifest(in directory: URL, preferredOutput: URL, segments: [URL], createdAt: Date? = nil) {
        let url = directory.appendingPathComponent(manifestName)
        let existing = (try? Data(contentsOf: url)).flatMap { try? decoder.decode(Manifest.self, from: $0) }
        let manifest = Manifest(
            preferredOutput: preferredOutput.path,
            segments: segments.map(\.lastPathComponent),
            createdAt: createdAt ?? existing?.createdAt ?? Date()
        )
        if let data = try? encoder.encode(manifest) {
            try? data.write(to: url, options: .atomic)
        }
    }

    /// 读一个会话目录；清单缺失或一个分段都不在时返回 nil。
    public init?(directory: URL) {
        let url = directory.appendingPathComponent(Self.manifestName)
        guard let data = try? Data(contentsOf: url),
              let manifest = try? Self.decoder.decode(Manifest.self, from: data) else { return nil }
        var segments = manifest.segments
            .map { directory.appendingPathComponent($0, isDirectory: false) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        // 清单之外的分段（应用在这一段收尾前退出/崩溃）也收进来，排在后面——能不能播由收尾校验决定，
        // 但至少不会被悄悄遗忘在磁盘上。
        let listed = Set(segments.map(\.lastPathComponent))
        let extra = ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [])
            .filter { $0.hasPrefix("segment-") && $0.hasSuffix(".mp4") && !listed.contains($0) }
            .sorted()
            .map { directory.appendingPathComponent($0, isDirectory: false) }
        segments += extra
        guard !segments.isEmpty else { return nil }
        self.directory = directory
        self.preferredOutput = URL(fileURLWithPath: manifest.preferredOutput)
        self.segments = segments
        self.createdAt = manifest.createdAt
    }

    /// 所有待恢复的会话（按时间先后）。
    public static func pending(in root: URL = rootDirectory) -> [RecordingRecovery] {
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else { return [] }
        return items.compactMap { RecordingRecovery(directory: $0) }.sorted { $0.createdAt < $1.createdAt }
    }

    // MARK: - 收尾

    /// 合并 → 校验 → 无覆盖提交。成功返回最终路径并删除会话目录；失败抛错且会话目录保持原样。
    public func finalize() async throws -> URL {
        let expectsAudio = await Self.anyHasAudio(segments)
        let candidate: URL
        if segments.count == 1 {
            candidate = segments[0]
        } else {
            candidate = directory.appendingPathComponent("merged-\(UUID().uuidString).mp4")
            do {
                try await ScreenRecorder.mergeSegments(segments, to: candidate)
            } catch {
                try? FileManager.default.removeItem(at: candidate)
                throw error
            }
        }
        do {
            try await Self.verify(candidate, expectsAudio: expectsAudio)
        } catch {
            if candidate != segments.first { try? FileManager.default.removeItem(at: candidate) }
            throw error
        }
        let final = try Self.move(candidate, toDirectory: outputDirectory, baseName: baseName, ext: "mp4")
        try? FileManager.default.removeItem(at: directory)
        return final
    }

    /// 不合并，把每段单独导出为 `<名称>-part1.mp4`…；全部成功后删除会话目录。
    public func exportSegments() throws -> [URL] {
        var exported: [URL] = []
        for (index, segment) in segments.enumerated() {
            exported.append(try Self.move(segment, toDirectory: outputDirectory, baseName: "\(baseName)-part\(index + 1)", ext: "mp4"))
        }
        try? FileManager.default.removeItem(at: directory)
        return exported
    }

    /// 放弃恢复：把会话目录移入废纸篓（不直接删除，误点还能从废纸篓找回）。
    public func discard() {
        if (try? FileManager.default.trashItem(at: directory, resultingItemURL: nil)) == nil {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    var outputDirectory: URL { preferredOutput.deletingLastPathComponent() }
    var baseName: String { preferredOutput.deletingPathExtension().lastPathComponent }

    /// 无覆盖改名；跨卷（EXDEV）时退回「复制 + 无覆盖改名 + 删源」。
    static func move(_ source: URL, toDirectory directory: URL, baseName: String, ext: String) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        do {
            return try UniqueFileWriter.commit(source, directory: directory, baseName: baseName, ext: ext)
        } catch let error as NSError where error.domain == NSPOSIXErrorDomain && error.code == Int(EXDEV) {
            let url = try UniqueFileWriter.copyCommit(source, directory: directory, baseName: baseName, ext: ext)
            try? FileManager.default.removeItem(at: source)
            return url
        }
    }

    // MARK: - 校验

    static func anyHasAudio(_ urls: [URL]) async -> Bool {
        for url in urls {
            if let tracks = try? await AVURLAsset(url: url).loadTracks(withMediaType: .audio), !tracks.isEmpty {
                return true
            }
        }
        return false
    }

    /// 可读的容器 + 时长 > 0 + 有视频轨；分段里有音轨时成品也必须有。
    public static func verify(_ url: URL, expectsAudio: Bool) async throws {
        let asset = AVURLAsset(url: url)
        let duration: CMTime
        do {
            duration = try await asset.load(.duration)
        } catch {
            throw CaptureError.recordingFailed("无法读取录像容器：\(ScreenRecorder.errorDetails(error))")
        }
        guard duration.isValid, duration.seconds > 0 else {
            throw CaptureError.recordingFailed("录像时长为 0")
        }
        guard let video = try? await asset.loadTracks(withMediaType: .video), !video.isEmpty else {
            throw CaptureError.recordingFailed("录像缺少视频轨")
        }
        if expectsAudio {
            guard let audio = try? await asset.loadTracks(withMediaType: .audio), !audio.isEmpty else {
                throw CaptureError.recordingFailed("录像缺少音轨")
            }
        }
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}

/// 收尾失败：录像没有生成，但分段已保留，可恢复。
public struct RecordingFinalizeError: LocalizedError, Sendable {
    public let recovery: RecordingRecovery
    public let reason: String

    public var errorDescription: String? {
        "录像收尾失败（\(reason)）。已录制的 \(recovery.segments.count) 段已保留，可重试合并或逐段导出。"
    }
}
