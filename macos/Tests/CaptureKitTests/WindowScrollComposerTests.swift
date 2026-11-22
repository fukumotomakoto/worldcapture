// 2026-11-22《长图重复界面修正报告》验收样例：合成「带固定界面的窗口帧」→ 最终 PNG，
// 直接校验输出尺寸、固定界面是否进入正文、正文逐行连续。

import CoreGraphics
import Foundation
import Testing
@testable import CaptureKit

/// 合成窗口：标题栏（灰 200）、左侧栏（灰 230）、底部输入框（灰 180）都固定；正文白底，内容随 offset 滚动。
private struct FakeWindow {
    var width = 800, height = 600
    var titleHeight = 64, sidebarWidth = 220, inputTop = 540
    /// 页面第 p 行、第 x 列的灰度（只对正文区域调用）；nil = 白底。
    var page: (Int, Int) -> UInt8?
    /// 某些列可以有自己的滚动偏移（模拟独立滚动的两列）。
    var columnOffset: ((Int, Int) -> Int)? = nil

    func frame(offset: Int) -> CGImage {
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let v: UInt8
                if y < titleHeight {
                    v = (y == 30 && x % 9 == 0) ? 50 : 200
                } else if y >= inputTop {
                    v = y == inputTop ? 90 : ((y == 570 && x % 5 == 0) ? 60 : 180)
                } else if x < sidebarWidth {
                    v = ((y / 40) % 2 == 0 && x > 20 && x < 120 && y % 40 < 12) ? 70 : 230
                } else {
                    let o = columnOffset?(x, offset) ?? offset
                    v = page(o + y - titleHeight, x) ?? 255
                }
                let p = (y * width + x) * 4
                bytes[p] = v; bytes[p + 1] = v; bytes[p + 2] = v; bytes[p + 3] = 255
            }
        }
        return CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: CGDataProvider(data: Data(bytes) as CFData)!, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )!
    }
}

/// 稀疏正文：每段 `textRows` 行字，段间 `gap` 行空白；字形图案含段号，段与段、行与行都不相同。
private func sparsePage(textRows: Int, gap: Int, columns: Range<Int> = 240..<760) -> (Int, Int) -> UInt8? {
    { p, x in
        guard p >= 0, columns.contains(x) else { return nil }
        let period = textRows + gap
        let paragraph = p / period, row = p % period
        guard row < textRows else { return nil }
        return ((x / 7 + row * 3 + paragraph * 11) % 5 == 0) ? 30 : nil
    }
}

private func gray(_ image: CGImage) -> GrayImage { GrayImage(cgImage: image)! }

/// 把输出与「期望长图」逐行比对：顶部 header 行 = 标题栏，之后第 r 行 = 页面第 r 行。
private func verifyOutput(_ image: CGImage, window: FakeWindow, bodyX: Int, expectedHeight: Int) -> (bad: Int, sidebar: Int, input: Int) {
    let g = gray(image)
    var bad = 0, sidebar = 0, input = 0
    for y in 0..<g.height {
        for x in stride(from: 0, to: g.width, by: 3) {
            let v = g.pixels[y * g.width + x]
            if v == 230 { sidebar += 1 }
            if v == 180 { input += 1 }
            let wx = x + bodyX
            let expected: UInt8 = y < window.titleHeight
                ? ((y == 30 && wx % 9 == 0) ? 50 : 200)
                : (window.page(y - window.titleHeight, wx) ?? 255)
            if abs(Int(v) - Int(expected)) > 2 { bad += 1 }
        }
    }
    _ = expectedHeight
    return (bad, sidebar, input)
}

@Test func windowScroll_fixedChromeAppearsOnceAndBodyIsContinuous() throws {
    // 报告样例：800×600，正文从 x=220、y=64 开始，高 476；三个视口偏移 0、180、360。
    let window = FakeWindow(page: sparsePage(textRows: 30, gap: 100))
    let f0 = window.frame(offset: 0), f1 = window.frame(offset: 180), f2 = window.frame(offset: 360)

    let detection = WindowScrollRegion.detect(f0, f1)
    #expect(detection == .body(CGRect(x: 220, y: 64, width: 580, height: 476)))
    guard case .body(let rect) = detection else { return }

    var composer = try #require(WindowScrollComposer(firstFrame: f0, body: rect))
    #expect(composer.append(f1) == .appended(newRows: 180))
    #expect(composer.append(f2) == .appended(newRows: 180))
    let output = try #require(composer.makeImage())

    #expect(output.width == 580)
    #expect(output.height == 900) // 64 标题栏一次 + 476 + 360 正文
    let check = verifyOutput(output, window: window, bodyX: 220, expectedHeight: 900)
    #expect(check.bad == 0)
    #expect(check.sidebar == 0) // 侧栏像素没进入长图
    #expect(check.input == 0)   // 输入框像素没进入长图
}

