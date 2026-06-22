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

@Test func hitTestSelectsRectangleNearItsEdge() {
    let rect = CaptureAnnotation(
        kind: .rectangle,
        start: NormalizedPoint(x: 0.2, y: 0.2),
        end: NormalizedPoint(x: 0.6, y: 0.6)
    )
    #expect(rect.hitTest(NormalizedPoint(x: 0.21, y: 0.59), tolerance: 0.02))
    #expect(!rect.hitTest(NormalizedPoint(x: 0.9, y: 0.9), tolerance: 0.02))
}

@Test func hitTestSelectsArrowAlongItsLine() {
    let arrow = CaptureAnnotation(
        kind: .arrow,
        start: NormalizedPoint(x: 0.1, y: 0.1),
        end: NormalizedPoint(x: 0.9, y: 0.9)
    )
    #expect(arrow.hitTest(NormalizedPoint(x: 0.5, y: 0.5), tolerance: 0.02))
    #expect(!arrow.hitTest(NormalizedPoint(x: 0.1, y: 0.9), tolerance: 0.02))
}

@Test func translatingAnnotationKeepsEndpointsInBounds() {
    let annotation = CaptureAnnotation(
        kind: .rectangle,
        start: NormalizedPoint(x: 0.8, y: 0.8),
        end: NormalizedPoint(x: 0.95, y: 0.95)
    )
    let moved = annotation.translated(by: (dx: 0.3, dy: 0.3))
    #expect(moved.start == NormalizedPoint(x: 1, y: 1))
    #expect(moved.end == NormalizedPoint(x: 1, y: 1))
    #expect(moved.id == annotation.id)
}

@Test func parsesSixDigitHexColor() {
    let color = RGBAColor(hex: "#007AFF")
    #expect(abs(color.red - 0) < 0.01)
    #expect(abs(color.green - 122.0 / 255) < 0.01)
    #expect(abs(color.blue - 1) < 0.01)
    #expect(color.alpha == 1)
}

@Test func invalidHexFallsBackToDefaultRed() {
    let color = RGBAColor(hex: "not-a-color")
    #expect(abs(color.red - 1) < 0.01)
    #expect(abs(color.green - 0.231) < 0.01)
}

@Test func annotationColorRoundTripsAndDefaults() throws {
    let colored = CaptureAnnotation(
        kind: .rectangle,
        start: NormalizedPoint(x: 0, y: 0),
        end: NormalizedPoint(x: 1, y: 1),
        colorHex: "#34C759"
    )
    let decoded = try JSONDecoder().decode(
        CaptureAnnotation.self,
        from: try JSONEncoder().encode(colored)
    )
    #expect(decoded.colorHex == "#34C759")
    #expect(decoded.resolvedColorHex == "#34C759")

    let plain = CaptureAnnotation(kind: .arrow, start: NormalizedPoint(x: 0, y: 0), end: NormalizedPoint(x: 1, y: 1))
    #expect(plain.colorHex == nil)
    #expect(plain.resolvedColorHex == CaptureAnnotation.defaultColorHex)
}

@Test func decodesLegacyAnnotationWithoutColorKey() throws {
    let legacy = #"{"id":"B4347D55-A690-4B3C-990F-4CFCC45956F3","kind":"text","start":{"x":0.1,"y":0.2},"end":{"x":0.3,"y":0.4}}"#
    let decoded = try JSONDecoder().decode(CaptureAnnotation.self, from: Data(legacy.utf8))
    #expect(decoded.colorHex == nil)
    #expect(decoded.resolvedColorHex == CaptureAnnotation.defaultColorHex)
}

@Test func lineWidthRoundTripsAndDefaultsToOne() throws {
    let thick = CaptureAnnotation(
        kind: .rectangle,
        start: NormalizedPoint(x: 0, y: 0),
        end: NormalizedPoint(x: 1, y: 1),
        lineWidth: 1.8
    )
    let decoded = try JSONDecoder().decode(
        CaptureAnnotation.self,
        from: try JSONEncoder().encode(thick)
    )
    #expect(decoded.lineWidth == 1.8)
    #expect(decoded.resolvedLineWidth == 1.8)

    let plain = CaptureAnnotation(kind: .arrow, start: NormalizedPoint(x: 0, y: 0), end: NormalizedPoint(x: 1, y: 1))
    #expect(plain.lineWidth == nil)
    #expect(plain.resolvedLineWidth == 1)
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
