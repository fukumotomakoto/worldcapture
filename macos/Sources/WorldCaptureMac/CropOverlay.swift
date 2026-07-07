import AppKit
import SwiftUI

/// 裁切覆盖层：在内容区显示底图 + 可拖拽的裁切框（四角手柄可缩放、内部可平移、空白可重新框选），
/// 框外区域变暗。底部条提供「取消 / 应用」。裁切框以归一化坐标（左上原点）通过 `region` 绑定回模型。
struct CropOverlay: View {
    let image: NSImage
    @Binding var region: CGRect
    let onApply: () -> Void
    let onCancel: () -> Void

    /// 拖拽会话：缩放某角（记录锚定对角）、平移、或从空白新建。
    private enum Session {
        case corner(index: Int, anchor: CGPoint)
        case move(origin: CGRect, from: CGPoint)
        case create(from: CGPoint)
    }

    @State private var session: Session?

    private let handleHitRadius: CGFloat = 14
    private let handleSize: CGFloat = 10
    private let minSize: CGFloat = 0.03

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { proxy in
                let imageRect = aspectFitRect(content: image.size, container: proxy.size)
                let crop = screenRect(region, in: imageRect)
                ZStack(alignment: .topLeading) {
                    Image(nsImage: image)
                        .resizable()
                        .frame(width: imageRect.width, height: imageRect.height)
                        .position(x: imageRect.midX, y: imageRect.midY)

                    // 裁切框外变暗（even-odd 挖空）。
                    Path { p in
                        p.addRect(CGRect(origin: .zero, size: proxy.size))
                        p.addRect(crop)
                    }
                    .fill(Color.black.opacity(0.5), style: FillStyle(eoFill: true))

                    Rectangle()
                        .stroke(Color.white, lineWidth: 1.5)
                        .frame(width: crop.width, height: crop.height)
                        .position(x: crop.midX, y: crop.midY)

                    ForEach(Array(corners(of: crop).enumerated()), id: \.offset) { _, pt in
                        Rectangle()
                            .fill(Color.white)
                            .frame(width: handleSize, height: handleSize)
                            .position(x: pt.x, y: pt.y)
                    }
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if session == nil { session = begin(at: value.startLocation, crop: crop, imageRect: imageRect) }
                            update(to: value.location, imageRect: imageRect)
                        }
                        .onEnded { _ in session = nil }
                )
            }

            Divider()

            HStack(spacing: 12) {
                Image(systemName: "crop")
                    .foregroundStyle(.secondary)
                Text(Loc.s("crop.hint"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(Loc.s("crop.cancel")) { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Button(Loc.s("crop.apply")) { onApply() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(region.width < minSize || region.height < minSize)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
        }
    }

    // MARK: - 手势

    private func begin(at location: CGPoint, crop: CGRect, imageRect: CGRect) -> Session {
        for (index, pt) in corners(of: crop).enumerated() {
            if hypot(location.x - pt.x, location.y - pt.y) <= handleHitRadius {
                let opposite = corners(of: crop)[3 - index] // TL↔BR、TR↔BL
                return .corner(index: index, anchor: opposite)
            }
        }
        if crop.contains(location) {
            return .move(origin: region, from: location)
        }
        return .create(from: clamped(location, to: imageRect))
    }

    private func update(to location: CGPoint, imageRect: CGRect) {
        let p = clamped(location, to: imageRect)
        switch session {
        case let .corner(_, anchor):
            region = normalizedRect(from: anchor, to: p, imageRect: imageRect)
        case let .move(origin, from):
            var dx = (location.x - from.x) / imageRect.width
            var dy = (location.y - from.y) / imageRect.height
            dx = min(max(dx, -origin.minX), 1 - origin.maxX)
            dy = min(max(dy, -origin.minY), 1 - origin.maxY)
            region = origin.offsetBy(dx: dx, dy: dy)
        case let .create(from):
            region = normalizedRect(from: from, to: p, imageRect: imageRect)
        case .none:
            break
        }
    }

    // MARK: - 坐标

    private func normalizedRect(from a: CGPoint, to b: CGPoint, imageRect: CGRect) -> CGRect {
        let x0 = (min(a.x, b.x) - imageRect.minX) / imageRect.width
        let y0 = (min(a.y, b.y) - imageRect.minY) / imageRect.height
        let x1 = (max(a.x, b.x) - imageRect.minX) / imageRect.width
        let y1 = (max(a.y, b.y) - imageRect.minY) / imageRect.height
        return CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }

    private func screenRect(_ region: CGRect, in imageRect: CGRect) -> CGRect {
        CGRect(
            x: imageRect.minX + region.minX * imageRect.width,
            y: imageRect.minY + region.minY * imageRect.height,
            width: region.width * imageRect.width,
            height: region.height * imageRect.height
        )
    }

    /// 顺序：左上、右上、左下、右下（与 3-index 取对角一致）。
    private func corners(of rect: CGRect) -> [CGPoint] {
        [
            CGPoint(x: rect.minX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.minX, y: rect.maxY),
            CGPoint(x: rect.maxX, y: rect.maxY),
        ]
    }

    private func aspectFitRect(content: CGSize, container: CGSize) -> CGRect {
        guard content.width > 0, content.height > 0 else { return .zero }
        let scale = min(container.width / content.width, container.height / content.height)
        let size = CGSize(width: content.width * scale, height: content.height * scale)
        return CGRect(
            x: (container.width - size.width) / 2,
            y: (container.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
    }

    private func clamped(_ point: CGPoint, to rect: CGRect) -> CGPoint {
        CGPoint(
            x: min(rect.maxX, max(rect.minX, point.x)),
            y: min(rect.maxY, max(rect.minY, point.y))
        )
    }
}
