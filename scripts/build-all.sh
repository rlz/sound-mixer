#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ "$(xcode-select -p)" == "/Library/Developer/CommandLineTools" ]] &&
    [[ -d "/Applications/Xcode.app/Contents/Developer" ]]; then
    export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
fi

cd "$root/Web"
npm ci
npm run build

cd "$root"
xcodebuild -project SoundMixer.xcodeproj -scheme SoundMixer -configuration Debug \
    -destination 'platform=macOS' -derivedDataPath "$root/DerivedData" \
    CODE_SIGNING_ALLOWED=NO build
