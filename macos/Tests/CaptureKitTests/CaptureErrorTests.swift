import Testing
@testable import CaptureKit

@Test func captureErrorsHaveUserFacingDescriptions() {
    #expect(CaptureError.noDisplayAvailable.errorDescription?.isEmpty == false)
    #expect(CaptureError.permissionDenied.errorDescription?.contains("权限") == true)
    #expect(CaptureError.imageEncodingFailed.errorDescription?.contains("PNG") == true)
}

