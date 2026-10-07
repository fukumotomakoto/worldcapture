import AppKit
import CoreGraphics
import CoreText
import Foundation

/// 「译文块」的排版与着色：把译文塞进原文所在的矩形里。
///
/// 三个纯函数：① 采样矩形边缘像素的平均色当底色（盖住原文时和周围融为一体）；
/// ② 按底色明度选黑/白字；③ 用 CoreText 二分出「能装进矩形的最大字号」。
/// 渲染器和画布共用这里算出的字号，导出图和预览才一致。
public enum TranslationBlockLayout {
    /// 文字与矩形边缘的留白（像素）。
    public static let padding: CGFloat = 2
    public static let minimumFontSize: CGFloat = 6
    public static let fontName = "PingFangSC-Regular"

    // MARK: - 字号

    /// 译文字号相对原文行高的比例。Vision 给拉丁文的行框约为字号的 0.93 倍，中日文方块字的可见高度
    /// 约为字号的 0.9 倍，所以 1.0 时译文看起来与原文同大。
    public static let fontScaleOfLineHeight: CGFloat = 1.0
    /// 缩到基准的这个比例以下就不再缩字，改为把框向下加高。
    public static let minimumFontScale: CGFloat = 0.6
    /// 框最多加高到原高的这个倍数（再高会盖住下面的内容）。
    public static let maximumGrowth: CGFloat = 2.5

    public struct Layout: Equatable, Sendable {
        public var rect: CGRect
        public var fontSize: CGFloat
    }

    /// 一个块周围可用的空间：向右能扩到最近的「同一行高范围内、位于右侧」的块（或图像右边）；
    /// 向下能扩到最近的「横向有重叠、位于下方」的块（或图像底边）。留 6px 间隙。
    public static func freeSpace(for rect: CGRect, among others: [CGRect], imageSize: CGSize) -> (maxWidth: CGFloat, maxHeight: CGFloat) {
        let gap: CGFloat = 6
        var rightLimit = imageSize.width
        var bottomLimit = imageSize.height
        for other in others where other != rect {
            let verticalOverlap = min(rect.maxY, other.maxY) - max(rect.minY, other.minY)
            if verticalOverlap > 0, other.minX >= rect.maxX - 1 {
                rightLimit = min(rightLimit, other.minX - gap)
            }
            let horizontalOverlap = min(rect.maxX, other.maxX) - max(rect.minX, other.minX)
            if horizontalOverlap > 0, other.minY >= rect.maxY - 1 {
                bottomLimit = min(bottomLimit, other.minY - gap)
            }
        }
        return (max(rect.width, rightLimit - rect.minX), max(rect.height, bottomLimit - rect.minY))
    }

    /// 统一字号的排版：字号由原文行高决定（不由框高决定）。译文装不下时按顺序：
    /// ① 向右借用空白（到 `maxWidth`）② 向下加高（到 `maxHeight`、原高 2.5 倍或图像底边）③ 逐步缩字到下限。
    /// `maxWidth`/`maxHeight` 由 `freeSpace` 给出，不传则只受图像边界限制。
    public static func layout(text: String, in original: CGRect, lineHeight: CGFloat, imageSize: CGSize,
                              maxWidth: CGFloat? = nil, maxHeight explicitMaxHeight: CGFloat? = nil) -> Layout {
        // Vision 的框贴着字形，原文的上伸部/降部/字距会从译文块边缘漏出来：按字号外扩一圈再盖。
        let rect = original
            .insetBy(dx: -lineHeight * 0.12, dy: -lineHeight * 0.14)
            .intersection(CGRect(origin: .zero, size: imageSize))
        let base = max(minimumFontSize, lineHeight * fontScaleOfLineHeight)
        let floor = max(minimumFontSize, base * minimumFontScale)

        // ① 向右：单行放得下就拉成单行；放不下就用满可借的宽度减少换行。
        let widthLimit = min(imageSize.width - rect.minX, max(rect.width, maxWidth ?? rect.width))
        var boxWidth = rect.width
        let singleLine = singleLineWidth(for: text, fontSize: base) * 1.02 + 2 + padding * 2
        if singleLine > boxWidth {
            boxWidth = min(widthLimit, singleLine)
        }
        let textWidth = max(1, boxWidth - padding * 2)

        // ② 向下，③ 缩字。
        let growthCap = min(rect.height * maximumGrowth, imageSize.height - rect.minY)
        let maxHeight = max(rect.height, min(growthCap, explicitMaxHeight ?? growthCap))
        var size = base
        var needed = layoutHeight(for: text, fontSize: size, width: textWidth) + padding * 2
        while needed > maxHeight, size - 0.5 >= floor {
            size -= 0.5
            needed = layoutHeight(for: text, fontSize: size, width: textWidth) + padding * 2
        }
        let height = min(maxHeight, max(rect.height, needed))
        return Layout(rect: CGRect(x: rect.minX, y: rect.minY, width: boxWidth, height: height), fontSize: size)
    }

