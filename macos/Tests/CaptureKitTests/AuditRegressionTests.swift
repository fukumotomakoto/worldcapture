// 2026-11-22《WorldCapture 功能审查与修正报告》各条问题的回归测试。
// 每个测试注明对应的报告编号；测试复现报告里的样例，修复前应失败、修复后通过。

import AVFoundation
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import Testing
@testable import CaptureKit

// MARK: - 工具

private func solidImage(_ gray: CGFloat, width: Int = 32, height: Int = 32) -> CGImage {
    let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.setFillColor(CGColor(red: gray, green: gray, blue: gray, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage()!
}

private func makeTempDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("wc-audit-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

// MARK: - 01 同秒保存不覆盖

@Test func audit01_sameSecondSavesProduceDistinctFilesAndKeepTheOriginal() throws {
    let dir = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    // 固定时钟：两次保存拿到同一个时间戳名。
    let fixed = Date(timeIntervalSince1970: 1_800_000_000)
    let base = UniqueFileWriter.timestampedName(date: fixed)
    #expect(base == UniqueFileWriter.timestampedName(date: fixed))

    let first = try UniqueFileWriter.write(Data("first".utf8), directory: dir, baseName: base, ext: "png")
    let second = try UniqueFileWriter.write(Data("second".utf8), directory: dir, baseName: base, ext: "png")

    #expect(first != second)
    #expect(first.lastPathComponent == "\(base).png")
    #expect(second.lastPathComponent == "\(base)-2.png")
    #expect(try Data(contentsOf: first) == Data("first".utf8)) // 原文件完整
    #expect(try Data(contentsOf: second) == Data("second".utf8))
    // 没有残留临时文件。
    let leftovers = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasSuffix(".tmp") }
    #expect(leftovers.isEmpty)
}

@Test func audit01_concurrentSavesNeverOverwrite() async throws {
    let dir = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let base = UniqueFileWriter.timestampedName(date: Date(timeIntervalSince1970: 1_800_000_000))
    let count = 24
    let urls = try await withThrowingTaskGroup(of: URL.self) { group in
        for i in 0..<count {
            group.addTask {
                try UniqueFileWriter.write(Data("payload-\(i)".utf8), directory: dir, baseName: base, ext: "png")
            }
        }
        var all: [URL] = []
        for try await url in group { all.append(url) }
        return all
    }
    #expect(Set(urls).count == count)
    let contents = Set(try urls.map { String(decoding: try Data(contentsOf: $0), as: UTF8.self) })
    #expect(contents.count == count) // 每份内容都在，没有谁被覆盖
}

// MARK: - 04 图上译文不得静默截断

@Test func audit04_layoutReportsIncompleteWhenTextCannotFit() {
    // 窄框 + 下方紧挨着另一块（限高）：长段落在字号下限也装不下。
    let long = String(repeating: "这是一段很长的译文，用来模拟窄列里放不下的情况。", count: 14)
    #expect((long as NSString).length > 300)
    let box = CGRect(x: 10, y: 10, width: 60, height: 20)
    let below = CGRect(x: 10, y: 36, width: 60, height: 20)
    let space = TranslationBlockLayout.freeSpace(for: box, among: [box, below], imageSize: CGSize(width: 76, height: 400))
    let layout = TranslationBlockLayout.layout(
        text: long, in: box, lineHeight: 18, imageSize: CGSize(width: 76, height: 400),
        maxWidth: space.maxWidth, maxHeight: space.maxHeight
    )
    #expect(!layout.isComplete)
    #expect(layout.requiredHeight > layout.rect.height)

    // 短译文照常完整。
    let short = TranslationBlockLayout.layout(text: "设置", in: box, lineHeight: 18, imageSize: CGSize(width: 900, height: 400))
    #expect(short.isComplete)
}

// MARK: - 05 相似原文不得配到同一条译文

@Test func audit05_commonPrefixEchoNeverReusesOneTranslation() {
    // 报告样例：引擎只回了一条，回显是共同前缀，译文是第一条的。
    let inputs = ["按月续订", "按年续订"]
    let items = [TranslationResponseMatcher.Item(index: 1, source: "按", translation: "Monthly renewal")]
    let result = TranslationResponseMatcher.match(inputs, with: items)
    #expect(result[1] == nil) // 年度绝不能拿到月度的译文
    #expect(result.compactMap { $0 }.count <= 1)
}

@Test func audit05_idIsPrimaryAndEachResponseIsConsumedOnce() {
    let inputs = ["Renew monthly plan", "Renew yearly plan", "Cancel subscription"]
    // 乱序 + 正确 ID + 回显只给前几个词。
    let items = [
        TranslationResponseMatcher.Item(index: 3, source: "Cancel", translation: "取消订阅"),
        TranslationResponseMatcher.Item(index: 1, source: "Renew monthly", translation: "按月续订"),
        TranslationResponseMatcher.Item(index: 2, source: "Renew yearly", translation: "按年续订"),
    ]
    #expect(TranslationResponseMatcher.match(inputs, with: items) == ["按月续订", "按年续订", "取消订阅"])
}

@Test func audit05_duplicateMissingAndWrongIDsAreNotGuessed() {
    let inputs = ["Renew monthly plan", "Renew yearly plan", "Cancel subscription"]
    // ID 1 重复（含糊）；ID 3 缺失；还有一条错误 ID 9 但回显唯一指向第 3 条。
    let items = [
        TranslationResponseMatcher.Item(index: 1, source: "Renew", translation: "续订 A"),
        TranslationResponseMatcher.Item(index: 1, source: "Renew", translation: "续订 B"),
        TranslationResponseMatcher.Item(index: 2, source: "Renew yearly", translation: "按年续订"),
        TranslationResponseMatcher.Item(index: 9, source: "Cancel subscription", translation: "取消订阅"),
    ]
    let result = TranslationResponseMatcher.match(inputs, with: items)
    #expect(result[0] == nil)          // 重复 ID + 含糊回显「Renew」：不猜
    #expect(result[1] == "按年续订")
    #expect(result[2] == "取消订阅")   // 错误 ID，但回显唯一 → 可用
    // 没有任何一条响应被用两次。
    let used = result.compactMap { $0 }
    #expect(Set(used).count == used.count)
}

@Test func audit05_identicalInputLinesEachNeedTheirOwnResponse() {
    let inputs = ["Save", "Save"]
    let items = [TranslationResponseMatcher.Item(index: 1, source: "Save", translation: "保存")]
    let result = TranslationResponseMatcher.match(inputs, with: items)
    #expect(result == ["保存", nil]) // 一条响应只能消费一次
}

// MARK: - 07 拼接失败不能当成到底

private final class ScriptedFrames: @unchecked Sendable {
    var frames: [CGImage]
    var index = 0
    var scrolls: [Double] = []
    init(_ frames: [CGImage]) { self.frames = frames }
    func capture() -> CGImage {
        defer { index = min(index + 1, frames.count - 1) }
        return frames[index]
    }
}

private func stripedImage(seed: Int, width: Int = 16, height: Int = 60) -> CGImage {
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    for y in 0..<height {
        let v = UInt8(((y + seed) * 53) % 256)
        for x in 0..<width {
            let p = (y * width + x) * 4
            bytes[p] = v; bytes[p + 1] = v; bytes[p + 2] = v; bytes[p + 3] = 255
        }
    }
    return CGImage(
        width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
        provider: CGDataProvider(data: Data(bytes) as CFData)!, decode: nil, shouldInterpolate: false, intent: .defaultIntent
    )!
}

@Test func audit07_lostOverlapIsNotReportedAsReachedEnd() async {
    // 报告样例：一帧黑图后两帧白图。
    let script = ScriptedFrames([solidImage(0, height: 60), solidImage(1, height: 60), solidImage(1, height: 60), solidImage(1, height: 60)])
    let engine = ScrollCaptureEngine(options: .init(maxFrames: 10, endRepeatThreshold: 2, stitcher: .init(columnStep: 1)))
    let result = await engine.run(
        capture: { script.capture() },
        scroll: { (fraction: Double) in script.scrolls.append(fraction) }
    )
    #expect(!result.reachedEnd)
    #expect(!result.isComplete)
    #expect(result.endReason != .reachedEnd)
    #expect(result.frameCount == 1) // 只保留拼好的首帧
}

@Test func audit07_noScrollIsSentAfterTheLastAllowedFrame() async {
    // 内容永远在变（每帧都是新内容但能对齐），只能靠上限收尾。
    final class Page: @unchecked Sendable {
        var position = 0
        var scrolls = 0
        func capture() -> CGImage { stripedImage(seed: position) }
        func scroll(_ f: Double) { scrolls += 1; position += Int(20 * f) }
    }
    let page = Page()
    let engine = ScrollCaptureEngine(options: .init(maxFrames: 5, endRepeatThreshold: 2, stitcher: .init(columnStep: 1)))
    let result = await engine.run(capture: { page.capture() }, scroll: { (f: Double) in page.scroll(f) })
    #expect(result.endReason == .frameLimit)
    #expect(!result.isComplete)
    #expect(page.scrolls == 4) // 5 帧之间只滚 4 次，最后一帧之后不再滚
}

// MARK: - 11 GIF 末尾静止时间

@Test func audit11_lastFrameLastsUntilStopTime() throws {
    let a = solidImage(0.2), b = solidImage(0.8)
    // 报告样例：第 0 秒与第 0.5 秒两帧，之后静止到第 10 秒才停止。
    let base = 1000.0
    let frames = GIFEncoder.frames(from: [(a, base), (b, base + 0.5)], endTimestamp: base + 10, fallbackFPS: 12)
    #expect(abs(frames[0].delay - 0.5) < 0.0001)
    #expect(abs(frames[1].delay - 9.5) < 0.0001)

    // 编码后读回：总时长 = 10 秒（GIF 精度 1/100 秒）。
    let data = try GIFEncoder.encode(frames: frames)
    let source = CGImageSourceCreateWithData(data as CFData, nil)!
    var total = 0.0
    for i in 0..<CGImageSourceGetCount(source) {
        let props = CGImageSourceCopyPropertiesAtIndex(source, i, nil) as? [CFString: Any]
        let gif = props?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
        total += (gif?[kCGImagePropertyGIFUnclampedDelayTime] as? Double) ?? (gif?[kCGImagePropertyGIFDelayTime] as? Double) ?? 0
    }
    #expect(abs(total - 10) <= 0.01)
}

@Test func audit11_singleStaticFrameAndRoundingDoNotDrift() {
    let img = solidImage(0.5)
    let single = GIFEncoder.frames(from: [(img, 50)], endTimestamp: 80, fallbackFPS: 12)
    #expect(abs(single[0].delay - 30) < 0.0001)
    // 12 fps 的时间戳逐帧取整，总和仍等于停止时刻 − 首帧时刻（误差 ≤ 半个刻度）。
    let ts = (0..<120).map { (img, 7.0 + Double($0) / 12.0) }
    let frames = GIFEncoder.frames(from: ts, endTimestamp: 17.0, fallbackFPS: 12)
    let total = frames.reduce(0) { $0 + $1.delay }
    #expect(abs(total - 10.0) <= 0.005 + 1e-9)
}

// MARK: - 15 词表 Unicode 规范化

@Test func audit15_glossaryMatchesPrecomposedAndDecomposedForms() {
    let precomposed = "Caf\u{00E9}"   // é 预组合
    let decomposed = "Cafe\u{0301}"   // e + 组合重音
    let fromPrecomposed = TranslationGlossary.parse("[zh-Hans]\n\(precomposed) = 咖啡馆")
    let fromDecomposed = TranslationGlossary.parse("[zh-Hans]\n\(decomposed) = 咖啡馆")
    #expect(fromPrecomposed.lookup(decomposed, target: "zh-Hans") == "咖啡馆")
    #expect(fromDecomposed.lookup(precomposed, target: "zh-Hans") == "咖啡馆")
    #expect(TranslationGlossary.key(precomposed).unicodeScalars.elementsEqual(TranslationGlossary.key(decomposed).unicodeScalars))
    // 用户词表覆盖内置 + 语言标识回退。
    let merged = TranslationGlossary.combined(userFileText: "[zh-Hans]\nBilling = 计费\n\(decomposed) = 咖啡馆")
    #expect(merged.lookup("billing", target: "zh-Hans-CN") == "计费")
    #expect(merged.lookup(precomposed, target: "zh-Hans-CN") == "咖啡馆")
}

// MARK: - 10 录像收尾失败可恢复

/// 用 AVAssetWriter 生成一段很短的 H.264 MP4，模拟一个录好的分段。
private func writeTestSegment(to url: URL, frames: Int = 6) async throws {
    let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 64, AVVideoHeightKey: 64,
    ])
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey as String: 64, kCVPixelBufferHeightKey as String: 64,
    ])
    writer.add(input)
    writer.startWriting()
    writer.startSession(atSourceTime: .zero)
    for i in 0..<frames {
        while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 1_000_000) }
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(nil, 64, 64, kCVPixelFormatType_32BGRA, nil, &buffer)
        CVPixelBufferLockBaseAddress(buffer!, [])
        memset(CVPixelBufferGetBaseAddress(buffer!), Int32(i * 30), CVPixelBufferGetDataSize(buffer!))
        CVPixelBufferUnlockBaseAddress(buffer!, [])
        adaptor.append(buffer!, withPresentationTime: CMTime(value: CMTimeValue(i), timescale: 10))
    }
    input.markAsFinished()
    await writer.finishWriting()
    if writer.status != .completed { throw writer.error ?? CaptureError.recordingFailed("writer") }
}

