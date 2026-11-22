import CoreGraphics

/// 滚动截屏编排：反复「截当前帧 → 拼接 → 滚动一屏」，直到内容到底或达到帧数上限。
///
/// 真实的截图与滚动以闭包注入，因此编排与到底判定逻辑可独立单测，
/// 与 ScreenCaptureKit、CGEvent、Accessibility 等系统副作用解耦。
public struct ScrollCaptureEngine {
    public struct Options: Sendable {
        /// 安全上限，避免无法到底时无限滚动。
        public var maxFrames: Int
        /// 连续多少帧无新增内容即判定已到底。
        public var endRepeatThreshold: Int
        public var stitcher: ScrollStitcher.Options

        public init(
            maxFrames: Int = 80,
            endRepeatThreshold: Int = 2,
            stitcher: ScrollStitcher.Options = .init()
        ) {
            self.maxFrames = maxFrames
            self.endRepeatThreshold = endRepeatThreshold
            self.stitcher = stitcher
        }
    }

    /// 结束原因。只有 `.reachedEnd` 代表拼出了完整内容；其余都是「保留已拼部分、但不完整」。
    public enum EndReason: Equatable, Sendable {
        /// 连续多帧无新增内容：内容到底（正常结束）。
        case reachedEnd
        /// 新帧与已拼内容对不上（滚动跳跃过大等），减小步长回退重采仍失败。
        case lostOverlap
        /// 连续拿到无效帧（尺寸变化、解码失败等），重采仍失败。
        case invalidFrames
        /// 达到帧数上限，内容还没到底。
        case frameLimit
    }

    public struct Result {
        public let image: CGImage?
        public let frameCount: Int
        public let stitchedHeight: Int
        public let endReason: EndReason
        /// 是否因到达内容底部而正常结束（失去重叠、无效帧、触及上限都不算）。
        public var reachedEnd: Bool { endReason == .reachedEnd }
        /// 拼出来的是否是完整内容。
        public var isComplete: Bool { endReason == .reachedEnd }
    }

    public let options: Options
    /// 同一处失败（失去重叠 / 无效帧）最多补救几次。
    public var maxRecoveries = 2

    public init(options: Options = .init()) {
        self.options = options
    }

    /// 运行滚动捕获循环。
    /// - Parameters:
    ///   - capture: 截取当前可视帧。
    ///   - scroll: 按「基准步长 × fraction」滚动（fraction < 0 表示向上回退），应在内部等待界面稳定。
    ///
    /// 规则：
    /// - 重复帧连续 `endRepeatThreshold` 次 → 到底。
    /// - 失去重叠 → 步长减半并回退半步重采；补救 `maxRecoveries` 次仍失败 → `.lostOverlap`。
    /// - 无效帧 → 原地重采；补救次数用尽 → `.invalidFrames`。
    /// - 截满 `maxFrames` 帧即停，**最后一帧之后不再发送滚动**。
    public func run(
        capture: @Sendable () async throws -> CGImage,
        scroll: @Sendable (_ fraction: Double) async throws -> Void
    ) async rethrows -> Result {
        var stitcher = ScrollStitcher(options: options.stitcher)
        var duplicateStreak = 0
        var recoveries = 0
        var fraction = 1.0
        var captures = 0
        var endReason = EndReason.frameLimit

        loop: while captures < options.maxFrames {
            let frame = try await capture()
            captures += 1
            switch stitcher.append(frame) {
            case .first, .appended:
                duplicateStreak = 0
                recoveries = 0
            case .duplicate:
                duplicateStreak += 1
                recoveries = 0
                if duplicateStreak >= options.endRepeatThreshold {
                    endReason = .reachedEnd
                    break loop
                }
            case .noOverlap:
                guard recoveries < maxRecoveries else {
                    endReason = .lostOverlap
                    break loop
                }
                recoveries += 1
                guard captures < options.maxFrames else { break loop }
                // 跳过头了：步长减半，往回退半个旧步长，落在与已拼末帧重叠的位置再采。
                fraction = max(0.25, fraction / 2)
                try await scroll(-fraction)
                continue loop
            case .invalid:
                guard recoveries < maxRecoveries else {
                    endReason = .invalidFrames
                    break loop
                }
                recoveries += 1
                continue loop // 原地重采，不滚动
            }

            guard captures < options.maxFrames else { break loop }
            try await scroll(fraction)
        }

        return Result(
            image: stitcher.makeImage(),
            frameCount: stitcher.frameCount,
            stitchedHeight: stitcher.stitchedHeight,
            endReason: endReason
        )
    }

    /// 只能向下滚的调用方用这个：回退请求被忽略（失去重叠时只做原地重采）。
    public func run(
        capture: @Sendable () async throws -> CGImage,
        scroll: @Sendable () async throws -> Void
    ) async rethrows -> Result {
        try await run(capture: capture, scroll: { fraction in
            if fraction > 0 { try await scroll() }
        })
    }
}
