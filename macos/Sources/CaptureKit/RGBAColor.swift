import CoreGraphics

/// 与平台 UI 解耦的标注颜色：以 `#RRGGBB` 或 `#RRGGBBAA` 十六进制存储，便于跨平台工程文件复用。
public struct RGBAColor: Equatable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double
    public let alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// 解析 `#RGB`、`#RRGGBB`、`#RRGGBBAA`；无法解析时回退到默认强调色（红）。
    public init(hex: String) {
        var string = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if string.hasPrefix("#") { string.removeFirst() }

        func component(_ slice: Substring) -> Double {
            Double(Int(slice, radix: 16) ?? 0) / 255
        }

        switch string.count {
        case 3:
            let chars = Array(string)
            red = component(Substring(String(repeating: chars[0], count: 2)))
            green = component(Substring(String(repeating: chars[1], count: 2)))
            blue = component(Substring(String(repeating: chars[2], count: 2)))
            alpha = 1
        case 6, 8:
            let chars = Array(string)
            red = component(string[string.startIndex..<string.index(string.startIndex, offsetBy: 2)])
            green = component(Substring(String(chars[2...3])))
            blue = component(Substring(String(chars[4...5])))
            alpha = string.count == 8 ? component(Substring(String(chars[6...7]))) : 1
        default:
            red = 1; green = 0.231; blue = 0.188; alpha = 1 // #FF3B30
        }
    }

    public var cgColor: CGColor {
        CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }
}
