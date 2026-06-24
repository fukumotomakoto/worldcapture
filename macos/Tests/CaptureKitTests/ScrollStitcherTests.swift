import CoreGraphics
import Foundation
import Testing
@testable import CaptureKit

// MARK: - 测试辅助

private func makeGray(width: Int, height: Int) -> GrayImage {
    var pixels = [UInt8](repeating: 0, count: width * height)
    for y in 0..<height {
        for x in 0..<width {
            pixels[y * width + x] = UInt8((y * 37 + x * 5) % 256)
        }
    }
    return GrayImage(width: width, height: height, pixels: pixels)
}

private func slice(_ image: GrayImage, from: Int, rows: Int) -> GrayImage {
    var pixels = [UInt8](repeating: 0, count: image.width * rows)
    for y in 0..<rows {
        for x in 0..<image.width {
            pixels[y * image.width + x] = image.pixels[(from + y) * image.width + x]
        }
    }
    return GrayImage(width: image.width, height: rows, pixels: pixels)
}

/// 行 0 = 顶部、第 i 行灰度 = ((fromRow+i)*37) mod 256 的窗口图，避免 `cropping(to:)` 的坐标原点歧义。
private func makeWindowImage(width: Int, fromRow: Int, rows: Int, inverted: Bool = false) -> CGImage {
    var bytes = [UInt8](repeating: 0, count: width * rows * 4)
    for i in 0..<rows {
        let base = ((fromRow + i) * 37) % 256
        let value = UInt8(inverted ? 255 - base : base)
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
        width: width,
        height: rows,
        bitsPerComponent: 8,
        bitsPerPixel: 32,
        bytesPerRow: width * 4,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
        provider: provider,
        decode: nil,
        shouldInterpolate: false,
        intent: .defaultIntent
    )!
}

private func makeSourceImage(width: Int, height: Int, inverted: Bool = false) -> CGImage {
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    for y in 0..<height {
        let base = (y * 37) % 256
        let value = UInt8(inverted ? 255 - base : base)
        for x in 0..<width {
            let i = (y * width + x) * 4
            bytes[i] = value
            bytes[i + 1] = value
            bytes[i + 2] = value
            bytes[i + 3] = 255
        }
    }
    let provider = CGDataProvider(data: Data(bytes) as CFData)!
    return CGImage(
        width: width,
        height: height,
        bitsPerComponent: 8,
        bitsPerPixel: 32,
        bytesPerRow: width * 4,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
        provider: provider,
        decode: nil,
        shouldInterpolate: false,
        intent: .defaultIntent
    )!
}

// MARK: - 方向约定

@Test func grayImageRowZeroIsTopScanline() throws {
    // 行 0,1,2,3 的源值分别为 0、37、74、111。
    let image = makeWindowImage(width: 2, fromRow: 0, rows: 4)
    let gray = try #require(GrayImage(cgImage: image))
    #expect(gray.pixels[0] == 0)
    #expect(gray.pixels[3 * 2] == 111)
}

// MARK: - 纵向对齐

@Test func findsKnownVerticalShift() throws {
    let source = makeGray(width: 20, height: 130)
    let a = slice(source, from: 0, rows: 100)
    let b = slice(source, from: 15, rows: 100)

    let alignment = try #require(bestVerticalShift(a, b, columnStep: 1))
    #expect(alignment.shift == 15)
    #expect(alignment.score < 0.001)
}

@Test func identicalFramesYieldZeroShift() throws {
    let image = makeGray(width: 16, height: 60)
    let alignment = try #require(bestVerticalShift(image, image, columnStep: 1))
    #expect(alignment.shift == 0)
    #expect(alignment.score == 0)
}

@Test func rejectsMismatchedWidths() {
    let a = makeGray(width: 16, height: 40)
    let b = makeGray(width: 20, height: 40)
    #expect(bestVerticalShift(a, b) == nil)
}

// MARK: - 拼接

@Test func stitchesOverlappingFramesIntoTallImage() throws {
    let width = 16
    let sourceHeight = 120
    let frameHeight = 80
    let delta = 20
    let source = makeSourceImage(width: width, height: sourceHeight)

    var stitcher = ScrollStitcher(options: .init(columnStep: 1))
    var results: [ScrollStitcher.AppendResult] = []
    for offset in stride(from: 0, through: sourceHeight - frameHeight, by: delta) {
        let frame = makeWindowImage(width: width, fromRow: offset, rows: frameHeight)
        results.append(stitcher.append(frame))
    }

    #expect(results.first == .first)
    #expect(results.dropFirst().allSatisfy { $0 == .appended(newRows: delta) })
    #expect(stitcher.frameCount == 3)
    #expect(stitcher.stitchedHeight == sourceHeight)

    let stitched = try #require(stitcher.makeImage())
    #expect(stitched.width == width)
    #expect(stitched.height == sourceHeight)

    let sourceGray = try #require(GrayImage(cgImage: source))
    let stitchedGray = try #require(GrayImage(cgImage: stitched))
    var maxDiff = 0
    for y in stride(from: 0, to: sourceHeight, by: 7) {
        for x in stride(from: 0, to: width, by: 3) {
            let diff = abs(Int(sourceGray.pixels[y * width + x]) - Int(stitchedGray.pixels[y * width + x]))
            maxDiff = max(maxDiff, diff)
        }
    }
    #expect(maxDiff <= 3)
}

@Test func detectsDuplicateWhenNotScrolled() {
    let source = makeSourceImage(width: 16, height: 60)
    var stitcher = ScrollStitcher(options: .init(columnStep: 1))

    #expect(stitcher.append(source) == .first)
    #expect(stitcher.append(source) == .duplicate)
    #expect(stitcher.frameCount == 1)
    #expect(stitcher.stitchedHeight == 60)
}

@Test func stitchesPastStickyHeader() {
    // 模拟吸顶页眉：前 24 行无论怎么滚动都固定不变，其余内容随滚动上移。
    // 若从第 0 行比对，静止页眉会把对齐拉到 shift 0（误判“未滚动”）；
    // 跳过顶部后应正确求出滚动量并持续拼接。
    let width = 16
    let height = 200
    let headerRows = 24
    let delta = 30

    func frame(at position: Int) -> CGImage {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            // 顶部 headerRows 固定；其余按全局滚动位置取值。
            let base = y < headerRows ? 200 : ((position + y) * 37) % 256
            for x in 0..<width {
                let i = (y * width + x) * 4
                bytes[i] = UInt8(base); bytes[i + 1] = UInt8(base)
                bytes[i + 2] = UInt8(base); bytes[i + 3] = 255
            }
        }
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    }

    var stitcher = ScrollStitcher(options: .init(band: 80, columnStep: 1))
    #expect(stitcher.append(frame(at: 0)) == .first)
    #expect(stitcher.append(frame(at: delta)) == .appended(newRows: delta))
    #expect(stitcher.append(frame(at: 2 * delta)) == .appended(newRows: delta))
    #expect(stitcher.frameCount == 3)
}

@Test func reportsNoOverlapForUnrelatedFrame() {
    let a = makeSourceImage(width: 16, height: 60)
    let b = makeSourceImage(width: 16, height: 60, inverted: true)
    var stitcher = ScrollStitcher(options: .init(columnStep: 1))

    #expect(stitcher.append(a) == .first)
    #expect(stitcher.append(b) == .noOverlap)
    #expect(stitcher.frameCount == 1)
}
