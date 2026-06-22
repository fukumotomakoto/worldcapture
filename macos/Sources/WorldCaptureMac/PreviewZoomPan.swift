import AppKit
import SwiftUI

/// 预览区缩放/平移控制器。
///
/// 用 `NSEvent` 本地监视器接管两类交互，而不在预览上叠 AppKit 视图，
/// 这样标注的点击/拖拽手势仍由 SwiftUI 正常处理：
/// - 鼠标在预览图上方时，滚轮缩放（兼容触控板像素滚动与鼠标行滚动）；
/// - 按住空格时进入平移模式（配合 SwiftUI 拖拽手势移动画面）。
@MainActor
final class PreviewGestureController: ObservableObject {
    @Published var zoom: CGFloat = 1
    @Published var pan: CGSize = .zero
    @Published private(set) var isSpaceDown = false

    /// 预览图在 SwiftUI 全局坐标系（左上原点、y 向下）中的矩形，用于判断滚轮是否落在图上。
    var previewFrame: CGRect = .zero

    private var monitors: [Any] = []
    private var panAtDragStart: CGSize = .zero

    static let minZoom: CGFloat = 1
    static let maxZoom: CGFloat = 8

    func setZoom(_ value: CGFloat) {
        zoom = min(Self.maxZoom, max(Self.minZoom, value))
        if zoom == Self.minZoom { pan = .zero }
    }

    func reset() {
        zoom = Self.minZoom
        pan = .zero
        panAtDragStart = .zero
    }

    func beginPan() { panAtDragStart = pan }

    func updatePan(translation: CGSize) {
        pan = CGSize(
            width: panAtDragStart.width + translation.width,
            height: panAtDragStart.height + translation.height
        )
    }

    func start() {
        guard monitors.isEmpty else { return }

        let scroll = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, self.eventIsOverPreview(event) else { return event }
            let delta = event.hasPreciseScrollingDeltas
                ? event.scrollingDeltaY * 0.002
                : event.scrollingDeltaY * 0.05
            guard delta != 0 else { return event }
            self.setZoom(self.zoom * (1 + delta))
            return nil
        }

        let keyDown = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.keyCode == 49 else { return event } // 49 = space
            // 文本输入聚焦时不拦截空格，保证标注文字可以正常打空格。
            if event.window?.firstResponder is NSText { return event }
            self.isSpaceDown = true
            return nil
        }

        let keyUp = NSEvent.addLocalMonitorForEvents(matching: .keyUp) { [weak self] event in
            guard let self, event.keyCode == 49 else { return event }
            self.isSpaceDown = false
            return nil
        }

        monitors = [scroll, keyDown, keyUp].compactMap { $0 }
    }

    func stop() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors.removeAll()
        isSpaceDown = false
    }

    /// 把事件的窗口坐标（左下原点）换算成 SwiftUI 全局坐标（左上原点）后，判断是否落在预览图内。
    private func eventIsOverPreview(_ event: NSEvent) -> Bool {
        guard previewFrame != .zero,
              let contentHeight = event.window?.contentView?.bounds.height else { return false }
        let point = CGPoint(
            x: event.locationInWindow.x,
            y: contentHeight - event.locationInWindow.y
        )
        return previewFrame.contains(point)
    }
}
