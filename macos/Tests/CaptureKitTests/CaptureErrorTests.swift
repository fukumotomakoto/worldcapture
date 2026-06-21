import Testing
@testable import CaptureKit

@Test func captureErrorsHaveUserFacingDescriptions() {
    #expect(CaptureError.noDisplayAvailable.errorDescription?.isEmpty == false)
    #expect(CaptureError.windowUnavailable.errorDescription?.contains("窗口") == true)
    #expect(CaptureError.permissionDenied.errorDescription?.contains("权限") == true)
    #expect(CaptureError.imageEncodingFailed.errorDescription?.contains("PNG") == true)
    #expect(CaptureError.recordingAlreadyActive.errorDescription?.contains("已经") == true)
    #expect(CaptureError.recordingNotActive.errorDescription?.contains("没有") == true)
    #expect(CaptureError.recordingFailed("编码器").errorDescription?.contains("编码器") == true)
}
