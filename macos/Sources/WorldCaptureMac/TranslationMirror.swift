import AppKit
import CaptureKit
import SwiftUI
@preconcurrency import Translation

/// 翻译镜：框选屏幕上一块区域，持续截取、识别、翻译，并把译文块**原位**盖在屏幕上（点击穿透）。
///
/// 适合看外文视频字幕、直播弹幕、不断刷新的界面。两扇窗：
/// - 覆盖层：与选区同位置同大小、透明、点击穿透，只画译文块；
/// - 控制条：选区上方的小药丸，可拖动，提供暂停/继续与关闭。
/// 循环每 1.5 秒截一帧；帧内容没变就不重跑识别；译文按原文缓存，重复出现的句子零延迟。
/// 截取用 SCContentFilter 排除本应用窗口，所以覆盖层自己画的译文不会被再次识别。
@MainActor
final class TranslationMirrorController: ObservableObject {
    static let shared = TranslationMirrorController()

    @Published private(set) var isActive = false
    @Published var isPaused = false
    @Published private(set) var isTranslating = false
    @Published private(set) var blocks: [CaptureAnnotation] = []
    @Published private(set) var imagePixelSize = CGSize(width: 1, height: 1)
    /// 系统翻译路径：由覆盖层视图上的 translationTask 消费。
    @Published var systemConfiguration: TranslationSession.Configuration?

    static let interval: Duration = .milliseconds(1500)

    private var overlay: NSPanel?
    private var pill: NSPanel?
    private var selection: RegionSelection?
    private var loop: Task<Void, Never>?
    private let capturer = ScreenCapturer()
    private var lastSignature: [UInt8]?
    private var cache: [String: String] = [:]
    private var cacheTarget = ""
    private var pendingBlocks: [TextBlock] = []
    private var pendingTexts: [String] = []
    private var pendingResolved: [Int: String] = [:]
    private var lastImage: CGImage?

    private init() {}

    // MARK: - 开关

