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

