import AVFoundation

/// 麦克风权限的检测与申请。
///
/// 与屏幕录制（TCC 无用途说明键、首次调用时由系统兜底弹窗）不同，麦克风权限走
/// AVFoundation，要求 Info.plist 提供 `NSMicrophoneUsageDescription`，且必须由 App
/// 主动申请。录制前务必确认已授权：`SCStreamConfiguration.captureMicrophone` 在无
/// 授权时不保证会报错，用户可能拿到一段自以为有讲解声、实则静音的视频。
public enum MicrophonePermission {
    public static var status: AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .audio)
    }

    public static var isGranted: Bool { status == .authorized }

    /// 已被用户拒绝或受描述文件限制。此时 `request()` 不再弹窗，只能去系统设置里改。
    public static var isDenied: Bool { status == .denied || status == .restricted }

    /// 申请麦克风权限。仅在权限尚未决定时弹出系统对话框；返回调用后的当前状态。
    @discardableResult
    public static func request() async -> Bool {
        if isGranted { return true }
        if isDenied { return false }
        return await AVCaptureDevice.requestAccess(for: .audio)
    }
}
