# WorldCapture 开发文档

> 文档状态：与 `main` 分支同步
>
> 当前版本：`0.1.1` / build `2`
>
> 当前平台：macOS 15+
> Windows 状态：规划中，尚无可构建实现

## 1. 项目目标

WorldCapture 是一款本地优先的截屏、标注与录屏工具，目标平台为 macOS 和 Windows。

产品原则：

- 截图、录屏、标注默认完全在本机处理。
- 捕获层使用平台原生 API，不用浏览器或跨平台 UI 框架模拟屏幕捕获。
- 标注采用非破坏编辑：原图不修改，导出时才合成。
- UI 行为、标注语义和未来工程文件格式应在 macOS 与 Windows 间保持一致。
- 商业模式为纯本地免费工具：不做账号登录、付费墙（Pro）与云同步。
- 任何分享或 AI 能力若未来引入，必须本地优先、完全可选，绝不成为基础捕获流程的依赖。

## 2. 当前功能范围

| 能力 | macOS | Windows | 备注 |
|---|---:|---:|---|
| 主屏幕截图 | 已实现 | 未开始 | 保留 Retina 原始像素 |
| 区域截图 | 已实现 | 未开始 | `Command + Shift + 2` |
| 独立窗口截图 | 已实现 | 未开始 | 支持窗口刷新与选择 |
| 截取本应用窗口 | 已实现 | 未开始 | 截取 WorldCapture 自身主窗口（做软件演示图）|
| 窗口/屏幕缩略图选择器 | 已实现 | 未开始 | 网格缩略图挑选窗口或整屏，内嵌主界面内容区（非弹窗）|
| PNG 保存 | 已实现 | 未开始 | 原子写入 |
| 剪贴板复制 | 已实现 | 未开始 | PNG 数据 |
| 矩形标注 | 已实现 | 未开始 | 非破坏 |
| 箭头标注 | 已实现 | 未开始 | 非破坏 |
| 文字标注 | 已实现 | 未开始 | 红字、白描边 |
| 自动序号 | 已实现 | 未开始 | 依照当前序号标注数量递增 |
| 马赛克 | 已实现 | 未开始 | 导出时像素化 |
| 撤销/清空 | 已实现 | 未开始 | 当前为线性末项撤销 |
| 预览缩放/平移 | 已实现 | 未开始 | 滚轮缩放、空格+拖动平移，便于精准打码与查看清晰度 |
| 标注选中/移动/缩放/删除 | 已实现 | 未开始 | 点选后拖动移动、手柄缩放、Delete 删除 |
| 标注颜色（预设色板）| 已实现 | 未开始 | 每标注独立，`#RRGGBB` 存储于工程模型 |
| 标注线宽（细/中/粗）| 已实现 | 未开始 | 倍率存于模型，作用于矩形/箭头 |
| 文字标注就地改写 | 已实现 | 未开始 | 选中后工具栏编辑文案 |
| 多选与批量编辑 | 已实现 | 未开始 | Shift 加选、组移动、批量改色/线宽/删除 |
| 菜单栏常驻入口 | 已实现 | 未开始 | `MenuBarExtra`：区域/主屏/窗口截屏、录屏、显示主窗口 |
| 钉屏（置顶悬浮）| 已实现 | 未开始 | 多个可拖动浮窗，渲染含标注 |
| 捕获后悬浮预览 | 已实现 | 未开始 | 角落缩略图卡片，快捷复制/保存/钉屏/编辑，悬停暂停自动消失 |
| 屏幕录制权限自检 | 已实现 | 未开始 | `CGPreflightScreenCaptureAccess` + 设置深链横幅 |
| 屏幕录制 | 已实现 | 未开始 | macOS 15+ `SCRecordingOutput`；多屏时菜单选择录制哪块 |
| 录制完成高亮提示 | 已实现 | 未开始 | 绿色高亮条 + 醒目“在 Finder 中显示” |
| 最近保存快捷打开 | 已实现 | 未开始 | “保存”旁下拉列最近 5 条，点开文件 / 悬停定位 Finder |
| 复位回到初始界面 | 已实现 | 未开始 | 清空当前截图、标注与提示 |
| 界面国际化 | 已实现 | 未开始 | 中/英/日，默认跟随系统，设置内可切换（重启生效）|
| 设置页 | 已实现 | 未开始 | `Settings` 场景（⌘,）：语言、默认保存位置、快捷键说明 |
| 系统音频 | 已实现 | 未开始 | 48 kHz、双声道配置 |
| MP4 导出 | 已实现 | 未开始 | H.264/AAC |
| 录制计时 | 已实现 | 未开始 | 0.25 秒刷新 |
| 麦克风 | 未实现 | 未开始 | 已预留权限说明与 entitlement |
| 摄像头画中画 | 未实现 | 未开始 | 后续阶段 |
| GIF 导出 | 未实现 | 未开始 | 后续阶段 |
| OCR | 未实现 | 未开始 | 后续阶段 |
| 滚动截屏 | 已实现 | 未开始 | 选区→程序化滚动→逐屏拼接长图；需辅助功能权限 |
| 截图历史库 | 未实现 | 未开始 | 后续阶段 |

## 3. 已验证开发环境

- macOS 26.x，Apple Silicon
- Xcode 26.5
- Swift 6.2
- XcodeGen 2.45.4
- FFmpeg 8.x，仅用于人工检查生成文件，运行时不依赖

工程最低部署版本是 macOS 15。使用更旧的 Xcode 或 Swift 工具链前，应先确认其支持：

- Swift tools version 6.2
- `SCRecordingOutput`
- Swift Testing

## 4. 环境准备

### 4.1 安装 XcodeGen

```bash
brew install xcodegen
```

检查工具：

```bash
xcodebuild -version
swift --version
xcodegen --version
```

### 4.2 生成 Xcode 工程

