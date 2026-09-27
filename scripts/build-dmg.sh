#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tag_prefix="v"
temporary_dir=""
mount_dir=""
mounted_device=""
mounted=0

cleanup() {
    if [[ "$mounted" -eq 1 ]]; then
        if [[ -n "$mount_dir" ]]; then
            hdiutil detach -quiet "$mount_dir" >/dev/null 2>&1 || true
        elif [[ -n "$mounted_device" ]]; then
            hdiutil detach -quiet "$mounted_device" >/dev/null 2>&1 || true
        fi
    fi
    if [[ -n "$temporary_dir" && -d "$temporary_dir" ]]; then
        rm -rf "$temporary_dir"
    fi
}
trap cleanup EXIT

check_prerequisites() {
    local missing=0
    for command_name in git xcodebuild xcode-select hdiutil diskutil npm node osascript ditto; do
        if ! command -v "$command_name" >/dev/null 2>&1; then
            echo "Required command '$command_name' is missing." >&2
            missing=1
        fi
    done
    if [[ "$missing" -ne 0 ]]; then
        echo "Install Xcode and Node.js/npm before building the DMG." >&2
        exit 1
    fi
    if [[ "$(uname -s)" != "Darwin" ]]; then
        echo "DMG creation requires macOS and hdiutil." >&2
        exit 1
    fi
    if [[ "$(node --version)" != "v26.8.1" ]]; then
        echo "Node.js 26.8.1 is required; found $(node --version)." >&2
        exit 1
    fi
    if [[ "$(npm --version)" != "12.0.2" ]]; then
        echo "npm 12.0.2 is required; found $(npm --version)." >&2
        exit 1
    fi
    local xcode_version xcode_major
    xcode_version="$(xcodebuild -version | sed -n '1p')"
    if [[ ! "$xcode_version" =~ ^Xcode\ ([0-9]+)\. ]]; then
        echo "Could not determine Xcode version: $xcode_version" >&2
        exit 1
    fi
    xcode_major="${BASH_REMATCH[1]}"
    if (( xcode_major < 27 )); then
        echo "Xcode 27 or later is required; found $xcode_version." >&2
        exit 1
    fi
}

select_developer_directory() {
    if [[ "$(xcode-select -p)" == "/Library/Developer/CommandLineTools" ]] &&
        [[ -d "/Applications/Xcode.app/Contents/Developer" ]]; then
        export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
    fi
}

marketing_version() {
    local version
    version="$(xcodebuild -project "$root/SoundMixer.xcodeproj" -scheme SoundMixer \
        -configuration Release -showBuildSettings 2>/dev/null |
        awk -F ' = ' '/^[[:space:]]*MARKETING_VERSION = / { print $2; exit }')"
    if [[ -z "$version" ]]; then
        echo "Could not read MARKETING_VERSION from the Xcode project." >&2
        exit 1
    fi
    printf '%s' "$version"
}

