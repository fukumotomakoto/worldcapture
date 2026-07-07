import CoreGraphics

/// 灰度像素缓冲，行 0 约定为图像顶部。用于滚动截屏的纵向对齐计算。
public struct GrayImage: Equatable, Sendable {
    public let width: Int
    public let height: Int
    /// 行主序，长度 = width × height，行 0 为顶部。
    public var pixels: [UInt8]

    public init(width: Int, height: Int, pixels: [UInt8]) {
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    /// 将 `CGImage` 转为灰度缓冲（翻转上下，使行 0 对应图像顶部）。
    public init?(cgImage: CGImage) {
        let width = cgImage.width
        let height = cgImage.height
        guard width > 0, height > 0 else { return nil }

        var buffer = [UInt8](repeating: 0, count: width * height)
        let ok = buffer.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(
                data: raw.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return false }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard ok else { return nil }

        self.width = width
        self.height = height
        self.pixels = buffer
    }
}

/// 一次纵向对齐结果。
public struct VerticalAlignment: Equatable, Sendable {
    /// `b` 相对 `a` 向下滚动的像素行数。
    public let shift: Int
    /// 重叠区域的平均绝对差 / 255，越小越匹配。
    public let score: Double

    public init(shift: Int, score: Double) {
        self.shift = shift
        self.score = score
    }
}

/// 在 `[minShift, maxShift]` 内寻找使 `b`（从 `bandOrigin` 行起的一段）与 `a`（下移 d 行后）最匹配的 d。
///
/// 语义：滚动向下 d 行后，`a` 的第 `bandOrigin+d+i` 行 ≈ `b` 的第 `bandOrigin+i` 行。
/// 为控制开销，只比较从 `bandOrigin` 起的 `band` 行，并按 `columnStep` 抽样列。
/// `bandOrigin` 可避开顶部吸顶（sticky）页眉：页眉在滚动时不动，若从第 0 行比对，
/// 会让 d=0 误判为最佳匹配（“未滚动”），导致长截图过早结束。
///
/// `sideInset` 排除左右各若干列不参与比对（ShareX 的 `ignoreSideOffset` 同款做法）：
/// 滚动条、以及**固定/吸顶侧栏**在滚动时不动，若纳入比对会给 d=0 制造一个强匹配的
/// 竞争峰，把整宽相关性带偏 → 误判“未滚动”提前结束（Yahoo 那类左右固定、仅中列滚动的页面）。
/// 只用中间内容列估计位移，才能得到正确的滚动量。
public func bestVerticalShift(
    _ a: GrayImage,
    _ b: GrayImage,
    minShift: Int = 0,
    maxShift: Int? = nil,
    band: Int = 160,
    columnStep: Int = 4,
    bandOrigin: Int = 0,
    sideInset: Int = 0,
    columnRange: (Int, Int)? = nil
) -> VerticalAlignment? {
    guard a.width == b.width, a.width > 0, a.height > 0, b.height > 0 else { return nil }

    let width = a.width
    // 优先用显式的滚动列范围（避开宽侧栏）；否则用 sideInset 左右排除（仅避滚动条/窄边）。
    let xStart: Int
    let xEnd: Int
    if let range = columnRange {
        xStart = max(0, min(range.0, width - 1))
        xEnd = max(xStart + 1, min(range.1, width))
    } else {
        let inset = max(0, min(sideInset, width / 3))
        xStart = inset
        xEnd = width - inset
    }
    guard xStart < xEnd else { return nil }

    let origin = max(0, min(bandOrigin, b.height - 1))
    let upper = min(maxShift ?? (a.height - 1), a.height - 1)
    let lower = max(0, minShift)
    guard lower <= upper else { return nil }

    let step = max(1, columnStep)
    let minimumOverlapRows = 4

    var best: VerticalAlignment?
    for d in lower...upper {
        // b 取 [origin, origin+rows)；a 取 [origin+d, origin+d+rows)。
        let compareRows = min(band, min(b.height - origin, a.height - origin - d))
        guard compareRows >= minimumOverlapRows else { continue }

        var sum = 0
        var count = 0
        for i in 0..<compareRows {
            let aRow = (origin + d + i) * a.width
            let bRow = (origin + i) * b.width
            var x = xStart
            while x < xEnd {
                sum += abs(Int(a.pixels[aRow + x]) - Int(b.pixels[bRow + x]))
                count += 1
                x += step
            }
        }
        guard count > 0 else { continue }

        let score = Double(sum) / (Double(count) * 255.0)
        if best == nil || score < best!.score {
            best = VerticalAlignment(shift: d, score: score)
        }
    }
    return best
}

/// 累积滚动帧并拼接为一张长图。逐帧用 `bestVerticalShift` 求出新增行数，仅追加新增部分。
public struct ScrollStitcher {
    public struct Options: Sendable {
        /// 重叠匹配分数超过此阈值则视为无法对齐（跳变/内容突变）。
        public var matchThreshold: Double
        /// 小于此新增行数视为未滚动（重复帧）。
        public var minNewRows: Int
        public var band: Int
        public var columnStep: Int
        /// 对齐时只用的水平列范围 `[x0, x1)`（像素）。设为检测到的**滚动列**可避开固定/吸顶侧栏
        /// 干扰位移估计（Yahoo 那类页面）。为 nil 时回退到默认的左右排除（仅避滚动条/窄边）。
        public var alignColumns: (Int, Int)?
        /// 收尾防抖阈值：接近底部时页面只滚一点点（小位移），若此时匹配不够干净（分数 > 此值），
        /// 多半是橡皮筋回弹/半帧错位，判为到底、不追加，避免长图底部出现抖动接缝（ShareX 的
        /// “忽略最后一帧”同类思路）。仅作用于小位移帧，正常大位移的滚动帧不受影响。
        public var endCleanThreshold: Double

