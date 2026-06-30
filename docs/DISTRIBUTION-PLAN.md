# WorldCapture 上架与分发方案

> 状态：草案 · 2026-06-30
> 定位决策（见 [产品方向](../README.md) 与团队记忆）：**纯本地 · 免费**工具。本方案据此规划「免费工具的上架与分发」。
> 平台节奏：**macOS 先上，Windows 快速跟进**。
> macOS 渠道：**Developer ID 直分发为主，后续可加 MAS**。
> **许可决定（2026-06-30）：放弃商业化，采用 [MIT](../LICENSE) 开源，靠赞助维持。** 因此无需 EULA（MIT LICENSE 即许可条款）。原「订价 / 商业化」预研降级为[附录 A](#附录-a未来商业化订价路径已放弃保留备查)，仅备查。

---

## 1. 一句话策略

像 CleanShot X / Shottr / Snagit 一样，**官网直接下载 + Developer ID 签名公证**作为主分发口，保留滚动长图等全功能；待产品成熟再考虑上一个「精简版」到 Mac App Store。Windows 端等 Graphics Capture 后端就绪后，以官网直分发 + Microsoft Store 双线跟进。免费意味着没有内购/付费墙基建，但**自动更新、官网、下载托管、隐私与许可文案**这些「免费也必须有」的基建要补齐。

---

## 2. 现状盘点（已具备 / 缺口）

| 能力 | 状态 | 说明 |
|---|---|---|
| Developer ID 签名 | ✅ 已具备 | 证书 `Developer ID Application (43M5KN7MPD)` 已装钥匙串 |
| 公证流水线 | ✅ 已跑通 | `scripts/release.sh <notary-profile>`：归档→导出→**打包 DMG**→签名→公证→装订→验证，产物 `build/WorldCapture-<version>.dmg`；公证 profile 名 `BlissMeta-Notary` |
| 硬化运行时 | ✅ 已开 | `ENABLE_HARDENED_RUNTIME=YES` |
| 本地化 | ✅ zh-Hans/en/ja | `CFBundleLocalizations` 已配置 |
| 最低系统 | macOS 15.0 | 偏高，影响可触达用户数（见 §9 待决） |
| 版本号 | 0.1.0 | 距 1.0 还需收尾，见 §8 |
| **DMG 打包** | ✅ 已脚本化（待真机公证验证）| `release.sh` 已含 `hdiutil` 打包 + 签名 + 公证 + 装订 DMG（功能版）；带背景图布局留待后续 |
| **自动更新** | ✅ 已集成（待真机联网验证）| Sparkle 2.9.3：`UpdaterController` + 菜单「检查更新…」；`release.sh` 第 9 步生成 EdDSA 签名的 appcast。**SUFeedURL 仍是占位域名，待官网替换** |
| **官网 / 下载页** | ❌ 缺口 | 免费也要有承载下载、隐私政策、更新日志的站点 |
| **隐私清单 PrivacyInfo** | ✅ 已完成 | `macos/App/PrivacyInfo.xcprivacy`：零收集、不追踪，仅声明 UserDefaults(CA92.1)；已验证落入 bundle |
| **应用图标 / 视觉素材** | ⏸ 待定（设计）| 需品牌 1024 图标 + 官网/商店截图；属设计决定，未做 |
| Windows 后端 | ❌ 未开发 | Graphics Capture/WASAPI，路线图 Phase 3/5 |

---

## 3. 分发渠道方案

### 3.1 macOS — Developer ID 直分发（主渠道，立即可推进）

**机制**：官网提供 `.dmg`（内含已签名+已公证的 `WorldCapture.app`），用户拖入 `/Applications`，Gatekeeper 因已公证而直接放行。**保留全部功能**（滚动长图、辅助功能驱动的合成事件不受沙盒限制）。

**要补齐的三件事**：
1. **DMG 打包**：在 `release.sh` 末尾增加 `create-dmg`（或 `hdiutil`）步骤，生成带「拖入 Applications」引导背景的 DMG，并对 DMG 本身做签名 + 公证 + 装订。
2. **自动更新（Sparkle）**：
   - 集成 Sparkle 2.x（SPM）。
   - 生成 EdDSA 密钥对，**私钥离线保管**，公钥写入 `Info.plist`（`SUPublicEDKey`）。
   - 发布时用 `sign_update` 对 DMG/zip 签名，更新 `appcast.xml` 并托管到官网/CDN。
   - `release.sh` 增加「生成 appcast 条目」步骤。
3. **隐私清单**：新增 `PrivacyInfo.xcprivacy`（本地工具，几乎不收集数据 → 声明 None，是卖点）。

**优点**：今天就能做、保留全功能、不抽成、更新自主。
**代价**：自带获客（无商店流量）、自己做更新基建。

### 3.2 macOS — Mac App Store（后续，可选第二渠道）

**硬约束**：MAS 强制 App Sandbox，**滚动长图**依赖合成滚轮事件 + 辅助功能权限，沙盒下无法可靠获取 → **MAS 版必须砍掉滚动截图**（详见 `appstore-sandbox-constraint` 记忆）。沙盒兼容的能力：ScreenCaptureKit 截图/录屏、系统音频、用户选择路径保存、全局热键。

**双轨结论**：以**直分发为完整版**、**MAS 为精简版**（去掉滚动截图 + 改用沙盒 entitlements + 用户授权目录访问）。优先级低于 1.0 直分发首发，待主版本稳定后再投入。

**MAS 额外前置**：App Store Connect 应用记录、沙盒 entitlements、App Store 分发证书 + Provisioning、商店截图（每尺寸）、隐私问卷、年龄分级、出口合规（见 §6）。

### 3.3 Windows — 快速跟进（依赖后端开发）

**前置**：先完成 Windows Graphics Capture（截图/录屏）+ WASAPI（音频）后端（路线图 Phase 5）。功能对齐后再谈分发。

**渠道**：
- **官网直分发**：MSIX 或带签名的安装包（Inno Setup/MSI）。
- **Microsoft Store**：MSIX，审核相对宽松，自带更新与流量。
- **代码签名**：Windows 现强制走 **Azure Trusted Signing**（取代旧 OV/EV 证书的主流方案）以建立 SmartScreen 信誉，避免「未知发布者」拦截。这是一笔新的资质/费用，需提前申请。

**结论**：Windows 作为 Phase 2 里程碑（见 §7），不阻塞 macOS 首发。

---

## 4. 上架前置清单（按渠道）

### A. Developer ID 直分发（1.0 首发 · 必做）
- [ ] ⏸ 应用图标全套（含 1024×1024）、关于页版权信息 — **待品牌设计稿**
- [x] `PrivacyInfo.xcprivacy`（声明本地处理、无数据收集）— 已完成并验证
- [ ] TCC 用途文案审校：屏幕录制、麦克风（已有）、辅助功能（滚动截图）——文案要让用户看懂*为什么*
- [x] `release.sh` 扩展：DMG 打包 + DMG 公证装订 + Sparkle 签名 + appcast 生成（已验证）
- [x] Sparkle 集成 + EdDSA 密钥生成；`Info.plist` 写入 feed URL + 公钥（经 project.yml）
- [ ] **私钥离线备份**（`generate_keys -x`，存安全处不入库）
- [ ] **替换占位 `SUFeedURL`/`DOWNLOAD_URL_PREFIX` 为真实官网域名**
- [x] 许可与隐私文案：`LICENSE`(MIT)、`PRIVACY.md`、`.github/FUNDING.yml`（赞助）
- [ ] 官网：下载页 / 更新日志（链接到仓库的 PRIVACY/LICENSE）/ 系统要求
- [ ] 下载与 appcast 托管（对象存储 + CDN；走 HTTPS）
- [ ] 安装与升级回归测试（全新装、覆盖升级、TCC 权限保持）

### B. Mac App Store（后续 · 精简版）
- [ ] 砍掉滚动截图的 MAS 构建分支（build flag / target）
- [ ] App Sandbox entitlements + 用户选择目录的安全书签
- [ ] App Store 分发证书 + Provisioning Profile
- [ ] App Store Connect 记录、分级、隐私问卷、出口合规自述（仅用 HTTPS → 可豁免）
- [ ] 各尺寸商店截图 + 预览、关键词、本地化文案（zh/en/ja）

### C. Windows（Phase 2）
- [ ] Graphics Capture / WASAPI 后端达到与 macOS 对等的核心能力
- [ ] Azure Trusted Signing 资质与签名集成
- [ ] MSIX 打包；Microsoft Store 记录 + 官网安装包
- [ ] 自动更新（Store 自带 / 直分发用 MSIX 更新或自建）

---

## 5. 官网与分发基础设施（免费也必须有）

免费产品没有商店做托底时，官网就是「商店」：
- **下载页**：一键下 DMG，显示版本号、系统要求、SHA256、更新日志。
- **隐私政策**：本地优先、不上传、无追踪——这是免费工具的核心信任卖点，要写明白。
- **许可**：[MIT](../LICENSE) 开源（无需专有 EULA）；免责条款已含在 MIT 文本中。
- **appcast.xml 托管**：Sparkle 更新源，HTTPS + CDN。
- **支持入口**：邮箱 / GitHub Issues / 反馈表。
- **可选无埋点统计**：尊重隐私的下载量统计（服务端日志即可，不在 App 内埋点）。

---

## 6. 法务与合规

- **出口合规**：仅使用 HTTPS / 系统标准加密 → 通常可声明豁免（MAS 提交时勾选）。
- **隐私**：本地处理、不收集 PII → `PrivacyInfo` 与隐私政策保持一致。
- **TCC 用途字符串**：屏幕录制、麦克风、辅助功能的说明文案需准确、可信。
- **商标 / 名称**：上架前确认 "WorldCapture" 在目标地区无冲突（App Store 名称唯一性 + 商标检索）。
- **开源依赖许可**：Sparkle（MIT）等三方库的 License 在「关于」或官网致谢。

---

## 7. 里程碑与时间线（相对排期，按依赖排序）

**Phase 0 — 1.0 首发准备（macOS 直分发）**
1. 收尾产品（OCR / GIF / 录制增强等当前优先级，见 product-backlog）至 1.0 标准。
2. 补齐分发基建：DMG 打包、Sparkle 自动更新、PrivacyInfo、图标素材。
3. 搭官网 + 下载/更新/隐私/许可页 + appcast 托管。
4. 全流程发布演练（`release.sh` → 公证 → DMG → appcast → 官网下载 → 自动更新升级测试）。
5. **发布 1.0（Developer ID 直分发）。**

**Phase 1 — MAS 精简版（可选，1.0 稳定后）**
6. 拆 MAS 构建分支（去滚动截图 + 沙盒化）→ 提交审核 → 上架。

**Phase 2 — Windows 跟进**
7. Graphics Capture / WASAPI 后端 → 功能对齐。
8. Azure Trusted Signing + MSIX → 官网 + Microsoft Store。

> 不写绝对日期：Phase 0 步骤 1（产品收尾）是关键路径，取决于功能开发进度；基建（2–4）可与之并行。

---

## 8. 版本与 1.0 发布门槛

- 版本号：当前 `MARKETING_VERSION 0.1.0`。建议在功能达标 + 基建齐全后切 `1.0.0`。
- **1.0 门槛建议**：核心截图/标注/录屏/滚动长图/历史库稳定无回归；自动更新可用；官网与隐私/许可就绪；公证 + DMG 流程一键化；三语界面无截断（含日文 header）。
- 之后遵循语义化版本，重大功能走 minor，bug 修复走 patch；appcast 始终指向最新公证产物。

---

## 9. 风险与待决项

1. **最低系统 macOS 15.0 偏高**：会显著缩小可触达用户。待决：是否下探到 macOS 13/14（需评估 ScreenCaptureKit / 录制 API 的可用性与改造成本）。
2. **自动更新私钥管理**：Sparkle EdDSA 私钥一旦丢失/泄露，更新链断裂。须离线备份 + 访问控制。
3. **MAS 功能阉割的用户认知**：若上 MAS，需在商店描述明确「滚动长图请用官网版」，避免差评。
4. **Windows 签名成本/资质**：Azure Trusted Signing 的申请周期与费用要提前确认，别卡在临门一脚。
5. **公证偶发超时**：已知 `timestamp.apple.com` 偶发不可达导致 `A timestamp was expected but was not found`；重试 `xcodebuild -exportArchive` 即可，非配置问题（记忆已记录）。
6. **`release.sh | tee` 掩盖退出码**：`tee` 返回 0 会掩盖脚本失败，CI 化时要检查日志中的 `EXPORT FAILED`，不要只信 exit code。

---

## 附录 A：未来商业化 / 订价路径（已放弃，保留备查）

> **2026-06-30 决定：放弃商业化，走 MIT 开源 + 赞助。** 本附录的订价预研不再适用，仅作历史备查。MIT 一经发布即不可收回，重新商业化的代价远高于当初；若极端情况下需要，也只能靠新增闭源增值功能/服务，而非给现有 MIT 代码加付费墙。

### A.1 竞品定价基准（市场参考）
| 产品 | 模式 | 量级 |
|---|---|---|
| CleanShot X | 一次性买断（云存储另订阅）| 约 $29 一次性 |
| Snagit | 永久授权 + 维护 | 约 $39–62 |
| Shottr / Xnapper 类 | 免费或低价买断 | 免费 ~ $30 一次性 |
| ShareX | 完全免费开源 | — |

### A.2 可选模型对比
- **一次性买断 + 付费大版本**：最贴合本地/隐私调性（同 CleanShot X / Snagit）。推荐方向（若变现）。
- **订阅制**：现金流稳，但纯本地工具订阅说服力弱、易流失。
- **Freemium**：基础免费、Pro（OCR/滚动/GIF/历史）解锁；需重建之前砍掉的付费墙基建。

### A.3 若启用需补的基建（务必先评估再做）
- 许可证发放与校验（离线优先，避免与「本地/隐私」原则冲突）。
- 收款（Paddle / Lemon Squeezy 作 MoR 可代收税；或 MAS 内购走 Apple 抽成 15–30%）。
- 试用机制（限时全功能 vs 功能受限）、退款政策、地区定价（购买力平价）。

### A.4 定价决策待回答（启用时）
- 价格点与货币、是否地区差异化定价；
- 试用形态与时长；退款窗口；
- 大版本升级是否再收费、老用户优惠；
- 直分发 vs MAS 的价差与抽成取舍。
```
