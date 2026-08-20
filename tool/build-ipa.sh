#!/usr/bin/env bash
#
# 在任何一台 macOS 上產出未簽名 IPA —— 租的雲端 Mac、借來的 Mac、虛擬機都適用。
# 不需要 GitHub，也不需要任何 CI 服務。
#
# 用法：
#   1. 把整個專案傳到 Mac（scp -r / rsync / 隨身碟都行）
#   2. chmod +x tool/build-ipa.sh
#   3. ./tool/build-ipa.sh
#   4. 把產出的 GameMale.ipa 傳回自己電腦，用 Sideloadly / AltStore 側載
#
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
echo "專案位置：$ROOT"

# ── 前置檢查 ──────────────────────────────────────────────
if [[ "$(uname)" != "Darwin" ]]; then
  echo "✗ 這支腳本只能在 macOS 上跑（編 iOS 一定要 Xcode 工具鏈）"
  exit 1
fi

if ! xcode-select -p >/dev/null 2>&1; then
  echo "✗ 找不到 Xcode。請先從 App Store 安裝，再執行："
  echo "    sudo xcode-select --switch /Applications/Xcode.app"
  echo "    sudo xcodebuild -license accept"
  exit 1
fi

if ! command -v flutter >/dev/null 2>&1; then
  echo "找不到 flutter，正在裝到 ~/flutter …"
  git clone --depth 1 -b stable https://github.com/flutter/flutter.git "$HOME/flutter"
  export PATH="$HOME/flutter/bin:$PATH"
  echo "提示：之後可把這行加進 ~/.zshrc"
  echo "    export PATH=\"\$HOME/flutter/bin:\$PATH\""
fi

echo "Flutter：$(flutter --version | head -1)"
echo "Xcode  ：$(xcodebuild -version | head -1)"

# ── 建置 ──────────────────────────────────────────────────
echo
echo "▸ 取得相依套件"
flutter pub get

echo
echo "▸ 靜態分析"
flutter analyze

echo
echo "▸ 測試（沒有 test/fixtures 時解析測試會自動略過）"
flutter test || {
  echo "✗ 測試沒過。要跳過的話："
  echo "    SKIP_TESTS=1 ./tool/build-ipa.sh"
  [[ "${SKIP_TESTS:-0}" == "1" ]] || exit 1
}

echo
echo "▸ 編譯未簽名 Release"
flutter build ios --release --no-codesign

# ── 打包 ──────────────────────────────────────────────────
APP="build/ios/iphoneos/Runner.app"
[[ -d "$APP" ]] || { echo "✗ 找不到 $APP"; exit 1; }

rm -rf Payload GameMale.ipa
mkdir -p Payload
cp -R "$APP" Payload/
# 未簽名 App 殘留的簽章資料會讓部分側載工具重簽失敗
rm -rf Payload/Runner.app/_CodeSignature
zip -qry GameMale.ipa Payload
rm -rf Payload

echo
echo "✓ 完成：$ROOT/GameMale.ipa  ($(du -h GameMale.ipa | cut -f1))"
echo
echo "接下來把這個檔案傳回自己的電腦，例如在本機執行："
echo "    scp <使用者>@<這台Mac>:$ROOT/GameMale.ipa ."
echo
echo "然後用 Sideloadly（Windows）或 AltStore / SideStore / ESign 側載。"
echo "免費 Apple ID 憑證 7 天到期，重簽同一個 IPA 即可，不必重編。"