    /// 不换行时文字的宽度。
    public static func singleLineWidth(for text: String, fontSize: CGFloat) -> CGFloat {
        let line = CTLineCreateWithAttributedString(attributed(text, fontSize: fontSize, color: nil))
        return CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    }

    /// 能让 `text` 换行后装进 `rect` 的最大字号；上限为矩形高度（单行即整块高）或 `maxFontSize`。
    public static func fittingFontSize(for text: String, in rect: CGRect, maxFontSize: CGFloat? = nil) -> CGFloat {
        let available = CGSize(width: max(1, rect.width - padding * 2), height: max(1, rect.height - padding * 2))
        var low = minimumFontSize
        var high = max(minimumFontSize, min(available.height, maxFontSize ?? available.height))
        guard fits(text, size: low, in: available) else { return low }
        // 二分：精确到 0.5pt 就够了。
        while high - low > 0.5 {
            let mid = (low + high) / 2
            if fits(text, size: mid, in: available) { low = mid } else { high = mid }
        }
        return low
    }

    /// 单行译文的行高倍数（紧凑，让它装进原文那一行的框）；多行段落的行高倍数（可读性）。
    public static let singleLineHeightMultiple: CGFloat = 1.08
    public static let paragraphLineHeightMultiple: CGFloat = 1.3

    /// 这段文字在给定宽度、字号下是否一行放得下。渲染器与排版都用它决定行高倍数，两边才一致。
    public static func fitsOnOneLine(_ text: String, fontSize: CGFloat, width: CGFloat) -> Bool {
        // 留 2% 余量：CoreText 实际排版比排印宽度略宽时会意外换行，第二行装不下就整段消失。
        singleLineWidth(for: text, fontSize: fontSize) * 1.02 + 1 <= width
    }