`project.yml` 是 Xcode 工程、Info.plist 权限文字和 entitlements 的唯一事实源。

```bash
cd ~/Projects/apps/worldcapture
xcodegen generate
```

重要规则：

- 修改 target、部署版本、Bundle ID、权限文字或 entitlement 后，必须重新执行 `xcodegen generate`。
- `macos/App/Info.plist` 和 `macos/App/WorldCapture.entitlements` 由 XcodeGen生成。
- 不要只手工修改上述两个生成文件；下一次生成会覆盖改动。
- `WorldCapture.xcodeproj` 提交到 Git，方便直接打开；但其内容仍以 `project.yml` 为准。

## 5. 构建与运行

### 5.1 正式 `.app` 开发构建

```bash
cd ~/Projects/apps/worldcapture
xcodegen generate
xcodebuild \
  -project WorldCapture.xcodeproj \
  -scheme WorldCapture \
  -configuration Debug \
  -derivedDataPath .derived-data \
  build
```

产物：

```text
.derived-data/Build/Products/Debug/WorldCapture.app
```

启动：

```bash
open .derived-data/Build/Products/Debug/WorldCapture.app
```

当前 Debug 工程使用**手动签名 + Apple Development 证书**（`project.yml` 中 `CODE_SIGN_STYLE: Manual`、`CODE_SIGN_IDENTITY: "Apple Development"`、`DEVELOPMENT_TEAM: 43M5KN7MPD`，不使用 provisioning profile）。改用真实开发者证书而非 ad-hoc，是为了让代码签名的 designated requirement 跨重建保持稳定，从而**屏幕录制等 TCC 权限授权一次后不会因每次重建 cdhash 变化而失效**。它仍不是发布签名。

> 注意：`DEVELOPMENT_TEAM` 取证书 subject 的 **OU 字段**（此处 `43M5KN7MPD`），不是 CN 括号里的 `BKD92Y6PRD`。可用 `security find-certificate -c "Apple Development: <名字>" -p | openssl x509 -noout -subject -nameopt sep_multiline` 查看 OU。

### 5.2 Swift Package 快速运行

```bash
cd ~/Projects/apps/worldcapture/macos
swift test
swift run WorldCaptureMac
```

Swift Package 路径适合快速编译逻辑，但屏幕录制权限可能归属终端进程。需要验证 TCC 权限、签名、Info.plist 或录屏时，必须运行正式 `.app`。

### 5.3 Xcode 测试

```bash
cd ~/Projects/apps/worldcapture
xcodegen generate
xcodebuild \
  -project WorldCapture.xcodeproj \
  -scheme WorldCapture \
  -configuration Debug \
  -derivedDataPath .derived-data \
  test
```

## 6. 仓库结构

```text
worldcapture/
├── README.md
├── project.yml                         # XcodeGen 唯一事实源
├── WorldCapture.xcodeproj/             # 生成并提交的 Xcode 工程
├── docs/
│   ├── ARCHITECTURE.md                 # 架构摘要
│   └── DEVELOPMENT.md                  # 本文档
└── macos/
    ├── App/
    │   ├── Info.plist                  # XcodeGen 生成
    │   └── WorldCapture.entitlements   # XcodeGen 生成
    ├── Package.swift
    ├── Sources/
    │   ├── CaptureKit/                 # 捕获、录制、领域模型和导出
    │   └── WorldCaptureMac/            # SwiftUI/AppKit 应用层
    └── Tests/
        └── CaptureKitTests/
```

计划中的目录：

```text
core/       # 跨平台工程文件与时间线语义，尚未建立
windows/    # Windows Graphics Capture/WASAPI 后端，尚未建立
```

## 7. 架构总览

```text
SwiftUI / AppKit UI
        |
CaptureViewModel
        |
CaptureKit framework
   |          |             |
截图捕获    标注模型/渲染    屏幕录制
   |          |             |
ScreenCaptureKit + CoreGraphics/CoreText
```

### 7.1 Target 划分

| Target | 类型 | 责任 |
|---|---|---|
| `CaptureKit` | Framework | 截图、窗口枚举、区域坐标、标注模型、PNG 编码、录屏 |
| `WorldCapture` | macOS App | UI、快捷键、区域选择面板、保存面板、状态管理 |
| `CaptureKitTests` | Unit Tests | 领域模型、坐标、渲染和错误信息测试 |

`CaptureKit` 不持有 SwiftUI 视图。UI 层依赖 `CaptureKit`，反向依赖不允许。

## 8. 模块说明

### 8.1 CaptureKit

| 文件 | 责任 |
|---|---|
| `ScreenCapturer.swift` | 主屏幕/区域/窗口静态截图，窗口枚举 |
| `ScreenRecorder.swift` | 主屏幕和系统音频录制，等待原生封装完成 |
| `CaptureRegion.swift` | AppKit 坐标转 ScreenCaptureKit 逻辑坐标与输出像素 |
| `CaptureWindow.swift` | 可捕获窗口的跨 UI 元数据 |
| `CaptureAnnotation.swift` | Codable 非破坏标注模型 |
| `AnnotationRenderer.swift` | 原始分辨率标注合成与马赛克 |
| `PNGEncoder.swift` | `CGImage` 到 PNG `Data` |
| `RGBAColor.swift` | 与平台解耦的标注颜色（十六进制解析、CGColor）|
| `ScrollStitcher.swift` | 滚动截屏：灰度纵向对齐与多帧长图拼接（纯逻辑）|
| `ScrollCaptureEngine.swift` | 滚动截屏编排：截帧→拼接→滚动循环与到底判定（注入式，可测）|
| `ScreenCapturePermission.swift` | 屏幕录制权限检测与申请 |
| `CaptureError.swift` | 用户可读错误模型 |

### 8.2 WorldCaptureMac

