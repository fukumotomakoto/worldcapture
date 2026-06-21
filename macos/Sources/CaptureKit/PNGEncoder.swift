import AppKit
import CoreGraphics

public enum PNGEncoder {
    public static func encode(_ image: CGImage) throws -> Data {
        let representation = NSBitmapImageRep(cgImage: image)
        guard let data = representation.representation(using: .png, properties: [:]) else {
            throw CaptureError.imageEncodingFailed
        }
        return data
    }
}

