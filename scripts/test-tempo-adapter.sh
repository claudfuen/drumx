#!/bin/bash
set -euo pipefail

# Pure Foundation/C-ABI history and tempo adapter contracts. This does not open the app, connect
# MIDI, initialize audio, fetch samples, or touch the player's saved progress.
DRUMX_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [ "$(uname -s)" != "Darwin" ]; then
  echo "The Swift tempo adapter checks require macOS." >&2
  exit 1
fi
if [ -z "${DEVELOPER_DIR:-}" ] && [ -d /Applications/Xcode.app/Contents/Developer ]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
DRUMX_TEMPO_BUILD="$DRUMX_ROOT/.build/tempo-adapter"
DRUMX_TEMPO_TARGET="$(uname -m)-apple-macosx15.0"
mkdir -p "$DRUMX_TEMPO_BUILD"

for DRUMX_CORE_NAME in drumx_core drumx_tempo; do
  xcrun clang++ -target "$DRUMX_TEMPO_TARGET" -std=c++17 -O1 \
    -Wall -Wextra -Werror -pedantic \
    -c "$DRUMX_ROOT/native/core/$DRUMX_CORE_NAME.cpp" \
    -o "$DRUMX_TEMPO_BUILD/$DRUMX_CORE_NAME.o"
done
for DRUMX_ADAPTER_CHECK in DrumxLessonChecks DrumxTempoCoachChecks DrumxUnlockChecks; do
  xcrun swiftc -target "$DRUMX_TEMPO_TARGET" -swift-version 5 \
    -warnings-as-errors -parse-as-library \
    -import-objc-header "$DRUMX_ROOT/native/macos/DrumxBridging.h" \
    "$DRUMX_ROOT/native/macos/DrumxLesson.swift" \
    "$DRUMX_ROOT/native/macos/DrumxCourse.swift" \
    "$DRUMX_ROOT/native/macos/DrumxProgress.swift" \
    "$DRUMX_ROOT/native/macos/DrumxPracticePlan.swift" \
    "$DRUMX_ROOT/native/macos/DrumxTempoCoach.swift" \
    "$DRUMX_ROOT/native/macos/DrumxUnlocks.swift" \
    "$DRUMX_ROOT/native/macos/tests/${DRUMX_ADAPTER_CHECK}.swift" \
    "$DRUMX_TEMPO_BUILD/drumx_core.o" "$DRUMX_TEMPO_BUILD/drumx_tempo.o" \
    -Xlinker -lc++ -o "$DRUMX_TEMPO_BUILD/${DRUMX_ADAPTER_CHECK}"
  "$DRUMX_TEMPO_BUILD/${DRUMX_ADAPTER_CHECK}"
done
