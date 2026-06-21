import Foundation

public enum CaptureError: LocalizedError, Equatable {
    case noDisplayAvailable
    case windowUnavailable
    case permissionDenied
    case imageEncodingFailed
    case recordingAlreadyActive
    case recordingNotActive
    case recordingFailed(String)

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
        case .recordingAlreadyActive:
            "屏幕录制已经开始。"
        case .recordingNotActive:
            "当前没有正在进行的屏幕录制。"
        case let .recordingFailed(message):
            "录屏失败：\(message)"
        }
    }
}