@Test func audit10_finalizeCommitsWithoutOverwritingAndCleansUp() async throws {
    let root = try makeTempDirectory()
    let output = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: output) }

    // 目标路径上已经有一个旧文件：必须原样保留。
    let preferred = output.appendingPathComponent("WorldCapture-20270101-000000.mp4")
    try Data("old recording".utf8).write(to: preferred)

    let session = try RecordingRecovery.createSession(preferredOutput: preferred, root: root)
    let s1 = session.appendingPathComponent("segment-001.mp4")
    let s2 = session.appendingPathComponent("segment-002.mp4")
    try await writeTestSegment(to: s1)
    try await writeTestSegment(to: s2)
    RecordingRecovery.writeManifest(in: session, preferredOutput: preferred, segments: [s1, s2])

    let recovery = try #require(RecordingRecovery(directory: session))
    #expect(RecordingRecovery.pending(in: root).map(\.id) == [recovery.id])
    let final = try await recovery.finalize()

    #expect(final != preferred)
    #expect(final.lastPathComponent == "WorldCapture-20270101-000000-2.mp4")
    #expect(try Data(contentsOf: preferred) == Data("old recording".utf8))
    let duration = try await AVURLAsset(url: final).load(.duration).seconds
    #expect(duration > 1.0) // 两段拼起来（每段 0.6 秒）
    #expect(!FileManager.default.fileExists(atPath: session.path)) // 成功后清理
    #expect(RecordingRecovery.pending(in: root).isEmpty)
}

