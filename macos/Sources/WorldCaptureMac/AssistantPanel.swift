import AppKit
import SwiftUI
import WebKit

/// 可嵌入的对话助手：Claude 或 ChatGPT 的网页版。
///
/// 设计约束（见 PRIVACY.md「助手侧栏」）：这只是一个内嵌浏览器，用的是用户自己的账号；
/// WorldCapture 不接任何 API、不持有密钥、不主动发送任何数据。截图进入对话的唯一途径是
/// 用户自己粘贴（⌘V）或拖放——「发给助手」只负责把图放进剪贴板并预填一句提示。
enum AssistantProvider: String, CaseIterable, Identifiable {
    case claude
    case chatgpt

    var id: String { rawValue }

    var title: String {
        switch self {
        case .claude: return "Claude"
        case .chatgpt: return "ChatGPT"
        }
    }

    var homeURL: URL {
        switch self {
        case .claude: return URL(string: "https://claude.ai/new")!
        case .chatgpt: return URL(string: "https://chatgpt.com/")!
        }
    }

    /// 能否把提示预填进输入框而**不**自动发送。
    ///
    /// claude.ai/new?q= 只预填；chatgpt.com/?q= 实测（2026-09-21）会**立刻发送**，图还没贴就发出去了，
    /// 而 ?prompt= 什么都不做。所以 ChatGPT 不预填，只回首页，让用户贴图后自己输入要求。
    var supportsPromptPrefill: Bool {
        switch self {
        case .claude: return true
        case .chatgpt: return false
        }
    }

    func composeURL(prompt: String) -> URL? {
        guard supportsPromptPrefill else { return nil }
        var components = URLComponents(url: homeURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "q", value: prompt)]
        return components.url ?? homeURL
    }

    /// 登录态和聊天页面所在的站点；内嵌视图只在这些域名内导航，其余链接交给系统浏览器。
    var trustedHosts: [String] {
        switch self {
        case .claude: return ["claude.ai", "anthropic.com", "accounts.google.com", "appleid.apple.com"]
        case .chatgpt: return ["chatgpt.com", "openai.com", "auth0.com", "accounts.google.com", "appleid.apple.com", "login.microsoftonline.com"]
        }
    }
}

/// 侧栏状态 + 每家一个常驻的 WKWebView（切换回来不丢对话）。
@MainActor
final class AssistantController: NSObject, ObservableObject {
    static let shared = AssistantController()

    static let providerStorageKey = "assistant.provider"
    static let panelWidth: CGFloat = 440

    @Published var isVisible = false
    @Published var provider: AssistantProvider {
        didSet { UserDefaults.standard.set(provider.rawValue, forKey: Self.providerStorageKey) }
    }
    /// 「发给助手」之后显示的一次性提示（图已在剪贴板，请 ⌘V）。
    @Published var pasteHintVisible = false
    @Published private(set) var canGoBack = false

    private var webViews: [AssistantProvider: WKWebView] = [:]
    private var popupWindows: [NSWindow] = []
    private var backObservations: [AssistantProvider: NSKeyValueObservation] = [:]
    private var hintTask: Task<Void, Never>?
    /// 打开侧栏时把窗口加宽了多少；关闭时原样收回，不动用户自己调过的尺寸。
    private var widenedBy: CGFloat = 0

    private override init() {
        let stored = UserDefaults.standard.string(forKey: Self.providerStorageKey)
        provider = AssistantProvider(rawValue: stored ?? "") ?? .claude
        super.init()
    }

    // MARK: - 侧栏开关

    func toggle(in window: NSWindow?) {
        if isVisible {
            hide(in: window)
        } else {
            show(in: window)
        }
    }

    func show(in window: NSWindow?) {
        guard !isVisible else { return }
        isVisible = true
        guard let window, let screen = window.screen ?? NSScreen.main else { return }
        // 主内容区已经按 900 宽排版，直接挤进一个 440 宽的侧栏会把头部按钮挤断；
        // 屏幕放得下就把窗口右扩，放不下就退而缩小内容区。
        var frame = window.frame
        let room = screen.visibleFrame.maxX - frame.maxX
        let grow = min(Self.panelWidth, max(0, room))
        guard grow > 0 else { return }
        frame.size.width += grow
        widenedBy = grow
        window.setFrame(frame, display: true, animate: true)
    }

    func hide(in window: NSWindow?) {
        guard isVisible else { return }
        isVisible = false
        pasteHintVisible = false
        guard let window, widenedBy > 0 else { return }
        var frame = window.frame
        frame.size.width = max(window.minSize.width, frame.size.width - widenedBy)
        widenedBy = 0
        window.setFrame(frame, display: true, animate: true)
    }

    // MARK: - 发送截图

    /// 把 PNG 放进剪贴板、打开侧栏并预填翻译提示。图片本身不经网络离开本机，直到用户自己粘贴。
    func send(pngData: Data, prompt: String, in window: NSWindow?) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(pngData, forType: .png)

        show(in: window)
        webView(for: provider).load(URLRequest(url: provider.composeURL(prompt: prompt) ?? provider.homeURL))

