import Testing
@testable import CaptureKit

@Test func builtInGlossaryFixesCommonUILabels() {
    let g = TranslationGlossary.builtIn
    #expect(g.lookup("Billing", target: "zh-Hans") == "账单")
    #expect(g.lookup("  voice: ", target: "zh-Hans") == "语音")
    #expect(g.lookup("Preferences", target: "zh-Hans-CN") == "偏好设置")
    #expect(g.lookup("Billing", target: "ja") == "請求")
    #expect(g.lookup("Some long sentence that is not a label", target: "zh-Hans") == nil)
    #expect(g.lookup("Billing", target: "fr") == nil)
}

@Test func userGlossaryOverridesBuiltInAndSupportsSections() {
    let user = """
    # comment
    [zh-Hans]
    Billing = 计费
    Fiscal review log = 财务审阅日志
    [ja]
    Fiscal review log = 会計レビューログ
    """
    let g = TranslationGlossary.combined(userFileText: user)
    #expect(g.lookup("Billing", target: "zh-Hans") == "计费")
    #expect(g.lookup("fiscal review log", target: "zh-Hans") == "财务审阅日志")
    #expect(g.lookup("Fiscal review log", target: "ja") == "会計レビューログ")
    #expect(g.lookup("Voice", target: "zh-Hans") == "语音")
}

@Test func relevantEntriesOnlyIncludeTermsPresentInTheBatch() {
    let entries = TranslationGlossary.builtIn.entries(relevantTo: ["Open Billing settings", "Voice"], target: "zh-Hans")
    let sources = entries.map(\.source)
    #expect(sources.contains("billing"))
    #expect(sources.contains("voice"))
    #expect(sources.contains("settings"))
    #expect(!sources.contains("password"))
}