@Test func audit10_failedFinalizeKeepsSegmentsForRecovery() async throws {
    let root = try makeTempDirectory()
    let output = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: output) }

    let preferred = output.appendingPathComponent("broken.mp4")
    let session = try RecordingRecovery.createSession(preferredOutput: preferred, root: root)
    let good = session.appendingPathComponent("segment-001.mp4")
    let bad = session.appendingPathComponent("segment-002.mp4")
    try await writeTestSegment(to: good)
    try Data("not an mp4".utf8).write(to: bad) // 模拟回调缺失导致的未封口分段
    RecordingRecovery.writeManifest(in: session, preferredOutput: preferred, segments: [good, bad])

    let recovery = try #require(RecordingRecovery(directory: session))
    await #expect(throws: (any Error).self) { _ = try await recovery.finalize() }
    // 失败后：分段与清单都在，目标目录里没有半成品。
    #expect(FileManager.default.fileExists(atPath: good.path))
    #expect(FileManager.default.fileExists(atPath: bad.path))
    #expect(RecordingRecovery.pending(in: root).count == 1)
    #expect(try FileManager.default.contentsOfDirectory(atPath: output.path).isEmpty)

    // 逐段导出：每段都能拿回来。
    let exported = try recovery.exportSegments()
    #expect(exported.map(\.lastPathComponent) == ["broken-part1.mp4", "broken-part2.mp4"])
    #expect(RecordingRecovery.pending(in: root).isEmpty)
}

@Test func audit10_verifyRejectsMissingAudioWhenExpected() async throws {
    let dir = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let url = dir.appendingPathComponent("video-only.mp4")
    try await writeTestSegment(to: url)
    try await RecordingRecovery.verify(url, expectsAudio: false)
    await #expect(throws: (any Error).self) { try await RecordingRecovery.verify(url, expectsAudio: true) }
}

@Test func audit10_segmentsMissingFromManifestAreStillRecoverable() async throws {
    let root = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let preferred = root.appendingPathComponent("out/crash.mp4")
    let session = try RecordingRecovery.createSession(preferredOutput: preferred, root: root)
    let listed = session.appendingPathComponent("segment-001-aaaa.mp4")
    let orphan = session.appendingPathComponent("segment-002-bbbb.mp4") // 崩溃前没来得及写进清单
    try await writeTestSegment(to: listed)
    try await writeTestSegment(to: orphan)
    RecordingRecovery.writeManifest(in: session, preferredOutput: preferred, segments: [listed])
    let recovery = try #require(RecordingRecovery(directory: session))
    #expect(recovery.segments.map(\.lastPathComponent) == ["segment-001-aaaa.mp4", "segment-002-bbbb.mp4"])
}