| 文件 | 责任 |
|---|---|
| `WorldCaptureApp.swift` | SwiftUI 应用入口与最小窗口尺寸 |
| `CaptureView.swift` | 主界面、ViewModel、文件保存、剪贴板、录制状态 |
| `RegionSelector.swift` | 全屏透明 AppKit 区域选择层 |
| `AnnotationCanvas.swift` | 标注预览与拖拽手势 |
| `GlobalHotKey.swift` | Carbon 全局快捷键注册与释放 |
| `MenuBarCommands.swift` | 菜单栏常驻入口（`MenuBarExtra` 命令）|
| `PinnedImage.swift` | 钉屏：置顶悬浮、可拖动的截图浮窗 |
| `CaptureSourcePicker.swift` | 窗口/屏幕缩略图选择器（网格挑选捕获目标，内嵌主界面）|
| `CapturePreview.swift` | 捕获后角落悬浮预览卡片与快捷动作 |
| `ScrollInput.swift` | 辅助功能权限检测与合成滚轮事件（滚动捕获驱动）|
| `PreviewZoomPan.swift` | 预览缩放/平移控制器（滚轮缩放与空格平移的 NSEvent 监视）|
| `Localization.swift` | 本地化封装 `Loc` 与界面语言偏好 `AppLanguage`（zh/en/ja）|
| `SettingsView.swift` | 偏好设置界面（语言、默认保存位置、快捷键说明）|

## 9. 静态截图流程

### 9.1 主屏幕截图

```text
用户点击“截取主屏幕”
  -> CaptureViewModel.capture()
  -> ScreenCapturer.captureMainDisplay()
  -> SCShareableContent 获取显示器
  -> SCContentFilter 选择主显示器
  -> pointPixelScale 计算原始像素尺寸
  -> SCScreenshotManager.captureImage
  -> NSImage 预览
```

主显示器通过 `CGMainDisplayID()` 匹配；匹配失败时回退到第一块可用显示器。

截图过滤器以 `excludingApplications` 排除 WorldCapture 自身全部窗口（主窗口、区域选择遮罩、钉屏浮窗），因此区域/全屏截图不会把暗色选择遮罩或本应用界面拍进去。区域选择遮罩在弹出前会 `NSApp.activate(ignoringOtherApps:)`，确保经全局热键在其他应用前台触发时也能获得焦点并正常关闭。

### 9.2 窗口截图

窗口列表只保留：

- 当前在屏幕上的窗口；
- `windowLayer == 0`；
- 至少 100×80 points；
- 不属于 WorldCapture 当前进程。

窗口截图使用 `SCContentFilter(desktopIndependentWindow:)`。窗口可能在列表显示后被关闭，因此捕获前会重新获取 `SCShareableContent` 并按 `CGWindowID` 查找；找不到时返回 `windowUnavailable`。

### 9.3 区域截图

`RegionSelector` 在**每块显示器**上各创建一个透明无边框 `NSPanel`（支持跨屏：在任意屏框选，按该屏的 `CGDirectDisplayID` 截图）：

- 鼠标按下记录起点；
- 拖动更新选择框；
- 鼠标释放返回区域；
- Esc 取消；
- 小于 2×2 points 的选择视为无效。

发起区域截屏前（按钮或全局热键），先 `orderOut` 隐藏 WorldCapture 自身全部可见窗口，使待截内容完全可见、便于精确框选；截屏完成或取消后再 `orderFront` 恢复并弹出捕获后悬浮预览。

## 10. 坐标与 Retina 处理

macOS 捕获涉及三套量纲：

1. AppKit 全局坐标：原点在屏幕左下。
2. ScreenCaptureKit `sourceRect`：显示器逻辑坐标，原点按捕获坐标系计算。
3. 输出图片：实际像素尺寸。

转换公式：

```text
sourceX = selection.minX - displayFrame.minX
sourceY = displayFrame.maxY - selection.maxY
pixelWidth  = selection.width  × displayPixelWidth  / displayPointWidth
pixelHeight = selection.height × displayPixelHeight / displayPointHeight
```

主屏幕、窗口与区域截图的输出像素尺寸**统一以 `SCContentFilter.pointPixelScale` × 点尺寸**计算，确保与 ScreenCaptureKit 原生分辨率 1:1、不被重采样而发虚。区域选择面板仍用 `CGDisplayMode.pixelWidth/pixelHeight` 求归一化所需的显示器原生像素（避免缩放模式下 `CGDisplayPixelsWide/High` 的逻辑尺寸），但最终截图分辨率由 `pointPixelScale` 决定。

任何坐标逻辑改动都必须运行 `CaptureRegionTests`。

## 11. 标注数据模型

### 11.1 类型

```swift
enum AnnotationKind: String, Codable {
    case rectangle
    case arrow
    case text
    case number
    case mosaic
}
```

每个 `CaptureAnnotation` 包含：

- UUID；
- 标注类型；
- 归一化起点；
- 归一化终点；
- 可选文字或序号。

归一化坐标始终限制在 `0...1`，因此标注不依赖预览窗口大小或截图像素尺寸。

JSON 示例：

```json
{
  "id": "B4347D55-A690-4B3C-990F-4CFCC45956F3",
  "kind": "arrow",
  "start": { "x": 0.1, "y": 0.2 },
  "end": { "x": 0.8, "y": 0.9 },
  "label": null
}
```

当前尚未定义完整项目文件；Codable 标注模型是未来跨平台项目格式的基础。

### 11.2 预览与导出

- 预览：`AnnotationCanvas` 使用 SwiftUI `Canvas`。
- 导出：`AnnotationRenderer` 使用 Core Graphics/CoreText。
- 保存与复制前才调用渲染器；ViewModel 中的原始 `NSImage` 不被覆盖。
- 新截图会清空当前标注。

### 11.3 马赛克实现

