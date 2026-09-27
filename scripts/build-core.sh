#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
configuration="${1:-${BUILD_CONFIGURATION:-Debug}}"

if [[ "$(xcode-select -p)" == "/Library/Developer/CommandLineTools" ]] &&
    [[ -d "/Applications/Xcode.app/Contents/Developer" ]]; then
    export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
fi

cd "$root"
build_args=(
    -project SoundMixer.xcodeproj
    -scheme SoundMixer
    -configuration "$configuration"
    -destination 'platform=macOS'
)
if [[ -n "${DERIVED_DATA_PATH:-}" ]]; then
    build_args+=(-derivedDataPath "$DERIVED_DATA_PATH")
fi
xcodebuild "${build_args[@]}" CODE_SIGNING_ALLOWED=NO build
