import CoreGraphics
import Foundation
import Testing
@testable import CaptureKit

/// 构造一张图：左右两侧为固定色块，中间列填入按 `phase` 逐行平移的灰度渐变
/// （模拟真实滚动内容——每行都在变，且变化区域连续）。
private func framed(width: Int, height: Int, midX0: Int, midX1: Int, phase: Int) -> CGImage {
    let ctx = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    // 固定背景（两侧都是它）。
    ctx.setFillColor(CGColor(red: 0.8, green: 0.8, blue: 0.8, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    // 中间列：逐行灰度随 (y + phase) 变化 → 平移后每一行都不同，且连续。
    for y in 0..<height {
        let v = Double((y * 3 + phase * 11) % 256) / 255.0
        ctx.setFillColor(CGColor(red: v, green: v, blue: v, alpha: 1))
        ctx.fill(CGRect(x: midX0, y: y, width: midX1 - midX0, height: 1))
    }
    return ctx.makeImage()!
}

@Test func detectsScrollingMiddleColumn() throws {
    let w = 240, h = 400
    let a = framed(width: w, height: h, midX0: 90, midX1: 150, phase: 0)
    let b = framed(width: w, height: h, midX0: 90, midX1: 150, phase: 8)
    let rect = try #require(ContentRegionDetector.changedRect(a, b))
    // 变化区域应集中在中间列（左右固定不变）。
    #expect(rect.minX >= 70 && rect.minX <= 100)
    #expect(rect.maxX >= 140 && rect.maxX <= 170)
    // 纵向应覆盖大部分高度。
    #expect(rect.height >= Double(h) * 0.6)
}

@Test func returnsNilWhenWholeFrameChanges() {
    let w = 200, h = 300
    // 整帧都是变化的条纹 → 没有可裁的固定部分 → 回退 nil。
    let a = framed(width: w, height: h, midX0: 0, midX1: w, phase: 0)
    let b = framed(width: w, height: h, midX0: 0, midX1: w, phase: 8)
    #expect(ContentRegionDetector.changedRect(a, b) == nil)
}

@Test func returnsNilWhenIdentical() {
    let w = 200, h = 300
    let a = framed(width: w, height: h, midX0: 80, midX1: 120, phase: 4)
    #expect(ContentRegionDetector.changedRect(a, a) == nil)
}