1. 从原图裁剪标注区域；
2. 以约 14 px 块大小降采样；
3. 关闭插值放大到原区域；
4. 其他矩形、箭头和文字在马赛克之后绘制。

## 12. PNG 保存与剪贴板

保存流程：

```text
原始 CGImage + annotations
  -> AnnotationRenderer
  -> PNGEncoder
  -> Data.write(options: .atomic)
```

剪贴板流程使用 `NSPasteboard.general`，类型为 `.png`。保存面板使用 `NSSavePanel`，默认文件名：

```text
WorldCapture-yyyyMMdd-HHmmss.png
```

## 13. 录屏架构

### 13.1 采用原生录制输出

录屏最低版本为 macOS 15，使用：

- `SCStream`：画面与系统音频采集；
- `SCRecordingOutput`：H.264/AAC MP4 原生封装；
- `SCRecordingOutputDelegate`：开始、完成和失败通知。

禁止重新引入旧的“双队列 CMSampleBuffer 直接 append 到 AVAssetWriter”方案。该方案曾因音视频时间戳竞争触发 `AVFoundationErrorDomain -11800 / OSStatus -16122`，生成缺少 `moov` 的无效 MP4。

### 13.2 当前录制配置

| 配置 | 值 |
|---|---|
| 捕获对象 | 选定显示器（默认主屏，多屏可菜单选择）|
| 分辨率 | `contentRect × pointPixelScale` |
| 帧率目标 | 60 fps |
| 像素格式 | BGRA |
| 队列深度 | 6 |
| 光标 | 显示 |
| 系统音频 | 开启 |
| 应用自身音频 | 排除 |
| 采样率 | 48 kHz |
| 声道 | 2 |
| 文件 | MP4 |
| 视频编码 | H.264 |

WorldCapture 自身应用画面会从录制内容中过滤；如果无法识别当前进程对应的 `SCRunningApplication`，回退到普通显示器过滤器。

### 13.3 状态机

```text
idle
  -> 用户选择输出 URL
  -> configure stream/output
  -> startCapture
recording
  -> UI 每 0.25 秒更新时间
  -> stopCapture
stopping
  -> 等待 recordingOutputDidFinishRecording
  -> 检查 terminalError
finished / failed
```

`ScreenRecorder` 用 `NSLock` 保护 `SCStream`、`SCRecordingOutput`、终止错误与 continuation。停止操作只有在原生封装 delegate 确认后才返回成功。

默认文件名：

```text
WorldCapture-yyyyMMdd-HHmmss.mp4
```

## 14. UI 与状态管理

`CaptureViewModel` 标注为 `@MainActor`，主要状态包括：

- 当前截图；
- 捕获中状态；
- 可用窗口与选中窗口 ID；
- 标注列表、当前标注工具和文字；
- 录制状态、时长和最后输出 URL；
- 用户可读错误信息。

界面采用分区竖向布局，统一 24pt 水平留白，避免控件与文案贴边：

1. 顶部标题栏：产品标题与副标题（左）；录制、钉屏、保存、复制（右，图标+文字）。
2. 捕获来源栏：区域、主屏幕、滚动长图、本窗口；窗口下拉菜单（直接截某窗口）、缩略图选择（切换内嵌选择器）。
3. 标注工具栏分上下两段，避免选中文字时整行重排：
   - 工具区：绘制工具、颜色色板、线宽；
   - 操作区：文字输入框（始终占位）、删除、撤销、清空、提示。
4. 内容区：内嵌缩略图选择器 / 截图预览（叠加标注画布，支持滚轮缩放、空格+拖动平移，右下角有缩放控件）/ 空态三选一。

窗口下拉为空时显示“没有可用窗口”。权限变化或新开窗口后，用下拉菜单内“刷新列表”重新枚举。缩略图选择器内嵌于内容区（非模态弹窗），右上角可关闭。

## 15. 全局快捷键

当前快捷键：

| 快捷键 | 行为 |
|---|---|
| `Command + Shift + 2` | 区域截图 |
| `Command + Shift + C` | 应用内复制当前截图 |
| `Command + Z` | 撤销最后一个标注 |

全局区域截图使用 Carbon `RegisterEventHotKey`，签名为 `WCCP`，ID 为 `1`。对象销毁时必须注销热键和事件处理器。

快捷键目前不可配置，也未处理注册冲突。

## 16. 权限、TCC 与签名

### 16.1 权限来源

`project.yml` 当前生成：

- `NSAudioCaptureUsageDescription`
- `NSMicrophoneUsageDescription`
- `com.apple.security.device.audio-input`

屏幕录制权限由 macOS TCC 在第一次调用 ScreenCaptureKit 时处理。授权后系统可能要求重启应用。

滚动截屏额外需要**辅助功能（Accessibility）权限**：合成滚轮事件驱动目标内容滚动受 `kTCCServiceAccessibility` 管控。首次点击「滚动截屏」时通过 `AXIsProcessTrustedWithOptions` 弹出系统提示，并在工具栏显示引导横幅；该权限无对应 Info.plist 用途说明键，重置用 `tccutil reset Accessibility io.worldcapture.app`。

### 16.2 重置开发权限

只重置 WorldCapture：

```bash
tccutil reset ScreenCapture io.worldcapture.app
```

不要无条件执行全局 `tccutil reset ScreenCapture`，它会影响其他应用。

### 16.3 验证签名

```bash
codesign --verify --deep --strict --verbose=2 \
  .derived-data/Build/Products/Debug/WorldCapture.app

codesign -d --entitlements - \
  .derived-data/Build/Products/Debug/WorldCapture.app
```

检查权限文字：

```bash
plutil -p \
  .derived-data/Build/Products/Debug/WorldCapture.app/Contents/Info.plist
```

Swift Package 可执行文件不能替代 `.app` 权限验证。

## 17. 自动化测试

