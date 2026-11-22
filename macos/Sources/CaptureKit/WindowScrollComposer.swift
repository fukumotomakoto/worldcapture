import CoreGraphics

/// 全窗口滚动长图：先确认「真正在滚动的正文矩形」，再只拼正文，标题栏从首帧取一次放在顶部。
///
/// 为什么单独做：旧实现只按行带裁切、横向保留整窗宽度，固定侧栏的像素留在每一帧里，
/// 拼出来侧栏沿长图一段段重复；行带检测在「变化行太短 / 找不到 / 整高都在变」时统一返回 nil，
/// 调用方又把整帧交给拼接器，标题栏也跟着每帧重复（2026-11-22 长图重复界面修正报告）。
///
/// 默认输出 = **正文模式**：标题栏（裁到正文同宽）一次 + 连续正文；固定侧栏与底部输入框不进长图。
public enum WindowScrollRegion {
    /// 检测结果。三种状态分开，调用方据此选择安全的行为，不再把「证据不足」当成「整窗都在滚」。
    public enum Detection: Equatable, Sendable {
        /// 确认的正文矩形（图像像素，左上原点）。
        case body(CGRect)
        /// 整个窗口都在滚动（没有可分离的固定界面）。
        case wholeWindow
        /// 无法可靠判断：调用方应提示改用区域滚动截图。
        case undetermined(Reason)
    }

    public enum Reason: Equatable, Sendable {
        /// 两帧几乎没有变化（没滚动、已到底，或滚轮落在了不可滚动的地方）。
        case noMotion
        /// 变化区域太小，像是光标、加载提示之类的局部变化。
        case tooSmall
        /// 有几块区域在变，但移动量不一致（各自独立滚动），不知道用户要哪一块。
        case independentColumns
    }

    static let pixelThreshold = 22

    /// 用滚动前后两帧找出正文矩形。
    ///
    /// - 横向：统计每列「有变化的行数」，把间隔不超过 6% 宽度的变化列合成一簇（保留正文里的缩进与
    ///   段内留白）；最强的一簇是正文。若还有别的大簇，检查它们的纵向位移是否与正文一致：
    ///   一致（同步滚动的多列）就连同中间留白一起并入，不一致就判为独立滚动，交给用户框选。
    ///   窄于 3% 宽度的簇（滚动条、闪烁光标）当噪声忽略。
    /// - 纵向：在正文列范围内取首个到末个变化行（**不是最长连续段**——段间大留白不会把正文切断），
    ///   再向上/向下吞并与正文背景同色的空白行，止于标题栏、输入框的边界。
    public static func detect(_ a: CGImage, _ b: CGImage) -> Detection {
        guard a.width == b.width, a.height == b.height,
              let ga = GrayImage(cgImage: a), let gb = GrayImage(cgImage: b) else { return .undetermined(.noMotion) }
        let w = ga.width, h = ga.height
        guard w > 8, h > 8 else { return .undetermined(.noMotion) }

        // 1) 每列有变化的行数（抽样）。
        let sy = max(1, h / 700)
        var colChanged = [Int](repeating: 0, count: w)
        var sampledRows = 0
        for y in stride(from: 0, to: h, by: sy) {
            sampledRows += 1
            let base = y * w
            for x in 0..<w where abs(Int(ga.pixels[base + x]) - Int(gb.pixels[base + x])) >= pixelThreshold {
                colChanged[x] += 1
            }
        }
        let colMin = max(1, sampledRows / 100)
        let clusters = changeClusters(colChanged, minCount: colMin, mergeGap: max(2, w * 6 / 100), minWidth: max(2, w * 3 / 100))
        guard let main = clusters.max(by: { $0.mass < $1.mass }) else { return .undetermined(.noMotion) }

        // 2) 其他大簇：同步滚动才并入。
        var x0 = main.start, x1 = main.end
        let others = clusters.filter { $0.start != main.start && $0.mass * 4 >= main.mass }
        if !others.isEmpty {
            // 每块只在自己「有变化的行范围」内比对位移，固定的标题栏、输入框不参与（它们两帧一样，会把结果拉向 0）。
            func blockShift(_ c: Cluster) -> TexturedAlignment.Result? {
                guard let rows = changedRowSpan(ga, gb, x0: c.start, x1: c.end),
                      let sa = ga.sub(x0: c.start, x1: c.end, y0: rows.0, y1: rows.1),
                      let sb = gb.sub(x0: c.start, x1: c.end, y0: rows.0, y1: rows.1) else { return nil }
                return TexturedAlignment.shift(previous: sa, current: sb)
            }
            guard let mainShift = blockShift(main)?.shift else {
                return .undetermined(.independentColumns)
            }
            for other in others {
                guard let s = blockShift(other),
                      abs(s.shift - mainShift) <= 2, s.score <= 0.06 else {
                    return .undetermined(.independentColumns)
                }
                x0 = min(x0, other.start)
                x1 = max(x1, other.end)
            }
        }

        // 3) 正文列范围内的首、末变化行。
        guard let span = changedRowSpan(ga, gb, x0: x0, x1: x1) else { return .undetermined(.noMotion) }
        var y0 = span.0, y1 = span.1

        // 4) 吞并与正文背景同色的空白行（两帧都是空白），止于有纹理或颜色不同的行（标题栏、输入框）。
        if let background = dominantValue(ga, x0: x0, x1: x1, y0: y0, y1: y1) {
            func blank(_ y: Int) -> Bool {
                isUniformRow(ga, y: y, x0: x0, x1: x1, value: background) && isUniformRow(gb, y: y, x0: x0, x1: x1, value: background)
            }
            while y0 > 0, blank(y0 - 1) { y0 -= 1 }
            while y1 < h, blank(y1) { y1 += 1 }
            // 横向同理：正文容器两侧的空白边距也属于正文，止于侧栏等颜色不同的区域。
            func blankColumn(_ x: Int) -> Bool {
                isUniformColumn(ga, x: x, y0: y0, y1: y1, value: background) && isUniformColumn(gb, x: x, y0: y0, y1: y1, value: background)
            }
            while x0 > 0, blankColumn(x0 - 1) { x0 -= 1 }
            while x1 < w, blankColumn(x1) { x1 += 1 }
        }

        // 5) 判定。
        let rect = CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
        guard rect.width >= Double(w) * 0.15, rect.height >= Double(h) * 0.2 else { return .undetermined(.tooSmall) }
        if x0 <= w * 3 / 100, x1 >= w * 97 / 100, y0 <= h * 3 / 100, y1 >= h * 97 / 100 { return .wholeWindow }
        return .body(rect)
    }

