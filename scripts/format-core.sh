#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tool="$root/.tools/bin/swiftformat"
if [[ ! -x "$tool" ]]; then
    echo "SwiftFormat is missing. Run scripts/install-swift-tools.sh first." >&2
    exit 1
fi
"$tool" "$root/SoundMixer" "$root/Tests" --cache ignore --config "$root/.swiftformat"
