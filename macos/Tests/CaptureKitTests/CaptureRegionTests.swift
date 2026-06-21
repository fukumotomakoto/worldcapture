import CoreGraphics
import Testing
@testable import CaptureKit

@Test func convertsAppKitSelectionToScreenCaptureCoordinatesAtRetinaScale() throws {
    let region = try #require(CaptureRegion(
        selection: CGRect(x: 100, y: 200, width: 300, height: 250),
        displayFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        pixelSize: CGSize(width: 3024, height: 1964)
    ))

    #expect(region.sourceRect == CGRect(x: 100, y: 532, width: 300, height: 250))
    #expect(region.pixelWidth == 600)
    #expect(region.pixelHeight == 500)
}

@Test func clipsSelectionToDisplayBounds() throws {
    let region = try #require(CaptureRegion(
        selection: CGRect(x: -20, y: 80, width: 100, height: 50),
        displayFrame: CGRect(x: 0, y: 0, width: 200, height: 100),
        pixelSize: CGSize(width: 400, height: 200)
    ))

    #expect(region.sourceRect == CGRect(x: 0, y: 0, width: 80, height: 20))
    #expect(region.pixelWidth == 160)
    #expect(region.pixelHeight == 40)
}

@Test func rejectsEmptySelection() {
    #expect(CaptureRegion(
        selection: CGRect(x: 10, y: 10, width: 1, height: 1),
        displayFrame: CGRect(x: 0, y: 0, width: 100, height: 100),
        pixelSize: CGSize(width: 200, height: 200)
    ) == nil)
}

