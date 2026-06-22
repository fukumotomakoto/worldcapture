import AppKit
import SwiftUI

/// 把截图“钉”到屏幕上：无边框、置顶、可拖动的悬浮面板，可同时存在多个。
@MainActor
final class PinnedImageController {
    static let shared = PinnedImageController()

    private var panels: [NSPanel] = []
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

        panel.contentView = NSHostingView(rootView: PinnedImageView(image: image) { [weak self, weak panel] in
            guard let panel else { return }
            self?.close(panel)
        })

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

    private func close(_ panel: NSPanel) {
        panel.orderOut(nil)
        panels.removeAll { $0 == panel }
    }
}

private struct PinnedImageView: View {
    let image: NSImage
    let onClose: () -> Void

    @State private var hovering = false

    var body: some View {
        Image(nsImage: image)
            .resizable()
            .scaledToFit()
            .overlay(alignment: .topTrailing) {
                if hovering {
                    Button(action: onClose) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .black.opacity(0.55))
                    }
                    .buttonStyle(.plain)
                    .padding(6)
                    .help("取消钉屏")
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.25), lineWidth: 1)
            )
            .onHover { hovering = $0 }
    }
}
