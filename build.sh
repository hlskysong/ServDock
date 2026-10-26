#!/usr/bin/env bash
# 编译并打包 ServDock.app（SwiftUI + swiftc，无需 Xcode 工程）
#
# 环境变量（都可省略，省略时走本地默认）：
#   SERVDOCK_ARCHS      编译架构，空格分隔，如 "arm64 x86_64"；多个架构用 lipo 合成通用二进制
#   SERVDOCK_MIN_MACOS  最低系统版本，默认 14.0
#   SERVDOCK_VERSION    覆盖 Info.plist 的 CFBundleShortVersionString（CI 用 tag 注入）
#   SERVDOCK_BUILD      覆盖 CFBundleVersion
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="ServDock"
BUILD_DIR="$ROOT/build"
APP="$BUILD_DIR/$APP_NAME.app"
SDK="$(xcrun --show-sdk-path)"
ARCHS="${SERVDOCK_ARCHS:-$(uname -m)}"
MIN_MACOS="${SERVDOCK_MIN_MACOS:-14.0}"
PLIST="$APP/Contents/Info.plist"

echo "==> 收集源文件"
SOURCES=()
while IFS= read -r file; do
    SOURCES+=("$file")
done < <(find "$ROOT/Sources" -name '*.swift' | sort)
echo "    ${#SOURCES[@]} 个 Swift 文件"

echo "==> 准备 app 包"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

BINARIES=()
for ARCH in $ARCHS; do
    OUT="$BUILD_DIR/$APP_NAME-$ARCH"
    echo "==> 编译 target: ${ARCH}-apple-macos${MIN_MACOS}"
    swiftc \
        -O \
        -parse-as-library \
        -swift-version 5 \
        -target "${ARCH}-apple-macos${MIN_MACOS}" \
        -sdk "$SDK" \
        "${SOURCES[@]}" \
        -o "$OUT"
    BINARIES+=("$OUT")
done

if [ "${#BINARIES[@]}" -eq 1 ]; then
    mv "${BINARIES[0]}" "$APP/Contents/MacOS/$APP_NAME"
else
    echo "==> lipo 合并 ${#BINARIES[@]} 个架构：$ARCHS"
    lipo -create "${BINARIES[@]}" -output "$APP/Contents/MacOS/$APP_NAME"
    rm -f "${BINARIES[@]}"
fi

echo "==> 拷贝资源"
cp "$ROOT/Resources/Info.plist" "$PLIST"
if [ -f "$ROOT/Resources/AppIcon.icns" ]; then
    cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi
printf 'APPL????' > "$APP/Contents/PkgInfo"

# 版本号以 tag 为准，避免 tag 与 Info.plist 不一致导致更新检测误判
if [ -n "${SERVDOCK_VERSION:-}" ]; then
    echo "==> 注入版本号 ${SERVDOCK_VERSION}（build ${SERVDOCK_BUILD:-1}）"
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $SERVDOCK_VERSION" "$PLIST"
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${SERVDOCK_BUILD:-1}" "$PLIST"
fi

echo "==> 签名（ad-hoc）"
codesign --force --sign - --timestamp=none "$APP" >/dev/null 2>&1 || true

echo "==> 完成：$APP"
