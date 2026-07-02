import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import CaptureKit

private func colorFrame(_ gray: CGFloat, size: Int = 16) -> CGImage {
    let context = CGContext(
        data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.setFillColor(CGColor(red: gray, green: gray, blue: gray, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: size, height: size))
    return context.makeImage()!
}

@Test func encodesAnimatedGIFWithFrameCount() throws {
    let frames = [
        GIFEncoder.Frame(image: colorFrame(0.1), delay: 0.1),
        GIFEncoder.Frame(image: colorFrame(0.5), delay: 0.1),
        GIFEncoder.Frame(image: colorFrame(0.9), delay: 0.1),
    ]
    let data = try GIFEncoder.encode(frames: frames)

    // GIF magic header "GIF8".
    #expect(Array(data.prefix(4)) == [0x47, 0x49, 0x46, 0x38])

    let source = CGImageSourceCreateWithData(data as CFData, nil)
    #expect(source != nil)
    #expect(CGImageSourceGetCount(source!) == 3)
}

@Test func emptyFramesThrows() {
    #expect(throws: (any Error).self) {
        _ = try GIFEncoder.encode(frames: [])
    }
}

@Test func delaysComputedFromTimestamps() {
    let img = colorFrame(0.4)
    let timestamped: [(image: CGImage, timestamp: TimeInterval)] = [
        (img, 0.0), (img, 0.2), (img, 0.5),
    ]
    let frames = GIFEncoder.frames(from: timestamped, fallbackFPS: 10)
    #expect(frames.count == 3)
    #expect(abs(frames[0].delay - 0.2) < 0.0001)
    #expect(abs(frames[1].delay - 0.3) < 0.0001)
    // Last frame falls back to 1/fps.
    #expect(abs(frames[2].delay - 0.1) < 0.0001)
}
