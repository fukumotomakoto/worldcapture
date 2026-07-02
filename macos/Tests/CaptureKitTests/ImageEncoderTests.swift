import CoreGraphics
import Foundation
import Testing
@testable import CaptureKit

private func solidImage(width: Int = 32, height: Int = 24) -> CGImage {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage()!
}

@Test func encodesPNGWithPNGSignature() throws {
    let data = try ImageEncoder.encode(solidImage(), as: .png)
    #expect(Array(data.prefix(4)) == [0x89, 0x50, 0x4E, 0x47]) // \x89 P N G
}

@Test func encodesJPEGWithJFIFMarker() throws {
    let data = try ImageEncoder.encode(solidImage(), as: .jpeg)
    #expect(Array(data.prefix(2)) == [0xFF, 0xD8]) // SOI marker
}

@Test func encodesTIFFWithByteOrderMarker() throws {
    let data = try ImageEncoder.encode(solidImage(), as: .tiff)
    let magic = Array(data.prefix(2))
    #expect(magic == [0x49, 0x49] || magic == [0x4D, 0x4D]) // "II" or "MM"
}

@Test func encodesPDFWithHeader() throws {
    let data = try ImageEncoder.encode(solidImage(), as: .pdf)
    #expect(String(decoding: data.prefix(5), as: UTF8.self) == "%PDF-")
}

@Test func formatRoundTripsThroughExtension() {
    for format in ImageFormat.allCases {
        #expect(ImageFormat(fileExtension: format.fileExtension) == format)
    }
    #expect(ImageFormat(fileExtension: "JPEG") == .jpeg)
    #expect(ImageFormat(fileExtension: "tif") == .tiff)
    #expect(ImageFormat(fileExtension: "heic") == nil)
}