当前共有 11 项 Swift Testing 测试。

### 17.1 CaptureRegionTests

- AppKit 到 ScreenCaptureKit 坐标转换；
- Retina 2× 像素换算；
- 超出显示器区域的裁剪；
- 空选择拒绝。

### 17.2 CaptureWindowTests

- 应用名与窗口标题组合；
- 无标题窗口回退到应用名。

### 17.3 CaptureAnnotationTests

- 标注 JSON 往返；
- 归一化坐标限制；
- 文字标签持久化；
- 渲染保持图片尺寸；
- 马赛克确实修改像素且不改变画布尺寸。

### 17.4 CaptureErrorTests

- 所有错误具有非空、可理解的中文说明；
- 录制底层错误信息能够透传。

### 17.5 当前测试缺口

- ScreenCaptureKit 权限集成测试；
- 真实多显示器截图；
- 窗口关闭竞态；
- 真实 MP4 播放与音轨验证；
- UI 自动化；
- 全局快捷键冲突；
- 长时间录制、磁盘写满和系统休眠。

这些测试涉及隐私授权、真实桌面或硬件，不能放进默认无交互单元测试。

## 18. 人工验收清单

### 18.1 截图

- [ ] 主屏截图清晰且尺寸符合 Retina 像素。
- [ ] 区域截图位置、尺寸正确。
- [ ] Esc 能取消区域截图。
- [ ] 窗口列表可见，刷新后包含新窗口。
- [ ] 关闭窗口后捕获会显示合理错误。
- [ ] 保存 PNG 可正常打开。
- [ ] 剪贴板可粘贴到预览、聊天或文档应用。

### 18.2 标注

- [ ] 五种工具预览位置正确。
- [ ] 撤销只移除最后一项。
- [ ] 清空不修改原图。
- [ ] 导出结果与预览大致一致。
- [ ] 马赛克在原始分辨率下不可读。

### 18.3 录屏

- [ ] 首次授权流程明确。
- [ ] 录制计时递增。
- [ ] WorldCapture 自身窗口不进入画面。
- [ ] 停止后出现成功状态。
- [ ] Finder 能定位文件。
- [ ] `ffprobe` 能读取 MP4，存在视频和音频流。
- [ ] QuickTime 可播放并听到系统音频。

验证命令：

```bash
ffprobe -v error \
  -show_entries format=duration,size \
  -show_entries stream=index,codec_type,codec_name,width,height,sample_rate,channels \
  -of json /path/to/recording.mp4
```

## 19. 故障排查

### 19.1 窗口选择为空

检查顺序：

1. 点击窗口栏右侧刷新按钮；
2. 确认至少存在尺寸大于 100×80 的普通应用窗口；
3. 确认 WorldCapture 已获屏幕录制权限；
4. 授权后完全退出并重新启动应用；
5. 必要时执行针对 Bundle ID 的 TCC reset 后重新授权。

### 19.2 看不到窗口选择控件

当前版本已将窗口选择放在独立第二行，最小窗口宽度为 900。若仍缺失，优先确认运行的是最新构建：

```bash
pkill -x WorldCapture
xcodebuild -project WorldCapture.xcodeproj -scheme WorldCapture \
  -configuration Debug -derivedDataPath .derived-data build
open .derived-data/Build/Products/Debug/WorldCapture.app
```

### 19.3 截图提示权限不足

进入：

```text
系统设置 -> 隐私与安全性 -> 屏幕与系统音频录制
```

启用 WorldCapture 并重启应用。

### 19.4 停止录制报错或 MP4 无法播放

先检查文件：

```bash
ffprobe -v error -show_format -show_streams /path/to/file.mp4
```

当前实现必须使用 `SCRecordingOutput`。若生成文件提示 `moov atom not found`：

- 确认没有运行旧版应用；
- 确认 `ScreenRecorder.swift` 没有恢复 `AVAssetWriterInput.append` 方案；
- 重新构建并重新启动 `.app`；
- 读取系统日志中的 `ScreenCaptureKit` 和 `CoreMedia` 错误。

日志示例：

```bash
/usr/bin/log show --last 10m --style compact \
  --predicate 'process == "WorldCapture"'
```
### 19.5 权限文字或 entitlement 消失

通常是直接编辑生成文件或 `project.yml` 缺少 `info.properties` / `entitlements.properties`。修复 `project.yml` 后重新执行：

```bash
xcodegen generate
xcodebuild -project WorldCapture.xcodeproj -scheme WorldCapture \
  -configuration Debug -derivedDataPath .derived-data build
```

### 19.6 输出路径已有文件

`SCRecordingOutput` 需要新的输出 URL。正常 UI 通过时间戳避免重名；测试代码直接传 URL 时，应先选择不存在的文件名。

## 20. 日志与错误策略

对用户显示的捕获错误统一使用 `CaptureError`。录制底层错误会包含：

- NSError domain；
- code；
- localized description；
- failure reason；
- recovery suggestion。

不要只显示 “The operation could not be completed”；底层域和代码是定位 AVFoundation、ScreenCaptureKit 与 TCC 问题的必要信息。

下一阶段应引入 `OSLog.Logger`，至少建立以下 subsystem/category：

- capture；
- recording；
- permissions；
- export。

日志不得记录截图内容、窗口文本全文、文件内容或用户音频。

## 21. 发布流程

### 21.1 版本来源

当前版本配置在 `project.yml`：

```yaml
MARKETING_VERSION: 0.1.1
CURRENT_PROJECT_VERSION: 2
```

发布时同时更新：

- `MARKETING_VERSION`；
- `CURRENT_PROJECT_VERSION`；
- README 当前版本；
- 本文档头部状态；
- changelog（尚未建立）。

### 21.2 签名分发（Developer ID + 公证）

