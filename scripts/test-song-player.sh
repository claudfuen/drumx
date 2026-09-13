#!/bin/bash
set -euo pipefail
DRUMX_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [ -d /Applications/Xcode.app/Contents/Developer ]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
DRUMX_TEST_BUILD="$DRUMX_ROOT/.build/song-checks"
mkdir -p "$DRUMX_TEST_BUILD"
xcrun clang++ -target "$(uname -m)-apple-macosx15.0" -std=c++17 -O2 -Wall -Wextra -pedantic -c \
  "$DRUMX_ROOT/native/core/drumx_core.cpp" -o "$DRUMX_TEST_BUILD/drumx_core.o"
xcrun swiftc -target "$(uname -m)-apple-macosx15.0" -swift-version 5 -O -parse-as-library \
  -import-objc-header "$DRUMX_ROOT/native/macos/DrumxBridging.h" \
  "$DRUMX_ROOT/native/macos/DrumxIO.swift" \
  "$DRUMX_ROOT/native/macos/DrumxSampler.swift" \
  "$DRUMX_ROOT/native/macos/DrumxSongLibrary.swift" \
  "$DRUMX_ROOT/native/macos/DrumxSongGrid.swift" \
  "$DRUMX_ROOT/native/macos/DrumxSongStemMix.swift" \
  "$DRUMX_ROOT/native/macos/tests/DrumxSongChecks.swift" \
  "$DRUMX_TEST_BUILD/drumx_core.o" -Xlinker -lc++ \
  -framework AVFoundation -framework AVFAudio -framework CoreMIDI \
  -framework CoreAudio -framework AudioToolbox -o "$DRUMX_TEST_BUILD/DrumxSongChecks"
"$DRUMX_TEST_BUILD/DrumxSongChecks" "$@"
bash "$DRUMX_ROOT/scripts/test-song-geometry.sh"
bash "$DRUMX_ROOT/scripts/test-song-grid.sh"
bash "$DRUMX_ROOT/scripts/test-song-timing-feedback.sh"
bash "$DRUMX_ROOT/scripts/test-song-scores.sh"
bash "$DRUMX_ROOT/scripts/test-song-stem-mix.sh"
bash "$DRUMX_ROOT/scripts/test-song-stem-transport.sh"
