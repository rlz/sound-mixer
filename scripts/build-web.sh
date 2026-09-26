#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cd "$root/Web"
npm ci
if [[ "${1:-}" == "--debug" ]]; then
    npm run build:debug
else
    npm run build
fi
