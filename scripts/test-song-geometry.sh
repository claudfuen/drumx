#!/bin/bash
set -euo pipefail
DRUMX_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [ -d /Applications/Xcode.app/Contents/Developer ]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
DRUMX_TEST_BUILD="$DRUMX_ROOT/.build/song-geometry-checks"
mkdir -p "$DRUMX_TEST_BUILD"
xcrun swiftc -swift-version 5 -O -parse-as-library \
  "$DRUMX_ROOT/native/macos/DrumxProjection.swift" \
  "$DRUMX_ROOT/native/macos/DrumxSongGeometry.swift" \
  "$DRUMX_ROOT/native/macos/tests/DrumxSongGeometryChecks.swift" \
  -o "$DRUMX_TEST_BUILD/DrumxSongGeometryChecks"
"$DRUMX_TEST_BUILD/DrumxSongGeometryChecks"
