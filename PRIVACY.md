# 隐私政策 / Privacy Policy

_最后更新 / Last updated: 2026-06-30_

---

## 中文

WorldCapture 是一个**本地优先**的截屏、标注与录屏工具。我们的原则很简单：**你的内容属于你，不离开你的设备。**

### 我们不收集任何数据
- 没有账号、没有注册、没有登录。
- 没有分析、没有埋点、没有遥测、没有广告、没有第三方追踪 SDK。
- 你的截图、录屏、OCR 文本**全部在本机处理，永不上传**。

### 数据存放在哪里
所有数据都保存在**你自己的 Mac 上**，由你掌控：
- 历史记录：`~/Library/Application Support/WorldCapture/history.json`；
- 截图/录屏文件：保存在你自己选择的位置；
- 偏好设置（如界面语言、是否自动检查更新）：保存在系统 `UserDefaults`。

卸载或手动删除这些文件即可清除全部数据。

### 唯一的联网行为：检查更新
WorldCapture **唯一**会发起的网络请求，是**可选的自动更新检查**（基于开源组件 [Sparkle](https://sparkle-project.org)）：
- 它会访问我们的更新源（appcast）以判断是否有新版本；
- 这类请求按 HTTP 的固有机制，会让承载更新源的服务器看到标准连接信息（如 IP 地址、App 版本、macOS 版本、CPU 架构）；
- 你可以在「设置 → 更新」中**关闭自动检查**；关闭后除非你手动点「检查更新」，否则不会有任何联网。

除此之外，WorldCapture 自身不进行任何其他网络连接。

### 助手侧栏（可选）：一个内嵌浏览器
主窗口可以打开一个「助手」侧栏，里面是 **Claude（claude.ai）或 ChatGPT（chatgpt.com）的网页版**，用的是**你自己的账号**：
- 它就是一个内嵌的浏览器视图。WorldCapture 不接入任何 AI 接口、不保存任何密钥，也**不会替你发送任何内容**；
- 「发给助手」只把当前截图复制到**剪贴板**并预填一句提示，截图只有在你自己在对话框里粘贴并发送时才会离开这台 Mac；
- 你在侧栏里输入或粘贴的内容，受所选服务（Anthropic 或 OpenAI）的隐私政策约束，与 WorldCapture 无关；
- 侧栏的登录态存放在系统的网站数据存储里，和 Safari 的做法一致；不打开侧栏就不会有任何相关联网。

### 系统权限
WorldCapture 会申请屏幕录制、（可选）麦克风、（滚动长图所需的）辅助功能权限。这些权限**仅用于在本机完成捕获**，不会因此向任何地方传输数据。

### 开源可验证
WorldCapture 以 **MIT 许可**开源。以上承诺都可以通过审计源码来核实——这正是我们开源的原因之一。

### 联系方式
有隐私相关问题，请通过项目仓库的 Issue 联系，或发送邮件至 <worldcapture@fukumoto.jp>。

---

## English

WorldCapture is a **local-first** screenshot, annotation, and screen-recording tool. Our principle is simple: **your content is yours and never leaves your device.**

### We collect nothing
- No account, no sign-up, no login.
- No analytics, no telemetry, no ads, no third-party tracking SDKs.
- Your screenshots, recordings, and OCR text are **processed entirely on-device and never uploaded.**

### Where your data lives
Everything stays **on your own Mac**, under your control:
- History: `~/Library/Application Support/WorldCapture/history.json`;
- Screenshots/recordings: saved to locations you choose;
- Preferences (e.g. UI language, auto-update toggle): stored in the system `UserDefaults`.

Uninstalling or deleting these files removes all data.

### The only network activity: update checks
The **only** network request WorldCapture makes is the **optional automatic update check** (via the open-source component [Sparkle](https://sparkle-project.org)):
- It contacts our update feed (appcast) to see whether a newer version exists;
- As with any HTTP request, this lets the server hosting the feed see standard connection metadata (IP address, app version, macOS version, CPU architecture);
- You can **turn automatic checks off** in Settings → Updates. After that, no network connection is made unless you manually click "Check for Updates."

Beyond that, WorldCapture itself makes no other network connections.

### Assistant sidebar (optional): an embedded browser
The main window can open an "Assistant" sidebar that shows **the web version of Claude (claude.ai) or ChatGPT (chatgpt.com)**, signed in with **your own account**:
- It is simply an embedded browser view. WorldCapture integrates no AI API, stores no keys, and **never sends anything on your behalf**;
- "Send to Assistant" only copies the current screenshot to the **clipboard** and prefills a prompt; the screenshot leaves this Mac only when you paste it into the chat box and send it yourself;
- Whatever you type or paste in the sidebar is governed by the chosen service's (Anthropic's or OpenAI's) privacy policy, not by WorldCapture;
- The sidebar's sign-in state lives in the system website data store, exactly as Safari does; if you never open the sidebar, no related connection is made.

### System permissions
WorldCapture requests Screen Recording, (optional) Microphone, and Accessibility (for scrolling capture) permissions. These are used **solely for on-device capture** and transmit nothing.

### Open source, verifiable
WorldCapture is open source under the **MIT License**. Every claim above can be verified by auditing the source — which is one reason we open-sourced it.

### Contact
For privacy questions, please open an issue in the project repository, or email <worldcapture@fukumoto.jp>.
