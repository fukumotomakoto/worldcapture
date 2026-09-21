import AppKit
import SwiftUI

/// 顶部工具条：一个吸附在屏幕顶端（菜单栏正下方）的小标签，鼠标指上去滑出一排横向按钮，移开即收回。
///
/// 师弟 2026-09-21 定的形态：它是启动后的**唯一前脸**（主窗口默认不显示，截完才弹编辑器），
/// 默认开启；设置里可以关掉（铁律 9：自用时把前脸让给桌面精灵）。
/// 实现上是一扇不激活的浮动面板：折叠时只有 56×9 的标签，展开时整条工具条；
/// 用全局鼠标移动监视器判断悬停，面板可左右拖动，位置按屏宽比例记住。
@MainActor
final class TopDockController: ObservableObject {
    static let shared = TopDockController()

    static let enabledKey = "dock.enabled"
    static let xFractionKey = "dock.xFraction"

    /// 启动时读一次（决定主窗口是否随启动打开）。
    static var isEnabledAtLaunch: Bool {
        UserDefaults.standard.object(forKey: enabledKey) == nil ? true : UserDefaults.standard.bool(forKey: enabledKey)
    }

    @Published private(set) var isEnabled = TopDockController.isEnabledAtLaunch
    @Published private(set) var isExpanded = false

    static let collapsedSize = CGSize(width: 56, height: 9)
    static let expandedSize = CGSize(width: 512, height: 46)

    private var panel: NSPanel?
    private var model: CaptureViewModel?
    private var monitors: [Any] = []
    private var collapseTask: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []
    private var isRepositioning = false

    private init() {}

    func attach(model: CaptureViewModel) {
        self.model = model
        if isEnabled { show() }
    }

    func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: Self.enabledKey)
        isEnabled = enabled
        if enabled { show() } else { hide() }
    }

    // MARK: - 面板

    private func show() {
        guard panel == nil, let model else { return }
        let panel = NSPanel(
            contentRect: CGRect(origin: .zero, size: Self.collapsedSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentView = NSHostingView(rootView: TopDockView(controller: self, model: model))
        self.panel = panel
        reposition()
        panel.orderFrontRegardless()
        installMonitors()
    }

    private func hide() {
        removeMonitors()
        panel?.orderOut(nil)
        panel = nil
        isExpanded = false
    }

    /// 屏幕：带菜单栏的主屏。顶边 = visibleFrame.maxY（菜单栏正下方）。
    private var screen: NSScreen? { NSScreen.screens.first ?? NSScreen.main }

    private var xFraction: CGFloat {
        get {
            let stored = UserDefaults.standard.object(forKey: Self.xFractionKey) as? Double
            return CGFloat(stored ?? 0.5)
        }
        set { UserDefaults.standard.set(Double(newValue), forKey: Self.xFractionKey) }
    }

    private func frame(expanded: Bool) -> CGRect {
        guard let screen else { return .zero }
        let size = expanded ? Self.expandedSize : Self.collapsedSize
        let top = screen.visibleFrame.maxY
        var x = screen.frame.minX + screen.frame.width * xFraction - size.width / 2
        x = min(max(x, screen.frame.minX + 8), screen.frame.maxX - size.width - 8)
        return CGRect(x: x, y: top - size.height, width: size.width, height: size.height)
    }

    private func reposition() {
        guard let panel else { return }
        isRepositioning = true
        panel.setFrame(frame(expanded: isExpanded), display: true)
        isRepositioning = false
    }

    private func setExpanded(_ expanded: Bool) {
        guard isExpanded != expanded, let panel else { return }
        isExpanded = expanded
        isRepositioning = true
        panel.setFrame(frame(expanded: expanded), display: true, animate: false)
        isRepositioning = false
    }

    // MARK: - 悬停与拖动

    private func installMonitors() {
        guard monitors.isEmpty else { return }
        let handler: (NSEvent) -> Void = { [weak self] _ in
            Task { @MainActor in self?.mouseMoved(to: NSEvent.mouseLocation) }
        }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: handler) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: { event in
            handler(event)
            return event
        }) {
            monitors.append(local)
        }
        observers.append(NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification, object: nil, queue: .main
        ) { [weak self] note in
            // NSWindow 不是 Sendable：只把窗口号（Int）带进主 actor。
            let number = (note.object as? NSWindow)?.windowNumber
            Task { @MainActor in self?.panelDidMove(windowNumber: number) }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.reposition() }
        })
    }

    private func removeMonitors() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors = []
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers = []
        collapseTask?.cancel()
    }

    private func mouseMoved(to point: CGPoint) {
        guard let panel else { return }
        let hot = panel.frame.insetBy(dx: -10, dy: -10)
        if hot.contains(point) {
            collapseTask?.cancel()
            collapseTask = nil
            if !isExpanded { setExpanded(true) }
        } else if isExpanded, collapseTask == nil {
            collapseTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled else { return }
                self?.collapseTask = nil
                guard let self, let panel = self.panel else { return }
                if !panel.frame.insetBy(dx: -10, dy: -10).contains(NSEvent.mouseLocation) {
                    self.setExpanded(false)
                }
            }
        }
    }

    /// 拖动后：y 吸回顶边，x 按屏宽比例记住。
    private func panelDidMove(windowNumber: Int?) {
        guard let panel, windowNumber == panel.windowNumber, !isRepositioning, let screen else { return }
        let centerX = panel.frame.midX
        xFraction = (centerX - screen.frame.minX) / max(1, screen.frame.width)
        reposition()
    }
}