@Test func windowScroll_sparseBodyWithLargeGapsKeepsEveryParagraphOnceInOrder() throws {
    // 段间留白 180 行，超过旧拼接器 160 行的比对带；步长 300。
    let window = FakeWindow(page: sparsePage(textRows: 20, gap: 180))
    let frames = [0, 300, 600, 900].map { window.frame(offset: $0) }
    guard case .body(let rect) = WindowScrollRegion.detect(frames[0], frames[1]) else {
        Issue.record("body not detected"); return
    }
    var composer = try #require(WindowScrollComposer(firstFrame: frames[0], body: rect))
    for f in frames.dropFirst() { #expect(composer.append(f) == .appended(newRows: 300)) }
    let output = try #require(composer.makeImage())
    #expect(output.height == 64 + 476 + 900)
    let check = verifyOutput(output, window: window, bodyX: Int(rect.minX), expectedHeight: output.height)
    #expect(check.bad == 0) // 每段恰好一次、顺序连续、段间空白完整
}

@Test func windowScroll_synchronousColumnsAreKeptTogetherWithTheGap() {
    // 两列同步滚动，中间留白 80 列（大于合并间隔）。
    let page: (Int, Int) -> UInt8? = { p, x in
        let left = sparsePage(textRows: 30, gap: 60, columns: 240..<460)
        let right = sparsePage(textRows: 30, gap: 60, columns: 540..<760)
        return left(p, x) ?? right(p + 17, x)
    }
    let window = FakeWindow(page: page)
    let detection = WindowScrollRegion.detect(window.frame(offset: 0), window.frame(offset: 150))
    guard case .body(let rect) = detection else { Issue.record("got \(detection)"); return }
    #expect(rect.minX <= 240 && rect.maxX >= 760) // 两列连同中间留白都在
}

@Test func windowScroll_independentColumnsAskTheUserToSelect() {
    var window = FakeWindow(page: { p, x in
        let left = sparsePage(textRows: 30, gap: 40, columns: 240..<460)
        let right = sparsePage(textRows: 30, gap: 40, columns: 560..<760)
        return left(p, x) ?? right(p + 9, x)
    })
    // 右列只滚一半：两块区域位移不一致。
    window.columnOffset = { x, offset in x >= 520 ? offset / 2 : offset }
    let detection = WindowScrollRegion.detect(window.frame(offset: 0), window.frame(offset: 160))
    #expect(detection == .undetermined(.independentColumns))
}

@Test func windowScroll_wholeWindowScrollingKeepsEverything() {
    // 没有任何固定界面：整窗都在滚。
    var window = FakeWindow(page: { p, x in ((x / 5 + p * 7) % 9 == 0) ? 40 : nil })
    window.titleHeight = 0; window.sidebarWidth = 0; window.inputTop = 600
    #expect(WindowScrollRegion.detect(window.frame(offset: 0), window.frame(offset: 200)) == .wholeWindow)
}

@Test func windowScroll_noMotionOrTinyChangeIsUndetermined() {
    let window = FakeWindow(page: sparsePage(textRows: 30, gap: 100))
    let f = window.frame(offset: 0)
    #expect(WindowScrollRegion.detect(f, f) == .undetermined(.noMotion))
}

@Test func windowScroll_layoutChangeStopsWithInvalidAndKeepsConfirmedPart() throws {
    let window = FakeWindow(page: sparsePage(textRows: 30, gap: 100))
    let f0 = window.frame(offset: 0), f1 = window.frame(offset: 180)
    guard case .body(let rect) = WindowScrollRegion.detect(f0, f1) else { Issue.record("no body"); return }
    var composer = try #require(WindowScrollComposer(firstFrame: f0, body: rect))
    #expect(composer.append(f1) == .appended(newRows: 180))
    let before = try #require(composer.makeImage())

    var resized = window
    resized.width = 760 // 窗口宽度中途变了
    #expect(composer.append(resized.frame(offset: 360)) == .invalid)
    // 注入一帧完全对不上的内容。
    let garbage = FakeWindow(page: { p, x in ((x * 13 + p * 29) % 7 == 0) ? 10 : nil }).frame(offset: 5000)
    #expect(composer.append(garbage) == .noOverlap)

    let after = try #require(composer.makeImage())
    #expect(after.height == before.height)
    #expect(gray(after).pixels == gray(before).pixels) // 已保留部分与此前输出逐像素一致
}
