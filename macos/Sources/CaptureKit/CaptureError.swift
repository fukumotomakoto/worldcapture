import Foundation

public enum CaptureError: LocalizedError, Equatable {
    case noDisplayAvailable
    case permissionDenied
    case imageEncodingFailed

    public var errorDescription: String? {
        switch self {
        case .noDisplayAvailable:
            "没有找到可捕获的显示器。"
        case .permissionDenied:
            "缺少屏幕录制权限。请在系统设置的隐私与安全性中允许 WorldCapture。"
        case .imageEncodingFailed:
            "无法将捕获内容编码为 PNG。"
        }
    }
}

