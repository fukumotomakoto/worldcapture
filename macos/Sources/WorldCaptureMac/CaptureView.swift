import AppKit
import CaptureKit
import SwiftUI

@MainActor
final class CaptureViewModel: ObservableObject {
    @Published var image: NSImage?
    @Published var isCapturing = false
    @Published var errorMessage: String?
    @Published var windows: [CaptureWindow] = []
    @Published var selectedWindowID: CGWindowID?
    @Published var annotations: [CaptureAnnotation] = []
    @Published var selectedAnnotationIDs: Set<UUID> = []
    @Published var annotationTool: AnnotationKind = .rectangle
    @Published var annotationText = "说明"
    @Published var annotationColorHex = CaptureAnnotation.defaultColorHex
    @Published var annotationLineWidth: Double = 1

    static let palette = ["#FF3B30", "#FF9500", "#FFCC00", "#34C759", "#007AFF", "#FFFFFF", "#000000"]
    static let lineWidthPresets: [(name: String, value: Double)] = [("细", 0.6), ("中", 1.0), ("粗", 1.8)]

    /// 仅当恰好选中一个标注时返回它（用于文字就地改写等单项操作）。
    var selectedAnnotation: CaptureAnnotation? {
        guard selectedAnnotationIDs.count == 1, let id = selectedAnnotationIDs.first else { return nil }
        return annotations.first { $0.id == id }
    }

    var isTextSelected: Bool {
        selectedAnnotation?.kind == .text
    }

    var hasSelection: Bool {
        !selectedAnnotationIDs.isEmpty
    }
    @Published var isRecording = false
    @Published var lastRecordingURL: URL?
    @Published var recordingDuration: TimeInterval = 0
    @Published var hasScreenPermission = true
    @Published var hasAccessibilityPermission = true
    /// 是否在主界面内容区内嵌显示缩略图捕获目标选择器。
    @Published var showSourcePicker = false
    /// 可录制的显示器（多屏时供选择，单屏时直接录主屏）。
    @Published var availableDisplays: [DisplayOption] = []
    /// 最近保存的截图（最多 5 条，供“保存”旁的下拉快速打开）。
    @Published var recentSaves: [URL] = []

    struct DisplayOption: Identifiable, Hashable {
        let id: CGDirectDisplayID
        let name: String
    }

    private static let maxRecentSaves = 5

    var nextAnnotationNumber: Int {
        annotations.filter { $0.kind == .number }.count + 1
    }

    private let capturer: any ScreenCapturing
    private let regionSelector = RegionSelector()
    private let screenRecorder = ScreenRecorder()
    private var globalHotKey: GlobalHotKey?
    private var recordingTimer: Timer?
    private var recordingStartedAt: Date?

    var recordingDurationText: String {
        let totalSeconds = max(0, Int(recordingDuration))
        return String(format: "%02d:%02d", totalSeconds / 60, totalSeconds % 60)
    }

    init(capturer: any ScreenCapturing = ScreenCapturer()) {
        self.capturer = capturer
    }

