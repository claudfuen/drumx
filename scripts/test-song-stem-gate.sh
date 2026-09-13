#!/bin/bash
set -euo pipefail
DRUMX_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [ -d /Applications/Xcode.app/Contents/Developer ]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
DRUMX_GATE_BUILD="$DRUMX_ROOT/.build/song-stem-gate-checks"
mkdir -p "$DRUMX_GATE_BUILD"
xcrun clang++ -target "$(uname -m)-apple-macosx15.0" -std=c++17 -O2 -Wall -Wextra -pedantic -c \
  "$DRUMX_ROOT/native/core/drumx_core.cpp" -o "$DRUMX_GATE_BUILD/drumx_core.o"
xcrun swiftc -target "$(uname -m)-apple-macosx15.0" -swift-version 5 -O -parse-as-library \
  -import-objc-header "$DRUMX_ROOT/native/core/drumx_core.h" \
  "$DRUMX_ROOT/native/macos/DrumxSongScores.swift" \
  "$DRUMX_ROOT/native/macos/DrumxSongStemGate.swift" \
  "$DRUMX_ROOT/native/macos/tests/DrumxSongStemGateChecks.swift" \
  "$DRUMX_GATE_BUILD/drumx_core.o" -Xlinker -lc++ \
  -o "$DRUMX_GATE_BUILD/DrumxSongStemGateChecks"
"$DRUMX_GATE_BUILD/DrumxSongStemGateChecks"