    /// 排好版的文字所需高度（用于在矩形内垂直居中）。
    public static func layoutHeight(for text: String, fontSize: CGFloat, width: CGFloat) -> CGFloat {
        let single = fitsOnOneLine(text, fontSize: fontSize, width: width)
        let framesetter = CTFramesetterCreateWithAttributedString(attributed(text, fontSize: fontSize, color: nil, singleLine: single))
        let size = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter, CFRange(location: 0, length: 0), nil,
            CGSize(width: max(1, width), height: .greatestFiniteMagnitude), nil
        )
        return size.height
    }

    private static func fits(_ text: String, size: CGFloat, in available: CGSize) -> Bool {
        let single = fitsOnOneLine(text, fontSize: size, width: available.width)
        let framesetter = CTFramesetterCreateWithAttributedString(attributed(text, fontSize: size, color: nil, singleLine: single))
        var fitRange = CFRange()
        let needed = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter, CFRange(location: 0, length: 0), nil,
            CGSize(width: available.width, height: .greatestFiniteMagnitude), &fitRange
        )
        return fitRange.length >= (text as NSString).length && needed.height <= available.height
    }

    public static func attributed(_ text: String, fontSize: CGFloat, color: CGColor?, singleLine: Bool = false) -> NSAttributedString {
        let font = CTFontCreateWithName(fontName as CFString, fontSize, nil)
        let paragraph = NSMutableParagraphStyle()
        let lineHeight = fontSize * (singleLine ? singleLineHeightMultiple : paragraphLineHeightMultiple)
        paragraph.minimumLineHeight = lineHeight
        paragraph.maximumLineHeight = lineHeight
        paragraph.lineBreakMode = .byWordWrapping
        var attributes: [NSAttributedString.Key: Any] = [.font: font, .paragraphStyle: paragraph]
        if let color { attributes[.foregroundColor] = color }
        return NSAttributedString(string: text, attributes: attributes)
    }

    // MARK: - 颜色

    /// 底色：取 `rect`（像素坐标，原点左上）外扩 2px 的一圈像素平均色；采不到就回退白色。
    public static func backgroundColor(around rect: CGRect, in image: CGImage) -> RGBAColor {
        let ring: CGFloat = 2
        let outer = rect.insetBy(dx: -ring, dy: -ring).integral
            .intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard outer.width >= 3, outer.height >= 3, let pixels = ImagePixels(image: image, rect: outer) else {
            return RGBAColor(red: 1, green: 1, blue: 1)
        }
        // 取各通道的中位数而不是均值：环里偶尔混进相邻文字或边框的像素，均值会被拉偏，中位数不会。
        var rs: [Double] = [], gs: [Double] = [], bs: [Double] = []
        for y in 0..<pixels.height {
            for x in 0..<pixels.width {
                let onRing = x < Int(ring) || y < Int(ring) || x >= pixels.width - Int(ring) || y >= pixels.height - Int(ring)
                guard onRing else { continue }
                let p = pixels[x, y]
                rs.append(p.r); gs.append(p.g); bs.append(p.b)
            }
        }
        guard !rs.isEmpty else { return RGBAColor(red: 1, green: 1, blue: 1) }
        func median(_ v: [Double]) -> Double { let s = v.sorted(); return s[s.count / 2] }
        return RGBAColor(red: median(rs), green: median(gs), blue: median(bs))
    }

    /// 字色：按底色相对明度选黑或白。
    public static func textColor(on background: RGBAColor) -> RGBAColor {
        background.relativeLuminance > 0.45
            ? RGBAColor(red: 0.08, green: 0.08, blue: 0.08)
            : RGBAColor(red: 0.98, green: 0.98, blue: 0.98)
    }
}

public extension RGBAColor {
    /// `#RRGGBB`（alpha 为 1 时）或 `#RRGGBBAA`。
    var hexString: String {
        func hex(_ v: Double) -> String { String(format: "%02X", Int((min(1, max(0, v)) * 255).rounded())) }
        let rgb = hex(red) + hex(green) + hex(blue)
        return "#" + (alpha >= 0.999 ? rgb : rgb + hex(alpha))
    }

    /// WCAG 相对明度（0 黑 ～ 1 白）。
    var relativeLuminance: Double {
        func linear(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }
}

/// 把图像的一块区域读成 RGBA 像素数组（sRGB、8 位、非预乘），供采样用。
struct ImagePixels {
    let width: Int
    let height: Int
    private let data: [UInt8]

    init?(image: CGImage, rect: CGRect) {
        guard let crop = image.cropping(to: rect) else { return nil }
        let w = crop.width, h = crop.height
        var buffer = [UInt8](repeating: 0, count: w * h * 4)
        let ok = buffer.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(
                data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
            ) else { return false }
            context.draw(crop, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard ok else { return nil }
        width = w
        height = h
        data = buffer
    }

    subscript(x: Int, y: Int) -> (r: Double, g: Double, b: Double) {
        let i = (y * width + x) * 4
        return (Double(data[i]) / 255, Double(data[i + 1]) / 255, Double(data[i + 2]) / 255)
    }
}
