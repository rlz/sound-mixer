#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

"$root/scripts/build-web.sh" --debug
"$root/scripts/build-core.sh"
open "$root/DerivedData/Build/Products/Debug/SoundMixer.app"
