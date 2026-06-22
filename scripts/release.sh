#!/usr/bin/env bash
#
# WorldCapture 发布脚本：归档 → 导出（Developer ID）→ 公证 → 装订 → 验证。
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
#   scripts/release.sh <notary-profile-name>
#
set -euo pipefail

PROFILE="${1:-}"
if [ -z "$PROFILE" ]; then
  echo "用法: $0 <notary-profile-name>"
  echo "（先执行 xcrun notarytool store-credentials <profile> ... 见脚本顶部说明）"
  exit 1
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

BUILD="$ROOT/build"
ARCHIVE="$BUILD/WorldCapture.xcarchive"
EXPORT="$BUILD/export"
APP="$EXPORT/WorldCapture.app"
ZIP="$BUILD/WorldCapture.zip"

mkdir -p "$BUILD"

echo "▸ 1/7 生成 Xcode 工程"
xcodegen generate

echo "▸ 2/7 归档（Release / Developer ID 签名）"
rm -rf "$ARCHIVE"
xcodebuild archive \
  -project WorldCapture.xcodeproj \
  -scheme WorldCapture \
  -configuration Release \
  -archivePath "$ARCHIVE" \
  -derivedDataPath "$BUILD/dd"

echo "▸ 3/7 导出 .app"
rm -rf "$EXPORT"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportPath "$EXPORT" \
  -exportOptionsPlist "$ROOT/scripts/ExportOptions.plist"

echo "▸ 4/7 打包 zip 供公证"
rm -f "$ZIP"
/usr/bin/ditto -c -k --keepParent "$APP" "$ZIP"

echo "▸ 5/7 提交公证并等待（首次可能数分钟）"
xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait

echo "▸ 6/7 装订（staple）"
xcrun stapler staple "$APP"

echo "▸ 7/7 验证签名与 Gatekeeper"
codesign --verify --deep --strict --verbose=2 "$APP"
spctl -a -vvv --type execute "$APP"

# 重新打一个装订后的 zip 作为最终分发物
FINAL="$BUILD/WorldCapture-notarized.zip"
rm -f "$FINAL"
/usr/bin/ditto -c -k --keepParent "$APP" "$FINAL"

echo ""
echo "✅ 完成"
echo "   已签名+已公证 App: $APP"
echo "   可分发压缩包:      $FINAL"
