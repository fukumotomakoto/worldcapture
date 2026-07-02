import Foundation
import Vision

/// 本地文字识别（OCR）。基于 Apple Vision 框架，完全在设备上运行、零网络请求，
/// 与产品「纯本地」定位一致。识别在后台执行器上进行，不占用主线程。
public enum TextRecognizer {
    /// 识别结果：按视觉顺序（自上而下）排列的文本行。
    public struct Result: Sendable {
        public let lines: [String]

        public init(lines: [String]) {
            self.lines = lines
        }

        /// 以换行拼接的完整文本。
        public var text: String { lines.joined(separator: "\n") }

        public var isEmpty: Bool { lines.isEmpty }
    }

    /// 默认识别语言：简体中文 / 英文 / 日文，覆盖本工具的目标用户。
    public static let defaultLanguages = ["zh-Hans", "en-US", "ja"]

    /// 对给定图像做本地 OCR。`async` 且在后台线程执行 Vision 的同步 `perform`。
    public static func recognize(
        cgImage: CGImage,
        languages: [String] = defaultLanguages
    ) async throws -> Result {
        // CGImage 未标注 Sendable（Swift 6 严格并发）；用不可变盒子跨执行器传递。
        let box = ImageBox(cgImage)
        return try await Task.detached(priority: .userInitiated) {
            try performRecognition(box.image, languages: languages)
        }.value
    }

    private struct ImageBox: @unchecked Sendable {
        let image: CGImage
        init(_ image: CGImage) { self.image = image }
    }

    private static func performRecognition(_ cgImage: CGImage, languages: [String]) throws -> Result {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = languages

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])

        let observations = request.results ?? []
        let lines = observations.compactMap { $0.topCandidates(1).first?.string }
        return Result(lines: lines)
    }
}
