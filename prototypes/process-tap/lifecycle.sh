#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
temporary_directory="$(mktemp -d "${TMPDIR:-/private/tmp}/sound-mixer-tap.XXXXXX")"
player=0
probe=0

cleanup() {
    if [[ "$probe" -ne 0 ]]; then
        kill "$probe" 2>/dev/null || true
        wait "$probe" 2>/dev/null || true
    fi
    if [[ "$player" -ne 0 ]]; then
        kill "$player" 2>/dev/null || true
        wait "$player" 2>/dev/null || true
    fi
    rm -rf "$temporary_directory"
}
trap cleanup EXIT

python3 - "$temporary_directory/tone.wav" <<'PY'
import math
import struct
import sys
import wave

with wave.open(sys.argv[1], "wb") as output:
    output.setnchannels(1)
    output.setsampwidth(2)
    output.setframerate(48000)
    samples = (struct.pack("<h", round(500 * math.sin(2 * math.pi * 440 * index / 48000))) for index in range(48000 * 45))
    output.writeframes(b"".join(samples))
PY

bash "$root/run.sh" self-check
before="$("$root/.build/process-tap-probe" resources)"
printf '%s\n' "$before"
before_output="$(awk '/^Default output:/ {print $3}' <<< "$before")"
if [[ "$before_output" == 0 ]]; then
    echo "Core Audio is unavailable; run outside a restricted environment" >&2
    exit 1
fi

/usr/bin/afplay -v 0.1 "$temporary_directory/tone.wav" &
player=$!
sleep 2

"$root/.build/process-tap-probe" cycle "$player" --seconds 3
kill -0 "$player"

"$root/.build/process-tap-probe" capture "$player" --seconds 120 > "$temporary_directory/crash.log" 2>&1 &
probe=$!
for attempt in {1..100}; do
    if rg -q '^Tap UID:' "$temporary_directory/crash.log"; then
        break
    fi
    sleep 0.1
done
rg '^Capturing|^Tap UID:' "$temporary_directory/crash.log"
kill -9 "$probe"
wait "$probe" 2>/dev/null || true
probe=0
sleep 1
kill -0 "$player"

fresh_capture=""
fresh_capture_succeeded=0
for attempt in {1..10}; do
    if fresh_capture="$("$root/.build/process-tap-probe" capture "$player" --seconds 2 2> "$temporary_directory/retry.log")"; then
        echo "Fresh capture succeeded on attempt $attempt"
        fresh_capture_succeeded=1
        break
    fi
    echo "Fresh capture attempt $attempt: $(cat "$temporary_directory/retry.log")" >&2
    sleep 1
done
test "$fresh_capture_succeeded" -eq 1
printf '%s\n' "$fresh_capture"
awk '/^Captured frames:/ {if ($3 > 0 && $5 > 0) found = 1} END {exit !found}' <<< "$fresh_capture"

after="$("$root/.build/process-tap-probe" resources)"
printf '%s\n' "$after"
after_output="$(awk '/^Default output:/ {print $3}' <<< "$after")"
test "$before_output" = "$after_output"
echo "Lifecycle checks passed; player remained active and a fresh tap received audio after SIGKILL"
