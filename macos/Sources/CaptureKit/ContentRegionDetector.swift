import CoreGraphics

/// 从两帧滚动前后的画面中，找出「真正在滚动的内容区域」。
///
/// 全窗口滚动长图的老大难：整窗里有大量**固定**部分（浏览器标签栏/地址栏、左右侧栏、留白），
/// 只有中间一栏真正滚动。把整窗逐帧拼接会把固定部分重复叠加成一坨乱图（GoFullPage 靠渲染 DOM 规避）。
/// 这里用「两帧差分」定位变化区域：固定部分两帧几乎相同 → 被排除；滚动列每行都变 → 被保留。
public enum ContentRegionDetector {
    /// 找出「滚动内容的纵向行带」`[y0, y1)`（像素，**左上角原点**）：中间随滚动逐行变化的区域。
    /// `y0` 之上是**固定顶带**（浏览器工具栏 / 吸顶导航），`y1` 之下是**固定底带**（固定页脚 / 广告）。
    ///
    /// 这是全窗口长图的正确切分方式：只对「滚动行带」逐帧拼接（固定带不参与，避免被重复叠加），
    /// 再由调用方把 frame0 的固定顶/底带各拼回一次 —— 得到「顶栏一次 + 全宽长内容 + 底栏一次」，
    /// 逼近 GoFullPage 的取景。**按行分离、保留全宽**，从而支持左/中/右多列同时滚动的页面。
    ///
    /// 近乎整高都在变（无固定带可分离，如整窗滚动的原生视图）时返回 nil，调用方回退为整帧拼接。
    public static func scrollingRowBand(
        _ a: CGImage,
        _ b: CGImage,
        threshold: Int = 22,
        lineFraction: Double = 0.05
    ) -> (Int, Int)? {
        guard a.width == b.width, a.height == b.height,
              let ga = GrayImage(cgImage: a), let gb = GrayImage(cgImage: b) else { return nil }
        let w = ga.width, h = ga.height
        guard w > 0, h > 0 else { return nil }

        let stepX = max(1, w / 500)
        let stepY = max(1, h / 800)
        var rowChanged = [Int](repeating: 0, count: h)
        let sampledCols = (w + stepX - 1) / stepX
        for y in stride(from: 0, to: h, by: stepY) {
            let base = y * w
            for x in stride(from: 0, to: w, by: stepX) {
                if abs(Int(ga.pixels[base + x]) - Int(gb.pixels[base + x])) >= threshold { rowChanged[y] += 1 }
            }
        }

        // 某行「变化采样点」占比超过阈值才算滚动行（抗噪：固定带/零星变化不计）。
        let rowMin = Int(Double(sampledCols) * lineFraction)
        // 取变化行的最长连续段 = 中间滚动带（跳过固定顶带/底带，且容忍带内的小静止行）。
        guard let (y0, y1) = longestRun(rowChanged, step: stepY, limit: h, minCount: rowMin) else { return nil }
        // 滚动带太薄（误检）→ 回退。
        guard y1 - y0 >= Int(Double(h) * 0.25) else { return nil }
        // 几乎整高都在变（没有可分离的固定带）→ 回退整帧拼接。
        if y0 <= Int(Double(h) * 0.02), y1 >= Int(Double(h) * 0.98) { return nil }
        return (y0, y1)
    }

    /// 找出「真正在滚动的那一列内容」的水平范围 `[x0, x1)`（像素）。用于把拼接**对齐**限制在
    /// 滚动列上——固定/吸顶侧栏（Yahoo 的左导航/右侧栏）在滚动时不动，若纳入整宽相关性会在
    /// d=0 制造竞争峰、把位移估计带偏 → 误判「未滚动」提前结束。只用最长的连续变化列估计位移，
    /// 才能得到正确滚动量（ShareX 用固定 `ignoreSideOffset` 只避滚动条，挡不住宽侧栏，故这里按检测）。
    /// 变化列近乎整宽（整宽都滚，如 Amazon）返回 nil，调用方回退为默认排除（仅避滚动条）。
    public static func scrollingColumnRange(
        _ a: CGImage,
        _ b: CGImage,
        threshold: Int = 22,
        lineFraction: Double = 0.05
    ) -> (Int, Int)? {
        guard a.width == b.width, a.height == b.height,
              let ga = GrayImage(cgImage: a), let gb = GrayImage(cgImage: b) else { return nil }
        let w = ga.width, h = ga.height
        guard w > 0, h > 0 else { return nil }

        let stepX = max(1, w / 800)
        let stepY = max(1, h / 500)
        var colChanged = [Int](repeating: 0, count: w)
        var sampledRows = 0
        for y in stride(from: 0, to: h, by: stepY) {
            sampledRows += 1
            let base = y * w
            for x in stride(from: 0, to: w, by: stepX) {
                if abs(Int(ga.pixels[base + x]) - Int(gb.pixels[base + x])) >= threshold { colChanged[x] += 1 }
            }
        }

        let colMin = Int(Double(sampledRows) * lineFraction)
        guard let (x0, x1) = longestRun(colChanged, step: stepX, limit: w, minCount: colMin) else { return nil }
        // 太窄（误检）→ 回退。近乎整宽（整宽都滚）→ 回退让调用方用默认排除。
        guard x1 - x0 >= Int(Double(w) * 0.15) else { return nil }
        if x0 <= Int(Double(w) * 0.03), x1 >= Int(Double(w) * 0.97) { return nil }
        return (x0, x1)
    }

