import CaptureKit
import SwiftUI

/// 内嵌于主窗口的捕获目标选择器：以缩略图网格挑选窗口或整个屏幕（类似浏览器的“选择要分享的内容”）。
/// 直接铺在主界面内容区，不再以独立模态弹窗呈现。
struct CaptureSourcePicker: View {
    let onPickWindow: (CGWindowID) -> Void
    let onPickDisplay: (CGDirectDisplayID) -> Void
    let onClose: () -> Void

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

    private let columns = [GridItem(.adaptive(minimum: 200), spacing: 16)]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("选择要捕获的内容")
                    .font(.headline)
                Spacer()
                Picker("", selection: $tab) {
                    ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 200)
                Button {
                    Task { await load() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("刷新")
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("关闭选择器")
            }
            .padding(20)

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
                                }
                            }
                        } else {
                            ForEach(displays) { display in
                                ThumbnailCell(title: display.name,
                                              loader: { await capturer.displayThumbnail(id: display.id) }) {
                                    onPickDisplay(display.id)
                                }
                            }
                        }
                    }
                    .padding(20)
                }
            }
        }
        .task { await load() }
    }

    private func load() async {
        isLoading = true
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
    @State private var isHovering = false

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
            .frame(height: 130)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isHovering ? Color.accentColor : Color.primary.opacity(0.12),
                            lineWidth: isHovering ? 2 : 1)
            )

            Text(title)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture { onTap() }
        .task {
            if let cgImage = await loader() {
                image = NSImage(cgImage: cgImage, size: .zero)
            }
        }
    }
}
