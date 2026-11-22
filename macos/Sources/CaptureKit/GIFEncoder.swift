import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// 把一串带延时的帧编码为动图 GIF。
public enum GIFEncoder {
    public struct Frame: Sendable {
        public let image: CGImage
        /// 本帧显示时长（秒），即到下一帧的间隔。
        public let delay: Double

        public init(image: CGImage, delay: Double) {
            self.image = image
            self.delay = delay
        }
    }

    /// `loopCount == 0` 表示无限循环。GIF 规范延时以 1/100 秒为单位，最小取 0.02s（避免浏览器把过小值钳到 0.1s 之外的行为差异）。
    public static func encode(frames: [Frame], loopCount: Int = 0) throws -> Data {
        guard !frames.isEmpty else { throw CaptureError.imageEncodingFailed }

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data as CFMutableData,
            UTType.gif.identifier as CFString,
            frames.count,
            nil
        ) else {
            throw CaptureError.imageEncodingFailed
        }

        let fileProperties = [
            kCGImagePropertyGIFDictionary as String: [
                kCGImagePropertyGIFLoopCount as String: loopCount,
            ],
        ]
        CGImageDestinationSetProperties(destination, fileProperties as CFDictionary)

        for frame in frames {
            let delay = max(0.02, frame.delay)
            let frameProperties = [
                kCGImagePropertyGIFDictionary as String: [
                    kCGImagePropertyGIFDelayTime as String: delay,
                    kCGImagePropertyGIFUnclampedDelayTime as String: delay,
                ],
            ]
            CGImageDestinationAddImage(destination, frame.image, frameProperties as CFDictionary)
        }

        guard CGImageDestinationFinalize(destination) else {
            throw CaptureError.imageEncodingFailed
        }
        return data as Data
    }

    /// GIF 延时的精度：1/100 秒。
    static let tick: Double = 0.01

    /// 由带时间戳的帧计算每帧延时：第 i 帧显示到第 i+1 帧出现；末帧显示到 `endTimestamp`（停止时刻，
    /// 与帧时间戳同一时钟）。没给停止时刻才退回按 `fallbackFPS` 估。
    ///
    /// 每个时间点先按 GIF 精度（1/100 秒）取整再相减，逐帧舍入误差不会累积：
    /// 总时长 = 取整后的（停止时刻 − 首帧时刻），与录制时长的误差不超过半个刻度。
    public static func frames(
        from timestamped: [(image: CGImage, timestamp: TimeInterval)],
        endTimestamp: TimeInterval? = nil,
        fallbackFPS: Int
    ) -> [Frame] {
        guard let origin = timestamped.first?.timestamp else { return [] }
        let fallbackDelay = 1.0 / Double(max(1, fallbackFPS))
        func ticks(_ t: TimeInterval) -> Int { Int(((t - origin) / tick).rounded()) }
        return timestamped.enumerated().map { index, frame in
            let start = ticks(frame.timestamp)
            let delay: Double
            if index + 1 < timestamped.count {
                delay = Double(ticks(timestamped[index + 1].timestamp) - start) * tick
            } else if let endTimestamp, endTimestamp > frame.timestamp {
                delay = Double(ticks(endTimestamp) - start) * tick
            } else {
                delay = fallbackDelay
            }
            return Frame(image: frame.image, delay: max(0.02, delay))
        }
    }
}
