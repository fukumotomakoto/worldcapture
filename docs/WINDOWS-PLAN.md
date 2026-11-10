# WorldCapture for Windows · 方案

> 2026-11-11 立项。技术栈已定：**C# + WinUI 3 原生**（师弟拍板）。本文是方案与清单，不是规格；
> 每一期开工前按本文拆出验收标准。标「待核实」的是还没查证的外部事实，别当成已知。

## 1. 原则（与 macOS 版一致）

- 纯本地、免费、无账号、无云。OCR、翻译都在本机完成，不联网。
- 功能与体验对齐 macOS 版，不追求像素级一致：遵守 Windows 的习惯（托盘、Win11 圆角、Mica 材质）。
- 保存目录一致：`文档\WorldCapture\{Images,Videos,OCR}`。
- 四种界面语言：简中、英、日、韩。文案的键名与 macOS 的 `Localizable.strings` 共用一套。

## 2. 代码能复用多少

Swift 代码不能直接跑在 Windows 上。能复用的是**算法与数据契约**，要按原样移植成 C#，并把测试一起移过去：

| macOS（CaptureKit，约 2700 行） | Windows | 方式 |
|---|---|---|
| `CaptureAnnotation` / `CaptureRegion` / `RGBAColor` | `WorldCapture.Core` | 逐行移植，JSON 格式保持兼容 |
| `AnnotationRenderer`（含马赛克块大小规则） | Core + Win2D 绘制 | 规则移植，绘制层重写 |
| `TranslationBlockLayout` / `TextBlockGrouper` / `TextChunker` / `TranslationGlossary` | Core | 纯逻辑，整体移植 |
| `ScrollStitcher` / `ContentRegionDetector` | Core | 纯逻辑，整体移植 |
| `GIFEncoder` | Core（或 WIC 的 GIF 编码器） | 移植 |
| Safari 扩展的 JS（`content.js` / `background.js` / `popup` / `result`） | Chrome / Edge 扩展（MV3） | **直接复用**，只改外壳与原生通信 |
| 92 个单元测试 | `WorldCapture.Core.Tests`（xUnit） | 一并移植，结果对齐 |

`WorldCapture.Core` 是 `net10.0` 纯库、不依赖 Windows，**可以在这台 Mac 上 `dotnet test`**。大约一半的移植工作因此不需要 Windows 机器。

## 3. 平台能力对照

| 功能 | macOS 现在用的 | Windows 方案 | 备注 |
|---|---|---|---|
| 全屏 / 区域截图 | ScreenCaptureKit | DXGI Desktop Duplication 或 GDI BitBlt；区域截图用全屏冻结 + 覆盖层框选 | 多屏 + 每屏不同 DPI 是主要难点 |
| 窗口截图（含被遮挡） | SCK | Windows.Graphics.Capture（WGC） | Win11 可去掉黄色捕获边框（需要 `GraphicsCaptureAccess` 授权） |
| 录屏 + 系统声音 + 麦克风 | SCK + AVAssetWriter | WGC + Media Foundation（H.264 MP4）；WASAPI loopback 录系统声音 | |
| GIF | 自研编码器 | 移植的编码器 | |
| 滚动截图 | 合成滚轮事件 + 拼接 | `SendInput` 滚轮 + 移植的拼接算法 | Windows 不需要辅助功能授权 |
| OCR | Vision | `Windows.Media.Ocr`（系统自带、离线） | 每种语言要装对应的系统语言包；准确度要实测，不行就备选 PaddleOCR（ONNX） |
| 端上翻译 | Apple Translation / Apple 智能 | **最大的未知**，见 §4 | |
| 标注编辑器 | SwiftUI Canvas | WinUI 3 + Win2D | 工作量最大的一块 |
| 钉图（点击穿透） | NSPanel | 置顶窗口 + `WS_EX_LAYERED \| WS_EX_TRANSPARENT` | |
| 翻译镜 | 浮层 + 周期 OCR | 同上的置顶穿透窗口 + 周期截图 + OCR | |
| 顶部工具条 | NSPanel + 全局鼠标监视 | 无边框置顶窗口 + 定时读取 `GetCursorPos`，跟随鼠标换屏 | 多屏跟随规则照搬 macOS |
| 菜单栏图标 | MenuBarExtra | 托盘图标（H.NotifyIcon.WinUI，MIT） | |
| 全局快捷键 | Carbon RegisterEventHotKey | Win32 `RegisterHotKey` | 键位见 §5 |
| 助手侧栏 | WKWebView | WebView2（系统自带） | |
| 历史库 | 本地文件 + 索引 | 同样的结构 | |
| 自动更新 | Sparkle | 商店版由 Store 负责；GitHub 版用 Velopack（MIT） | 见 §6 |

## 4. 端上翻译（需要先调研）

Windows 没有和 Apple Translation 对等的、所有机器都能用的离线翻译 API。候选：

