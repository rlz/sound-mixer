#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
format_tool="$root/.tools/bin/swiftformat"
lint_tool="$root/.tools/bin/swiftlint"
if [[ ! -x "$format_tool" || ! -x "$lint_tool" ]]; then
    echo "SwiftFormat or SwiftLint is missing. Run scripts/install-swift-tools.sh first." >&2
    exit 1
fi
"$format_tool" "$root/SoundMixer" "$root/Tests" --lint --cache ignore --config "$root/.swiftformat"
"$lint_tool" lint --strict --no-cache --config "$root/.swiftlint.yml" "$root/SoundMixer" "$root/Tests"
