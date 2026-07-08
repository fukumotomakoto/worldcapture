import Foundation

/// 统一默认输出目录：`~/Documents/WorldCapture/{Images,Videos,OCR}`，首次使用时自动创建。
///
/// 产品意图（跨平台）：无论 macOS 还是 Windows，都落在「我的文档」根目录下的 `WorldCapture`，
/// 再按类型分二级目录。macOS 主应用非沙盒，可直接写入 `~/Documents`。
enum OutputLocation {
    enum Kind {
        case image, video, ocr
        var folder: String {
            switch self {
            case .image: return "Images"
            case .video: return "Videos"
            case .ocr: return "OCR"
            }
        }
    }

    /// 默认输出根目录：文档目录下的 WorldCapture。
    static var root: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents", isDirectory: true)
        return docs.appendingPathComponent("WorldCapture", isDirectory: true)
    }

    /// 指定类型的子目录（自动创建）。
    static func directory(for kind: Kind) -> URL {
        let dir = root.appendingPathComponent(kind.folder, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// 默认输出文件 URL（子目录已创建）。`name` 不含扩展名。
    static func file(for kind: Kind, name: String, ext: String) -> URL {
        directory(for: kind).appendingPathComponent("\(name).\(ext)", isDirectory: false)
    }
}
