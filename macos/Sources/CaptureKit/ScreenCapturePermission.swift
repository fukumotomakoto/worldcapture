import CoreGraphics

/// 屏幕录制（含系统音频）权限的检测与申请。
///
/// macOS 的屏幕录制权限由 TCC 管理，没有对应的 Info.plist 用途说明键；首次调用
/// ScreenCaptureKit 时由系统弹窗处理。对 ad-hoc 签名的开发构建，TCC 按二进制 cdhash
/// 记账，因此每次重新构建都可能让此前的授权失配；用 `isGranted` 检测真实状态，避免
/// 依赖系统设置里可能陈旧的条目。
public enum ScreenCapturePermission {
    /// 当前二进制是否真正拥有屏幕录制权限。
    public static var isGranted: Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// 申请屏幕录制权限。仅在权限尚未决定时弹出系统对话框；返回调用后的当前状态。
    /// 授权后通常需要重启应用才会对本进程生效。
    @discardableResult
    public static func request() -> Bool {
        CGRequestScreenCaptureAccess()
    }
}
