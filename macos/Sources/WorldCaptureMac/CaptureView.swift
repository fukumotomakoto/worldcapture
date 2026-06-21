import AppKit
import CaptureKit
import SwiftUI

@MainActor
final class CaptureViewModel: ObservableObject {
    @Published var image: NSImage?
    @Published var isCapturing = false
    @Published var errorMessage: String?

    private let capturer: any ScreenCapturing

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
                Button("截取主屏幕") {
                    Task { await model.capture() }
                }
                .keyboardShortcut("2", modifiers: [.command, .shift])
                .disabled(model.isCapturing)

                Button("保存 PNG") { model.save() }
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
    }
}