    struct Cluster { var start: Int; var end: Int; var mass: Int }

    /// 列范围 `[x0, x1)` 内首个到末个「有变化」的行，返回 `[y0, y1)`。
    static func changedRowSpan(_ ga: GrayImage, _ gb: GrayImage, x0: Int, x1: Int) -> (Int, Int)? {
        let w = ga.width
        let sx = max(1, (x1 - x0) / 500)
        var sampledCols = 0
        for _ in stride(from: x0, to: x1, by: sx) { sampledCols += 1 }
        let rowMin = max(1, sampledCols / 100)
        var firstRow: Int?
        var lastRow: Int?
        for y in 0..<ga.height {
            let base = y * w
            var count = 0
            for x in stride(from: x0, to: x1, by: sx) where abs(Int(ga.pixels[base + x]) - Int(gb.pixels[base + x])) >= pixelThreshold {
                count += 1
            }
            if count >= rowMin {
                if firstRow == nil { firstRow = y }
                lastRow = y
            }
        }
        guard let first = firstRow, let last = lastRow else { return nil }
        return (first, last + 1)
    }

    /// 把计数 ≥ minCount 的位置合成簇：间隔 ≤ mergeGap 的合并；宽度 < minWidth 的丢弃。
    static func changeClusters(_ counts: [Int], minCount: Int, mergeGap: Int, minWidth: Int) -> [Cluster] {
        var clusters: [Cluster] = []
        var current: Cluster?
        var lastHit = -1
        for (x, c) in counts.enumerated() where c >= minCount {
            if var cur = current, x - lastHit - 1 <= mergeGap {
                cur.end = x + 1
                cur.mass += c
                current = cur
            } else {
                if let cur = current { clusters.append(cur) }
                current = Cluster(start: x, end: x + 1, mass: c)
            }
            lastHit = x
        }
        if let cur = current { clusters.append(cur) }
        return clusters.filter { $0.end - $0.start >= minWidth }
    }

