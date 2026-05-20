#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

cd "$ROOT_DIR"
mkdir -p "$ROOT_DIR/.build/clang-module-cache" "$ROOT_DIR/.build/swiftpm-cache"
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$ROOT_DIR/.build/clang-module-cache}"
export SWIFTPM_CACHE_PATH="${SWIFTPM_CACHE_PATH:-$ROOT_DIR/.build/swiftpm-cache}"

swift run \
  --disable-sandbox \
  --scratch-path "$ROOT_DIR/.build" \
  CodexQuotaCoreSmokeTests
