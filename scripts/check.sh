#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

if [[ "$(xcode-select -p)" == "/Library/Developer/CommandLineTools" ]] &&
    [[ -d "/Applications/Xcode.app/Contents/Developer" ]]; then
    export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
fi

"$root/scripts/install-swift-tools.sh"
"$root/.tools/bin/swiftformat" SoundMixer --lint --cache ignore --config .swiftformat
"$root/.tools/bin/swiftlint" lint --strict --no-cache --config .swiftlint.yml

cd Web
npm ci
npm run check
cd "$root"

xcodebuild -project SoundMixer.xcodeproj -scheme SoundMixer -configuration Debug \
    -destination 'platform=macOS' -derivedDataPath "$root/DerivedData" \
    CODE_SIGNING_ALLOWED=NO build
