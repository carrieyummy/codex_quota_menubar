#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="${CONFIG:-release}"
APP_DIR="$ROOT/.build/Codex Quota.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"

cd "$ROOT"
export CLANG_MODULE_CACHE_PATH="$ROOT/.build/clang-module-cache"
export SWIFTPM_HOME="$ROOT/.build/swiftpm-home"
mkdir -p "$CLANG_MODULE_CACHE_PATH" "$SWIFTPM_HOME"
swift build -c "$CONFIG"

rm -rf "$APP_DIR"
mkdir -p "$MACOS" "$CONTENTS/Resources"
cp ".build/$CONFIG/CodexQuota" "$MACOS/CodexQuota"
cp "$ROOT/Resources/Info.plist" "$CONTENTS/Info.plist"
cp "$ROOT/Resources/CodexQuotaIcon.icns" "$CONTENTS/Resources/CodexQuotaIcon.icns"

echo "$APP_DIR"