check_version() {
    if [[ ! "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]]; then
        echo "Version must look like 0.9.1; received '$1'." >&2
        exit 1
    fi
}

build_tagged_dmg() {
    local version="$1"
    local tag="${tag_prefix}${version}"
    local dmg_name="RlzSoundMixer-${version}.dmg"
    local output="$root/dist/$dmg_name"
    local source_dir staged_image app_path temporary_output attach_output volume_name

    check_version "$version"
    if ! git -C "$root" rev-parse -q --verify "refs/tags/$tag" >/dev/null; then
        echo "Git tag '$tag' does not exist." >&2
        exit 1
    fi
    if [[ -e "$output" ]]; then
        echo "Refusing to overwrite existing DMG: $output" >&2
        exit 1
    fi

    temporary_dir="$(mktemp -d "${TMPDIR:-/tmp}/rlz-sound-mixer-dmg.XXXXXX")"
    source_dir="$temporary_dir/source"
    mkdir -p "$source_dir"
    git -C "$root" archive "$tag" | tar -x -C "$source_dir"

    DERIVED_DATA_PATH="$temporary_dir/DerivedData" \
        "$source_dir/scripts/build-all.sh" Release
    app_path="$temporary_dir/DerivedData/Build/Products/Release/Rlz Sound Mixer.app"
    if [[ ! -d "$app_path" ]]; then
        echo "Release app was not produced at the expected path: $app_path" >&2
        exit 1
    fi

    mkdir -p "$temporary_dir/image-root/.background"
    ditto "$app_path" "$temporary_dir/image-root/Rlz Sound Mixer.app"
    cp "$source_dir/packaging/dmg-background.png" "$temporary_dir/image-root/.background/background.png"
    ln -s /Applications "$temporary_dir/image-root/Applications"

    staged_image="$temporary_dir/RlzSoundMixer-${version}-staging.dmg"
    hdiutil create -quiet -volname "Rlz Sound Mixer ${version}" -srcfolder "$temporary_dir/image-root" \
        -fs HFS+ -format UDRW "$staged_image"
    attach_output="$(diskutil image attach "$staged_image")"
    mounted=1
    mounted_device="$(printf '%s\n' "$attach_output" | awk '/Apple_HFS/ { print $1; exit }')"
    mount_dir="$(printf '%s\n' "$attach_output" | sed -nE 's#^/dev/[^[:space:]]+[[:space:]]+Apple_HFS[[:space:]]+(/Volumes/.*)$#\1#p')"
    if [[ -z "$mount_dir" ]]; then
        echo "Could not determine the DMG mount point from hdiutil output:" >&2
        printf '%s\n' "$attach_output" >&2
        exit 1
    fi
    volume_name="${mount_dir##*/}"

osascript <<APPLESCRIPT
tell application "Finder"
    with timeout of 30 seconds
        tell disk "$volume_name"
            open
            set current view of container window to icon view
            set toolbar visible of container window to false
            set statusbar visible of container window to false
            set bounds of container window to {100, 100, 900, 620}
            set icon size of icon view options of container window to 96
            set background picture of icon view options of container window to file ".background:background.png"
            set position of item "Rlz Sound Mixer.app" of container window to {535, 290}
            set position of item "Applications" of container window to {730, 290}
            update without registering applications
            close
        end tell
    end timeout
end tell
APPLESCRIPT

    hdiutil detach -quiet "$mount_dir"
    mounted=0
    mkdir -p "$root/dist"
    temporary_output="$temporary_dir/$dmg_name"
    hdiutil convert "$staged_image" -quiet -format UDZO -imagekey zlib-level=9 -o "$temporary_output"
    if [[ -e "$output" ]]; then
        echo "Refusing to overwrite existing DMG: $output" >&2
        exit 1
    fi
    mv "$temporary_output" "$output"
    rm -rf "$temporary_dir"
    temporary_dir=""
    echo "Created $output"
}

check_prerequisites
select_developer_directory

if [[ "$#" -gt 1 ]]; then
    echo "Usage: $0 [version]" >&2
    exit 2
fi

if [[ "$#" -eq 1 ]]; then
    build_tagged_dmg "$1"
    exit 0
fi

if [[ -n "$(git -C "$root" status --porcelain --untracked-files=all)" ]]; then
    echo "Working tree is not clean. Commit or remove all changes before release." >&2
    exit 1
fi

version="$(marketing_version)"
check_version "$version"
tag="${tag_prefix}${version}"
output="$root/dist/RlzSoundMixer-${version}.dmg"
if git -C "$root" rev-parse -q --verify "refs/tags/$tag" >/dev/null; then
    echo "Git tag '$tag' already exists; refusing to create or replace it." >&2
    exit 1
fi
if [[ -e "$output" ]]; then
    echo "Refusing to overwrite existing DMG: $output" >&2
    exit 1
fi

"$root/scripts/test-all.sh"
temporary_dir="$(mktemp -d "${TMPDIR:-/tmp}/rlz-sound-mixer-preflight.XXXXXX")"
BUILD_CONFIGURATION=Release DERIVED_DATA_PATH="$temporary_dir/DerivedData" \
    "$root/scripts/build-all.sh" Release
rm -rf "$temporary_dir"
temporary_dir=""

git -C "$root" tag "$tag"
echo "Created git tag $tag after tests and Release build passed."
"$0" "$version"
