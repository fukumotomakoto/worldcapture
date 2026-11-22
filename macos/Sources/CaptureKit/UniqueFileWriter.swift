import Darwin
import Foundation

/// 无覆盖写入：输出文件名保留可读时间戳，撞名时追加 `-2`、`-3`… 后缀，**绝不覆盖已有文件**。
///
/// 为什么需要它：截图/录像文件名只精确到秒，同一秒保存两次会落到同一路径，
/// 旧的 `write(to:options:.atomic)` 是「原子替换」语义，会把上一张静默覆盖掉。
///
/// 做法：先把数据写进同目录下的临时文件，再用 `renamex_np(RENAME_EXCL)` 提交到目标名——
/// 这一步由文件系统原子地保证「目标已存在就失败」，并发调用也不会互相覆盖；失败就换下一个后缀重试。
public enum UniqueFileWriter {
    /// 撞名重试上限（同一秒内保存上千次才可能用尽）。
    static let maxAttempts = 1000

    /// 文件名主干：`<prefix>-yyyyMMdd-HHmmss`（本地时区）。
    public static func timestampedName(prefix: String = "WorldCapture", date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "\(prefix)-\(formatter.string(from: date))"
    }

    /// 第 `attempt` 个候选文件名（0 → `base.ext`，1 → `base-2.ext`…）。
    public static func candidateName(base: String, ext: String, attempt: Int) -> String {
        attempt == 0 ? "\(base).\(ext)" : "\(base)-\(attempt + 1).\(ext)"
    }

    /// 把 `data` 写到 `directory` 下一个尚不存在的文件名，返回实际路径。
    @discardableResult
    public static func write(_ data: Data, directory: URL, baseName: String, ext: String) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let temp = directory.appendingPathComponent(".wc-\(UUID().uuidString).tmp", isDirectory: false)
        try data.write(to: temp)
        do {
            return try commit(temp, directory: directory, baseName: baseName, ext: ext)
        } catch {
            try? FileManager.default.removeItem(at: temp)
            throw error
        }
    }

    /// 把一个已写好的文件（须与目标同卷，通常同目录）以无覆盖语义改名到 `directory` 下的空闲文件名。
    /// 成功后源文件即不存在；失败则源文件原样保留，调用方可据此恢复。
    public static func commit(_ source: URL, directory: URL, baseName: String, ext: String) throws -> URL {
        for attempt in 0..<maxAttempts {
            let target = directory.appendingPathComponent(candidateName(base: baseName, ext: ext, attempt: attempt), isDirectory: false)
            let result = source.withUnsafeFileSystemRepresentation { from in
                target.withUnsafeFileSystemRepresentation { to in
                    renamex_np(from!, to!, UInt32(RENAME_EXCL))
                }
            }
            if result == 0 { return target }
            let code = errno
            if code == EEXIST { continue }
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(code), userInfo: [
                NSFilePathErrorKey: target.path,
                NSLocalizedDescriptionKey: String(cString: strerror(code)),
            ])
        }
        throw CocoaError(.fileWriteFileExists, userInfo: [NSFilePathErrorKey: directory.path])
    }

    /// 跨卷提交：先复制到目标目录的临时文件，再无覆盖改名；源文件保留不动（由调用方决定何时删）。
    public static func copyCommit(_ source: URL, directory: URL, baseName: String, ext: String) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let temp = directory.appendingPathComponent(".wc-\(UUID().uuidString).tmp", isDirectory: false)
        try FileManager.default.copyItem(at: source, to: temp)
        do {
            return try commit(temp, directory: directory, baseName: baseName, ext: ext)
        } catch {
            try? FileManager.default.removeItem(at: temp)
            throw error
        }
    }
}
