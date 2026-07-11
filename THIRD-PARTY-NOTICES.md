# 第三方组件声明

WorldCapture 本身以 [MIT](LICENSE) 发布。发行版（DMG）中另打包了以下第三方组件，
它们各自遵循其原有许可证。许可证全文见 [`LICENSES/`](LICENSES/)。

| 组件 | 版本 | 许可证 | 用途 | 上游 |
|---|---|---|---|---|
| Tesseract.js | 5.1.1 | Apache-2.0 | Safari 扩展内的浏览器端 OCR | https://github.com/naptha/tesseract.js |
| tesseract.js-core（WASM） | 随 5.1.1 打包 | Apache-2.0 | 上者的 WebAssembly 引擎 | https://github.com/naptha/tesseract.js-core |
| tessdata 训练数据（`eng` / `jpn` / `chi_sim` / `chi_tra`） | — | Apache-2.0 | OCR 语言模型 | https://github.com/tesseract-ocr/tessdata |
| Sparkle | 2.5.0+ | MIT（含 BSD 等子组件） | Developer ID 直分发的自动更新 | https://github.com/sparkle-project/Sparkle |

## 许可证副本

- Apache-2.0 全文：[`LICENSES/Apache-2.0.txt`](LICENSES/Apache-2.0.txt)，
  同时随代码打包在 [`macos/SafariExtension/vendor/tesseract/LICENSE`](macos/SafariExtension/vendor/tesseract/LICENSE)。
- Sparkle 全文（含其内嵌的 bsdiff / sais-lite / Ed25519 等组件的各自版权与许可）：
  [`LICENSES/Sparkle-MIT.txt`](LICENSES/Sparkle-MIT.txt)。

## 说明

上述 Apache-2.0 组件均未被修改，以原始发行形式打包（`macos/SafariExtension/vendor/tesseract/`）。
三个上游项目均未提供 `NOTICE` 文件，故本仓库无对应的 NOTICE 需要转载。

Tesseract.js 与训练数据全部在本地运行，OCR 过程不产生任何网络请求——这与 [PRIVACY.md](PRIVACY.md)
所述的「一切处理均在设备上完成」一致。
