import CoreGraphics
import Foundation
import Testing
@testable import CaptureKit

@Test func annotationsRoundTripThroughJSON() throws {
    let annotation = CaptureAnnotation(
        id: UUID(uuidString: "B4347D55-A690-4B3C-990F-4CFCC45956F3")!,
        kind: .arrow,
        start: NormalizedPoint(x: 0.1, y: 0.2),
        end: NormalizedPoint(x: 0.8, y: 0.9)
    )
    let data = try JSONEncoder().encode(annotation)
    #expect(try JSONDecoder().decode(CaptureAnnotation.self, from: data) == annotation)
}

@Test func normalizedPointsClampToImageBounds() {
    #expect(NormalizedPoint(x: -1, y: 2) == NormalizedPoint(x: 0, y: 1))
}

@Test func textAnnotationPersistsItsLabel() throws {
    let annotation = CaptureAnnotation(
        kind: .text,
        start: NormalizedPoint(x: 0.2, y: 0.3),
        end: NormalizedPoint(x: 0.2, y: 0.3),
        label: "重点"
    )
    let data = try JSONEncoder().encode(annotation)
    let decoded = try JSONDecoder().decode(CaptureAnnotation.self, from: data)
    #expect(decoded.label == "重点")
    #expect(decoded.kind == .text)
}

@Test func rendererPreservesImageDimensions() throws {
    let context = try #require(CGContext(
        data: nil,
        width: 120,
        height: 80,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ))
    let image = try #require(context.makeImage())
    let rendered = try #require(AnnotationRenderer.render(
        image: image,
        annotations: [CaptureAnnotation(
            kind: .rectangle,
            start: NormalizedPoint(x: 0.1, y: 0.1),
            end: NormalizedPoint(x: 0.9, y: 0.9)
        )]
    ))
    #expect(rendered.width == image.width)
    #expect(rendered.height == image.height)
}

@Test func mosaicChangesPixelsWithoutChangingCanvasSize() throws {
    let context = try #require(CGContext(
        data: nil,
        width: 140,
        height: 80,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ))
    for x in 0..<140 {
        context.setFillColor(gray: CGFloat(x) / 139, alpha: 1)
        context.fill(CGRect(x: x, y: 0, width: 1, height: 80))
    }
    let image = try #require(context.makeImage())
    let rendered = try #require(AnnotationRenderer.render(
        image: image,
        annotations: [CaptureAnnotation(
            kind: .mosaic,
            start: NormalizedPoint(x: 0, y: 0),
            end: NormalizedPoint(x: 1, y: 1)
        )]
    ))
    let originalData = try #require(image.dataProvider?.data)
    let renderedData = try #require(rendered.dataProvider?.data)

    #expect(rendered.width == image.width)
    #expect(rendered.height == image.height)
    #expect(!CFEqual(originalData, renderedData))
}
