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

    public struct Result {
        public let image: CGImage?
        public let frameCount: Int
        public let stitchedHeight: Int
        /// 是否因到达内容底部而正常结束（而非触及帧数上限）。
        public let reachedEnd: Bool
    }

    public let options: Options

    public init(options: Options = .init()) {
        self.options = options
    }

    /// 运行滚动捕获循环。
    /// - Parameters:
    ///   - capture: 截取当前可视帧。
    ///   - scroll: 向下滚动一屏（应在内部等待界面渲染稳定）。
    public func run(
        capture: @Sendable () async throws -> CGImage,
        scroll: @Sendable () async throws -> Void
    ) async rethrows -> Result {
        var stitcher = ScrollStitcher(options: options.stitcher)
        var nonProgressStreak = 0
        var reachedEnd = false

        for _ in 0..<options.maxFrames {
            let frame = try await capture()
            switch stitcher.append(frame) {
            case .first, .appended:
                nonProgressStreak = 0
            case .duplicate, .noOverlap, .invalid:
                nonProgressStreak += 1
                if nonProgressStreak >= options.endRepeatThreshold {
                    reachedEnd = true
                }
            }

            if reachedEnd { break }
            try await scroll()
        }

        return Result(
            image: stitcher.makeImage(),
            frameCount: stitcher.frameCount,
            stitchedHeight: stitcher.stitchedHeight,
            reachedEnd: reachedEnd
        )
    }
}
