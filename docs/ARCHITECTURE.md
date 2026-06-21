# 架构

WorldCapture 采用共享领域模型与平台原生采集后端分离的结构。

```text
UI / Editor
    |
Capture domain model + project format
    |
macOS ScreenCaptureKit | Windows Graphics Capture
    |
CoreAudio / WASAPI + hardware video encoders
```

## 边界

- `macos/`：macOS 权限、屏幕/窗口枚举、像素捕获与录制。
- `windows/`：Windows 捕获后端，Phase 4 建立。
- `core/`：跨平台工程文件、标注、时间线与导出语义，Phase 2 建立。

当前标注模型使用归一化坐标保存，与截图像素尺寸和 UI 缩放无关。预览时由 SwiftUI Canvas 绘制，保存或复制时由 Core Graphics 合成到原始分辨率；原图始终不被改写。文字和序号作为结构化标注保存，马赛克在导出时对选区执行降采样再无插值放大。

视频与截图不经过云服务。未来的分享服务必须保持可选，并与采集进程隔离。

## 录屏管线

`SCStream` 分别在视频和音频队列输出采样，`AVAssetWriter` 实时写入 H.264/AAC MP4。编码会话以首个有效视频帧的时间戳开始，停止采集后依次结束输入并完成文件封装。应用自身画面与音频默认从主屏幕录制中过滤。

## 首个垂直切片

应用列出主显示器，通过 ScreenCaptureKit 捕获一帧，在应用内预览，并允许用户保存 PNG。该切片用于验证权限、色彩空间、Retina 尺寸和错误处理。
