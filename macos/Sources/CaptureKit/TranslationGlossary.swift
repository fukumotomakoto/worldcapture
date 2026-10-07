import Foundation

/// 术语表：界面常用词的固定译法，补机器翻译的短板（把 Billing 译成「开具发票」、Voice 译成「嗓音」那种）。
///
/// 两层来源：① 内置表（英 → 简中 / 日）；② 用户词表文件（`glossary.txt`，`原文 = 译文` 一行一条，
/// 用 `[zh-Hans]` / `[ja]` 分节）。用户条目覆盖内置条目。
/// 用法：① 短文本整体命中 → 直接用译法、不送引擎；② 送大模型引擎时把相关条目放进提示。
public struct TranslationGlossary: Sendable {
    /// 目标语言标识（`Locale.Language.minimalIdentifier`）→ 小写原文 → 译文。
    private var tables: [String: [String: String]]

    public init(tables: [String: [String: String]] = [:]) {
        self.tables = tables
    }

    public static let builtIn = TranslationGlossary(tables: [
        "zh-Hans": Self.normalized(Self.englishToSimplifiedChinese),
        "zh": Self.normalized(Self.englishToSimplifiedChinese),
        "ja": Self.normalized(Self.englishToJapanese),
    ])

    /// 内置表 + 用户词表；用户条目优先。
    public static func combined(userFileText: String?) -> TranslationGlossary {
        var glossary = builtIn
        if let userFileText { glossary.merge(Self.parse(userFileText)) }
        return glossary
    }

    public var isEmpty: Bool { tables.values.allSatisfy(\.isEmpty) }

    public mutating func merge(_ other: TranslationGlossary) {
        for (language, table) in other.tables {
            tables[language, default: [:]].merge(table) { _, user in user }
        }
    }

    /// 整段精确命中（忽略大小写、首尾空白与末尾的冒号/省略号）。
    public func lookup(_ text: String, target: String) -> String? {
        guard let table = table(for: target) else { return nil }
        return table[Self.key(text)]
    }

    /// 与这批文本相关的条目（原文出现在任一文本里），供放进大模型提示。
    public func entries(relevantTo texts: [String], target: String) -> [(source: String, target: String)] {
        guard let table = table(for: target) else { return [] }
        let haystack = texts.map { $0.lowercased() }
        return table
            .filter { entry in haystack.contains { $0.contains(entry.key) } }
            .map { (source: $0.key, target: $0.value) }
            .sorted { $0.source < $1.source }
    }

    private func table(for target: String) -> [String: String]? {
        if let exact = tables[target] { return exact }
        // "zh-Hans-CN" → "zh-Hans" → "zh"
        var parts = target.split(separator: "-").map(String.init)
        while !parts.isEmpty {
            parts.removeLast()
            if let table = tables[parts.joined(separator: "-")] { return table }
        }
        return nil
    }

    // MARK: - 用户词表

    /// 词表文件模板（首次打开时写入）。
    public static let userFileTemplate = """
    # WorldCapture 翻译词表 / Translation glossary
    # 一行一条：原文 = 译文（忽略大小写；整条短文本命中时直接采用，送大模型翻译时作为术语提示）
    # 用 [zh-Hans] / [ja] 分节指定目标语言；# 开头是注释。
    #
    # One entry per line: source = translation (case-insensitive). Sections select the
    # target language; lines starting with # are comments.

    [zh-Hans]
    Fiscal review log = 财务审阅日志

    [ja]
    Fiscal review log = 会計レビューログ

    """

    public static func parse(_ text: String) -> TranslationGlossary {
        var tables: [String: [String: String]] = [:]
        var current = "zh-Hans"
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            if line.hasPrefix("["), line.hasSuffix("]") {
                current = String(line.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
                continue
            }
            guard let separator = line.range(of: "=") else { continue }
            let source = key(String(line[..<separator.lowerBound]))
            let target = String(line[separator.upperBound...]).trimmingCharacters(in: .whitespaces)
            guard !source.isEmpty, !target.isEmpty else { continue }
            tables[current, default: [:]][source] = target
        }
        return TranslationGlossary(tables: tables)
    }

    static func key(_ text: String) -> String {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        while let last = s.last, ":：…".contains(last) { s.removeLast() }
        return s
    }

    private static func normalized(_ pairs: [(String, String)]) -> [String: String] {
        Dictionary(pairs.map { (key($0.0), $0.1) }) { _, latest in latest }
    }

    // MARK: - 内置表

