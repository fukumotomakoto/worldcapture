import CoreGraphics

public struct CaptureWindow: Identifiable, Equatable, Sendable {
    public let id: CGWindowID
    public let applicationName: String
    public let title: String
    public let frame: CGRect

    public init(id: CGWindowID, applicationName: String, title: String, frame: CGRect) {
        self.id = id
        self.applicationName = applicationName
        self.title = title
        self.frame = frame
    }

    public var displayName: String {
        title.isEmpty ? applicationName : "\(applicationName) — \(title)"
    }
}


public extension Array where Element == CaptureWindow {
    /// 去掉 App 的隐形辅助窗口。
    ///
    /// Chrome 之类的 App 会在主窗口周围挂几块无标题的透明覆盖层（宽度等于主窗口、几十像素高），
    /// 系统把它们当普通窗口列出来；单独截取时 ScreenCaptureKit 只会把主窗口缩成一角画进去，对用户毫无意义。
    /// 规则：同一 App 已有带标题的窗口时，丢掉它的无标题窗口；App 只有无标题窗口时（如桌面精灵）原样保留。
    /// 以 applicationName 归组而不是进程号，是因为 CaptureWindow 不带进程号，而同名 App 并存的情况极少。
    func droppingUntitledHelperWindows() -> [CaptureWindow] {
        let appsWithTitledWindows = Set(
            compactMap { $0.title.isEmpty ? nil : $0.applicationName }
        )
        return filter { !$0.title.isEmpty || !appsWithTitledWindows.contains($0.applicationName) }
    }
}