    func start(selection: RegionSelection) {
        stop()
        self.selection = selection
        isActive = true
        isPaused = false
        blocks = []
        lastSignature = nil
        imagePixelSize = CGSize(width: selection.region.pixelWidth, height: selection.region.pixelHeight)

        let overlay = NSPanel(
            contentRect: selection.globalRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        overlay.level = .floating
        overlay.backgroundColor = .clear
        overlay.isOpaque = false
        overlay.hasShadow = false
        overlay.ignoresMouseEvents = true
        overlay.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        overlay.contentView = NSHostingView(rootView: TranslationMirrorOverlay(controller: self))
        overlay.setFrame(selection.globalRect, display: true)
        overlay.orderFrontRegardless()
        self.overlay = overlay

        let pillSize = CGSize(width: 232, height: 30)
        var pillOrigin = CGPoint(x: selection.globalRect.minX, y: selection.globalRect.maxY + 6)
        if pillOrigin.y + pillSize.height > selection.screenFrame.maxY {
            pillOrigin.y = selection.globalRect.minY - pillSize.height - 6
        }
        let pill = NSPanel(
            contentRect: CGRect(origin: pillOrigin, size: pillSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        pill.level = .floating
        pill.backgroundColor = .clear
        pill.isOpaque = false
        pill.hasShadow = true
        pill.isMovableByWindowBackground = true
        pill.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        pill.contentView = NSHostingView(rootView: TranslationMirrorPill(controller: self))
        pill.orderFrontRegardless()
        self.pill = pill

        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.tick()
                try? await Task.sleep(for: Self.interval)
            }
        }
    }

    func stop() {
        loop?.cancel()
        loop = nil
        overlay?.orderOut(nil)
        pill?.orderOut(nil)
        overlay = nil
        pill = nil
        selection = nil
        isActive = false
        isTranslating = false
        blocks = []
        pendingBlocks = []
        pendingTexts = []
        systemConfiguration = nil
    }

    func togglePause() { isPaused.toggle() }

    // MARK: - 循环

    private func tick() async {
        guard isActive, !isPaused, !isTranslating, let selection else { return }
        guard let image = try? await capturer.captureDisplay(id: selection.displayID, region: selection.region) else { return }
        let signature = Self.signature(of: image)
        // 画面没变：什么都不做，译文块留着。
        if let last = lastSignature, Self.isSimilar(last, signature) { return }
        lastSignature = signature
        lastImage = image
        await translateFrame(image)
    }

    private func translateFrame(_ image: CGImage) async {
        isTranslating = true
        defer { if pendingTexts.isEmpty { isTranslating = false } }

        guard let result = try? await TextRecognizer.recognize(cgImage: image) else { return }
        let found = TextBlockGrouper.group(result.textLines)
        guard !found.isEmpty else {
            blocks = []
            return
        }

        let stored = UserDefaults.standard.string(forKey: OCRResultView.targetLanguageKey) ?? ""
        let target = stored.isEmpty ? Locale.current.language : Locale.Language(identifier: stored)
        if cacheTarget != target.minimalIdentifier {
            cache = [:]
            cacheTarget = target.minimalIdentifier
        }
        let glossary = UserGlossary.load()

        var resolved: [Int: String] = [:]
        var todo: [(index: Int, text: String)] = []
        for (index, block) in found.enumerated() {
            let text = block.text
            if let hit = cache[text] ?? glossary.lookup(text, target: target.minimalIdentifier) {
                resolved[index] = hit
            } else {
                todo.append((index, text))
            }
        }
        pendingBlocks = found
        pendingResolved = resolved

        guard !todo.isEmpty else {
            finish(with: [:])
            return
        }
        pendingTexts = todo.map(\.text)

        if TranslationEngineChoice.current.usesAppleIntelligence {
            let terms = glossary.entries(relevantTo: pendingTexts, target: target.minimalIdentifier)
            do {
                let translated = try await AppleIntelligenceTranslator.translate(pendingTexts, to: target, glossary: terms)
                var byText: [String: String] = [:]
                for (text, output) in zip(pendingTexts, translated) { if let output { byText[text] = output } }
                finish(with: byText)
            } catch {
                pendingTexts = []
                isTranslating = false
            }
        } else {
            // 系统翻译：交给覆盖层视图上的 translationTask，翻完回调 finish。
            if var existing = systemConfiguration, existing.target == target {
                existing.invalidate()
                systemConfiguration = existing
            } else {
                systemConfiguration = TranslationSession.Configuration(source: nil, target: target)
            }
        }
    }

    /// 系统翻译路径的回调（在覆盖层视图的 translationTask 里调用）。
    func runSystemTranslation(with session: TranslationSession) async {
        let texts = pendingTexts
        guard !texts.isEmpty else { return }
        do {
            let translated = try await ImageTranslation.translate(texts, with: session)
            var byText: [String: String] = [:]
            for (index, text) in texts.enumerated() { if let output = translated[index] { byText[text] = output } }
            finish(with: byText)
        } catch {
            pendingTexts = []
            isTranslating = false
        }
    }

    private func finish(with translated: [String: String]) {
        for (text, output) in translated { cache[text] = output }
        let image = lastImage
        let width = imagePixelSize.width, height = imagePixelSize.height
        var next: [CaptureAnnotation] = []
        for (index, block) in pendingBlocks.enumerated() {
            guard let text = (pendingResolved[index] ?? translated[block.text])?
                .trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { continue }
            let background = image.map { TranslationBlockLayout.backgroundColor(around: block.rect, in: $0) }
                ?? RGBAColor(red: 1, green: 1, blue: 1)
            let foreground = TranslationBlockLayout.textColor(on: background)
            let layout = TranslationBlockLayout.layout(
                text: text, in: block.rect, lineHeight: block.lineHeight, imageSize: imagePixelSize
            )
            next.append(CaptureAnnotation(
                kind: .translation,
                start: NormalizedPoint(x: layout.rect.minX / width, y: layout.rect.minY / height),
                end: NormalizedPoint(x: layout.rect.maxX / width, y: layout.rect.maxY / height),
                label: text,
                colorHex: foreground.hexString,
                fillColorHex: background.hexString,
                fontSize: Double(layout.fontSize)
            ))
        }
        blocks = next
        pendingTexts = []
        pendingBlocks = []
        pendingResolved = [:]
        isTranslating = false
    }

    // MARK: - 帧签名

    /// 24×24 灰度缩略图当签名，判断画面有没有变化（不必逐像素比）。
    nonisolated static func signature(of image: CGImage) -> [UInt8] {
        let side = 24
        var buffer = [UInt8](repeating: 0, count: side * side)
        buffer.withUnsafeMutableBytes { raw in
            guard let context = CGContext(
                data: raw.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side,
                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return }
            context.interpolationQuality = .low
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        }
        return buffer
    }

    nonisolated static func isSimilar(_ a: [UInt8], _ b: [UInt8]) -> Bool {
        guard a.count == b.count, !a.isEmpty else { return false }
        var total = 0
        for i in 0..<a.count { total += abs(Int(a[i]) - Int(b[i])) }
        return total / a.count < 3
    }
}

/// 覆盖层：只画译文块，坐标按覆盖层尺寸 / 截图像素尺寸缩放。
private struct TranslationMirrorOverlay: View {
    @ObservedObject var controller: TranslationMirrorController

