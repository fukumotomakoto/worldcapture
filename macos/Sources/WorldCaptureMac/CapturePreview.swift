import AppKit
import SwiftUI

/// 捕获后悬浮预览的快捷动作。
struct CapturePreviewActions {
    let copy: () -> Void
    let save: () -> Void
    let pin: () -> Void
    let edit: () -> Void
}

/// 截屏后在屏幕左下角弹出的缩略图卡片：提供快捷动作，数秒后自动消失，悬停时暂停。
@MainActor
final class CapturePreviewController {
    static let shared = CapturePreviewController()

    private var panel: NSPanel?
    private var dismissTask: Task<Void, Never>?
    private let autoDismissSeconds: UInt64 = 6

    func present(image: NSImage, actions: CapturePreviewActions) {
        dismiss()

        let cardSize = CGSize(width: 244, height: 196)
        let panel = NSPanel(
            contentRect: CGRect(origin: .zero, size: cardSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        panel.contentView = NSHostingView(rootView: CapturePreviewView(
            image: image,
            actions: actions,
            onClose: { [weak self] in self?.dismiss() },
            onHoverChange: { [weak self] hovering in
                if hovering { self?.cancelDismiss() } else { self?.scheduleDismiss() }
            }
        ))

        if let screen = NSScreen.main {
            let visible = screen.visibleFrame
            panel.setFrameOrigin(CGPoint(x: visible.minX + 24, y: visible.minY + 24))
        }

        panel.orderFrontRegardless()
        self.panel = panel
        scheduleDismiss()
    }

    func dismiss() {
        cancelDismiss()
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
    }

    private func scheduleDismiss() {
        cancelDismiss()
        dismissTask = Task { [weak self] in
            guard let seconds = self?.autoDismissSeconds else { return }
            try? await Task.sleep(nanoseconds: seconds * 1_000_000_000)
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    private func cancelDismiss() {
        dismissTask?.cancel()
        dismissTask = nil
    }
}

private struct CapturePreviewView: View {
    let image: NSImage
    let actions: CapturePreviewActions
    let onClose: () -> Void
    let onHoverChange: (Bool) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: 244, height: 150)
                .clipped()
                .contentShape(Rectangle())
                .onTapGesture { actions.edit(); onClose() }

            Divider()

            HStack(spacing: 14) {
                action("doc.on.doc", "复制") { actions.copy() }
                action("square.and.arrow.down", "保存") { actions.save() }
                action("pin", "钉屏") { actions.pin() }
                action("pencil", "编辑") { actions.edit() }
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark").font(.callout)
                }
                .buttonStyle(.borderless)
                .help("关闭")
            }
            .padding(.horizontal, 12)
            .frame(height: 44)
        }
        .frame(width: 244, height: 196)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.primary.opacity(0.12), lineWidth: 1))
        .onHover { onHoverChange($0) }
    }

    private func action(_ symbol: String, _ help: String, perform: @escaping () -> Void) -> some View {
        Button {
            perform()
            onClose()
        } label: {
            Image(systemName: symbol).font(.callout)
        }
        .buttonStyle(.borderless)
        .help(help)
    }
}