    func capture() async {
        isCapturing = true
        errorMessage = nil
        defer { isCapturing = false }

        do {
            let captured = try await capturer.captureMainDisplay()
            image = NSImage(cgImage: captured, size: .zero)
            annotations = []
            selectedAnnotationIDs = []
            presentCapturePreview()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func captureRegion() async {
        // 区域选择期间隐藏本应用窗口，使待截内容完全可见、便于精确框选。
        let restoreWindows = hideOwnWindows()
        guard let selection = await regionSelector.selectRegion() else {
            restoreWindows()
            return
        }
        isCapturing = true
        errorMessage = nil
        defer { isCapturing = false }

        do {
            let captured = try await capturer.captureDisplay(id: selection.displayID, region: selection.region)
            restoreWindows()
            image = NSImage(cgImage: captured, size: .zero)
            annotations = []
            selectedAnnotationIDs = []
            presentCapturePreview()
        } catch {
            restoreWindows()
            errorMessage = error.localizedDescription
        }
    }

    /// 滚动截屏：选区后自动逐屏滚动并拼接为长图。
    func captureScrolling() async {
        guard AccessibilityPermission.isTrusted else {
            hasAccessibilityPermission = false
            AccessibilityPermission.requestPrompt()
            return
        }
        hasAccessibilityPermission = true

        let restoreWindows = hideOwnWindows()
        guard let selection = await regionSelector.selectRegion() else {
            restoreWindows()
            return
        }
        isCapturing = true
        errorMessage = nil

        let capturer = self.capturer
        let region = selection.region
        let displayID = selection.displayID
        let scrollPoint = appKitToCG(CGPoint(x: selection.globalRect.midX, y: selection.globalRect.midY))
        // 每步滚动约视口高度的 60%，留约 40% 重叠供拼接对齐。
        let scrollPixels = max(40, Int(selection.globalRect.height * 0.6))
        let engine = ScrollCaptureEngine()

        do {
            let result = try await engine.run(
                capture: { try await capturer.captureDisplay(id: displayID, region: region) },
                scroll: {
                    ScrollEventSender.scrollDown(at: scrollPoint, pixels: scrollPixels)
                    try? await Task.sleep(nanoseconds: 350_000_000) // 等待界面滚动渲染稳定
                }
            )
            restoreWindows()
            isCapturing = false
            guard let stitched = result.image else {
                errorMessage = "滚动截屏未获取到内容。"
                return
            }
            image = NSImage(cgImage: stitched, size: .zero)
            annotations = []
            selectedAnnotationIDs = []
            presentCapturePreview()
        } catch {
            restoreWindows()
            isCapturing = false
            errorMessage = error.localizedDescription
        }
    }

    func refreshAccessibilityPermission() {
        hasAccessibilityPermission = AccessibilityPermission.isTrusted
    }

    func openAccessibilitySettings() {
        guard let url = URL(string:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }

    /// AppKit 全局坐标（左下原点）转 CoreGraphics 全局坐标（左上原点），用于合成事件定位。
    /// 多屏下以主屏（原点位于 (0,0) 的那块）的高度为翻转基准，覆盖整个全局坐标平面。
    private func appKitToCG(_ point: CGPoint) -> CGPoint {
        let primaryHeight = NSScreen.screens.first(where: { $0.frame.origin == .zero })?.frame.height
            ?? NSScreen.main?.frame.height
            ?? 0
        return CGPoint(x: point.x, y: primaryHeight - point.y)
    }

    /// 隐藏 WorldCapture 自身全部可见窗口，返回恢复闭包（区域截屏时避免遮挡）。
    private func hideOwnWindows() -> () -> Void {
        let hidden = NSApp.windows.filter { $0.isVisible }
        hidden.forEach { $0.orderOut(nil) }
        return {
            guard !hidden.isEmpty else { return }
            hidden.forEach { $0.orderFront(nil) }
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func loadWindows() async {
        do {
            windows = try await capturer.availableWindows()
            hasScreenPermission = true
            if !windows.contains(where: { $0.id == selectedWindowID }) {
                selectedWindowID = windows.first?.id
            }
        } catch CaptureError.permissionDenied {
            refreshScreenPermission()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func captureSelectedWindow() async {
        guard let selectedWindowID else { return }
        await captureWindow(id: selectedWindowID)
        await loadWindows()
    }

    /// 捕获指定窗口（供可视化窗口选择器调用）。
    func captureWindow(id: CGWindowID) async {
        isCapturing = true
        errorMessage = nil
        defer { isCapturing = false }

        do {
            let captured = try await capturer.captureWindow(id: id)
            image = NSImage(cgImage: captured, size: .zero)
            annotations = []
            selectedAnnotationIDs = []
            presentCapturePreview()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 截取 WorldCapture 自身主窗口（含工具栏界面），用于做软件本身的演示截图。
    func captureOwnWindow() async {
        let candidate = NSApp.mainWindow
            ?? NSApp.keyWindow
            ?? NSApp.windows.first(where: { $0.isVisible && !($0 is NSPanel) })
        guard let window = candidate, window.windowNumber > 0 else {
            errorMessage = "找不到可截取的本应用窗口。"
            return
        }
        await captureWindow(id: CGWindowID(window.windowNumber))
    }

    /// 捕获指定显示器整屏（供可视化选择器的“整个屏幕”使用）。
    func captureDisplayFull(id displayID: CGDirectDisplayID) async {
        isCapturing = true
        errorMessage = nil
        defer { isCapturing = false }

        do {
            let captured = try await capturer.captureDisplay(id: displayID, region: nil)
            image = NSImage(cgImage: captured, size: .zero)
            annotations = []
            selectedAnnotationIDs = []
            presentCapturePreview()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func copyToClipboard() {
        guard let cgImage = renderedImage() else {
            return
        }
        do {
            let data = try PNGEncoder.encode(cgImage)
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setData(data, forType: .png)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 刷新屏幕录制权限状态；尚未决定时触发一次系统授权弹窗。
    func refreshScreenPermission(requestIfNeeded: Bool = false) {
        let granted = ScreenCapturePermission.isGranted
        hasScreenPermission = granted
        if !granted && requestIfNeeded {
            ScreenCapturePermission.request()
            hasScreenPermission = ScreenCapturePermission.isGranted
        }
    }

    func openScreenRecordingSettings() {
        guard let url = URL(string:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else { return }
        NSWorkspace.shared.open(url)
    }

    func installGlobalHotKey() {
        guard globalHotKey == nil else { return }
        globalHotKey = GlobalHotKey { [weak self] in
            Task { await self?.captureRegion() }
        }
    }

    func undoAnnotation() {
        guard !annotations.isEmpty else { return }
        let removed = annotations.removeLast()
        selectedAnnotationIDs.remove(removed.id)
    }

    func clearAnnotations() {
        annotations.removeAll()
        selectedAnnotationIDs = []
    }

    /// 删除全部选中标注。
    func deleteSelectedAnnotation() {
        guard !selectedAnnotationIDs.isEmpty else { return }
        annotations.removeAll { selectedAnnotationIDs.contains($0.id) }
        selectedAnnotationIDs = []
    }

    /// 设为当前绘制颜色；选中的标注一并更新（支持多选批量改色）。
    func setAnnotationColor(_ hex: String) {
        annotationColorHex = hex
        for index in annotations.indices where selectedAnnotationIDs.contains(annotations[index].id) {
            annotations[index].colorHex = hex
        }
    }

    /// 设为当前线宽；选中的标注一并更新（支持多选批量改线宽）。
    func setAnnotationLineWidth(_ width: Double) {
        annotationLineWidth = width
        for index in annotations.indices where selectedAnnotationIDs.contains(annotations[index].id) {
            annotations[index].lineWidth = width
        }
    }

    /// 更新选中文字标注的文案（仅单选时）。
    func updateSelectedLabel(_ text: String) {
        guard let id = selectedAnnotation?.id,
              let index = annotations.firstIndex(where: { $0.id == id }) else { return }
        annotations[index].label = text
    }

    /// 枚举所有可录制显示器（主屏标注“（主）”，附原生像素尺寸）。
    func loadDisplays() {
        let mainID = CGMainDisplayID()
        availableDisplays = NSScreen.screens.enumerated().compactMap { index, screen in
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
                return nil
            }
            let pixelWidth = Int((screen.frame.width * screen.backingScaleFactor).rounded())
            let pixelHeight = Int((screen.frame.height * screen.backingScaleFactor).rounded())
            let name = "屏幕 \(index + 1)\(id == mainID ? "（主）" : "") · \(pixelWidth)×\(pixelHeight)"
            return DisplayOption(id: id, name: name)
        }
    }

    func toggleRecording() async {
        if isRecording {
            await stopRecording()
        } else {
            await beginRecording(displayID: CGMainDisplayID())
        }
    }

    /// 录制指定显示器：先选输出路径，再开始录制。
    func beginRecording(displayID: CGDirectDisplayID) async {
        guard !isRecording else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.mpeg4Movie]
        panel.nameFieldStringValue = "WorldCapture-\(Self.timestamp()).mp4"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try await screenRecorder.startRecording(displayID: displayID, to: url)
            lastRecordingURL = url
            isRecording = true
            startRecordingTimer()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func stopRecording() async {
        do {
            try await screenRecorder.stopRecording()
            isRecording = false
            stopRecordingTimer()
        } catch {
            isRecording = screenRecorder.isRecording
            if !isRecording { stopRecordingTimer() }
            errorMessage = error.localizedDescription
        }
    }

    /// 把当前截图（含已渲染标注）钉到屏幕上。
    func pinCurrentImage() {
        guard let cgImage = renderedImage() else { return }
        PinnedImageController.shared.pin(NSImage(cgImage: cgImage, size: .zero))
    }

    /// 截屏后在屏幕角落弹出悬浮预览卡片。
    private func presentCapturePreview() {
        guard let image else { return }
        CapturePreviewController.shared.present(image: image, actions: CapturePreviewActions(
            copy: { [weak self] in self?.copyToClipboard() },
            save: { [weak self] in self?.save() },
            pin: { [weak self] in self?.pinCurrentImage() },
            edit: { NSApp.activate(ignoringOtherApps: true) }
        ))
    }

    func revealLastRecording() {
        guard let lastRecordingURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([lastRecordingURL])
    }

    func save() {
        guard let cgImage = renderedImage() else {
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "WorldCapture-\(Self.timestamp()).png"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try PNGEncoder.encode(cgImage).write(to: url, options: .atomic)
            recordRecentSave(url)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func recordRecentSave(_ url: URL) {
        recentSaves.removeAll { $0 == url }
        recentSaves.insert(url, at: 0)
        if recentSaves.count > Self.maxRecentSaves {
            recentSaves = Array(recentSaves.prefix(Self.maxRecentSaves))
        }
    }

    /// 在默认应用中打开文件（如预览）。
    func openSavedFile(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    /// 在 Finder 中定位文件。
    func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// 复位到初始界面：清空当前截图、标注与录制提示（录制中不允许）。
    func reset() {
        guard !isRecording else { return }
        image = nil
        annotations = []
        selectedAnnotationIDs = []
        errorMessage = nil
        lastRecordingURL = nil
        recordingDuration = 0
        showSourcePicker = false
        annotationTool = .rectangle
    }

    private func renderedImage() -> CGImage? {
        guard let image, let original = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        guard !annotations.isEmpty else { return original }
        return AnnotationRenderer.render(image: original, annotations: annotations)
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }

    private func startRecordingTimer() {
        recordingDuration = 0
        recordingStartedAt = Date()
        recordingTimer?.invalidate()
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let recordingStartedAt = self.recordingStartedAt else { return }
                self.recordingDuration = Date().timeIntervalSince(recordingStartedAt)
            }
        }
    }

    private func stopRecordingTimer() {
        if let recordingStartedAt {
            recordingDuration = Date().timeIntervalSince(recordingStartedAt)
        }
        recordingStartedAt = nil
        recordingTimer?.invalidate()
        recordingTimer = nil
    }
}

struct CaptureView: View {
    @ObservedObject var model: CaptureViewModel
    @StateObject private var preview = PreviewGestureController()
    @State private var showRecentSaves = false
    @State private var panActive = false

    static func swatchColor(_ hex: String) -> Color {
        let c = RGBAColor(hex: hex)
        return Color(.sRGB, red: c.red, green: c.green, blue: c.blue, opacity: c.alpha)
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            captureBar
            Divider()

            if !model.hasScreenPermission {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("需要屏幕录制权限")
                            .font(.callout.weight(.semibold))
                        Text("请在系统设置中允许 WorldCapture，授权后请重新启动应用。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("打开系统设置") { model.openScreenRecordingSettings() }
                    Button("重新检查") { model.refreshScreenPermission() }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(Color(nsColor: .controlBackgroundColor))
            }

            if !model.hasAccessibilityPermission {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("滚动截屏需要辅助功能权限")
                            .font(.callout.weight(.semibold))
                        Text("请在系统设置中允许 WorldCapture 控制电脑（辅助功能），授权后重试。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("打开系统设置") { model.openAccessibilitySettings() }
                    Button("重新检查") { model.refreshAccessibilityPermission() }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(Color(nsColor: .controlBackgroundColor))
            }

            if model.isRecording {
                HStack(spacing: 8) {
                    Circle().fill(.red).frame(width: 8, height: 8)
                    Text("正在录制主屏幕与系统音频")
                        .font(.callout.weight(.medium))
                    Text(model.recordingDurationText)
                        .font(.system(.callout, design: .monospaced).weight(.semibold))
                    Spacer()
                    Text(model.lastRecordingURL?.lastPathComponent ?? "")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 10)
            } else if let recordingURL = model.lastRecordingURL {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("录制已保存：\(recordingURL.lastPathComponent)")
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(model.recordingDurationText)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        model.revealLastRecording()
                    } label: {
                        Label("在 Finder 中显示", systemImage: "folder")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 10)
                .background(Color.green.opacity(0.12))
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Color.green.opacity(0.45)).frame(height: 1)
                }
            }

            if model.image != nil && !model.showSourcePicker {
                annotationToolArea
                annotationOperationArea
                Divider()
            }

            contentArea
        }
        .alert("操作失败", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "未知错误")
        }
        .task {
            model.installGlobalHotKey()
            model.refreshScreenPermission(requestIfNeeded: true)
            model.loadDisplays()
            await model.loadWindows()
        }
        .onAppear { preview.start() }
        .onDisappear { preview.stop() }
    }

    // MARK: - 顶部标题与全局动作

    private var headerBar: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("WorldCapture")
                    .font(.title2.bold())
                Text("本地优先的跨平台截屏与录屏工具")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 24)
            HStack(spacing: 10) {
                Button {
                    model.reset()
                } label: {
                    Label("复位", systemImage: "arrow.counterclockwise")
                }
                .disabled(model.isRecording || (model.image == nil && model.lastRecordingURL == nil))
                .help("清空当前截图与标注，回到初始界面")

                recordingControl

                Button {
                    model.pinCurrentImage()
                } label: {
                    Label("钉屏", systemImage: "pin")
                }
                .disabled(model.image == nil)
                .help("把当前截图钉为置顶悬浮窗")

                saveControl

                Button {
                    model.copyToClipboard()
                } label: {
                    Label("复制", systemImage: "doc.on.doc")
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(model.image == nil)
            }
            .labelStyle(.titleAndIcon)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    /// 录制控件：录制中显示停止；多屏时用菜单选屏；单屏直接录主屏。
    @ViewBuilder
    private var recordingControl: some View {
        if model.isRecording {
            Button {
                Task { await model.toggleRecording() }
            } label: {
                Label("停止录制", systemImage: "stop.circle.fill")
            }
            .tint(Color.red)
        } else if model.availableDisplays.count > 1 {
            Menu {
                ForEach(model.availableDisplays) { display in
                    Button(display.name) {
                        Task { await model.beginRecording(displayID: display.id) }
                    }
                }
            } label: {
                Label("录制屏幕", systemImage: "record.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("选择要录制的显示器")
        } else {
            Button {
                Task { await model.toggleRecording() }
            } label: {
                Label("录制屏幕", systemImage: "record.circle")
            }
        }
    }

    /// 保存控件：主按钮保存；右侧下拉列出最近保存记录。
    private var saveControl: some View {
        HStack(spacing: 2) {
            Button {
                model.save()
            } label: {
                Label("保存", systemImage: "square.and.arrow.down")
            }
            .disabled(model.image == nil)

            Button {
                showRecentSaves.toggle()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
            }
            .disabled(model.recentSaves.isEmpty)
            .help("最近保存的截图")
            .popover(isPresented: $showRecentSaves, arrowEdge: .bottom) {
                RecentSavesList(
                    urls: model.recentSaves,
                    onOpenFile: { model.openSavedFile($0) },
                    onRevealFolder: { model.revealInFinder($0) }
                )
            }
        }
    }

    // MARK: - 捕获来源工具栏

    private var captureBar: some View {
        HStack(spacing: 12) {
            Button {
                Task { await model.captureRegion() }
            } label: {
                Label("区域", systemImage: "selection.pin.in.out")
            }
            .disabled(model.isCapturing)

            Button {
                Task { await model.capture() }
            } label: {
                Label("主屏幕", systemImage: "display")
            }
            .disabled(model.isCapturing)

            Button {
                Task { await model.captureScrolling() }
            } label: {
                Label("滚动长图", systemImage: "arrow.down.doc")
            }
            .disabled(model.isCapturing)
            .help("选择区域后自动滚动并拼接成长截图")

            Button {
                Task { await model.captureOwnWindow() }
            } label: {
                Label("本窗口", systemImage: "macwindow.on.rectangle")
            }
            .disabled(model.isCapturing)
            .help("截取 WorldCapture 自身窗口")

            Divider().frame(height: 22)

            Menu {
                if model.windows.isEmpty {
                    Text("没有可用窗口")
                } else {
                    ForEach(model.windows) { window in
                        Button(window.displayName) {
                            Task { await model.captureWindow(id: window.id) }
                        }
                    }
                }
                Divider()
                Button("刷新列表") { Task { await model.loadWindows() } }
            } label: {
                Label("窗口", systemImage: "macwindow")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .disabled(model.isCapturing)
            .help("直接截取某个窗口")

            Button {
                model.showSourcePicker.toggle()
            } label: {
                Label("缩略图选择", systemImage: "square.grid.2x2")
            }
            .disabled(model.isCapturing)
            .help("以缩略图选择窗口或整个屏幕")

            Spacer(minLength: 12)
            Text("⌘⇧2")
                .font(.callout.monospaced())
                .foregroundStyle(.secondary)
                .help("区域截屏快捷键")
        }
        .labelStyle(.titleAndIcon)
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
    }

    // MARK: - 标注：工具区（绘制工具 / 颜色 / 线宽）

    private var annotationToolArea: some View {
        HStack(spacing: 14) {
            Picker("标注工具", selection: $model.annotationTool) {
                Text("矩形").tag(AnnotationKind.rectangle)
                Text("箭头").tag(AnnotationKind.arrow)
                Text("文字").tag(AnnotationKind.text)
                Text("序号").tag(AnnotationKind.number)
                Text("马赛克").tag(AnnotationKind.mosaic)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 320)

            Divider().frame(height: 20)

            HStack(spacing: 6) {
                ForEach(CaptureViewModel.palette, id: \.self) { hex in
                    let isSelected = model.annotationColorHex == hex
                    Circle()
                        .fill(Self.swatchColor(hex))
                        .frame(width: 18, height: 18)
                        .overlay(
                            Circle().stroke(
                                isSelected ? Color.accentColor : Color.primary.opacity(0.25),
                                lineWidth: isSelected ? 2.5 : 1
                            )
                        )
                        .onTapGesture { model.setAnnotationColor(hex) }
                }
            }
            .help("标注颜色")

            Divider().frame(height: 20)

            Picker("线宽", selection: Binding(
                get: { model.annotationLineWidth },
                set: { model.setAnnotationLineWidth($0) }
            )) {
                ForEach(CaptureViewModel.lineWidthPresets, id: \.value) { preset in
                    Text(preset.name).tag(preset.value)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 130)
            .help("线宽")

            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 6)
    }

    // MARK: - 标注：操作区（文字输入 / 删除 / 撤销 / 清空）

    private var annotationOperationArea: some View {
        HStack(spacing: 12) {
            TextField(textFieldPrompt, text: textFieldBinding)
                .textFieldStyle(.roundedBorder)
                .frame(width: 220)
                .disabled(!isTextFieldEditable)

            Button {
                model.deleteSelectedAnnotation()
            } label: {
                Label("删除", systemImage: "trash")
            }
            .keyboardShortcut(.delete, modifiers: [])
            .disabled(!model.hasSelection)

            Button {
                model.undoAnnotation()
            } label: {
                Label("撤销", systemImage: "arrow.uturn.backward")
            }
            .keyboardShortcut("z", modifiers: .command)
            .disabled(model.annotations.isEmpty)

            Button {
                model.clearAnnotations()
            } label: {
                Label("清空", systemImage: "xmark")
            }
            .disabled(model.annotations.isEmpty)

            Spacer()
            Text("点选拖动/缩放 · Shift 多选 · 滚轮缩放图片 · 空格+拖动平移 · 保存或复制时才渲染")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .labelStyle(.titleAndIcon)
        .padding(.horizontal, 24)
        .padding(.top, 6)
        .padding(.bottom, 12)
    }

    private var isTextFieldEditable: Bool {
        model.isTextSelected || model.annotationTool == .text
    }

    private var textFieldPrompt: String {
        if model.isTextSelected {
            return "编辑选中文字"
        } else if model.annotationTool == .text {
            return "标注文字"
        } else {
            return "选择“文字”工具以输入"
        }
    }

    private var textFieldBinding: Binding<String> {
        if model.isTextSelected {
            return Binding(
                get: { model.selectedAnnotation?.label ?? "" },
                set: { model.updateSelectedLabel($0) }
            )
        } else {
            return $model.annotationText
        }
    }

    // MARK: - 内容区（缩略图选择器 / 预览 / 空态）

    private var contentArea: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            if model.showSourcePicker {
                CaptureSourcePicker(
                    onPickWindow: { id in
                        model.showSourcePicker = false
                        Task { await model.captureWindow(id: id) }
                    },
                    onPickDisplay: { id in
                        model.showSourcePicker = false
                        Task { await model.captureDisplayFull(id: id) }
                    },
                    onClose: { model.showSourcePicker = false }
                )
            } else if let image = model.image {
                imagePreview(image)
            } else if model.isCapturing {
                ProgressView("正在捕获…")
            } else {
                ContentUnavailableView(
                    "尚无截屏",
                    systemImage: "rectangle.dashed",
                    description: Text("点击“截取主屏幕”验证原生捕获链路。")
                )
            }
        }
    }

    /// 截图预览：支持滚轮缩放与空格+拖动平移，便于精准打码与查看清晰度。
    @ViewBuilder
    private func imagePreview(_ image: NSImage) -> some View {
        GeometryReader { proxy in
            ZStack {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                AnnotationCanvas(
                    imageSize: image.size,
                    annotations: $model.annotations,
                    selectedIDs: $model.selectedAnnotationIDs,
                    tool: model.annotationTool,
                    textLabel: model.annotationText,
                    nextNumber: model.nextAnnotationNumber,
                    colorHex: model.annotationColorHex,
                    lineWidth: model.annotationLineWidth
                )
                .allowsHitTesting(!preview.isSpaceDown)
            }
            .scaleEffect(preview.zoom)
            .offset(preview.pan)
            .frame(width: proxy.size.width, height: proxy.size.height)
            .contentShape(Rectangle())
            .gesture(panGesture, including: preview.isSpaceDown ? .gesture : .subviews)
            .onAppear { preview.previewFrame = proxy.frame(in: .global) }
            .onChange(of: proxy.frame(in: .global)) { _, newValue in
                preview.previewFrame = newValue
            }
        }
        .padding(24)
        .clipped()
        .overlay(alignment: .bottomTrailing) { zoomControls }
        .overlay(alignment: .top) { panHint }
        .onChange(of: model.image.map(ObjectIdentifier.init)) { _, _ in
            preview.reset()
            panActive = false
        }
    }

    private var panGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                guard preview.isSpaceDown else { return }
                if !panActive {
                    panActive = true
                    preview.beginPan()
                }
                preview.updatePan(translation: value.translation)
            }
            .onEnded { _ in panActive = false }
    }

    private var zoomControls: some View {
        HStack(spacing: 8) {
            Button { preview.setZoom(preview.zoom / 1.25) } label: {
                Image(systemName: "minus.magnifyingglass")
            }
            .disabled(preview.zoom <= PreviewGestureController.minZoom)

            Text("\(Int(preview.zoom * 100))%")
                .font(.caption.monospaced())
                .frame(width: 46)

            Button { preview.setZoom(preview.zoom * 1.25) } label: {
                Image(systemName: "plus.magnifyingglass")
            }
            .disabled(preview.zoom >= PreviewGestureController.maxZoom)

            Button { preview.reset() } label: {
                Image(systemName: "arrow.up.left.and.down.right.magnifyingglass")
            }
            .help("适应窗口")
            .disabled(preview.zoom == PreviewGestureController.minZoom && preview.pan == .zero)
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.thinMaterial, in: Capsule())
        .padding(16)
    }

    @ViewBuilder
    private var panHint: some View {
        if preview.isSpaceDown {
            Label("平移模式：拖动移动画面", systemImage: "hand.draw")
                .font(.caption.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.thinMaterial, in: Capsule())
                .padding(.top, 16)
        }
    }
}

/// “保存”旁下拉的最近保存列表：点文件名打开图片，悬停显示文件夹图标可定位到 Finder。
private struct RecentSavesList: View {
    let urls: [URL]
    let onOpenFile: (URL) -> Void
    let onRevealFolder: (URL) -> Void

    @State private var hovered: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("最近保存")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 2)

            ForEach(urls, id: \.self) { url in
                HStack(spacing: 8) {
                    Image(systemName: "photo")
                        .foregroundStyle(.secondary)
                    Text(url.lastPathComponent)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 12)
                    Button {
                        onRevealFolder(url)
                    } label: {
                        Image(systemName: "folder")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .opacity(hovered == url ? 1 : 0)
                    .help("在 Finder 中显示")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
                .background(hovered == url ? Color.accentColor.opacity(0.12) : Color.clear)
                .onHover { hovering in
                    hovered = hovering ? url : (hovered == url ? nil : hovered)
                }
                .onTapGesture { onOpenFile(url) }
            }
        }
        .frame(width: 340)
        .padding(.bottom, 8)
    }
}
