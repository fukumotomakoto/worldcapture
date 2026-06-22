import CoreGraphics
import Foundation
import Testing
@testable import CaptureKit

private func windowImage(width: Int, fromRow: Int, rows: Int) -> CGImage {
    var bytes = [UInt8](repeating: 0, count: width * rows * 4)
    for i in 0..<rows {
        let value = UInt8(((fromRow + i) * 37) % 256)
        for x in 0..<width {
            let p = (i * width + x) * 4
            bytes[p] = value
            bytes[p + 1] = value
            bytes[p + 2] = value
            bytes[p + 3] = 255
        }
    }
    let provider = CGDataProvider(data: Data(bytes) as CFData)!
    return CGImage(
        width: width, height: rows, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
        provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
    )!
}

/// 模拟一个可滚动页面：当前滚动位置上的视口被截取，滚动到底后位置被夹住。
/// 测试为单线程顺序执行，标 `@unchecked Sendable` 以满足引擎的 `@Sendable` 闭包要求。
private final class FakeScrollablePage: @unchecked Sendable {
    let width: Int
    let viewport: Int
    let totalHeight: Int
    let step: Int
    private(set) var position = 0

    init(width: Int, viewport: Int, totalHeight: Int, step: Int) {
        self.width = width
        self.viewport = viewport
        self.totalHeight = totalHeight
        self.step = step
    }

    var maxPosition: Int { totalHeight - viewport }

    func capture() -> CGImage {
        windowImage(width: width, fromRow: position, rows: viewport)
    }

    func scroll() {
        position = min(maxPosition, position + step)
    }
}

@Test func scrollCaptureReconstructsFullPageAndStopsAtBottom() async {
    let page = FakeScrollablePage(width: 16, viewport: 80, totalHeight: 300, step: 40)
    let engine = ScrollCaptureEngine(options: .init(maxFrames: 80, endRepeatThreshold: 2, stitcher: .init(columnStep: 1)))

    let result = await engine.run(
        capture: { page.capture() },
        scroll: { page.scroll() }
    )

    #expect(result.reachedEnd)
    #expect(result.stitchedHeight == page.totalHeight)
    #expect(result.image?.height == page.totalHeight)
    #expect(result.image?.width == page.width)

    let expected = GrayImage(cgImage: windowImage(width: 16, fromRow: 0, rows: 300))!
    let actual = GrayImage(cgImage: result.image!)!
    var maxDiff = 0
    for y in stride(from: 0, to: 300, by: 9) {
        for x in stride(from: 0, to: 16, by: 3) {
            maxDiff = max(maxDiff, abs(Int(expected.pixels[y * 16 + x]) - Int(actual.pixels[y * 16 + x])))
        }
    }
    #expect(maxDiff <= 3)
}

@Test func scrollCaptureHonorsMaxFrameSafetyCap() async {
    // 视口永远在“滚动”（步长把位置一直推进，但 totalHeight 极大，永远到不了底），
    // 用 maxFrames 作为安全上限收尾。
    let page = FakeScrollablePage(width: 16, viewport: 40, totalHeight: 100_000, step: 20)
    let engine = ScrollCaptureEngine(options: .init(maxFrames: 5, endRepeatThreshold: 2, stitcher: .init(columnStep: 1)))

    let result = await engine.run(
        capture: { page.capture() },
        scroll: { page.scroll() }
    )

    #expect(!result.reachedEnd)
    #expect(result.frameCount == 5)
}

@Test func scrollCaptureWithNoScrollProgressStopsQuickly() async {
    // 完全无法滚动（step 0）：第一帧后连续重复，应迅速判定到底。
    let page = FakeScrollablePage(width: 16, viewport: 50, totalHeight: 200, step: 0)
    let engine = ScrollCaptureEngine(options: .init(maxFrames: 80, endRepeatThreshold: 2, stitcher: .init(columnStep: 1)))

    let result = await engine.run(
        capture: { page.capture() },
        scroll: { page.scroll() }
    )

    #expect(result.reachedEnd)
    #expect(result.frameCount == 1)
    #expect(result.stitchedHeight == 50)
}
