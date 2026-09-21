import CoreGraphics
import Foundation

/// 一段文字：若干 OCR 行合并而成，`rect` 为图像像素坐标（原点左上）的外接矩形。
public struct TextBlock: Equatable, Sendable {
    public var rect: CGRect
    public var lines: [String]

    public init(rect: CGRect, lines: [String]) {
        self.rect = rect
        self.lines = lines
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

        var blocks: [(rect: CGRect, lastBox: CGRect, lines: [String])] = []
        for line in ordered {
            // 从最近的段落往前找，找到第一个能接上的；找不到就另起一段。
            if let index = blocks.indices.reversed().first(where: { canAppend(line.box, after: blocks[$0].lastBox) }) {
                blocks[index].rect = blocks[index].rect.union(line.box)
                blocks[index].lastBox = line.box
                blocks[index].lines.append(line.text)
            } else {
                blocks.append((line.box, line.box, [line.text]))
            }
        }
        return blocks.map { TextBlock(rect: $0.rect, lines: $0.lines) }
    }

    static func canAppend(_ box: CGRect, after previous: CGRect) -> Bool {
        let height = (box.height + previous.height) / 2
        guard height > 0 else { return false }
        let heightRatio = box.height / previous.height
        guard heightRatio >= 0.55, heightRatio <= 1.8 else { return false }

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