    /// 区域内出现最多的灰度值（正文背景色）。
    static func dominantValue(_ g: GrayImage, x0: Int, x1: Int, y0: Int, y1: Int) -> UInt8? {
        var histogram = [Int](repeating: 0, count: 256)
        let sx = max(1, (x1 - x0) / 200), sy = max(1, (y1 - y0) / 200)
        for y in stride(from: y0, to: y1, by: sy) {
            for x in stride(from: x0, to: x1, by: sx) { histogram[Int(g.pixels[y * g.width + x])] += 1 }
        }
        guard let peak = histogram.indices.max(by: { histogram[$0] < histogram[$1] }), histogram[peak] > 0 else { return nil }
        return UInt8(peak)
    }

    static func isUniformColumn(_ g: GrayImage, x: Int, y0: Int, y1: Int, value: UInt8) -> Bool {
        let sy = max(1, (y1 - y0) / 300)
        for y in stride(from: y0, to: y1, by: sy) where abs(Int(g.pixels[y * g.width + x]) - Int(value)) > 4 { return false }
        return true
    }

    static func isUniformRow(_ g: GrayImage, y: Int, x0: Int, x1: Int, value: UInt8) -> Bool {
        let base = y * g.width
        let sx = max(1, (x1 - x0) / 300)
        for x in stride(from: x0, to: x1, by: sx) where abs(Int(g.pixels[base + x]) - Int(value)) > 4 { return false }
        return true
    }
}

/// 只用「有内容的行」估计纵向位移，覆盖整个重叠区。
///
/// 旧拼接器只比对固定位置的 160 行：正文稀疏、段间留白大时，这 160 行可能整段空白，
/// 任何位移都同样「匹配」，于是判成没滚动或错位。这里只统计至少一帧有纹理的行。
enum TexturedAlignment {
    struct Result { let shift: Int; let score: Double; let rows: Int }

    /// 至少要比对这么多有纹理的行才算有证据。
    static let minimumEvidenceRows = 6

    static func texturedRows(_ g: GrayImage, columns: (Int, Int)) -> [Bool] {
        let (x0, x1) = columns
        let sx = max(1, (x1 - x0) / 200)
        return (0..<g.height).map { y in
            let base = y * g.width
            var lo = 255, hi = 0
            for x in stride(from: x0, to: x1, by: sx) {
                let v = Int(g.pixels[base + x])
                lo = min(lo, v); hi = max(hi, v)
                if hi - lo >= 30 { return true }
            }
            return false
        }
    }

    /// `current` 相对 `previous` 向下滚动了多少行（previous 第 i+d 行 ≈ current 第 i 行）。
    /// 分数相同（±0.002）时取更接近 `hint` 的位移。
    static func shift(previous a: GrayImage, current b: GrayImage, columns: (Int, Int)? = nil,
                      hint: Int? = nil, maxShift: Int? = nil) -> Result? {
        guard a.width == b.width, a.height == b.height, a.width > 0 else { return nil }
        let cols = columns ?? (0, a.width)
        let ta = texturedRows(a, columns: cols), tb = texturedRows(b, columns: cols)
        let h = a.height
        let sx = max(1, (cols.1 - cols.0) / 160)
        let rowStep = max(1, h / 400)
        var best: Result?
        for d in 0...min(h - 1, maxShift ?? h - 1) {
            var sum = 0, count = 0, rows = 0
            var i = 0
            while i < h - d {
                if tb[i] || ta[i + d] {
                    rows += 1
                    let ra = (i + d) * a.width, rb = i * b.width
                    for x in stride(from: cols.0, to: cols.1, by: sx) {
                        sum += abs(Int(a.pixels[ra + x]) - Int(b.pixels[rb + x]))
                        count += 1
                    }
                }
                i += rowStep
            }
            guard rows >= minimumEvidenceRows, count > 0 else { continue }
            let score = Double(sum) / (Double(count) * 255)
            if let current = best {
                let better = score < current.score - 0.002
                let tie = abs(score - current.score) <= 0.002
                let closer = hint.map { abs(d - $0) < abs(current.shift - $0) } ?? false
                if better || (tie && closer) { best = Result(shift: d, score: score, rows: rows) }
            } else {
                best = Result(shift: d, score: score, rows: rows)
            }
        }
        return best
    }
}