1. **Opus-MT（Helsinki-NLP，CC-BY 4.0）转 ONNX，用 ONNX Runtime 跑**：每个语言对单独一个模型（约 300MB，量化后更小），按需下载。许可干净。中日互译可能没有直连模型，需要经英文中转（**待核实**）。
2. **NLLB-200 蒸馏版**：一个模型覆盖全部语言，但权重是 **CC-BY-NC**（非商用）。项目本身免费，但有许可风险，不作为首选。
3. **Windows AI API（Phi Silica 等）**：只在 Copilot+ PC 上有，覆盖面太窄，只能当可选增强。

**做法**：P2 开工前先做一个 2～3 天的技术验证：中→日、日→中、英→中各跑一遍，比较质量、速度、体积，再定方案。在那之前，翻译相关的界面先留着，引擎接口抽象好。

## 5. 快捷键（Windows）

macOS 的 ⌃⌥ 对应 Windows 的 **Ctrl+Alt**，字母沿用：Ctrl+Alt+A 区域、W 窗口、F 全屏、S 滚动、O 取字、T 翻译镜、R 录屏、G GIF、Z 重复。

需要注意的两点：

- **Ctrl+Alt 在欧洲键盘上等于 AltGr**，会吞掉那些语言要打的字符（比如德语键盘的 Ctrl+Alt+Q 打出 @）。目标用户主要用中日美式键盘，所以默认用 Ctrl+Alt；**设置里要能改键**（macOS 版目前也不能改，两边一起补）。
- **PrintScreen**：Win11 默认由截图工具接管（系统设置里有开关）。可以提供「用 PrintScreen 区域截图」的选项，并提示用户先关掉系统那项。

## 6. 签名与分发

- **首选 Microsoft Store（MSIX）**：Store 替我们签名、负责更新，省掉代码签名证书。个人开发者注册费用**待核实**（2025 年有过「个人开发者免费」的公告）。
- **GitHub Releases**：免安装版或安装包。未签名的程序会被 SmartScreen 警告，需要代码签名。候选是 Azure Trusted Signing（约 10 美元/月，个人资格有国家/地区限制，**待核实**）。没签名之前，GitHub 版只放给愿意折腾的用户。
- **winget**：等有了签名的安装包之后再提交清单。
- 官网 `worldcapture.fukumoto.jp` 增加 Windows 下载入口。

## 7. 目录结构（提案，待审）

与 `macos/` 平级，新开 `windows/`，不改动现有 Mac 工程：

```
windows/
  WorldCapture.slnx
  src/WorldCapture.Core/          net10.0 纯逻辑（Mac 上可测）
  src/WorldCapture.App/           WinUI 3（net10.0-windows10.0.19041），打包为 MSIX
  tests/WorldCapture.Core.Tests/  xUnit，从 macos/Tests 移植
browser-extension/                （可选）Chrome/Edge 扩展，与 Safari 扩展共用 JS
.github/workflows/windows.yml     windows-latest 上构建 App + 跑测试 + 打 MSIX
```

最低支持 Windows 10 1903（WGC 的最低版本）。体验以 Win11 为准。同时出 x64 与 ARM64。

## 8. 开发环境（阻塞项）

WinUI 3 只能在 Windows 上构建和运行。按铁律「验证到观察到真实行为为止」，必须有一台能跑的 Windows：

- **方案 A**：在 Mac Studio 上用 Parallels Desktop 装 Windows 11 ARM。微软官方支持这种组合，Visual Studio 2022 有 ARM64 原生版，M3 Ultra 跑起来很宽裕。缺点是 Parallels 要付年费，也测不到 x64 和真实的多显卡多屏。
- **方案 B**：用 UTM 装 Windows 11 ARM。免费，但图形性能弱，截图和录屏相关的行为可能和实机不一样。
- **方案 C**：用一台实体 Windows 机（x64）做最终验证。
- **建议**：日常开发用 A，发布前用 C 验一遍；CI 用 GitHub Actions 的 windows-latest 保证每次提交都能构建。

## 9. 分期

| 期 | 内容 | 能在 Mac 上做的 |
|---|---|---|
| P0 骨架 | 解决方案、CI、Core 库与测试移植（模型、渲染规则）、托盘、全局快捷键、全屏/区域截图 → 剪贴板 + 自动保存 | Core 与测试 |
| P1 编辑器 | 标注全套（矩形、椭圆、箭头、文字、序号、马赛克、笔、裁切）、撤销、导出、钉图、历史库 | 渲染规则测试 |
| P2 文字 | OCR、OCR 结果面板；翻译技术验证 → 引擎 → 图上翻译回贴 → 翻译镜 | 版式算法测试 |
| P3 录制 | 窗口截图、录屏（系统声音、麦克风）、GIF、滚动截图、延时截图 | 拼接算法测试 |
| P4 完整形态 | 顶部工具条（多屏跟随）、助手侧栏、浏览器扩展、四语言、Store 上架、官网入口 | 扩展 JS |

P0 + P1 完成后，就是一个可以先发 Store 测试版的「截图 + 标注」工具。
