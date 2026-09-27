#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
configuration="${1:-${BUILD_CONFIGURATION:-Debug}}"

"$root/scripts/build-web.sh"
"$root/scripts/build-core.sh" "$configuration"
