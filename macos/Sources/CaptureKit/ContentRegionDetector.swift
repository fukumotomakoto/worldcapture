import CoreGraphics

/// 从两帧滚动前后的画面中，找出「真正在滚动的内容区域」。
///
/// 全窗口滚动长图的老大难：整窗里有大量**固定**部分（浏览器标签栏/地址栏、左右侧栏、留白），
/// 只有中间一栏真正滚动。把整窗逐帧拼接会把固定部分重复叠加成一坨乱图（GoFullPage 靠渲染 DOM 规避）。
/// 这里用「两帧差分」定位变化区域：固定部分两帧几乎相同 → 被排除；滚动列每行都变 → 被保留。
public enum ContentRegionDetector {
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
