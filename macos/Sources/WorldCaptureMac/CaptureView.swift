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

    private let capturer: any ScreenCapturing
    private let regionSelector = RegionSelector()
    private var globalHotKey: GlobalHotKey?

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
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func captureRegion() async {
        guard let region = await regionSelector.selectRegion() else { return }
        isCapturing = true
        errorMessage = nil
        defer { isCapturing = false }

        do {
            let captured = try await capturer.captureMainDisplay(region: region)
            image = NSImage(cgImage: captured, size: .zero)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadWindows() async {
        do {
            windows = try await capturer.availableWindows()
            if !windows.contains(where: { $0.id == selectedWindowID }) {
                selectedWindowID = windows.first?.id
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func captureSelectedWindow() async {
        guard let selectedWindowID else { return }
        isCapturing = true
        errorMessage = nil
        defer { isCapturing = false }

        do {
            let captured = try await capturer.captureWindow(id: selectedWindowID)
            image = NSImage(cgImage: captured, size: .zero)
            await loadWindows()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func copyToClipboard() {
        guard let image, let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
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

    func installGlobalHotKey() {
        guard globalHotKey == nil else { return }
        globalHotKey = GlobalHotKey { [weak self] in
            Task { await self?.captureRegion() }
        }
    }

    func save() {
        guard let image, let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
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

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }
}

struct CaptureView: View {
    @StateObject private var model = CaptureViewModel()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("WorldCapture")
                        .font(.title2.bold())
                    Text("本地优先的跨平台截屏与录屏工具")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Picker("窗口", selection: $model.selectedWindowID) {
                    Text("选择窗口").tag(CGWindowID?.none)
                    ForEach(model.windows) { window in
                        Text(window.displayName).tag(Optional(window.id))
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 240)

                Button("截取窗口") {
                    Task { await model.captureSelectedWindow() }
                }
                .disabled(model.isCapturing || model.selectedWindowID == nil)

                Button("选择区域") {
                    Task { await model.captureRegion() }
                }
                .disabled(model.isCapturing)

                Button("截取主屏幕") {
                    Task { await model.capture() }
                }
                .keyboardShortcut("2", modifiers: [.command, .shift])
                .disabled(model.isCapturing)

                Button("保存 PNG") { model.save() }
                    .disabled(model.image == nil)

                Button("复制") { model.copyToClipboard() }
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                    .disabled(model.image == nil)
            }
            .padding(20)

            Divider()

            ZStack {
                Color(nsColor: .windowBackgroundColor)
                if let image = model.image {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
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
        .alert("截屏失败", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "未知错误")
        }
        .task {
            model.installGlobalHotKey()
            await model.loadWindows()
        }
    }
}
