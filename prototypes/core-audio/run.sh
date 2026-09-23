#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -d /Applications/Xcode.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
mkdir -p "$root/.build/module-cache"
CLANG_MODULE_CACHE_PATH="$root/.build/module-cache" swiftc -module-cache-path "$root/.build/module-cache" \
    "$root/main.swift" -o "$root/.build/core-audio-probe" -framework AudioToolbox -framework CoreAudio
exec "$root/.build/core-audio-probe" "$@"
