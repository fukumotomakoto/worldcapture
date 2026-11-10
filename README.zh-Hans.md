# WorldCapture

**中文** · [English](README.en.md) · [日本語](README.ja.md)

macOS 上的截图、录屏和**图上翻译**工具。截一张外文界面，译文直接贴回原位；框选屏幕一块区域，字幕和弹幕持续翻译。所有处理都在你的 Mac 上完成：**免费、MIT 开源、无账号、无遥测、无水印，15 MB。**

![翻译前 → 翻译后：译文按原文的位置、字号和底色贴回原位](docs/assets/hero-translate-zh.png)

## 下载

- [官网下载](https://worldcapture.fukumoto.jp/) · [GitHub Releases](https://github.com/fukumotomakoto/worldcapture/releases)
- macOS 15 或更高，Apple Silicon 与 Intel 通用。Apple 智能翻译引擎需要 macOS 26 并开启 Apple 智能，否则自动使用系统翻译。
- 已签名、已公证，内置自动更新（可关闭）。

## 它能做什么

**翻译**
- **翻译图片**：识别截图里的文字，按段落翻译，把译文贴回原来的位置。字号跟随原文，底色取自周围像素，每一块都能拖动、缩放、删除，导出时一并带上。
- **翻译镜**（⌘⇧6）：框选屏幕上的一块区域，持续识别并把译文原位盖上去，点击穿透。看外文字幕、直播弹幕、会刷新的界面时用。
- **提取文字**：OCR 结果面板里直接翻译，原文｜译文两栏，可选目标语言，译文单独复制。
- **引擎与词表**：Apple 智能（端上大模型）或系统翻译，都不联网。内置界面常用词的中文、日文译法，可以在 `~/Documents/WorldCapture/glossary.txt` 里加你自己的术语。

**截图与录屏**
- 区域、全屏、窗口（含浮动面板）、滚动长图、延时截图。
- 屏幕 / 区域 / 窗口录制，系统声音与麦克风，GIF。
- 标注：矩形、椭圆、箭头、文字、序号、马赛克、自由笔、裁切；钉屏（可点击穿透）；历史库。

**入口**
- 顶部工具条：菜单栏下方的小标签，鼠标指上去滑出按钮。设置里可关闭。
- 菜单栏图标、全局快捷键（⌘⇧2 区域截图等）。
- 助手侧栏：主窗口内嵌 Claude 或 ChatGPT 网页版，用你自己的账号；「发给助手」把截图放进剪贴板，粘贴即发。
- Safari 扩展：整页截图、浏览器内 OCR，可交给 App 继续编辑。

## 隐私

截图、录屏、文字识别、翻译都不离开这台 Mac。没有账号，没有埋点。唯一的联网行为是可选的更新检查，以及你自己登录的助手侧栏。详见 [隐私政策](PRIVACY.md)。

## 从源码构建

```bash
cd macos && swift test            # 核心逻辑测试
cd .. && xcodegen generate
xcodebuild -project WorldCapture.xcodeproj -scheme WorldCapture \
  -configuration Debug -derivedDataPath .derived-data build
```

开发、权限、发布流程见 [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md)，架构见 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)。

## 许可与赞助

[MIT](LICENSE)。发行版打包了 Sparkle（自动更新）与 Tesseract.js（浏览器端 OCR），声明见 [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md)。

WorldCapture 不商业化，靠赞助维持。如果它对你有用，欢迎通过 GitHub Sponsors 支持。
