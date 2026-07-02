import AppKit
import CoreGraphics
import UniformTypeIdentifiers

/// 截图可导出的静态格式。
public enum ImageFormat: String, CaseIterable, Sendable {
    case png
    case jpeg
    case tiff
    case pdf

    public var utType: UTType {
        switch self {
        case .png: return .png
        case .jpeg: return .jpeg
        case .tiff: return .tiff
        case .pdf: return .pdf
        }
    }

    /// 保存时使用的文件扩展名。
    public var fileExtension: String {
        switch self {
        case .png: return "png"
        case .jpeg: return "jpg"
        case .tiff: return "tiff"
        case .pdf: return "pdf"
        }
    }

    /// 从文件扩展名反推格式（保存面板选定格式后据此编码）。
    public init?(fileExtension ext: String) {
        switch ext.lowercased() {
        case "png": self = .png
        case "jpg", "jpeg": self = .jpeg
        case "tif", "tiff": self = .tiff
        case "pdf": self = .pdf
        default: return nil
        }
    }
}

/// 把一张 `CGImage` 编码为多种静态格式（PNG/JPEG/TIFF/PDF）。
public enum ImageEncoder {
    public static func encode(_ image: CGImage, as format: ImageFormat, jpegQuality: Double = 0.9) throws -> Data {
        switch format {
        case .png:
            return try encodeBitmap(image, using: .png, properties: [:])
        case .jpeg:
            return try encodeBitmap(image, using: .jpeg, properties: [.compressionFactor: jpegQuality])
        case .tiff:
            return try encodeBitmap(image, using: .tiff, properties: [:])
        case .pdf:
            return try encodePDF(image)
        }
    }

    private static func encodeBitmap(
        _ image: CGImage,
        using type: NSBitmapImageRep.FileType,
        properties: [NSBitmapImageRep.PropertyKey: Any]
    ) throws -> Data {
        let representation = NSBitmapImageRep(cgImage: image)
        guard let data = representation.representation(using: type, properties: properties) else {
            throw CaptureError.imageEncodingFailed
        }
        return data
    }

    /// 单页 PDF：以图像的像素尺寸为页面尺寸，1:1 绘制。
    private static func encodePDF(_ image: CGImage) throws -> Data {
        let data = NSMutableData()
        var mediaBox = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw CaptureError.imageEncodingFailed
        }
        context.beginPDFPage(nil)
        context.draw(image, in: mediaBox)
        context.endPDFPage()
        context.closePDF()
        return data as Data
    }
}
