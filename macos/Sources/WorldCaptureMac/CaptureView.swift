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
    @Published var isWindowPickerPresented = false

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

    func toggleRecording() async {
        if isRecording {
            await stopRecording()
        } else {
            await startRecording()
        }
    }

    private func startRecording() async {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.mpeg4Movie]
        panel.nameFieldStringValue = "WorldCapture-\(Self.timestamp()).mp4"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try await screenRecorder.startMainDisplayRecording(to: url)
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
        } catch {
            errorMessage = error.localizedDescription
        }
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

    static func swatchColor(_ hex: String) -> Color {
        let c = RGBAColor(hex: hex)
        return Color(.sRGB, red: c.red, green: c.green, blue: c.blue, opacity: c.alpha)
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("WorldCapture")
                            .font(.title2.bold())
                        Text("本地优先的跨平台截屏与录屏工具")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        Task { await model.toggleRecording() }
                    } label: {
                        Label(
                            model.isRecording ? "停止录制" : "录制屏幕",
                            systemImage: model.isRecording ? "stop.circle.fill" : "record.circle"
                        )
                        .foregroundStyle(model.isRecording ? .red : .primary)
                    }

                    Button("钉屏") { model.pinCurrentImage() }
                        .disabled(model.image == nil)
                        .help("把当前截图钉为置顶悬浮窗")

                    Button("保存 PNG") { model.save() }
                        .disabled(model.image == nil)

                    Button("复制") { model.copyToClipboard() }
                        .keyboardShortcut("c", modifiers: [.command, .shift])
                        .disabled(model.image == nil)
                }

                HStack(spacing: 10) {
                    Text("窗口")
                        .font(.callout.weight(.medium))
                    Picker("选择窗口", selection: $model.selectedWindowID) {
                        Text(model.windows.isEmpty ? "没有可用窗口" : "选择窗口").tag(CGWindowID?.none)
                        ForEach(model.windows) { window in
                            Text(window.displayName).tag(Optional(window.id))
                        }
                    }
                    .labelsHidden()
                    .frame(minWidth: 260, maxWidth: 380)

                    Button {
                        Task { await model.loadWindows() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("刷新窗口列表")

                    Button("截取窗口") {
                        Task { await model.captureSelectedWindow() }
                    }
                    .disabled(model.isCapturing || model.selectedWindowID == nil)

                    Button("窗口预览…") { model.isWindowPickerPresented = true }
                        .disabled(model.isCapturing)
                        .help("以缩略图选择窗口或整个屏幕")

                    Divider().frame(height: 20)

                    Button("选择区域") {
                        Task { await model.captureRegion() }
                    }
                    .disabled(model.isCapturing)

                    Button("截取主屏幕") {
                        Task { await model.capture() }
                    }
                    .disabled(model.isCapturing)

                    Button("滚动截屏") {
                        Task { await model.captureScrolling() }
                    }
                    .disabled(model.isCapturing)
                    .help("选择区域后自动滚动并拼接成长截图")

                    Spacer()
                    Text("⌘⇧2 区域截屏")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(20)

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
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text("录制已保存：\(recordingURL.lastPathComponent)")
                        .font(.callout)
                        .lineLimit(1)
                    Text(model.recordingDurationText)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("在 Finder 中显示") { model.revealLastRecording() }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 10)
            }

            if model.image != nil {
                HStack(spacing: 10) {
                    Picker("标注工具", selection: $model.annotationTool) {
                        Text("矩形").tag(AnnotationKind.rectangle)
                        Text("箭头").tag(AnnotationKind.arrow)
                        Text("文字").tag(AnnotationKind.text)
                        Text("序号").tag(AnnotationKind.number)
                        Text("马赛克").tag(AnnotationKind.mosaic)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 360)

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
                    .frame(width: 120)
                    .help("线宽")

                    if model.isTextSelected {
                        TextField("编辑文字", text: Binding(
                            get: { model.selectedAnnotation?.label ?? "" },
                            set: { model.updateSelectedLabel($0) }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 160)
                    } else if model.annotationTool == .text {
                        TextField("标注文字", text: $model.annotationText)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 160)
                    }

                    Button("删除选中") { model.deleteSelectedAnnotation() }
                        .keyboardShortcut(.delete, modifiers: [])
                        .disabled(!model.hasSelection)
                    Button("撤销") { model.undoAnnotation() }
                        .keyboardShortcut("z", modifiers: .command)
                        .disabled(model.annotations.isEmpty)
                    Button("清空标注") { model.clearAnnotations() }
                        .disabled(model.annotations.isEmpty)
                    Spacer()
                    Text("点选可拖动/缩放，Shift 点选多选并批量改色改线宽或删除；保存/复制时才渲染")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            }

            Divider()

            ZStack {
                Color(nsColor: .windowBackgroundColor)
                if let image = model.image {
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
                    }
                    .padding(24)
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
        .alert("操作失败", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "未知错误")
        }
        .sheet(isPresented: $model.isWindowPickerPresented) {
            WindowPickerSheet(
                onPickWindow: { id in Task { await model.captureWindow(id: id) } },
                onPickDisplay: { id in Task { await model.captureDisplayFull(id: id) } }
            )
        }
        .task {
            model.installGlobalHotKey()
            model.refreshScreenPermission(requestIfNeeded: true)
            await model.loadWindows()
        }
    }
}
