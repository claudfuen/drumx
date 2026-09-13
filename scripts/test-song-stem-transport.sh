#!/bin/bash
set -euo pipefail
DRUMX_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [ -d /Applications/Xcode.app/Contents/Developer ]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
DRUMX_TEST_BUILD="$DRUMX_ROOT/.build/song-stem-transport-checks"
mkdir -p "$DRUMX_TEST_BUILD"
xcrun swiftc -target "$(uname -m)-apple-macosx15.0" -swift-version 5 -O -parse-as-library \
  "$DRUMX_ROOT/native/macos/DrumxIO.swift" \
  "$DRUMX_ROOT/native/macos/DrumxSampler.swift" \
  "$DRUMX_ROOT/native/macos/DrumxSongLibrary.swift" \
  "$DRUMX_ROOT/native/macos/DrumxSongStemMix.swift" \
  "$DRUMX_ROOT/native/macos/tests/DrumxSongStemTransportChecks.swift" \
  -framework AVFoundation -framework AVFAudio -framework CoreMIDI \
  -framework CoreAudio -framework AudioToolbox -o "$DRUMX_TEST_BUILD/DrumxSongStemTransportChecks"
"$DRUMX_TEST_BUILD/DrumxSongStemTransportChecks"