分发走 **Developer ID + 公证**（非 App Store），原因见 §22 与产品定位（纯本地免费工具，滚动截屏依赖合成事件与辅助功能权限，无法在 App Store 沙盒中存活）。

`project.yml` 已按配置区分签名身份：

- **Debug** → `Apple Development`（本地开发，TCC 授权跨重建稳定）；
- **Release** → `Developer ID Application`（分发签名，配合 hardened runtime 与公证）。

#### 一次性准备（由发布负责人提供，不入库）

1. 加入 Apple Developer Program（付费），在钥匙串安装 **Developer ID Application** 证书
   （Xcode → Settings → Accounts → Manage Certificates → `+` → Developer ID Application）。
2. 存储公证凭据为一个 keychain profile：

   ```bash
   xcrun notarytool store-credentials <profile> \
     --apple-id <你的 Apple ID> \
     --team-id 43M5KN7MPD \
     --password <App 专用密码>
   ```

   （App 专用密码在 appleid.apple.com 生成；也可改用 App Store Connect API 密钥。）

#### 一键发布

```bash
scripts/release.sh <profile> [signing-identity]
```

- `<profile>`：notarytool 的 keychain profile 名（如 `BlissMeta-Notary`）。
- `[signing-identity]`：给 DMG 签名用的证书名，默认 `Developer ID Application`；钥匙串里有多张同名证书时显式指定。

脚本依次执行（8 步）：生成工程 → `Release` 归档 → 按 `scripts/ExportOptions.plist`（`developer-id`）导出 `.app` → 用 `hdiutil` 打包 **DMG**（内含 `.app` 与拖入用的 `/Applications` 符号链接）→ `codesign --timestamp` 给 DMG 签名 → `notarytool submit --wait` 公证 DMG → `stapler staple` 装订到 DMG → `codesign`/`spctl`/`stapler validate` 验证。

交付物为单个 **`build/WorldCapture-<version>.dmg`**（已签名 + 已公证 + 已装订，可直接分发）；版本号自动取自 `project.yml` 的 `MARKETING_VERSION`。

> DMG 为零依赖功能版（App + Applications 链接）。如需带背景图/窗口布局的精美 DMG，改用 `create-dmg`（Homebrew）或追加一段 AppleScript 布局脚本。

> 排错提醒：用 `| tee` 记录日志时，`tee` 返回 0 会掩盖脚本失败——务必检查日志中是否出现 `EXPORT FAILED`，不要只看 exit code。首次导出偶发 `A timestamp was expected but was not found`（codesign 连不上 `timestamp.apple.com`），重试 `xcodebuild -exportArchive` 即可，非配置问题。

证书与公证凭据必须由发布负责人提供，**不得写入仓库**。

### 21.3 自动更新（Sparkle）

直分发版通过 **Sparkle 2** 自动更新（SPM 依赖，配置在 `project.yml` 的 `packages.Sparkle`，当前解析到 2.9.3）。代码封装在 `Updater.swift`（`UpdaterController`），应用入口 `WorldCaptureApp` 持有它，主菜单「检查更新…」与菜单栏均可触发；菜单文案走 `Loc.s("menu.checkUpdates")`（三语已加）。

更新链路两个关键配置写在 **Info.plist**（经 `project.yml` 的 `info.properties` 注入，**不要直接改 `macos/App/Info.plist`——它由 XcodeGen 生成、每次 `xcodegen generate` 会被覆盖**）：

- `SUFeedURL` — appcast 地址，`https://worldcapture.fukumoto.jp/appcast.xml`。**这个值编译进每一个已发布的二进制，几乎不可撤回**：想换它只能发新版本让用户升上来，而那次升级本身又依赖旧地址还活着。因此它用自有域名的子域名做一层间接（托管随时可迁移，URL 不动），而不是 `*.github.io` 这类绑定账号/仓库名的地址。DMG 的下载地址是另一回事，见下。
- `SUPublicEDKey` — EdDSA 验签公钥（`S9o2kOwFSWxEpNJ9z43Jxa15FwBBjVG6lmKXu2Kw8yY=`）。

> 版本比较：Sparkle 用 bundle 的 `CFBundleVersion`/`CFBundleShortVersionString`。两者已改为引用 `$(MARKETING_VERSION)`/`$(CURRENT_PROJECT_VERSION)`（同样在 `project.yml`），与 DMG 命名保持单一来源；发版时只改 `project.yml` 里的版本号即可。

#### EdDSA 密钥（一次性 + 须备份）

私钥已用 Sparkle 的 `generate_keys` 生成并存入**登录钥匙串**（条目 “Private key for signing Sparkle updates”）。

- **务必离线备份私钥**：`generate_keys -x sparkle_private_key.txt`（导出后存到安全处，**不得入库**）。私钥丢失 = 无法再发布能被老版本接受的更新，更新链断裂。
- 换机/CI 上恢复：`generate_keys -f sparkle_private_key.txt` 导入。
- 工具位置：随 Sparkle SPM artifact 落在 `build/dd/SourcePackages/artifacts/sparkle/Sparkle/bin/`（archive 后存在）。

#### 发布脚本生成 appcast

`scripts/release.sh`（第 9 步）在公证装订后用 `generate_appcast` 扫描 `build/appcast/`、以钥匙串私钥 EdDSA 签名、生成/更新 `appcast.xml`：

