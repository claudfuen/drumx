#!/bin/bash
set -euo pipefail
DRUMX_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [ -d /Applications/Xcode.app/Contents/Developer ]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
DRUMX_TEST_BUILD="$DRUMX_ROOT/.build/song-stem-mix-checks"
mkdir -p "$DRUMX_TEST_BUILD"
xcrun swiftc -target "$(uname -m)-apple-macosx15.0" -swift-version 5 -O -parse-as-library \
  "$DRUMX_ROOT/native/macos/DrumxSongStemMix.swift" \
  "$DRUMX_ROOT/native/macos/tests/DrumxSongStemMixChecks.swift" \
  -o "$DRUMX_TEST_BUILD/DrumxSongStemMixChecks"
"$DRUMX_TEST_BUILD/DrumxSongStemMixChecks"
