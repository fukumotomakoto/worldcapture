#!/usr/bin/env bash
#
# WorldCapture 发布脚本：
#   归档 → 导出（Developer ID）→ 打包 DMG → 签名 → 公证 → 装订 → 验证。
#
# 交付物：build/WorldCapture-<version>.dmg（已签名 + 已公证 + 已装订，可直接分发）。
#
# 前置条件（一次性准备，均由发布负责人提供，不入库）：
#   1) 钥匙串已安装 "Developer ID Application" 证书
#      （Xcode → Settings → Accounts → Manage Certificates → + Developer ID Application；
#        需要 Apple Developer Program 付费会员）。
#   2) 已用 notarytool 存储公证凭据为一个 keychain profile：
#        xcrun notarytool store-credentials <profile> \
#          --apple-id <你的 Apple ID> \
#          --team-id 43M5KN7MPD \
#          --password <App 专用密码>
#      （App 专用密码在 appleid.apple.com → 登录与安全 → App 专用密码 生成；
#        也可改用 App Store Connect API 密钥 --key/--key-id/--issuer。）
#
# 用法：
#   scripts/release.sh <notary-profile-name> [signing-identity]
#     <notary-profile-name>  notarytool 的 keychain profile 名（如 BlissMeta-Notary）
#     [signing-identity]     给 DMG 签名用的证书名，默认 "Developer ID Application"
#
set -euo pipefail

PROFILE="${1:-}"
SIGN_ID="${2:-Developer ID Application}"
if [ -z "$PROFILE" ]; then
  echo "用法: $0 <notary-profile-name> [signing-identity]"
  echo "（先执行 xcrun notarytool store-credentials <profile> ... 见脚本顶部说明）"
  exit 1
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

BUILD="$ROOT/build"
ARCHIVE="$BUILD/WorldCapture.xcarchive"
EXPORT="$BUILD/export"
APP="$EXPORT/WorldCapture.app"
STAGING="$BUILD/dmg-staging"

# 从 project.yml 读取 MARKETING_VERSION 给 DMG 命名（取不到则回退 dev）。
VERSION="$(grep -m1 'MARKETING_VERSION:' "$ROOT/project.yml" | sed -E 's/.*MARKETING_VERSION:[[:space:]]*"?([^"[:space:]]+)"?.*/\1/' || true)"
VERSION="${VERSION:-dev}"
DMG="$BUILD/WorldCapture-$VERSION.dmg"

# Sparkle 自动更新：appcast 输出目录（持久，跨版本累积发布记录）、
# Sparkle 命令行工具目录（随 SPM artifact 落在 derivedDataPath 内）、
# 下载托管前缀（appcast 里 enclosure URL 的基址，占位域名，按官网替换；可用环境变量覆盖）。
APPCAST_DIR="$BUILD/appcast"
SPARKLE_BIN="$BUILD/dd/SourcePackages/artifacts/sparkle/Sparkle/bin"
DOWNLOAD_URL_PREFIX="${DOWNLOAD_URL_PREFIX:-https://worldcapture.io/}"

mkdir -p "$BUILD"

echo "▸ 1/9 生成 Xcode 工程"
xcodegen generate

echo "▸ 2/9 归档（Release / Developer ID 签名）"
rm -rf "$ARCHIVE"
xcodebuild archive \
  -project WorldCapture.xcodeproj \
  -scheme WorldCapture \
  -configuration Release \
  -archivePath "$ARCHIVE" \
  -derivedDataPath "$BUILD/dd"

echo "▸ 3/9 导出 .app"
rm -rf "$EXPORT"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportPath "$EXPORT" \
  -exportOptionsPlist "$ROOT/scripts/ExportOptions.plist"

echo "▸ 4/9 打包 DMG（含拖入 Applications 的符号链接）"
# 用临时挂载目录组织 DMG 内容：App + /Applications 快捷方式，方便用户拖拽安装。
# 零依赖（hdiutil）。如需带背景图/窗口布局的精美 DMG，可改用 create-dmg。
rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING"
/usr/bin/ditto "$APP" "$STAGING/WorldCapture.app"
ln -s /Applications "$STAGING/Applications"
hdiutil create \
  -volname "WorldCapture" \
  -srcfolder "$STAGING" \
  -fs HFS+ \
  -format UDZO \
  -ov \
  "$DMG"
rm -rf "$STAGING"

echo "▸ 5/9 给 DMG 签名（$SIGN_ID）"
codesign --force --sign "$SIGN_ID" --timestamp "$DMG"

echo "▸ 6/9 提交公证并等待（首次可能数分钟）"
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait

echo "▸ 7/9 装订（staple）到 DMG"
xcrun stapler staple "$DMG"

echo "▸ 8/9 验证签名与 Gatekeeper"
# 校验内部 App 的签名与硬化运行时
codesign --verify --deep --strict --verbose=2 "$APP"
spctl -a -vvv --type execute "$APP"
# 校验 DMG 的装订与安装放行
xcrun stapler validate "$DMG"
spctl -a -vvv --type open --context context:primary-signature "$DMG" || true

echo "▸ 9/9 生成 Sparkle appcast（EdDSA 签名）"
# generate_appcast 会扫描目录内所有归档、用钥匙串里的 EdDSA 私钥签名，
# 生成/更新 appcast.xml（enclosure URL = 前缀 + 文件名）。
# 私钥须先 generate_keys 生成（一次性）；缺工具或缺私钥时给出提示而非静默跳过。
if [ -x "$SPARKLE_BIN/generate_appcast" ]; then
  mkdir -p "$APPCAST_DIR"
  /usr/bin/ditto "$DMG" "$APPCAST_DIR/$(basename "$DMG")"
  "$SPARKLE_BIN/generate_appcast" \
    --download-url-prefix "$DOWNLOAD_URL_PREFIX" \
    "$APPCAST_DIR"
  echo "   appcast: $APPCAST_DIR/appcast.xml（enclosure 前缀 $DOWNLOAD_URL_PREFIX）"
else
  echo "   ⚠️ 未找到 $SPARKLE_BIN/generate_appcast，跳过 appcast 生成。"
  echo "      （需先 archive 解析 Sparkle SPM artifact；私钥须用 generate_keys 生成。）"
fi

echo ""
echo "✅ 完成"
echo "   已签名+已公证+已装订 DMG: $DMG"
echo "   （内部 App: $APP）"
echo "   Sparkle appcast:          $APPCAST_DIR/appcast.xml"
echo ""
echo "   分发清单：把 DMG 与 appcast.xml 上传到托管，确保 appcast 里的 enclosure URL"
echo "   与 Info.plist 的 SUFeedURL（$DOWNLOAD_URL_PREFIX...）一致。"