    static let englishToSimplifiedChinese: [(String, String)] = [
        ("Settings", "设置"), ("Preferences", "偏好设置"), ("General", "通用"), ("Account", "账户"),
        ("Privacy", "隐私"), ("Billing", "账单"), ("Usage", "用量"), ("Capabilities", "功能"),
        ("Memory", "记忆"), ("Design systems", "设计系统"), ("Skills", "技能"), ("Connectors", "连接器"),
        ("Plugins", "插件"), ("Platform", "平台"), ("API keys", "API 密钥"), ("API key", "API 密钥"),
        ("Customize", "自定义"), ("Appearance", "外观"), ("Theme", "主题"), ("Light", "浅色"), ("Dark", "深色"),
        ("System", "跟随系统"), ("Chat font", "聊天字体"), ("Font", "字体"), ("Motion", "动效"), ("Reduced", "减弱"),
        ("Tasks", "任务"), ("Voice", "语音"), ("Language", "语言"), ("Style", "风格"), ("Speed", "速度"),
        ("Normal", "正常"), ("Search", "搜索"), ("Share", "共享"), ("Reply", "回复"), ("Send", "发送"),
        ("Cancel", "取消"), ("OK", "好"), ("Done", "完成"), ("Save", "保存"), ("Save as", "另存为"),
        ("Delete", "删除"), ("Remove", "移除"), ("Edit", "编辑"), ("Rename", "重命名"), ("Copy", "复制"),
        ("Paste", "粘贴"), ("Cut", "剪切"), ("Undo", "撤销"), ("Redo", "重做"), ("Close", "关闭"),
        ("Open", "打开"), ("New", "新建"), ("New chat", "新对话"), ("Sign in", "登录"), ("Log in", "登录"),
        ("Sign out", "退出登录"), ("Log out", "退出登录"), ("Sign up", "注册"), ("Continue", "继续"),
        ("Back", "返回"), ("Next", "下一步"), ("Previous", "上一步"), ("Finish", "完成"), ("Submit", "提交"),
        ("Apply", "应用"), ("Reset", "重置"), ("Default", "默认"), ("Advanced", "高级"), ("Help", "帮助"),
        ("About", "关于"), ("Version", "版本"), ("Update", "更新"), ("Updates", "更新"), ("Check for updates", "检查更新"),
        ("Download", "下载"), ("Upload", "上传"), ("Import", "导入"), ("Export", "导出"), ("File", "文件"),
        ("Folder", "文件夹"), ("Home", "主页"), ("Dashboard", "仪表盘"), ("Overview", "概览"), ("Profile", "个人资料"),
        ("Notifications", "通知"), ("Security", "安全"), ("Password", "密码"), ("Username", "用户名"),
        ("Email", "邮箱"), ("Members", "成员"), ("Team", "团队"), ("Workspace", "工作区"), ("Project", "项目"),
        ("Projects", "项目"), ("History", "历史记录"), ("Recent", "最近"), ("Favorites", "收藏"), ("Trash", "废纸篓"),
        ("Enabled", "已启用"), ("Disabled", "已停用"), ("On", "开"), ("Off", "关"), ("Yes", "是"), ("No", "否"),
        ("Loading", "加载中"), ("Error", "错误"), ("Warning", "警告"), ("Success", "成功"), ("Failed", "失败"),
        ("Retry", "重试"), ("Learn more", "了解更多"), ("Get started", "开始使用"), ("Try it", "试一试"),
        ("Free", "免费"), ("Pro", "专业版"), ("Plan", "套餐"), ("Plans", "套餐"), ("Pricing", "定价"), ("Subscribe", "订阅"),
        ("Built-in browser", "内置浏览器"), ("Browser", "浏览器"), ("Preferred browser", "首选浏览器"),
        ("Desktop app", "桌面应用"), ("Mobile app", "手机应用"), ("Extension", "扩展"), ("Model", "模型"),
        ("Prompt", "提示词"), ("Token", "令牌"), ("Tokens", "令牌"), ("Context", "上下文"), ("Agent", "智能体"),
        ("Claude Code", "Claude Code"), ("Claude in Chrome", "Chrome 中的 Claude"),
        ("Keyboard Shortcuts", "键盘快捷键"), ("Shortcuts", "快捷键"), ("Screen Recording", "屏幕录制"),
        ("Privacy & Security", "隐私与安全"), ("Automatic updates", "自动更新"), ("Save Changes", "保存更改"),
        ("Accessibility", "辅助功能"), ("Microphone", "麦克风"), ("Camera", "相机"), ("Storage", "存储"),
    ]