        public init(
            matchThreshold: Double = 0.08,
            minNewRows: Int = 2,
            band: Int = 160,
            columnStep: Int = 4,
            alignColumns: (Int, Int)? = nil,
            endCleanThreshold: Double = 0.045
        ) {
            self.matchThreshold = matchThreshold
            self.minNewRows = minNewRows
            self.band = band
            self.columnStep = columnStep
            self.alignColumns = alignColumns
            self.endCleanThreshold = endCleanThreshold
        }
    }

    public enum AppendResult: Equatable, Sendable {
        case first
        case appended(newRows: Int)
        case duplicate
        case noOverlap
        case invalid
    }

    public private(set) var frameCount = 0
    public private(set) var stitchedHeight = 0

    private var frames: [CGImage] = []
    private var grays: [GrayImage] = []
    private var shifts: [Int] = []
    private let options: Options

    public init(options: Options = Options()) {
        self.options = options
    }

    @discardableResult
    public mutating func append(_ frame: CGImage) -> AppendResult {
        guard let gray = GrayImage(cgImage: frame) else { return .invalid }

        guard let previous = grays.last else {
            frames.append(frame)
            grays.append(gray)
            shifts.append(0)
            frameCount = 1
            stitchedHeight = frame.height
            return .first
        }

        guard previous.width == gray.width else { return .invalid }
        // 从画面上方约 12% 处开始比对，跳过常见的吸顶页眉（搜索栏/导航条），
        // 避免静止页眉把对齐结果拉到 d=0 而误判为“未滚动”导致提前结束。
        let bandOrigin = max(0, Int(Double(gray.height) * 0.12))
        // 有检测到的滚动列就用它（避开宽的固定侧栏）；否则退回 ShareX 同款左右排除 max(50,宽/20)（仅避滚动条）。
        let sideInset = min(gray.width / 3, max(50, gray.width / 20))
        guard let alignment = bestVerticalShift(
            previous, gray,
            minShift: 0,
            maxShift: gray.height - 1,
            band: options.band,
            columnStep: options.columnStep,
            bandOrigin: bandOrigin,
            sideInset: sideInset,
            columnRange: options.alignColumns
        ) else { return .invalid }

        if alignment.score > options.matchThreshold { return .noOverlap }
        if alignment.shift < options.minNewRows { return .duplicate }

        // 收尾防抖：位移很小（接近底部）且匹配不干净 → 判为到底，不追加这半帧抖动。
        let smallShift = alignment.shift < max(options.minNewRows + 1, gray.height / 20)
        if smallShift, alignment.score > options.endCleanThreshold { return .duplicate }

        frames.append(frame)
        grays.append(gray)
        shifts.append(alignment.shift)
        frameCount += 1
        stitchedHeight += alignment.shift
        return .appended(newRows: alignment.shift)
    }

    public func makeImage() -> CGImage? {
        guard let first = frames.first else { return nil }
        let width = first.width
        let frameHeight = first.height
        let totalHeight = stitchedHeight
        guard totalHeight > 0 else { return nil }

        guard let context = CGContext(
            data: nil,
            width: width,
            height: totalHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        // 不翻转 CTM（避免逐帧上下镜像）。在左下角原点坐标系中，按各帧累计偏移自顶向下放置：
        // 顶部 = 高 y。累计偏移 o_k 越大，帧越靠下。
        var cumulativeOffset = 0
        for (index, frame) in frames.enumerated() {
            cumulativeOffset += shifts[index] // shifts[0] == 0
            let y = totalHeight - cumulativeOffset - frameHeight
            context.draw(frame, in: CGRect(x: 0, y: y, width: width, height: frameHeight))
        }
        return context.makeImage()
    }
}