/// 正文模式的拼接与合成：每帧统一裁成同一个正文矩形，按纹理行对齐，最后把首帧标题栏
/// （裁到正文同宽）拼在顶部。窗口尺寸中途变化的帧返回 `.invalid`，调用方停止并标为不完整。
public struct WindowScrollComposer {
    public let body: CGRect
    public let frameWidth: Int
    public let frameHeight: Int
    let header: CGImage?
    private var frames: [CGImage] = []
    private var grays: [GrayImage] = []
    private var offsets: [Int] = []
    public private(set) var stitchedHeight = 0
    /// 下一帧预期的位移（像素），用于在多个同样好的匹配里挑最合理的一个。
    public var expectedShift: Int?

    public var frameCount: Int { frames.count }

    /// - Parameters:
    ///   - firstFrame: 首帧（完整窗口）。
    ///   - body: 确认的正文矩形（图像像素）；整窗滚动时传整帧矩形。
    ///   - includeHeader: 是否把正文上方的固定标题栏（裁到正文同宽）拼在顶部一次。
    public init?(firstFrame: CGImage, body: CGRect, includeHeader: Bool = true) {
        let bounds = CGRect(x: 0, y: 0, width: firstFrame.width, height: firstFrame.height)
        let rect = body.integral.intersection(bounds)
        guard rect.width >= 1, rect.height >= 1 else { return nil }
        self.body = rect
        frameWidth = firstFrame.width
        frameHeight = firstFrame.height
        if includeHeader, rect.minY >= 1 {
            header = firstFrame.cropping(to: CGRect(x: rect.minX, y: 0, width: rect.width, height: rect.minY))
        } else {
            header = nil
        }
        guard append(firstFrame) == .first else { return nil }
    }

    /// 追加一帧完整窗口截图（内部裁成正文）。
    @discardableResult
    public mutating func append(_ frame: CGImage) -> ScrollStitcher.AppendResult {
        guard frame.width == frameWidth, frame.height == frameHeight,
              let cropped = frame.cropping(to: body), let gray = GrayImage(cgImage: cropped) else { return .invalid }
        guard let previous = grays.last else {
            frames.append(cropped); grays.append(gray); offsets.append(0)
            stitchedHeight = gray.height
            return .first
        }
        guard let alignment = TexturedAlignment.shift(previous: previous, current: gray, hint: expectedShift) else {
            return .noOverlap // 重叠区里没有任何内容可比对（整屏空白），无法确认位置
        }
        if alignment.score > 0.08 { return .noOverlap }
        if alignment.shift < 2 { return .duplicate }
        if alignment.shift < max(3, gray.height / 20), alignment.score > 0.045 { return .duplicate }
        frames.append(cropped)
        grays.append(gray)
        offsets.append(offsets[offsets.count - 1] + alignment.shift)
        stitchedHeight = offsets[offsets.count - 1] + gray.height
        return .appended(newRows: alignment.shift)
    }

    /// 标题栏（如有）+ 连续正文。所有部分同宽。
    public func makeImage() -> CGImage? {
        guard !frames.isEmpty else { return nil }
        let width = Int(body.width)
        let headerHeight = header?.height ?? 0
        if let header, header.width != width { return nil }
        let total = headerHeight + stitchedHeight
        guard total > 0, let context = CGContext(
            data: nil, width: width, height: total, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        // CoreGraphics 原点在左下：自顶向下放置。
        if let header {
            context.draw(header, in: CGRect(x: 0, y: total - headerHeight, width: width, height: headerHeight))
        }
        for (index, frame) in frames.enumerated() {
            let top = headerHeight + offsets[index]
            context.draw(frame, in: CGRect(x: 0, y: total - top - frame.height, width: width, height: frame.height))
        }
        return context.makeImage()
    }
}

extension GrayImage {
    /// 取 `[x0, x1) × [y0, y1)` 子区域。
    func sub(x0: Int, x1: Int, y0: Int, y1: Int) -> GrayImage? {
        guard x0 >= 0, y0 >= 0, x1 <= width, y1 <= height, x1 > x0, y1 > y0 else { return nil }
        var out = [UInt8]()
        out.reserveCapacity((x1 - x0) * (y1 - y0))
        for y in y0..<y1 { out.append(contentsOf: pixels[(y * width + x0)..<(y * width + x1)]) }
        return GrayImage(width: x1 - x0, height: y1 - y0, pixels: out)
    }
}