        pasteHintVisible = true
        hintTask?.cancel()
        hintTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(12))
            guard !Task.isCancelled else { return }
            self?.pasteHintVisible = false
        }
    }

    // MARK: - 导航

    func goBack() { webView(for: provider).goBack() }
    func reload() { webView(for: provider).reload() }
    func goHome() { webView(for: provider).load(URLRequest(url: provider.homeURL)) }

    func openInBrowser() {
        let url = webView(for: provider).url ?? provider.homeURL
        NSWorkspace.shared.open(url)
    }

    // MARK: - WebView 管理

    func webView(for provider: AssistantProvider) -> WKWebView {
        if let existing = webViews[provider] { return existing }
        let webView = makeWebView()
        webViews[provider] = webView
        backObservations[provider] = webView.observe(\.canGoBack, options: [.initial, .new]) { [weak self] view, _ in
            Task { @MainActor in
                guard let self, self.webViews[self.provider] === view else { return }
                self.canGoBack = view.canGoBack
            }
        }
        webView.load(URLRequest(url: provider.homeURL))
        return webView
    }

    func providerDidChange() {
        canGoBack = webView(for: provider).canGoBack
    }

    private func makeWebView(configuration: WKWebViewConfiguration? = nil) -> WKWebView {
        let config = configuration ?? {
            let c = WKWebViewConfiguration()
            // 系统默认的持久化存储：登录一次，下次打开还是登录态。
            c.websiteDataStore = .default()
            c.preferences.isElementFullscreenEnabled = true
            c.preferences.javaScriptCanOpenWindowsAutomatically = true
            return c
        }()
        let webView = WKWebView(frame: .zero, configuration: config)
        // 声明成 Safari：Google 登录会拒绝它识别为「内嵌 WebView」的 UA。
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
        webView.allowsBackForwardNavigationGestures = true
        webView.navigationDelegate = self
        webView.uiDelegate = self
        return webView
    }
}

extension AssistantController: WKNavigationDelegate, WKUIDelegate {
    /// 站内与登录域名留在侧栏；其他外链（隐私政策、定价页……）交给系统浏览器。
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard let url = navigationAction.request.url, let host = url.host else { return .allow }
        guard url.scheme == "https" || url.scheme == "http" else { return .cancel }
        let trusted = AssistantProvider.allCases.flatMap(\.trustedHosts)
        let isTrusted = trusted.contains { host == $0 || host.hasSuffix("." + $0) }
        if isTrusted || navigationAction.navigationType != .linkActivated {
            return .allow
        }
        NSWorkspace.shared.open(url)
        return .cancel
    }

    /// `window.open`（Google/Apple 登录弹窗）：开一个共享同一 configuration 的真实子窗口，
    /// 这样弹窗和主页面才能互相通信、登录完成后回写 Cookie。页面调用 `window.close` 时收掉。
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        let popup = makeWebView(configuration: configuration)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 640),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered, defer: false
        )
        window.title = provider.title
        window.contentView = popup
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        popupWindows.append(window)
        return popup
    }

    func webViewDidClose(_ webView: WKWebView) {
        popupWindows.removeAll { window in
            guard window.contentView === webView else { return false }
            window.close()
            return true
        }
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo) async {
        let alert = NSAlert()
        alert.messageText = message
        alert.runModal()
    }
}

/// 把 controller 里常驻的 WKWebView 挂进 SwiftUI 布局。
private struct AssistantWebView: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

/// 主窗口右侧的助手侧栏。
struct AssistantPanel: View {
    @ObservedObject var controller: AssistantController
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Picker("", selection: $controller.provider) {
                    ForEach(AssistantProvider.allCases) { provider in
                        Text(provider.title).tag(provider)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 180)
                .onChange(of: controller.provider) { _, _ in controller.providerDidChange() }

                Spacer()

                Button { controller.goBack() } label: { Image(systemName: "chevron.left") }
                    .disabled(!controller.canGoBack)
                    .help(Loc.s("assistant.back"))
                Button { controller.goHome() } label: { Image(systemName: "house") }
                    .help(Loc.s("assistant.home"))
                Button { controller.reload() } label: { Image(systemName: "arrow.clockwise") }
                    .help(Loc.s("assistant.reload"))
                Button { controller.openInBrowser() } label: { Image(systemName: "safari") }
                    .help(Loc.s("assistant.openBrowser"))
                Button(action: onClose) { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help(Loc.s("assistant.close"))
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            if controller.pasteHintVisible {
                HStack(spacing: 8) {
                    Image(systemName: "doc.on.clipboard")
                    Text(Loc.s(controller.provider.supportsPromptPrefill ? "assistant.hint.paste" : "assistant.hint.paste.noPrefill"))
                        .font(.callout)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.accentColor.opacity(0.12))
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            AssistantWebView(webView: controller.webView(for: controller.provider))
                .id(controller.provider)
        }
        .frame(width: AssistantController.panelWidth)
        .background(Color(nsColor: .windowBackgroundColor))
        .animation(.easeInOut(duration: 0.2), value: controller.pasteHintVisible)
    }
}