- `build/appcast/` **持久保留**（跨版本累积发布记录，Sparkle 据此判断可升级项）。
- enclosure 下载前缀默认指向 GitHub Releases 的当前 tag：`https://github.com/fukumotomakoto/worldcapture/releases/download/v<version>/`。它与 `SUFeedURL` **性质不同**——只写进每次重新生成的 `appcast.xml`，随时可改，且下载包的完整性由 EdDSA 签名保证、不依赖来源可信，所以直接挂 GitHub Releases，省带宽也省仓库体积。可用环境变量覆盖：`DOWNLOAD_URL_PREFIX=... GH_REPO=... SITE_URL=... scripts/release.sh <profile>`。
- ⚠️ 实测（2026-10-07 发 0.1.1）：`generate_appcast` **会把已有条目的 enclosure URL 也改写成本次前缀**，历史版本因此指向不存在的目录。生成后必须 `grep 'url='` 检查，把旧版本条目改回各自 tag 的目录（EdDSA 签名只覆盖文件内容，改 URL 不影响验签）。
- 它还会生成 **delta 包**（`WorldCapture<新build>-<旧build>.delta`，Sparkle 优先走增量、失败再回退全量）和 `<sparkle:releaseNotesLink>`（指向 `SITE_URL/WorldCapture-<version>.html`，源文件放在 `build/appcast/` 同名 `.html`）。发布时 **delta 要和 DMG 一起传 GitHub Release，HTML 要和 appcast.xml 一起推 gh-pages**。
- 发版前先跑 `xcrun notarytool history --keychain-profile <profile>`：返回 403「A required agreement is missing or has expired」= Apple 开发者协议需在 developer.apple.com 重新接受（接受后约 1 分钟生效），别等归档完才在公证一步失败。
- `gh release create --target` 不接受短 SHA，用 `main` 或完整 SHA。
- **自动更新链路已于 2026-10-07 端到端验证**：装 0.1.0 → 「检查更新…」→ 发现 0.1.1 → 下载 → 验签 → 安装 → 自动重启，TCC 授权未丢。
- **分发时**（两处地址互不相干）：`WorldCapture-<version>.dmg` 传到 GitHub Release 的 `v<version>` tag；`appcast.xml` 传到 `SUFeedURL` 所在地址（`worldcapture.fukumoto.jp`）——**这一处必须同址**，否则老版本收不到更新。`build/appcast/old_updates/` 不要上传。

#### 仍需真机验证

应用内点「检查更新…」的实际联网行为，要等 `SUFeedURL` 指向真实可访问的 appcast 后才能端到端测试（占位域名不可达）。首次运行 Sparkle 会询问是否开启自动检查（未设 `SUEnableAutomaticChecks`，符合隐私优先）。

## 22. 隐私与安全要求

- 不上传截图或录屏，除非用户明确选择未来的分享功能。
- 不在日志中写入捕获像素、窗口内容或音频内容。
- 系统音频默认排除 WorldCapture 自身声音。
- 麦克风功能启用前必须提供独立开关和清晰状态指示。
- 马赛克是导出时的像素化处理；在提供可逆工程文件时，必须警告工程文件仍包含未遮挡原图。
- 保存到用户选择位置使用系统保存面板。
- 不提交证书、notarization 密钥、Apple ID 或个人 Team 配置。

## 23. 已知限制

- 录屏可选择单块显示器（多屏菜单选择），暂不支持多屏同时录制。
- 区域截屏与滚动截屏支持多显示器：选择遮罩铺设到所有屏幕，按选区所在显示器截图；但「截取主屏幕」全屏仍只取主显示器（暂无显示器选择器）。
- 录屏不含麦克风和摄像头。
- 录屏没有暂停/继续。
- 未捕获鼠标点击特效、按键显示和独立鼠标轨迹。
- 标注颜色可从预设色板选择、线宽可选细/中/粗（均每标注独立、可改选中项）；暂无自定义取色器与无级线宽。
- 文字标注创建后可选中并在工具栏就地改写文案；尚不支持多行、字体与字号。
- 标注支持单选/Shift 多选、移动（含多选组移动）、缩放、批量改色改线宽与删除；尚不支持框选、对齐与图层顺序调整。
- 没有截图历史、项目保存和崩溃恢复。
- 全局快捷键固定，未提供冲突检测。
- 没有 OCR、GIF 和云分享。
- 滚动截屏依赖程序化滚轮与图像拼接，对自定义滚动容器或惯性滚动较强的应用可能对齐不稳。
- Windows 后端尚未建立。

## 24. Windows 实现计划

Windows 后端原则：

- 截图/录屏：Windows Graphics Capture；
- 系统音频与麦克风：WASAPI；
- 视频编码：Media Foundation 硬件编码优先；
- UI：WinUI 3 或其他原生 Windows UI；
- 标注语义：复用归一化坐标和 `AnnotationKind`；
- 工程文件：与 macOS 使用相同 JSON schema。

Windows 开始前必须先形成跨平台 schema 文档，避免直接复制 Swift 类型导致格式漂移。需要决策的共享核心方案：

1. Rust 共享领域核心；或
2. 两端原生实现、用 JSON Schema 和一致性测试约束。

当前仓库没有 Rust 工具链，也没有 Windows SDK/真机验证环境，因此 Windows 代码不得标记为“完成”，直到在 Windows 11 真机或 CI 上通过构建与捕获测试。

## 25. 路线图

### Phase 0：macOS 截图与基础录屏

- [x] 主屏、区域、窗口截图
- [x] PNG 保存和剪贴板
- [x] 非破坏标注
- [x] 主屏录制和系统音频
- [x] 本地签名 `.app`
- [ ] 完成最新原生录制器人工验收

### Phase 1：macOS 录屏完善

- [ ] 麦克风混音
- [ ] 摄像头画中画
- [ ] 录制区域/窗口选择
- [ ] 暂停与继续
- [ ] 鼠标点击和按键显示
- [ ] 异常退出时安全收尾
- [ ] 长时间录制测试

### Phase 2：编辑与项目格式

- [x] 标注选择/移动/缩放/删除
- [ ] 工程文件与自动恢复
- [ ] 时间线、裁剪和片段合并
- [ ] 自动缩放、鼠标平滑
- [ ] GIF 与多比例导出

### Phase 3：Windows

