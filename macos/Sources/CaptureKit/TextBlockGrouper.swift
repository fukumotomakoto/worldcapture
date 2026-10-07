import CoreGraphics
import Foundation

/// 一段文字：若干 OCR 行合并而成，`rect` 为图像像素坐标（原点左上）的外接矩形。
public struct TextBlock: Equatable, Sendable {
    public var rect: CGRect
    public var lines: [String]
    /// 原文一行的高度（各行框高的中位数）；译文字号以它为基准，不随译文长短忽大忽小。
    public var lineHeight: CGFloat

    public init(rect: CGRect, lines: [String], lineHeight: CGFloat? = nil) {
        self.rect = rect
        self.lines = lines
        self.lineHeight = lineHeight ?? rect.height / CGFloat(max(1, lines.count))
    }

    /// 由行框高度和文字内容反推原文字号（em）。Vision 的行框贴着字形：有降部字母（g j p q y）的行
    /// 约 0.95 em 高，只有 x 高度和上伸部的行约 0.74 em，中日韩文字约 0.9 em。不做这个修正，
    /// 「General」和「Appearance」会因为一个 p 相差两成字号。
    public static func estimatedFontSize(boxHeight: CGFloat, text: String) -> CGFloat {
        let hasCJK = text.contains { $0.isCJK }
        if hasCJK { return boxHeight / 0.9 }
        let hasDescender = text.contains { "gjpqy".contains($0) }
        return boxHeight / (hasDescender ? 0.95 : 0.74)
    }

    /// 合并后的整段文字：相邻两行若接缝两侧都是中日韩字符则直接相连，否则以空格相连。
    /// 按段送翻译，句子才不会在换行处被切成两半。
    public var text: String {
        lines.reduce(into: "") { joined, line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return }
            if joined.isEmpty {
                joined = trimmed
            } else if let last = joined.last, let first = trimmed.first, last.isCJK, first.isCJK {
                joined += trimmed
            } else {
                joined += " " + trimmed
            }
        }
    }
}

/// 把 OCR 行按视觉排版合并成段落（纯逻辑，无框架依赖，可测试）。
///
/// 规则（都以行高为尺度）：候选行与段落最后一行 ①行高相近（0.55～1.8 倍）②竖向紧挨（行距小于 0.8 倍行高，
/// 允许少量重叠）③横向同一栏（x 范围有重叠，或左边缘相差不到 1.5 倍行高）。三条都满足才并入。
/// 段落按阅读顺序输出（先上后下，再左后右）。
public enum TextBlockGrouper {
    public static func group(_ lines: [TextRecognizer.Line]) -> [TextBlock] {
        let ordered = lines
            .filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty && $0.box.height > 0 }
            .sorted { a, b in
                if abs(a.box.minY - b.box.minY) > min(a.box.height, b.box.height) * 0.5 {
                    return a.box.minY < b.box.minY
                }
                return a.box.minX < b.box.minX
            }

        var blocks: [(rect: CGRect, lastBox: CGRect, lastSize: CGFloat, lines: [String], sizes: [CGFloat], tops: [CGFloat])] = []
        for line in ordered {
            let size = TextBlock.estimatedFontSize(boxHeight: line.box.height, text: line.text)
            // 从最近的段落往前找，找到第一个能接上的；找不到就另起一段。
            if let index = blocks.indices.reversed().first(where: {
                canAppend(line.box, size: size, after: blocks[$0].lastBox, size: blocks[$0].lastSize, blockLineCount: blocks[$0].lines.count)
            }) {
                blocks[index].rect = blocks[index].rect.union(line.box)
                blocks[index].lastBox = line.box
                blocks[index].lastSize = size
                blocks[index].lines.append(line.text)
                blocks[index].sizes.append(size)
                blocks[index].tops.append(line.box.minY)
            } else {
                blocks.append((line.box, line.box, size, [line.text], [size], [line.box.minY]))
            }
        }
        return blocks.map { block in
            // 多行段落：行距最可靠（Vision 对段落内行的框高会带上行距，不稳定）。界面/网页行距通常是字号的 1.25～1.45 倍。
            if block.tops.count >= 2, let first = block.tops.first, let last = block.tops.last, last > first {
                let pitch = (last - first) / CGFloat(block.tops.count - 1)
                return TextBlock(rect: block.rect, lines: block.lines, lineHeight: pitch / lineHeightOverFontSize)
            }
            let sorted = block.sizes.sorted()
            return TextBlock(rect: block.rect, lines: block.lines, lineHeight: sorted[sorted.count / 2])
        }
    }

    /// 段落行距 ÷ 字号 的典型值。
    public static let lineHeightOverFontSize: CGFloat = 1.35

    /// `size` 为按字形修正后的字号估计（见 `estimatedFontSize`）。
    static func canAppend(_ box: CGRect, size: CGFloat, after previous: CGRect, size previousSize: CGFloat, blockLineCount: Int) -> Bool {
        let height = (box.height + previous.height) / 2
        guard height > 0, previousSize > 0 else { return false }
        // 字号差超过 ±25% 多半是标题与正文，分开翻更准。
        // 例外：比前一行窄且左对齐的行多半是段落换行后的末行，Vision 对它的框高常偏小，下限放宽到 0.6。
        let sizeRatio = size / previousSize
        let looksLikeWrappedTail = box.width < previous.width && abs(box.minX - previous.minX) < height * 1.5
        guard sizeRatio >= (looksLikeWrappedTail ? 0.6 : 0.75), sizeRatio <= 1.33 else { return false }
        // 段落首行比下一行大 12% 以上 = 小标题（「Screen Recording」接说明文字），也分开，标题才能保住自己的字号。
        // 但首行比候选行长得多时，它是段落的正文首行而不是标题（候选行是换行后的末行），不适用。
        if blockLineCount == 1, sizeRatio < 0.88, previous.width <= box.width * 1.2 { return false }
        // 首行很短、下一行很长 = 标题接说明（框高不可靠时的保险）：标题一般不到说明行宽的 60%，说明行至少 20 个字符。
        if blockLineCount == 1, previous.width < box.width * 0.6, box.width > height * 12 { return false }

        let gap = box.minY - previous.maxY
        guard gap > -height * 0.35, gap < height * 0.8 else { return false }

        let horizontallyOverlapping = box.maxX > previous.minX && box.minX < previous.maxX
        let leftAligned = abs(box.minX - previous.minX) < height * 1.5
        return horizontallyOverlapping || leftAligned
    }
}

extension Character {
    /// 中日韩统一表意文字、假名、谚文——这些文字之间不需要空格。
    var isCJK: Bool {
        guard let scalar = unicodeScalars.first else { return false }
        switch scalar.value {
        case 0x3040...0x30FF,   // 平假名、片假名
             0x3400...0x4DBF,   // CJK 扩展 A
             0x4E00...0x9FFF,   // CJK 统一表意
             0xAC00...0xD7AF,   // 谚文音节
             0xF900...0xFAFF,   // CJK 兼容表意
             0xFF00...0xFFEF,   // 全角标点与字母
             0x3000...0x303F:   // CJK 标点
            return true
        default:
            return false
        }
    }
}