    /// 返回发生变化的内容区域（像素坐标，**左上角原点**，可直接用于 `CGImage.cropping(to:)`）。
    /// 变化不足或近乎整帧时返回 nil（调用方回退为整窗）。
    public static func changedRect(
        _ a: CGImage,
        _ b: CGImage,
        threshold: Int = 22,
        lineFraction: Double = 0.08
    ) -> CGRect? {
        guard a.width == b.width, a.height == b.height,
              let ga = GrayImage(cgImage: a), let gb = GrayImage(cgImage: b) else { return nil }

        let w = ga.width
        let h = ga.height
        guard w > 0, h > 0 else { return nil }

        // 抽样控制开销（长图很高，无需逐像素）。
        let stepX = max(1, w / 500)
        let stepY = max(1, h / 800)

        var colChanged = [Int](repeating: 0, count: w)
        var rowChanged = [Int](repeating: 0, count: h)
        let sampledCols = (w + stepX - 1) / stepX
        var sampledRows = 0

        for y in stride(from: 0, to: h, by: stepY) {
            sampledRows += 1
            let base = y * w
            for x in stride(from: 0, to: w, by: stepX) {
                let d = abs(Int(ga.pixels[base + x]) - Int(gb.pixels[base + x]))
                if d >= threshold {
                    colChanged[x] += 1
                    rowChanged[y] += 1
                }
            }
        }

        // 某列/行「变化的抽样点」占比超过阈值，才算属于滚动区域（抗噪：忽略零星变化）。
        let colMin = Int(Double(sampledRows) * lineFraction)
        let rowMin = Int(Double(sampledCols) * lineFraction)

        // 取「变化列/行的最长连续段」而非简单首尾跨度：这样即使侧栏有个动态广告也在变，
        // 主滚动列（最长的连续变化块）仍能被正确挑出，不会把范围撑到整帧。
        guard let (x0, x1) = longestRun(colChanged, step: stepX, limit: w, minCount: colMin),
              let (y0, y1) = longestRun(rowChanged, step: stepY, limit: h, minCount: rowMin) else {
            return nil
        }

        let rect = CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
        // 太小（误检）或近乎整帧（没有可裁的固定部分）都回退。
        guard rect.width >= Double(w) * 0.15, rect.height >= Double(h) * 0.25 else { return nil }
        if rect.width >= Double(w) * 0.92, rect.height >= Double(h) * 0.92 { return nil }
        return rect
    }

    /// 两帧是否已「稳定」（近乎一致）。用于滚动后**自适应等待**：画面停稳（滚动惯性结束、
    /// 懒加载图片渲染完成）即可立即继续，取代固定的 500ms 死等——静止页几乎瞬间返回，
    /// 仅懒加载/动画页才多等。`tolerance` 为「变化采样点占比」的上限（默认 0.6%）。
    public static func isStable(
        _ a: CGImage,
        _ b: CGImage,
        threshold: Int = 22,
        tolerance: Double = 0.006
    ) -> Bool {
        guard a.width == b.width, a.height == b.height,
              let ga = GrayImage(cgImage: a), let gb = GrayImage(cgImage: b) else { return false }
        let w = ga.width, h = ga.height
        guard w > 0, h > 0 else { return false }

        let stepX = max(1, w / 300)
        let stepY = max(1, h / 300)
        var changed = 0, total = 0
        for y in stride(from: 0, to: h, by: stepY) {
            let base = y * w
            for x in stride(from: 0, to: w, by: stepX) {
                total += 1
                if abs(Int(ga.pixels[base + x]) - Int(gb.pixels[base + x])) >= threshold { changed += 1 }
            }
        }
        guard total > 0 else { return false }
        return Double(changed) / Double(total) <= tolerance
    }

    /// 找出计数数组中「≥ minCount」的最长连续段（按 step 抽样，容忍 ≤maxGap 个采样点的小间断），
    /// 返回 [lo, hi) 像素范围。
    private static func longestRun(_ counts: [Int], step: Int, limit: Int, minCount: Int, maxGap: Int = 3) -> (Int, Int)? {
        var bestLo = -1, bestHi = -1, bestLen = -1
        var curLo = -1, curHi = -1, gap = 0
        var i = 0
        while i < limit {
            if counts[i] >= minCount {
                if curLo < 0 { curLo = i }
                curHi = i
                gap = 0
            } else if curLo >= 0 {
                gap += 1
                if gap > maxGap {
                    if curHi - curLo > bestLen { bestLen = curHi - curLo; bestLo = curLo; bestHi = curHi }
                    curLo = -1; curHi = -1; gap = 0
                }
            }
            i += step
        }
        if curLo >= 0, curHi - curLo > bestLen { bestLen = curHi - curLo; bestLo = curLo; bestHi = curHi }
        guard bestLo >= 0 else { return nil }
        return (bestLo, min(limit, bestHi + step))
    }
}
