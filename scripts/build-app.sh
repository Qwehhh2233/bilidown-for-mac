#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/build"
APP="$BUILD/Bilidown.app"

command -v swift >/dev/null || { echo "缺少 Swift 工具链" >&2; exit 1; }
command -v go >/dev/null || { echo "缺少 Go 工具链" >&2; exit 1; }
command -v ffmpeg >/dev/null || { echo "缺少 FFmpeg，请先执行 brew install ffmpeg" >&2; exit 1; }

rm -rf "$APP" "$BUILD/Bilidown.app.zip"
mkdir -p \
  "$APP/Contents/MacOS" \
  "$APP/Contents/Resources/backend/static" \
  "$APP/Contents/Resources/bridge-bin" \
  "$APP/Contents/Resources/zh-Hans.lproj"

echo "构建 Go 后端…"
(
  cd "$ROOT/backend"
  CGO_ENABLED=1 go build -o "$BUILD/bilidown-backend" .
)

echo "构建 SwiftUI 前端…"
(
  cd "$ROOT/native"
  swift build -c release
)
SWIFT_BIN_DIR="$(cd "$ROOT/native" && swift build -c release --show-bin-path)"

cp "$SWIFT_BIN_DIR/BilidownNative" "$APP/Contents/MacOS/Bilidown"
cp "$BUILD/bilidown-backend" "$APP/Contents/Resources/backend/bilidown"
cp -R "$ROOT/backend/static/." "$APP/Contents/Resources/backend/static/"
cp "$ROOT/assets/BilidownPink.icns" "$APP/Contents/Resources/BilidownPink.icns"
cp "$ROOT/packaging/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/packaging/open" "$APP/Contents/Resources/bridge-bin/open"
cp "$ROOT/packaging/zh-Hans.lproj/InfoPlist.strings" \
  "$APP/Contents/Resources/zh-Hans.lproj/InfoPlist.strings"

chmod 755 \
  "$APP/Contents/MacOS/Bilidown" \
  "$APP/Contents/Resources/backend/bilidown" \
  "$APP/Contents/Resources/bridge-bin/open"

codesign --force --deep --sign - "$APP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$BUILD/Bilidown.app.zip"

echo "构建完成："
echo "  $APP"
echo "  $BUILD/Bilidown.app.zip"
