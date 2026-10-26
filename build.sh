#!/usr/bin/env bash
# 编译并打包 ServDock.app（SwiftUI + swiftc，无需 Xcode 工程）
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="ServDock"
BUILD_DIR="$ROOT/build"
APP="$BUILD_DIR/$APP_NAME.app"
SDK="$(xcrun --show-sdk-path)"
ARCH="$(uname -m)"
TARGET="${ARCH}-apple-macos14.0"

echo "==> 收集源文件"
SOURCES=()
while IFS= read -r file; do
    SOURCES+=("$file")
done < <(find "$ROOT/Sources" -name '*.swift' | sort)
echo "    ${#SOURCES[@]} 个 Swift 文件"

echo "==> 准备 app 包"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "==> 编译 target: ${TARGET}"
swiftc \
    -O \
    -parse-as-library \
    -swift-version 5 \
    -target "$TARGET" \
    -sdk "$SDK" \
    "${SOURCES[@]}" \
    -o "$APP/Contents/MacOS/$APP_NAME"

echo "==> 拷贝资源"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
if [ -f "$ROOT/Resources/AppIcon.icns" ]; then
    cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "==> 签名（ad-hoc）"
codesign --force --sign - --timestamp=none "$APP" >/dev/null 2>&1 || true

echo "==> 完成：$APP"
