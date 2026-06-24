import CaptureKit
import SwiftUI

/// 内嵌于主窗口内容区的缩略图选择器：以缩略图网格挑选要截取的窗口，或要截图/录制的屏幕。
/// 全窗口、全屏幕、录制屏幕统一走这个内嵌网格，不再用下拉菜单。
struct CaptureSourcePicker: View {
    enum Kind { case window, screen }

    let kind: Kind
    let title: String
    let onPickWindow: (CGWindowID) -> Void
    let onPickDisplay: (CGDirectDisplayID) -> Void
    let onClose: () -> Void

    private let capturer = ScreenCapturer()
    @State private var windows: [CaptureWindow] = []
    @State private var displays: [DisplayInfo] = []
    @State private var isLoading = true

    private struct DisplayInfo: Identifiable {
        let id: CGDirectDisplayID
        let name: String
    }

    private let columns = [GridItem(.adaptive(minimum: 200), spacing: 16)]

    private var isEmpty: Bool {
        kind == .window ? windows.isEmpty : displays.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text(title)
                    .font(.headline)
                Spacer()
                Button {
                    Task { await load() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help(Loc.s("picker.refresh"))
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(Loc.s("picker.close"))
            }
            .padding(20)

            Divider()

            ScrollView {
                if isLoading {
                    ProgressView(Loc.s("picker.loading")).padding(40)
                } else if isEmpty {
                    Text(Loc.s("window.none"))
                        .foregroundStyle(.secondary)
                        .padding(40)
                } else {
                    LazyVGrid(columns: columns, spacing: 16) {
                        if kind == .window {
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
        // 直接在“窗口选择 ↔ 屏幕选择”之间切换时，SwiftUI 会复用同一视图实例，
        // 普通 .task 只在首次出现时执行、不会重跑，导致切换后仍显示上一次的（空）状态。
        // 绑定 kind 后，每次种类变化都会重新加载对应的窗口/屏幕列表。
        .task(id: kind) { await load() }
    }

    private func load() async {
        isLoading = true
        switch kind {
        case .window:
            windows = (try? await capturer.availableWindows()) ?? []
        case .screen:
            displays = NSScreen.screens.enumerated().compactMap { index, screen in
                guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
                    return nil
                }
                return DisplayInfo(id: id, name: Loc.s("screen.index", index + 1))
            }
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
