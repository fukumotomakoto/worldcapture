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

@Test func hitTestSelectsEllipseWithinBounds() {
    let ellipse = CaptureAnnotation(
        kind: .ellipse,
        start: NormalizedPoint(x: 0.2, y: 0.2),
        end: NormalizedPoint(x: 0.6, y: 0.6)
    )
    #expect(ellipse.hitTest(NormalizedPoint(x: 0.4, y: 0.4), tolerance: 0.02))
    #expect(!ellipse.hitTest(NormalizedPoint(x: 0.9, y: 0.9), tolerance: 0.02))
}

@Test func ellipseRoundTripsThroughJSON() throws {
    let ellipse = CaptureAnnotation(
        kind: .ellipse,
        start: NormalizedPoint(x: 0.1, y: 0.2),
        end: NormalizedPoint(x: 0.7, y: 0.5)
    )
    let data = try JSONEncoder().encode(ellipse)
    #expect(try JSONDecoder().decode(CaptureAnnotation.self, from: data) == ellipse)
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

@Test func freehandBoundsCoverAllPathPoints() {
    let pen = CaptureAnnotation(
        kind: .freehand,
        start: NormalizedPoint(x: 0.2, y: 0.5),
        end: NormalizedPoint(x: 0.7, y: 0.4),
        points: [
            NormalizedPoint(x: 0.2, y: 0.5),
            NormalizedPoint(x: 0.5, y: 0.3),
            NormalizedPoint(x: 0.7, y: 0.4),
        ]
    )
    let b = pen.normalizedBounds
    #expect(abs(b.minX - 0.2) < 0.0001)
    #expect(abs(b.minY - 0.3) < 0.0001)
    #expect(abs(b.maxX - 0.7) < 0.0001)
    #expect(abs(b.maxY - 0.5) < 0.0001)
}

@Test func freehandHitTestFollowsThePath() {
    let pen = CaptureAnnotation(
        kind: .freehand,
        start: NormalizedPoint(x: 0.1, y: 0.1),
        end: NormalizedPoint(x: 0.9, y: 0.1),
        points: [NormalizedPoint(x: 0.1, y: 0.1), NormalizedPoint(x: 0.9, y: 0.1)]
    )
    #expect(pen.hitTest(NormalizedPoint(x: 0.5, y: 0.105), tolerance: 0.02))
    #expect(!pen.hitTest(NormalizedPoint(x: 0.5, y: 0.4), tolerance: 0.02))
}

@Test func freehandTranslatesEveryPoint() {
    let pen = CaptureAnnotation(
        kind: .freehand,
        start: NormalizedPoint(x: 0.2, y: 0.2),
        end: NormalizedPoint(x: 0.4, y: 0.4),
        points: [NormalizedPoint(x: 0.2, y: 0.2), NormalizedPoint(x: 0.4, y: 0.4)]
    )
    let moved = pen.translated(by: (dx: 0.1, dy: 0.1))
    let pts = try! #require(moved.points)
    #expect(pts.count == 2)
    #expect(abs(pts[0].x - 0.3) < 0.0001 && abs(pts[0].y - 0.3) < 0.0001)
    #expect(abs(pts[1].x - 0.5) < 0.0001 && abs(pts[1].y - 0.5) < 0.0001)
}

@Test func freehandRoundTripsThroughJSON() throws {
    let pen = CaptureAnnotation(
        kind: .freehand,
        start: NormalizedPoint(x: 0.2, y: 0.2),
        end: NormalizedPoint(x: 0.4, y: 0.4),
        points: [NormalizedPoint(x: 0.2, y: 0.2), NormalizedPoint(x: 0.4, y: 0.4)]
    )
    #expect(try JSONDecoder().decode(CaptureAnnotation.self, from: try JSONEncoder().encode(pen)) == pen)
}

@Test func remapScalesAnnotationIntoCropRegion() {
    // 裁切框取右下四分之一 (0.5,0.5)-(1,1)：其中心 (0.75,0.75) 映射到新图中心 (0.5,0.5)。
    let dot = CaptureAnnotation(
        kind: .rectangle,
        start: NormalizedPoint(x: 0.6, y: 0.6),
        end: NormalizedPoint(x: 0.9, y: 0.9)
    )
    let mapped = dot.remapped(toCropRegion: CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5))
    let m = try! #require(mapped)
    #expect(abs(m.start.x - 0.2) < 0.0001)
    #expect(abs(m.start.y - 0.2) < 0.0001)
    #expect(abs(m.end.x - 0.8) < 0.0001)
    #expect(abs(m.end.y - 0.8) < 0.0001)
}

@Test func remapDropsAnnotationFullyOutsideCropRegion() {
    let far = CaptureAnnotation(
        kind: .rectangle,
        start: NormalizedPoint(x: 0.0, y: 0.0),
        end: NormalizedPoint(x: 0.2, y: 0.2)
    )
    #expect(far.remapped(toCropRegion: CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5)) == nil)
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

/// 回归：马赛克必须从「框住的那块」取样。旧实现把左下角原点的矩形交给左上角原点的
/// `CGImage.cropping`，从上下镜像的区域取样——上半白、下半黑的图，给上半打码会变黑。
@Test func mosaicSamplesTheRegionItCovers() throws {
    let width = 200, height = 200
    let context = try #require(CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ))
    context.setFillColor(gray: 0, alpha: 1)          // CG 左下角原点：下半黑
    context.fill(CGRect(x: 0, y: 0, width: width, height: height / 2))
    context.setFillColor(gray: 1, alpha: 1)          // 上半白
    context.fill(CGRect(x: 0, y: height / 2, width: width, height: height / 2))
    let image = try #require(context.makeImage())

    // 归一化坐标是左上角原点：y 0.05~0.35 = 图的上半部分（白）。
    let rendered = try #require(AnnotationRenderer.render(image: image, annotations: [CaptureAnnotation(
        kind: .mosaic, start: NormalizedPoint(x: 0.1, y: 0.05), end: NormalizedPoint(x: 0.9, y: 0.35)
    )]))
    let data = try #require(rendered.dataProvider?.data) as Data
    func gray(_ x: Int, _ yTop: Int) -> UInt8 { data[yTop * rendered.bytesPerRow + x * 4] }
    #expect(gray(100, 40) > 200)   // 框里仍是白色（没被换成镜像区域的黑）
    #expect(gray(100, 150) < 50)   // 框外下半部分不受影响
}

/// 马赛克块随图片放大：Retina 截图上固定 14 px 只有半个字高，挡不住大字。
@Test func mosaicBlockScalesWithImage() {
    #expect(AnnotationRenderer.mosaicBlockSize(imageWidth: 300, imageHeight: 200) == 16)
    #expect(AnnotationRenderer.mosaicBlockSize(imageWidth: 1920, imageHeight: 1280) == 28)
    #expect(AnnotationRenderer.mosaicBlockSize(imageWidth: 3840, imageHeight: 2160) == 48)
}