    var body: some View {
        Canvas { context, size in
            let scale = size.width / max(1, controller.imagePixelSize.width)
            for block in controller.blocks {
                let rect = CGRect(
                    x: block.start.x * size.width, y: block.start.y * size.height,
                    width: (block.end.x - block.start.x) * size.width,
                    height: (block.end.y - block.start.y) * size.height
                )
                let fill = RGBAColor(hex: block.fillColorHex ?? "#FFFFFF")
                let text = RGBAColor(hex: block.resolvedColorHex)
                context.fill(
                    Path(roundedRect: rect, cornerRadius: 3 * scale),
                    with: .color(Color(.sRGB, red: fill.red, green: fill.green, blue: fill.blue, opacity: 1))
                )
                let inset = TranslationBlockLayout.padding * scale
                context.draw(
                    Text(block.label ?? "")
                        .font(.custom("PingFang SC", size: CGFloat(block.fontSize ?? 12) * scale))
                        .foregroundStyle(Color(.sRGB, red: text.red, green: text.green, blue: text.blue, opacity: 1)),
                    in: rect.insetBy(dx: inset, dy: inset)
                )
            }
        }
        .translationTask(controller.systemConfiguration) { session in
            await controller.runSystemTranslation(with: session)
        }
    }
}

/// 控制条：状态 + 暂停/继续 + 关闭。
private struct TranslationMirrorPill: View {
    @ObservedObject var controller: TranslationMirrorController

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "character.bubble")
                .foregroundStyle(.white)
            Text(statusText)
                .font(.caption.weight(.medium))
                .foregroundStyle(.white)
                .lineLimit(1)
            Spacer(minLength: 4)
            if controller.isTranslating && !controller.isPaused {
                ProgressView().controlSize(.mini).tint(.white)
            }
            Button {
                controller.togglePause()
            } label: {
                Image(systemName: controller.isPaused ? "play.fill" : "pause.fill")
            }
            .help(Loc.s(controller.isPaused ? "mirror.resume" : "mirror.pause"))
            Button {
                controller.stop()
            } label: {
                Image(systemName: "xmark")
            }
            .help(Loc.s("mirror.close"))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .frame(width: 232, height: 30)
        .background(Color.black.opacity(0.78), in: Capsule())
    }

    private var statusText: String {
        if controller.isPaused { return Loc.s("mirror.paused") }
        return Loc.s("mirror.title")
    }
}
