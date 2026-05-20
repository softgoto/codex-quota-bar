#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONFIGURATION="${CONFIGURATION:-release}"
APP_DIR="$ROOT_DIR/.build/CodexQuotaBar.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

cd "$ROOT_DIR"
mkdir -p "$ROOT_DIR/.build/clang-module-cache" "$ROOT_DIR/.build/swiftpm-cache"
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$ROOT_DIR/.build/clang-module-cache}"
export SWIFTPM_CACHE_PATH="${SWIFTPM_CACHE_PATH:-$ROOT_DIR/.build/swiftpm-cache}"

swift build --disable-sandbox --scratch-path "$ROOT_DIR/.build" -c "$CONFIGURATION"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$ROOT_DIR/.build/$CONFIGURATION/CodexQuotaBar" "$MACOS_DIR/CodexQuotaBar"
cp "$ROOT_DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
chmod +x "$MACOS_DIR/CodexQuotaBar"

echo "$APP_DIR"
