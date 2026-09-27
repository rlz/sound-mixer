#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

"$root/scripts/build-web.sh" --debug
"$root/scripts/build-core.sh"

if [[ "$(xcode-select -p)" == "/Library/Developer/CommandLineTools" ]] &&
    [[ -d "/Applications/Xcode.app/Contents/Developer" ]]; then
    export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
fi

built_products_dir="$(xcodebuild -project "$root/SoundMixer.xcodeproj" -scheme SoundMixer \
    -configuration Debug -destination 'platform=macOS' -showBuildSettings |
    awk -F ' = ' '/^[[:space:]]*BUILT_PRODUCTS_DIR = / { print $2; exit }')"
if [[ -z "$built_products_dir" ]]; then
    echo "Could not locate the Xcode Debug app." >&2
    exit 1
fi
open "$built_products_dir/Rlz Sound Mixer.app"
