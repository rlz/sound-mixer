#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
mkdir -p "$root/.build/module-cache"
CLANG_MODULE_CACHE_PATH="$root/.build/module-cache" swiftc -module-cache-path "$root/.build/module-cache" \
    "$root/main.swift" -o "$root/.build/process-tap-probe" -framework AudioToolbox -framework CoreAudio
exec "$root/.build/process-tap-probe" "$@"