/// 工具条内容：折叠时是一个小标签，展开时是一排图标按钮。
private struct TopDockView: View {
    @ObservedObject var controller: TopDockController
    @ObservedObject var model: CaptureViewModel

    var body: some View {
        Group {
            if controller.isExpanded {
                expandedBar
            } else {
                tab
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var tab: some View {
        VStack {
            UnevenRoundedRectangle(bottomLeadingRadius: 6, bottomTrailingRadius: 6)
                .fill(.regularMaterial)
                .overlay(
                    Capsule().fill(Color.secondary.opacity(0.7)).frame(width: 28, height: 3)
                )
                .frame(width: TopDockController.collapsedSize.width, height: TopDockController.collapsedSize.height)
            Spacer(minLength: 0)
        }
    }

    private var expandedBar: some View {
        HStack(spacing: 2) {
            dockButton("capture.region", "selection.pin.in.out") { Task { await model.captureRegion() } }
            dockButton("capture.fullscreen", "display") { Task { await model.capture() } }
            dockButton("capture.window", "macwindow") {
                model.sourcePicker = .window
                model.openMainWindow()
            }
            dockButton("capture.scroll", "arrow.down.doc") { Task { await model.captureScrolling() } }
            Divider().frame(height: 22).padding(.horizontal, 4)
            dockButton(model.isRecording ? "record.stop" : "record.screen",
                       model.isRecording ? "stop.circle.fill" : "record.circle") { Task { await model.toggleRecording() } }
            dockButton("record.region", "rectangle.dashed.badge.record") { Task { await model.beginRegionRecording() } }
            dockButton(model.isGIFRecording ? "gif.stop" : "gif.button", "photo.stack") { Task { await model.toggleGIFRecording() } }
            Divider().frame(height: 22).padding(.horizontal, 4)
            dockButton("menu.ocr", "text.viewfinder") { Task { await model.captureRegionAndExtractText() } }
            dockButton("mirror.button", "character.bubble") { Task { await model.startTranslationMirror() } }
            Divider().frame(height: 22).padding(.horizontal, 4)
            dockButton("menu.showMain", "macwindow.on.rectangle") { model.openMainWindow() }
        }
        .padding(.horizontal, 10)
        .frame(width: TopDockController.expandedSize.width, height: TopDockController.expandedSize.height)
        .background(.regularMaterial, in: UnevenRoundedRectangle(bottomLeadingRadius: 12, bottomTrailingRadius: 12))
        .overlay(alignment: .bottom) {
            Capsule().fill(Color.secondary.opacity(0.5)).frame(width: 28, height: 3).padding(.bottom, 3)
        }
    }

    private func dockButton(_ key: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .medium))
                .frame(width: 34, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(Loc.s(key))
    }
}
