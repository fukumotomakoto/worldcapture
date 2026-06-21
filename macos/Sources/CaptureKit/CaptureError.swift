import Foundation

public enum CaptureError: LocalizedError, Equatable {
    case noDisplayAvailable
    case windowUnavailable
    case permissionDenied
    case imageEncodingFailed

    public var errorDescription: String? {
        switch self {
        case .noDisplayAvailable:
            "没有找到可捕获的显示器。"
        case .windowUnavailable:
            "目标窗口已经关闭或暂时无法捕获。"
        case .permissionDenied:
            "缺少屏幕录制权限。请在系统设置的隐私与安全性中允许 WorldCapture。"
        case .imageEncodingFailed:
            "无法将捕获内容编码为 PNG。"
        }
    }
}
