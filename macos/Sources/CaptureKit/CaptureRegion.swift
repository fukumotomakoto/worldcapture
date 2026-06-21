import CoreGraphics

public struct CaptureRegion: Equatable, Sendable {
    public let sourceRect: CGRect
    public let pixelWidth: Int
    public let pixelHeight: Int

    public init?(selection: CGRect, displayFrame: CGRect, pixelSize: CGSize) {
        let clipped = selection.standardized.intersection(displayFrame)
        guard !clipped.isNull, clipped.width >= 2, clipped.height >= 2,
              displayFrame.width > 0, displayFrame.height > 0 else {
            return nil
        }

        sourceRect = CGRect(
            x: clipped.minX - displayFrame.minX,
            y: displayFrame.maxY - clipped.maxY,
            width: clipped.width,
            height: clipped.height
        )
        pixelWidth = max(1, Int((clipped.width * pixelSize.width / displayFrame.width).rounded()))
        pixelHeight = max(1, Int((clipped.height * pixelSize.height / displayFrame.height).rounded()))
    }
}