- [ ] Windows 项目骨架
- [ ] Windows Graphics Capture
- [ ] WASAPI
- [ ] Media Foundation 导出
- [ ] 跨平台 schema 一致性测试
- [ ] Windows 安装包与代码签名

### Phase 4：高级能力

- [ ] OCR 文字识别（macOS Vision，完全本地）
- [x] 滚动截屏（选区滚动拼接，需辅助功能权限）
- [ ] 历史记录库（截图/录屏统一历史，支持搜索、收藏、快速定位）
- [ ] 设置页（界面语言、快捷键、默认保存路径）
- [ ] 录制 GIF 与多格式导出（PNG/JPG/MP4/GIF/PDF）
- [ ] 钉屏「点击穿透」开关
- [ ] 编辑器布局升级（浮动标注栏 + 右侧样式面板，参照 Snagit/CleanShot）
- 已弃：账号登录、Pro 付费墙、云同步（见 §1 产品原则）

## 26. 开发工作流

每次修改建议按以下顺序：

1. 修改源代码或 `project.yml`；
2. 若工程配置变化，执行 `xcodegen generate`；
3. 执行 `swift test`；
4. 执行 Xcode scheme 测试；
5. 对涉及权限、捕获或录制的改动运行正式 `.app` 人工验收；
6. 执行 `git diff --check`；
7. 提交单一、可解释的变更。

最低验证命令：

```bash
cd ~/Projects/apps/worldcapture/macos
swift test

cd ..
xcodegen generate
xcodebuild -project WorldCapture.xcodeproj -scheme WorldCapture \
  -configuration Debug -derivedDataPath .derived-data test

git diff --check
git status --short
```

## 27. 代码规范

- Swift 6 严格并发模型。
- UI 状态只在 `@MainActor` 修改。
- 平台对象跨队列时必须明确隔离或使用锁保护。
- 捕获和渲染逻辑进入 `CaptureKit`，不可直接堆在 SwiftUI View。
- 新领域模型优先 `Codable + Equatable + Sendable`。
- 坐标统一使用归一化结构对外存储。
- 用户错误必须可本地化且包含足够诊断信息。
- 不使用强制解包处理系统 API 返回值。
- 新功能至少增加纯逻辑单元测试；硬件能力增加人工验收项。

## 28. 关键工程决策

### ADR-001：平台原生捕获

macOS 使用 ScreenCaptureKit，Windows 计划使用 Windows Graphics Capture。原因是权限、性能、HDR、多显示器与系统音频均依赖平台能力。

### ADR-002：非破坏标注

原图和标注分开保存，导出时合成。这样可以撤销、跨平台重绘并为未来工程文件保留编辑能力。

### ADR-003：归一化坐标

标注保存为 `0...1` 坐标，避免 UI 缩放、Retina 和不同平台 DPI 导致格式不兼容。

### ADR-004：原生 MP4 封装

macOS 15+ 使用 `SCRecordingOutput`。废弃手工 AVAssetWriter 双队列方案，因为真实录制中出现音视频时序竞争和无 `moov` 文件。

### ADR-005：XcodeGen 唯一事实源

权限、entitlement、Bundle ID 和 target 配置放在 `project.yml`。生成的 plist 与 Xcode 工程可提交，但不能成为手工维护的第二事实源。

### ADR-006：界面国际化与双轨资源 bundle

界面文案用 `Localizable.strings`，基准语言 `zh-Hans`，另含 `en` 与 `ja`，放在 `macos/Sources/WorldCaptureMac/Resources/<lang>.lproj/`。

由于同一份源码既被 SwiftPM 编译（资源在 `Bundle.module`）又被 Xcode 应用编译（资源在 `Bundle.main`），`Loc`（`Localization.swift`）用 `#if SWIFT_PACKAGE` 选择正确的 bundle。所有界面文案必须走 `Loc.s("key")`，并在三个 `.strings` 中同步添加同名 key（语言名如“简体中文/English/日本語”用本族名，不翻译）。

界面语言默认跟随系统；设置页（⌘,）写入 `AppleLanguages` 覆盖，**重启应用后生效**（macOS 标准做法，避免运行时切换 bundle 的复杂度）。`project.yml` 设 `developmentLanguage: zh-Hans` 并在 Info.plist 声明 `CFBundleLocalizations`；`Package.swift` 设 `defaultLocalization` 与 `resources: [.process("Resources")]`。

## 29. 官方技术参考

- [ScreenCaptureKit](https://developer.apple.com/documentation/screencapturekit)
- [Capturing screen content in macOS](https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-in-macos)
- [SCRecordingOutput](https://developer.apple.com/documentation/screencapturekit/screcordingoutput)
- [SCRecordingOutputConfiguration](https://developer.apple.com/documentation/screencapturekit/screcordingoutputconfiguration)
- [NSMicrophoneUsageDescription](https://developer.apple.com/documentation/bundleresources/information-property-list/nsmicrophoneusagedescription)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

## 30. 常用命令速查

```bash
# 生成工程
xcodegen generate

# Swift 单元测试
(cd macos && swift test)

# Xcode 完整测试
xcodebuild -project WorldCapture.xcodeproj -scheme WorldCapture \
  -configuration Debug -derivedDataPath .derived-data test

# 构建应用
xcodebuild -project WorldCapture.xcodeproj -scheme WorldCapture \
  -configuration Debug -derivedDataPath .derived-data build

# 启动应用
open .derived-data/Build/Products/Debug/WorldCapture.app

# 验证签名
codesign --verify --deep --strict --verbose=2 \
  .derived-data/Build/Products/Debug/WorldCapture.app

# 重置本应用屏幕录制权限
tccutil reset ScreenCapture io.worldcapture.app

# 检查 MP4
ffprobe -v error -show_format -show_streams /path/to/recording.mp4

# 查看应用日志
/usr/bin/log show --last 10m --style compact \
  --predicate 'process == "WorldCapture"'
```
