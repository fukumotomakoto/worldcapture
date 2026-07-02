import AppKit
import SwiftUI

/// 把截图“钉”到屏幕上：无边框、置顶、可拖动的悬浮面板，可同时存在多个。
@MainActor
final class PinnedImageController: ObservableObject {
    static let shared = PinnedImageController()

    private var panels: [NSPanel] = []
    private var clickThroughPanels: Set<ObjectIdentifier> = []
    /// 当前处于「点击穿透」的钉屏数量（供菜单栏「取消穿透」按钮启用/禁用）。
    @Published private(set) var clickThroughCount = 0
    private let maxDimension: CGFloat = 480

    func pin(_ image: NSImage) {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return }

        let scale = min(1, maxDimension / max(size.width, size.height))
        let panelSize = CGSize(width: size.width * scale, height: size.height * scale)

        let panel = NSPanel(
            contentRect: CGRect(origin: .zero, size: panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        panel.contentView = NSHostingView(rootView: PinnedImageView(
            image: image,
            onClose: { [weak self, weak panel] in
                guard let panel else { return }
                self?.close(panel)
            },
            onEnableClickThrough: { [weak self, weak panel] in
                guard let panel else { return }
                self?.setClickThrough(panel, true)
            }
        ))

        if let screen = NSScreen.main {
            let visible = screen.visibleFrame
            let offset = CGFloat(panels.count % 6) * 28
            panel.setFrameOrigin(CGPoint(
                x: visible.maxX - panelSize.width - 40 - offset,
                y: visible.maxY - panelSize.height - 40 - offset
            ))
        }

        panel.orderFrontRegardless()
        panels.append(panel)
    }

    /// 设置某个钉屏是否「点击穿透」：开启后该面板忽略鼠标事件，点击落到下方窗口。
    /// 因为穿透后面板收不到点击、无法自行取消，取消入口在菜单栏「取消钉屏点击穿透」。
    func setClickThrough(_ panel: NSPanel, _ on: Bool) {
        panel.ignoresMouseEvents = on
        if on {
            clickThroughPanels.insert(ObjectIdentifier(panel))
        } else {
            clickThroughPanels.remove(ObjectIdentifier(panel))
        }
        clickThroughCount = clickThroughPanels.count
    }

    /// 取消所有钉屏的点击穿透（菜单栏调用的“逃生阀”）。
    func disableAllClickThrough() {
        for panel in panels { panel.ignoresMouseEvents = false }
        clickThroughPanels.removeAll()
        clickThroughCount = 0
    }

    private func close(_ panel: NSPanel) {
        panel.orderOut(nil)
        panels.removeAll { $0 == panel }
        clickThroughPanels.remove(ObjectIdentifier(panel))
        clickThroughCount = clickThroughPanels.count
    }
}

private struct PinnedImageView: View {
    let image: NSImage
    let onClose: () -> Void
    let onEnableClickThrough: () -> Void

    @State private var hovering = false

    var body: some View {
        Image(nsImage: image)
            .resizable()
            .scaledToFit()
            .overlay(alignment: .topTrailing) {
                if hovering {
                    HStack(spacing: 6) {
                        Button(action: onEnableClickThrough) {
                            Image(systemName: "cursorarrow.slash")
                                .font(.title3)
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, .black.opacity(0.55))
                        }
                        .buttonStyle(.plain)
                        .help(Loc.s("pin.clickThrough"))

                        Button(action: onClose) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title3)
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, .black.opacity(0.55))
                        }
                        .buttonStyle(.plain)
                        .help(Loc.s("pin.remove"))
                    }
                    .padding(6)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.25), lineWidth: 1)
            )
            .onHover { hovering = $0 }
    }
}
