import AppKit
import CaptureKit

@MainActor
final class RegionSelector {
    private var panel: SelectionPanel?
    private var continuation: CheckedContinuation<CaptureRegion?, Never>?

    func selectRegion() async -> CaptureRegion? {
        guard let screen = NSScreen.main,
              let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
            return nil
        }

        let pixelSize = CGSize(
            width: CGDisplayPixelsWide(screenNumber),
            height: CGDisplayPixelsHigh(screenNumber)
        )

        return await withCheckedContinuation { continuation in
            self.continuation = continuation

            let panel = SelectionPanel(
                contentRect: screen.frame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false,
                screen: screen
            )
            panel.level = .screenSaver
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

            let selectionView = SelectionView(frame: CGRect(origin: .zero, size: screen.frame.size))
            selectionView.onFinish = { [weak self] localRect in
                let globalRect = localRect.map {
                    $0.offsetBy(dx: screen.frame.minX, dy: screen.frame.minY)
                }
                let region = globalRect.flatMap {
                    CaptureRegion(selection: $0, displayFrame: screen.frame, pixelSize: pixelSize)
                }
                self?.finish(with: region)
            }
            panel.contentView = selectionView
            self.panel = panel
            panel.makeKeyAndOrderFront(nil)
            NSCursor.crosshair.push()
        }
    }

    private func finish(with region: CaptureRegion?) {
        NSCursor.pop()
        panel?.orderOut(nil)
        panel = nil
        continuation?.resume(returning: region)
        continuation = nil
    }
}

private final class SelectionPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

private final class SelectionView: NSView {
    var onFinish: ((CGRect?) -> Void)?
    private var startPoint: CGPoint?
    private var selection: CGRect?

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        startPoint = event.locationInWindow
        selection = nil
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let startPoint else { return }
        selection = CGRect(from: startPoint, to: event.locationInWindow)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let startPoint else {
            onFinish?(nil)
            return
        }
        let result = CGRect(from: startPoint, to: event.locationInWindow)
        onFinish?(result.width >= 2 && result.height >= 2 ? result : nil)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onFinish?(nil)
        } else {
            super.keyDown(with: event)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.34).setFill()
        let mask = NSBezierPath(rect: bounds)
        if let selection {
            mask.appendRect(selection)
            mask.windingRule = .evenOdd
        }
        mask.fill()

        guard let selection else { return }
        NSColor.white.setStroke()
        let border = NSBezierPath(rect: selection.insetBy(dx: 0.5, dy: 0.5))
        border.lineWidth = 1
        border.stroke()
    }
}

private extension CGRect {
    init(from start: CGPoint, to end: CGPoint) {
        self.init(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
    }
}

