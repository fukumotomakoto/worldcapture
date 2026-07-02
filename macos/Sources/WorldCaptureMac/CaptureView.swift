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
    @Published var annotationText = Loc.s("anno.text.default")
    @Published var annotationColorHex = CaptureAnnotation.defaultColorHex
    @Published var annotationLineWidth: Double = 1

    static let palette = ["#FF3B30", "#FF9500", "#FFCC00", "#34C759", "#007AFF", "#FFFFFF", "#000000"]
    static let lineWidthPresets: [(nameKey: String, value: Double)] = [("width.thin", 0.6), ("width.mid", 1.0), ("width.thick", 1.8)]

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
    @Published var isRecordingPaused = false
    @Published var lastRecordingURL: URL?
    @Published var recordingDuration: TimeInterval = 0
    /// GIF 录制：进行中标志与时长；区域 GIF 录制到内存帧，停止后编码。
    @Published var isGIFRecording = false
    @Published var gifRecordingDuration: TimeInterval = 0
    /// OCR：识别进行中标志；`ocrResult` 非 nil 时弹出结果面板（含空态）。
    @Published var isRecognizingText = false
    @Published var ocrResult: OCRResult?

    /// 一次 OCR 的结果，供结果面板以 `.sheet(item:)` 呈现。
    struct OCRResult: Identifiable {
        let id = UUID()
        let text: String
        var isEmpty: Bool { text.isEmpty }
    }
    @Published var hasScreenPermission = true
    @Published var hasAccessibilityPermission = true
    /// 主界面内容区内嵌的缩略图选择器当前模式；nil 表示不显示。
    /// 全窗口/全屏幕/录制屏幕都统一用这个内嵌网格选择，不再用下拉菜单。
    @Published var sourcePicker: SourcePickerMode?
    /// 可录制的显示器（多屏时供选择，单屏时直接录主屏）。
    @Published var availableDisplays: [DisplayOption] = []

    /// 内嵌选择器的用途：选窗口截图、选屏幕截图、选屏幕录制、选窗口录制。
    enum SourcePickerMode {
        case window
        case captureScreen
        case recordScreen
        case recordWindow
    }

    struct DisplayOption: Identifiable, Hashable {
        let id: CGDirectDisplayID
        let name: String
    }

    var nextAnnotationNumber: Int {
        annotations.filter { $0.kind == .number }.count + 1
    }

    /// GIF 录制帧率与时长上限（秒）。到时自动停止编码。
    static let gifFPS = 12
    static let gifMaxDuration: TimeInterval = 30

    private let capturer: any ScreenCapturing
    private let regionSelector = RegionSelector()
    private let screenRecorder = ScreenRecorder()
    private let gifRecorder = GIFRecorder()
    private var gifTimer: Timer?
    private var gifStartedAt: Date?
    private var globalHotKey: GlobalHotKey?
    private var recordingTimer: Timer?
    private var recordingStartedAt: Date?
    /// 累计已暂停时长，及当前这次暂停的起点——用于让显示时长排除暂停段（与输出实际时长一致）。
    private var recordingPausedTotal: TimeInterval = 0
    private var recordingPausedAt: Date?

    var recordingDurationText: String {
        let totalSeconds = max(0, Int(recordingDuration))
        return String(format: "%02d:%02d", totalSeconds / 60, totalSeconds % 60)
    }

    init(capturer: any ScreenCapturing = ScreenCapturer()) {
        self.capturer = capturer
    }

    func capture() async {
        sourcePicker = nil
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
        sourcePicker = nil
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

        sourcePicker = nil
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
                    try? await Task.sleep(nanoseconds: 500_000_000) // 等待界面滚动渲染稳定（含懒加载内容）
                }
            )
            restoreWindows()
            isCapturing = false
            guard let stitched = result.image else {
                errorMessage = Loc.s("error.scrollEmpty")
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
        sourcePicker = nil
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
            errorMessage = Loc.s("error.noOwnWindow")
            return
        }
        await captureWindow(id: CGWindowID(window.windowNumber))
    }

    /// 捕获指定显示器整屏（供可视化选择器的“整个屏幕”使用）。
    func captureDisplayFull(id displayID: CGDirectDisplayID) async {
        sourcePicker = nil
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

    /// 对当前截图做本地 OCR（Vision，纯设备端）。识别在后台执行，完成后弹出结果面板；
    /// 用已渲染图（含标注）作为输入，使马赛克遮盖的文字不会被提取。
    func extractText() async {
        guard !isRecognizingText, let cgImage = renderedImage() else { return }
        isRecognizingText = true
        errorMessage = nil
        defer { isRecognizingText = false }
        do {
            let result = try await TextRecognizer.recognize(cgImage: cgImage)
            ocrResult = OCRResult(text: result.text)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 把 OCR 识别出的文字写入剪贴板（纯文本）。
    func copyText(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
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
            let name = Loc.s("screen.index", index + 1)
                + (id == mainID ? Loc.s("display.main") : "")
                + " · \(pixelWidth)×\(pixelHeight)"
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
        await beginRecording(displayID: displayID, region: nil)
    }

    /// 录制区域：先框选区域，再选输出路径开始录制该选区。
    func beginRegionRecording() async {
        guard !isRecording, !isGIFRecording else { return }
        sourcePicker = nil
        let restoreWindows = hideOwnWindows()
        guard let selection = await regionSelector.selectRegion() else {
            restoreWindows()
            return
        }
        restoreWindows()
        await beginRecording(displayID: selection.displayID, region: selection.region)
    }

    /// 录制指定窗口：选输出路径后录制该窗口（跟随窗口，不含桌面其余部分）。
    func beginWindowRecording(windowID: CGWindowID) async {
        guard !isRecording, !isGIFRecording else { return }
        sourcePicker = nil
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.mpeg4Movie]
        panel.nameFieldStringValue = "WorldCapture-\(Self.timestamp()).mp4"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try await screenRecorder.startWindowRecording(
                windowID: windowID,
                includeMicrophone: RecordingPreferences.includeMicrophone,
                to: url
            )
            lastRecordingURL = url
            isRecording = true
            startRecordingTimer()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 录制核心：区域可选；是否录麦克风读设置。先选输出路径再开录。
    private func beginRecording(displayID: CGDirectDisplayID, region: CaptureRegion?) async {
        guard !isRecording else { return }
        sourcePicker = nil
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.mpeg4Movie]
        panel.nameFieldStringValue = "WorldCapture-\(Self.timestamp()).mp4"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try await screenRecorder.startRecording(
                displayID: displayID,
                region: region,
                includeMicrophone: RecordingPreferences.includeMicrophone,
                to: url
            )
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
            if let lastRecordingURL {
                HistoryStore.shared.record(lastRecordingURL, kind: .video)
            }
        } catch {
            isRecording = screenRecorder.isRecording
            if !isRecording { stopRecordingTimer() }
            errorMessage = error.localizedDescription
        }
    }

    var gifRecordingDurationText: String {
        let totalSeconds = max(0, Int(gifRecordingDuration))
        return String(format: "%02d:%02d", totalSeconds / 60, totalSeconds % 60)
    }

    /// 区域 GIF 录制：框选区域后开始逐帧抓取（到时上限自动停止）。
    func toggleGIFRecording() async {
        if isGIFRecording {
            await stopGIFRecording()
        } else {
            await beginGIFRecording()
        }
    }

    private func beginGIFRecording() async {
        guard !isGIFRecording, !isRecording else { return }
        sourcePicker = nil
        let restoreWindows = hideOwnWindows()
        guard let selection = await regionSelector.selectRegion() else {
            restoreWindows()
            return
        }
        restoreWindows()

        do {
            try await gifRecorder.start(displayID: selection.displayID, region: selection.region, fps: Self.gifFPS)
            isGIFRecording = true
            errorMessage = nil
            startGIFTimer()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func stopGIFRecording() async {
        guard isGIFRecording else { return }
        isGIFRecording = false
        stopGIFTimer()

        do {
            let captured = try await gifRecorder.stop()
            guard !captured.isEmpty else {
                errorMessage = Loc.s("error.gifEmpty")
                return
            }

            let panel = NSSavePanel()
            panel.allowedContentTypes = [.gif]
            panel.nameFieldStringValue = "WorldCapture-\(Self.timestamp()).gif"
            guard panel.runModal() == .OK, let url = panel.url else { return }

            let frames = GIFEncoder.frames(from: captured, fallbackFPS: Self.gifFPS)
            let data = try GIFEncoder.encode(frames: frames)
            try data.write(to: url, options: .atomic)
            lastRecordingURL = url
            HistoryStore.shared.record(url, kind: .image)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func startGIFTimer() {
        gifRecordingDuration = 0
        gifStartedAt = Date()
        gifTimer?.invalidate()
        gifTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let started = self.gifStartedAt else { return }
                self.gifRecordingDuration = Date().timeIntervalSince(started)
                // 到达时长上限自动停止并编码。
                if self.gifRecordingDuration >= Self.gifMaxDuration {
                    await self.stopGIFRecording()
                }
            }
        }
    }

    private func stopGIFTimer() {
        if let gifStartedAt {
            gifRecordingDuration = Date().timeIntervalSince(gifStartedAt)
        }
        gifStartedAt = nil
        gifTimer?.invalidate()
        gifTimer = nil
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
        // 面板底部出现「文件格式」下拉，用户可选 PNG/JPEG/TIFF/PDF；扩展名随之更新。
        panel.allowedContentTypes = ImageFormat.allCases.map(\.utType)
        panel.nameFieldStringValue = "WorldCapture-\(Self.timestamp())"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let format = ImageFormat(fileExtension: url.pathExtension) ?? .png
        do {
            try ImageEncoder.encode(cgImage, as: format).write(to: url, options: .atomic)
            HistoryStore.shared.record(url, kind: .image)
        } catch {
            errorMessage = error.localizedDescription
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
        sourcePicker = nil
        annotationTool = .rectangle
    }

    /// 重启本应用：拉起一个新实例后退出当前进程（常用于授予辅助功能权限后让其对本进程生效）。
    func restartApp() {
        guard !isRecording else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in
            Task { @MainActor in NSApp.terminate(nil) }
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

    /// 暂停/继续录制：分段实现在录制器内部，这里只切状态并累计暂停时长。
    func pauseOrResumeRecording() async {
        guard isRecording else { return }
        do {
            if isRecordingPaused {
                try await screenRecorder.resume()
                if let at = recordingPausedAt {
                    recordingPausedTotal += Date().timeIntervalSince(at)
                    recordingPausedAt = nil
                }
                isRecordingPaused = false
            } else {
                try await screenRecorder.pause()
                recordingPausedAt = Date()
                isRecordingPaused = true
            }
        } catch {
            errorMessage = error.localizedDescription
            isRecordingPaused = screenRecorder.isPaused
        }
    }

    private func startRecordingTimer() {
        recordingDuration = 0
        recordingStartedAt = Date()
        recordingPausedTotal = 0
        recordingPausedAt = nil
        recordingTimer?.invalidate()
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.recordingDuration = self.elapsedRecordingDuration()
            }
        }
    }

    /// 已录制时长 = 墙钟 − 累计暂停（含当前正在进行的暂停）。
    private func elapsedRecordingDuration() -> TimeInterval {
        guard let recordingStartedAt else { return 0 }
        let ongoingPause = recordingPausedAt.map { Date().timeIntervalSince($0) } ?? 0
        return max(0, Date().timeIntervalSince(recordingStartedAt) - recordingPausedTotal - ongoingPause)
    }

    private func stopRecordingTimer() {
        recordingDuration = elapsedRecordingDuration()
        recordingStartedAt = nil
        recordingPausedTotal = 0
        recordingPausedAt = nil
        isRecordingPaused = false
        recordingTimer?.invalidate()
        recordingTimer = nil
    }
}

struct CaptureView: View {
    @ObservedObject var model: CaptureViewModel
    @ObservedObject private var history = HistoryStore.shared
    @Environment(\.openWindow) private var openWindow
    @Environment(\.scenePhase) private var scenePhase
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
                        Text(Loc.s("perm.screen.title"))
                            .font(.callout.weight(.semibold))
                        Text(Loc.s("perm.screen.desc"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(Loc.s("perm.open.settings")) { model.openScreenRecordingSettings() }
                    Button(Loc.s("perm.recheck")) { model.refreshScreenPermission() }
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
                        Text(Loc.s("perm.ax.title"))
                            .font(.callout.weight(.semibold))
                        Text(Loc.s("perm.ax.desc"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(Loc.s("perm.open.settings")) { model.openAccessibilitySettings() }
                    Button(Loc.s("perm.recheck")) { model.refreshAccessibilityPermission() }
                    Button(Loc.s("action.restart")) { model.restartApp() }
                        .disabled(model.isRecording)
                        .help(Loc.s("action.restart.help"))
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(Color(nsColor: .controlBackgroundColor))
            }

            if model.isGIFRecording {
                HStack(spacing: 8) {
                    Circle().fill(.red).frame(width: 8, height: 8)
                    Text(Loc.s("gif.active"))
                        .font(.callout.weight(.medium))
                    Text(model.gifRecordingDurationText)
                        .font(.system(.callout, design: .monospaced).weight(.semibold))
                    Spacer()
                    Button {
                        Task { await model.toggleGIFRecording() }
                    } label: {
                        Label(Loc.s("gif.stop"), systemImage: "stop.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(Color.red.opacity(0.10))
            }

            if model.isRecording {
                HStack(spacing: 8) {
                    Circle().fill(model.isRecordingPaused ? Color.orange : Color.red).frame(width: 8, height: 8)
                    Text(model.isRecordingPaused ? Loc.s("record.paused") : Loc.s("record.active"))
                        .font(.callout.weight(.medium))
                    Text(model.recordingDurationText)
                        .font(.system(.callout, design: .monospaced).weight(.semibold))
                    Spacer()
                    Button {
                        Task { await model.pauseOrResumeRecording() }
                    } label: {
                        Label(model.isRecordingPaused ? Loc.s("record.resume") : Loc.s("record.pause"),
                              systemImage: model.isRecordingPaused ? "play.circle.fill" : "pause.circle.fill")
                    }
                    .help(Loc.s(model.isRecordingPaused ? "record.resume" : "record.pause"))
                    Text(model.lastRecordingURL?.lastPathComponent ?? "")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 10)
            } else if let recordingURL = model.lastRecordingURL {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(Loc.s("record.saved", recordingURL.lastPathComponent))
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
                        Label(Loc.s("reveal.finder"), systemImage: "folder")
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

            if model.image != nil && model.sourcePicker == nil {
                annotationToolArea
                annotationOperationArea
                Divider()
            }

            contentArea
        }
        .alert(Loc.s("error.title"), isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button(Loc.s("error.ok"), role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? Loc.s("error.unknown"))
        }
        .sheet(item: $model.ocrResult) { result in
            OCRResultView(text: result.text) { model.copyText($0) }
        }
        .task {
            model.installGlobalHotKey()
            model.refreshScreenPermission(requestIfNeeded: true)
            model.loadDisplays()
            await model.loadWindows()
        }
        .onAppear { preview.start() }
        .onDisappear { preview.stop() }
        .onChange(of: scenePhase) { _, phase in
            // 从系统设置授权后切回应用时，自动重新检测权限，使横幅自动消失，无需手动“重新检查”。
            // （辅助功能权限受系统进程缓存影响，可能仍需重启 App 才对本进程生效。）
            guard phase == .active else { return }
            if !model.hasScreenPermission { Task { await model.loadWindows() } }
            if !model.hasAccessibilityPermission { model.refreshAccessibilityPermission() }
        }
    }

    // MARK: - 顶部标题与全局动作

    private var headerBar: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("WorldCapture")
                    .font(.title2.bold())
                Text(Loc.s("app.subtitle"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 24)
            HStack(spacing: 10) {
                Button {
                    model.reset()
                } label: {
                    Label(Loc.s("action.reset"), systemImage: "arrow.counterclockwise")
                }
                .disabled(model.isRecording || (model.image == nil && model.lastRecordingURL == nil))
                .help(Loc.s("action.reset.help"))

                Button {
                    model.pinCurrentImage()
                } label: {
                    Label(Loc.s("action.pin"), systemImage: "pin")
                }
                .disabled(model.image == nil)
                .help(Loc.s("action.pin.help"))

                Button {
                    model.copyToClipboard()
                } label: {
                    Label(Loc.s("action.copy"), systemImage: "doc.on.doc")
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(model.image == nil)

                Button {
                    Task { await model.extractText() }
                } label: {
                    Label(Loc.s("action.ocr"), systemImage: "text.viewfinder")
                }
                .disabled(model.image == nil || model.isRecognizingText)
                .help(Loc.s("action.ocr.help"))

                saveControl

                Button {
                    openWindow(id: "history")
                } label: {
                    Label(Loc.s("library.open"), systemImage: "clock.arrow.circlepath")
                }
                .help(Loc.s("library.open.help"))
            }
            .labelStyle(.titleAndIcon)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    /// 录制控件：录制中显示停止；多屏时在内容区内嵌屏幕缩略图供选择（不用下拉菜单）；单屏直接录主屏。
    @ViewBuilder
    private var recordingControl: some View {
        if model.isRecording {
            Button {
                Task { await model.toggleRecording() }
            } label: {
                Label(Loc.s("record.stop"), systemImage: "stop.circle.fill")
            }
            .tint(Color.red)
        } else {
            Button {
                if model.availableDisplays.count > 1 {
                    model.sourcePicker = .recordScreen
                } else {
                    Task { await model.toggleRecording() }
                }
            } label: {
                Label(Loc.s("record.screen"), systemImage: "record.circle")
            }
            .help(Loc.s("record.pick.help"))
        }
    }

    /// 区域录制控件：框选区域并录制该选区为视频（录制中隐藏，用统一的停止横幅）。
    @ViewBuilder
    private var regionRecordControl: some View {
        if !model.isRecording {
            Button {
                Task { await model.beginRegionRecording() }
            } label: {
                Label(Loc.s("record.region"), systemImage: "rectangle.dashed.badge.record")
            }
            .disabled(model.isCapturing || model.isGIFRecording)
            .help(Loc.s("record.region.help"))
        }
    }

    /// 窗口录制控件：以缩略图网格选择一个窗口并录制它（录制中隐藏，用统一的停止横幅）。
    @ViewBuilder
    private var windowRecordControl: some View {
        if !model.isRecording {
            Button {
                model.sourcePicker = .recordWindow
            } label: {
                Label(Loc.s("record.window"), systemImage: "macwindow.badge.plus")
            }
            .disabled(model.isCapturing || model.isGIFRecording)
            .help(Loc.s("record.window.help"))
        }
    }

    /// GIF 录制控件：录制中显示停止（红色）；否则触发区域框选并开始 GIF 录制。
    @ViewBuilder
    private var gifControl: some View {
        if model.isGIFRecording {
            Button {
                Task { await model.toggleGIFRecording() }
            } label: {
                Label(Loc.s("gif.stop"), systemImage: "stop.circle.fill")
            }
            .tint(Color.red)
        } else {
            Button {
                Task { await model.toggleGIFRecording() }
            } label: {
                Label(Loc.s("gif.record"), systemImage: "circle.hexagongrid.circle")
            }
            .disabled(model.isCapturing || model.isRecording)
            .help(Loc.s("gif.record.help"))
        }
    }

    /// 保存控件：主按钮保存；右侧下拉列出最近保存记录。
    private var saveControl: some View {
        HStack(spacing: 2) {
            Button {
                model.save()
            } label: {
                Label(Loc.s("action.save"), systemImage: "square.and.arrow.down")
            }
            .disabled(model.image == nil)

            Button {
                showRecentSaves.toggle()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
            }
            .disabled(history.entries.isEmpty)
            .help(Loc.s("recent.help"))
            .popover(isPresented: $showRecentSaves, arrowEdge: .bottom) {
                RecentSavesList(
                    entries: Array(history.entries.prefix(6)),
                    onOpenFile: { model.openSavedFile($0) },
                    onRevealFolder: { model.revealInFinder($0) },
                    onShowAll: {
                        showRecentSaves = false
                        openWindow(id: "history")
                    }
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
                Label(Loc.s("capture.region"), systemImage: "selection.pin.in.out")
            }
            .disabled(model.isCapturing)

            fullScreenControl

            Button {
                model.sourcePicker = .window
            } label: {
                Label(Loc.s("capture.window"), systemImage: "macwindow")
            }
            .disabled(model.isCapturing)
            .help(Loc.s("capture.window.help"))

            Button {
                Task { await model.captureOwnWindow() }
            } label: {
                Label(Loc.s("capture.self"), systemImage: "macwindow.on.rectangle")
            }
            .disabled(model.isCapturing)
            .help(Loc.s("capture.self.help"))

            Button {
                Task { await model.captureScrolling() }
            } label: {
                Label(Loc.s("capture.scroll"), systemImage: "arrow.down.doc")
            }
            .disabled(model.isCapturing)
            .help(Loc.s("capture.scroll.help"))

            Divider().frame(height: 22)

            recordingControl
            regionRecordControl
            windowRecordControl
            gifControl

            Spacer(minLength: 12)
            Text("⌘⇧2")
                .font(.callout.monospaced())
                .foregroundStyle(.secondary)
                .help(Loc.s("region.shortcut.help"))
        }
        .labelStyle(.titleAndIcon)
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
    }

    /// 全屏幕截图：单屏直接截主屏；多屏时在内容区内嵌屏幕缩略图供选择（不用下拉菜单）。
    private var fullScreenControl: some View {
        Button {
            if model.availableDisplays.count > 1 {
                model.sourcePicker = .captureScreen
            } else {
                Task { await model.capture() }
            }
        } label: {
            Label(Loc.s("capture.fullscreen"), systemImage: "display")
        }
        .disabled(model.isCapturing)
        .help(Loc.s("capture.fullscreen.help"))
    }

    // MARK: - 标注：工具区（绘制工具 / 颜色 / 线宽）

    private var annotationToolArea: some View {
        HStack(spacing: 14) {
            Picker("", selection: $model.annotationTool) {
                Text(Loc.s("anno.rect")).tag(AnnotationKind.rectangle)
                Text(Loc.s("anno.arrow")).tag(AnnotationKind.arrow)
                Text(Loc.s("anno.text")).tag(AnnotationKind.text)
                Text(Loc.s("anno.number")).tag(AnnotationKind.number)
                Text(Loc.s("anno.mosaic")).tag(AnnotationKind.mosaic)
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
            .help(Loc.s("anno.color.help"))

            Divider().frame(height: 20)

            Picker("", selection: Binding(
                get: { model.annotationLineWidth },
                set: { model.setAnnotationLineWidth($0) }
            )) {
                ForEach(CaptureViewModel.lineWidthPresets, id: \.value) { preset in
                    Text(Loc.s(preset.nameKey)).tag(preset.value)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 130)
            .help(Loc.s("anno.width.help"))

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
                Label(Loc.s("anno.delete"), systemImage: "trash")
            }
            .keyboardShortcut(.delete, modifiers: [])
            .disabled(!model.hasSelection)

            Button {
                model.undoAnnotation()
            } label: {
                Label(Loc.s("anno.undo"), systemImage: "arrow.uturn.backward")
            }
            .keyboardShortcut("z", modifiers: .command)
            .disabled(model.annotations.isEmpty)

            Button {
                model.clearAnnotations()
            } label: {
                Label(Loc.s("anno.clear"), systemImage: "xmark")
            }
            .disabled(model.annotations.isEmpty)

            Spacer()
            Text(Loc.s("anno.hint"))
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
            return Loc.s("anno.text.editSelected")
        } else if model.annotationTool == .text {
            return Loc.s("anno.text.placeholder")
        } else {
            return Loc.s("anno.text.hintSelect")
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

    private func sourcePickerTitle(_ mode: CaptureViewModel.SourcePickerMode) -> String {
        switch mode {
        case .window: return Loc.s("picker.window.title")
        case .captureScreen: return Loc.s("picker.screen.title")
        case .recordScreen: return Loc.s("picker.record.title")
        case .recordWindow: return Loc.s("picker.recordWindow.title")
        }
    }

    private var contentArea: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            if let mode = model.sourcePicker {
                CaptureSourcePicker(
                    kind: (mode == .window || mode == .recordWindow) ? .window : .screen,
                    title: sourcePickerTitle(mode),
                    onPickWindow: { id in
                        model.sourcePicker = nil
                        Task {
                            switch mode {
                            case .recordWindow: await model.beginWindowRecording(windowID: id)
                            default: await model.captureWindow(id: id)
                            }
                        }
                    },
                    onPickDisplay: { id in
                        model.sourcePicker = nil
                        Task {
                            switch mode {
                            case .captureScreen: await model.captureDisplayFull(id: id)
                            case .recordScreen: await model.beginRecording(displayID: id)
                            case .window, .recordWindow: break
                            }
                        }
                    },
                    onClose: { model.sourcePicker = nil }
                )
            } else if let image = model.image {
                imagePreview(image)
            } else if model.isCapturing {
                ProgressView(Loc.s("capturing"))
            } else {
                ContentUnavailableView(
                    Loc.s("empty.title"),
                    systemImage: "rectangle.dashed",
                    description: Text(Loc.s("empty.desc"))
                )
            }
        }
    }

    /// 截图预览：支持滚轮缩放与空格+拖动平移，便于精准打码与查看清晰度。
    @ViewBuilder
    private func imagePreview(_ image: NSImage) -> some View {
        GeometryReader { proxy in
            // 基准缩放：让 1 个截图像素正好对应 1 个物理像素（不放大位图），
            // 否则小区域截图被 scaledToFit 撑满预览区会被插值放大、发虚。
            // 内容比预览区大时再按比例缩小以适配。
            let displayScale = NSScreen.main?.backingScaleFactor ?? 2
            let nativeScale = 1 / displayScale
            let paneScale = min(
                proxy.size.width / max(1, image.size.width),
                proxy.size.height / max(1, image.size.height)
            )
            let fit = min(nativeScale, paneScale)
            let displaySize = CGSize(width: image.size.width * fit, height: image.size.height * fit)
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
            .frame(width: displaySize.width, height: displaySize.height)
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
        // 内容区在“内嵌选择器 ↔ 图片预览”间切换会整体重建本视图，
        // 此时 onChange 不会对初始值触发；故出现时强制归位缩放/平移，
        // 消失时清空 previewFrame，避免全局滚轮监视器误缩放已隐藏的预览。
        .onAppear {
            preview.reset()
            panActive = false
        }
        .onDisappear {
            preview.previewFrame = .zero
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
            .help(Loc.s("zoom.fit.help"))
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
            Label(Loc.s("pan.mode.hint"), systemImage: "hand.draw")
                .font(.caption.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.thinMaterial, in: Capsule())
                .padding(.top, 16)
        }
    }
}

/// “保存”旁下拉的最近保存列表：点文件名打开，悬停显示文件夹图标可定位到 Finder，底部入口跳转完整历史库。
private struct RecentSavesList: View {
    let entries: [HistoryEntry]
    let onOpenFile: (URL) -> Void
    let onRevealFolder: (URL) -> Void
    let onShowAll: () -> Void

    @State private var hovered: HistoryEntry.ID?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(Loc.s("recent.title"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 2)

            ForEach(entries) { entry in
                HStack(spacing: 8) {
                    Image(systemName: entry.kind == .video ? "film" : "photo")
                        .foregroundStyle(.secondary)
                    Text(entry.fileName)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 12)
                    Button {
                        onRevealFolder(entry.url)
                    } label: {
                        Image(systemName: "folder")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .opacity(hovered == entry.id ? 1 : 0)
                    .help(Loc.s("reveal.finder"))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
                .background(hovered == entry.id ? Color.accentColor.opacity(0.12) : Color.clear)
                .onHover { hovering in
                    hovered = hovering ? entry.id : (hovered == entry.id ? nil : hovered)
                }
                .onTapGesture { onOpenFile(entry.url) }
            }

            Divider().padding(.vertical, 4)

            Button(action: onShowAll) {
                HStack(spacing: 6) {
                    Image(systemName: "clock.arrow.circlepath")
                    Text(Loc.s("library.showAll"))
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .frame(width: 340)
        .padding(.bottom, 8)
    }
}

/// OCR 结果面板：以只读、可选中的文本视图展示识别文字，可一键复制全部；无文字时显示空态。
private struct OCRResultView: View {
    let text: String
    let onCopy: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    private var isEmpty: Bool { text.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label(Loc.s("ocr.title"), systemImage: "text.viewfinder")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 12)

            Divider()

            if isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "text.badge.xmark")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                    Text(Loc.s("ocr.empty"))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(24)
            } else {
                TextEditor(text: .constant(text))
                    .font(.system(.body, design: .default))
                    .textSelection(.enabled)
                    .frame(minHeight: 220)
                    .padding(8)
            }

            Divider()

            HStack(spacing: 10) {
                Spacer()
                Button(Loc.s("ocr.close")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button {
                    onCopy(text)
                    copied = true
                } label: {
                    Label(copied ? Loc.s("ocr.copied") : Loc.s("ocr.copyAll"),
                          systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.borderedProminent)
                .disabled(isEmpty)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .frame(width: 460, height: 380)
    }
}
