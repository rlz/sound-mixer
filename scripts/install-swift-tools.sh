#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tool_dir="$root/.tools/bin"
mkdir -p "$tool_dir"

install_tool() {
    local name="$1" version="$2" archive_name="$3" checksum="$4" repository="$5"
    local target="$tool_dir/$name"
    if [[ -x "$target" ]] && [[ "$($target --version)" == "$version"* ]]; then
        return
    fi

    local temporary_dir
    temporary_dir="$(mktemp -d)"
    curl --fail --location --silent --show-error \
        "https://github.com/$repository/releases/download/$version/$archive_name" \
        --output "$temporary_dir/$archive_name"
    printf '%s  %s\n' "$checksum" "$temporary_dir/$archive_name" | shasum -a 256 --check --status
    unzip -q "$temporary_dir/$archive_name" -d "$temporary_dir/unpacked"
    local binary
    binary="$(find "$temporary_dir/unpacked" -type f -name "$name" -print -quit)"
    if [[ -z "$binary" ]]; then
        echo "Executable $name not found in the archive" >&2
        exit 1
    fi
    cp "$binary" "$target"
    chmod +x "$target"
    rm -rf "$temporary_dir"
    [[ "$($target --version)" == "$version"* ]]
}

install_tool swiftformat 0.62.1 swiftformat.zip \
    7cb1cb1fae04932047c7015441c543848e8e60e1572d808d080e0a1f1661114a \
    nicklockwood/SwiftFormat
install_tool swiftlint 0.65.0 portable_swiftlint.zip \
    d6cb0aa7a2f5f1ef306fc9e37bcb54dc9a26facc8f7784ac0c3dd3eccf5c6ba6 \
    realm/SwiftLint
