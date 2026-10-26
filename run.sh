#!/usr/bin/env bash
# 编译并启动 ServDock
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
bash "$ROOT/build.sh"

# 关闭旧实例再启动
pkill -f "ServDock.app/Contents/MacOS/ServDock" 2>/dev/null || true
sleep 0.3

open "$ROOT/build/ServDock.app"
echo "==> 已启动 启服"
