# WorldCapture

Windows 与 macOS 的本地优先截屏、标注和录屏工具。

当前阶段：Phase 0。macOS 已具备主屏幕捕获、拖拽区域选择、Retina 原始分辨率输出、应用内预览与 PNG 保存；随后接入窗口识别、共享编辑器、录屏管线和 Windows Graphics Capture。

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

## 近期路线

1. macOS 全屏捕获、区域选择、预览与 PNG 保存。✅
2. 窗口识别、剪贴板和全局快捷键。
3. 非破坏标注模型与编辑器。
4. ScreenCaptureKit 录屏、系统音频、麦克风和 MP4 导出。
5. Windows Graphics Capture / WASAPI 后端。
