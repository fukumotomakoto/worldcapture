import CaptureKit
import SwiftUI

/// 可视化捕获目标选择器：以缩略图网格展示窗口与显示器，类似浏览器的“选择要分享的内容”。
struct WindowPickerSheet: View {
    let onPickWindow: (CGWindowID) -> Void
    let onPickDisplay: (CGDirectDisplayID) -> Void

    @Environment(\.dismiss) private var dismiss

    private let capturer = ScreenCapturer()
    @State private var windows: [CaptureWindow] = []
    @State private var displays: [DisplayInfo] = []
    @State private var tab: Tab = .windows
    @State private var isLoading = true

    private enum Tab: String, CaseIterable, Identifiable {
        case windows = "窗口"
        case screens = "整个屏幕"
        var id: String { rawValue }
    }

    private struct DisplayInfo: Identifiable {
        let id: CGDirectDisplayID
        let name: String
    }

    private let columns = [GridItem(.adaptive(minimum: 180), spacing: 16)]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("选择要捕获的内容")
                    .font(.headline)
                Spacer()
                Picker("", selection: $tab) {
                    ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 200)
            }
            .padding()

            Divider()

            ScrollView {
                if isLoading {
                    ProgressView("正在载入…").padding(40)
                } else {
                    LazyVGrid(columns: columns, spacing: 16) {
                        if tab == .windows {
                            ForEach(windows) { window in
                                ThumbnailCell(title: window.displayName,
                                              loader: { await capturer.windowThumbnail(id: window.id) }) {
                                    onPickWindow(window.id)
                                    dismiss()
                                }
                            }
                        } else {
                            ForEach(displays) { display in
                                ThumbnailCell(title: display.name,
                                              loader: { await capturer.displayThumbnail(id: display.id) }) {
                                    onPickDisplay(display.id)
                                    dismiss()
                                }
                            }
                        }
                    }
                    .padding()
                }
            }

            Divider()

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()
        }
        .frame(width: 660, height: 500)
        .task { await load() }
    }

    private func load() async {
        windows = (try? await capturer.availableWindows()) ?? []
        displays = NSScreen.screens.enumerated().compactMap { index, screen in
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
                return nil
            }
            return DisplayInfo(id: id, name: "屏幕 \(index + 1)")
        }
        isLoading = false
    }
}

private struct ThumbnailCell: View {
    let title: String
    let loader: () async -> CGImage?
    let onTap: () -> Void

    @State private var image: NSImage?

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .controlBackgroundColor))
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .padding(4)
                } else {
                    ProgressView()
                }
            }
            .frame(height: 120)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.primary.opacity(0.1)))

            Text(title)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .task {
            if let cgImage = await loader() {
                image = NSImage(cgImage: cgImage, size: .zero)
            }
        }
    }
}