    static let englishToJapanese: [(String, String)] = [
        ("Settings", "設定"), ("Preferences", "環境設定"), ("General", "一般"), ("Account", "アカウント"),
        ("Privacy", "プライバシー"), ("Billing", "請求"), ("Usage", "使用状況"), ("Capabilities", "機能"),
        ("Memory", "メモリ"), ("Design systems", "デザインシステム"), ("Skills", "スキル"), ("Connectors", "コネクタ"),
        ("Plugins", "プラグイン"), ("Platform", "プラットフォーム"), ("API keys", "API キー"), ("API key", "API キー"),
        ("Customize", "カスタマイズ"), ("Appearance", "外観"), ("Theme", "テーマ"), ("Light", "ライト"), ("Dark", "ダーク"),
        ("System", "システム"), ("Chat font", "チャットのフォント"), ("Font", "フォント"), ("Motion", "アニメーション"),
        ("Reduced", "減らす"), ("Tasks", "タスク"), ("Voice", "音声"), ("Language", "言語"), ("Style", "スタイル"),
        ("Speed", "速度"), ("Normal", "標準"), ("Search", "検索"), ("Share", "共有"), ("Reply", "返信"), ("Send", "送信"),
        ("Cancel", "キャンセル"), ("OK", "OK"), ("Done", "完了"), ("Save", "保存"), ("Save as", "別名で保存"),
        ("Delete", "削除"), ("Remove", "削除"), ("Edit", "編集"), ("Rename", "名前を変更"), ("Copy", "コピー"),
        ("Paste", "ペースト"), ("Cut", "カット"), ("Undo", "取り消す"), ("Redo", "やり直す"), ("Close", "閉じる"),
        ("Open", "開く"), ("New", "新規"), ("New chat", "新しいチャット"), ("Sign in", "サインイン"), ("Log in", "ログイン"),
        ("Sign out", "サインアウト"), ("Log out", "ログアウト"), ("Sign up", "登録"), ("Continue", "続ける"),
        ("Back", "戻る"), ("Next", "次へ"), ("Previous", "前へ"), ("Finish", "完了"), ("Submit", "送信"),
        ("Apply", "適用"), ("Reset", "リセット"), ("Default", "デフォルト"), ("Advanced", "詳細"), ("Help", "ヘルプ"),
        ("About", "情報"), ("Version", "バージョン"), ("Update", "アップデート"), ("Updates", "アップデート"),
        ("Check for updates", "アップデートを確認"), ("Download", "ダウンロード"), ("Upload", "アップロード"),
        ("Import", "読み込む"), ("Export", "書き出す"), ("File", "ファイル"), ("Folder", "フォルダ"), ("Home", "ホーム"),
        ("Dashboard", "ダッシュボード"), ("Overview", "概要"), ("Profile", "プロフィール"), ("Notifications", "通知"),
        ("Security", "セキュリティ"), ("Password", "パスワード"), ("Username", "ユーザー名"), ("Email", "メール"),
        ("Members", "メンバー"), ("Team", "チーム"), ("Workspace", "ワークスペース"), ("Project", "プロジェクト"),
        ("Projects", "プロジェクト"), ("History", "履歴"), ("Recent", "最近"), ("Favorites", "お気に入り"), ("Trash", "ゴミ箱"),
        ("Enabled", "有効"), ("Disabled", "無効"), ("On", "オン"), ("Off", "オフ"), ("Yes", "はい"), ("No", "いいえ"),
        ("Loading", "読み込み中"), ("Error", "エラー"), ("Warning", "警告"), ("Success", "成功"), ("Failed", "失敗"),
        ("Retry", "再試行"), ("Learn more", "詳しくはこちら"), ("Get started", "はじめる"), ("Try it", "試す"),
        ("Free", "無料"), ("Pro", "プロ"), ("Plan", "プラン"), ("Plans", "プラン"), ("Pricing", "料金"), ("Subscribe", "登録する"),
        ("Built-in browser", "内蔵ブラウザ"), ("Browser", "ブラウザ"), ("Preferred browser", "優先ブラウザ"),
        ("Desktop app", "デスクトップアプリ"), ("Mobile app", "モバイルアプリ"), ("Extension", "拡張機能"), ("Model", "モデル"),
        ("Prompt", "プロンプト"), ("Token", "トークン"), ("Tokens", "トークン"), ("Context", "コンテキスト"), ("Agent", "エージェント"),
        ("Claude Code", "Claude Code"), ("Claude in Chrome", "Chrome の Claude"),
        ("Keyboard Shortcuts", "キーボードショートカット"), ("Shortcuts", "ショートカット"), ("Screen Recording", "画面収録"),
        ("Privacy & Security", "プライバシーとセキュリティ"), ("Automatic updates", "自動アップデート"), ("Save Changes", "変更を保存"),
        ("Accessibility", "アクセシビリティ"), ("Microphone", "マイク"), ("Camera", "カメラ"), ("Storage", "ストレージ"),
    ]
}
