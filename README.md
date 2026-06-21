# WorldCapture

Windows 与 macOS 的本地优先截屏、标注和录屏工具。

当前阶段：Phase 0。macOS 截图与非破坏标注首版已经完整。主屏幕录制与系统音频已接入 ScreenCaptureKit，并使用 H.264/AAC 输出 MP4；真实权限环境的短录制验收仍待执行。

## 原则

- 本地优先：截图、录屏和 OCR 默认不离开设备。
- 原生捕获：macOS 使用 ScreenCaptureKit，Windows 使用 Windows Graphics Capture。
- 非破坏编辑：保留原始媒体和操作记录，导出时再渲染。
- 跨平台一致：项目文件、编辑模型、快捷键语义和导出结果保持一致。

## 当前运行

```bash
cd macos
swift test
swift run WorldCaptureMac
```

首次截屏时，macOS 会请求屏幕录制权限。

全局快捷键：`Command + Shift + 2` 启动区域截屏；应用内 `Command + Shift + C` 复制当前截图。

## 近期路线

1. macOS 全屏捕获、区域选择、预览与 PNG 保存。✅
2. 窗口识别、剪贴板和全局快捷键。✅
3. 非破坏标注模型与编辑器：矩形、箭头、文字、序号和马赛克。✅
4. ScreenCaptureKit 主屏幕录制、系统音频和 MP4 导出已实现；麦克风与真实录制验收待完成。
5. Windows Graphics Capture / WASAPI 后端。
