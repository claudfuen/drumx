#!/bin/bash
set -euo pipefail
DRUMX_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [ -d /Applications/Xcode.app/Contents/Developer ]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
DRUMX_SCORE_BUILD="$DRUMX_ROOT/.build/song-score-checks"
mkdir -p "$DRUMX_SCORE_BUILD"
xcrun swiftc -target "$(uname -m)-apple-macosx15.0" -swift-version 5 -O -parse-as-library \
  "$DRUMX_ROOT/native/macos/DrumxSongScores.swift" \
  "$DRUMX_ROOT/native/macos/tests/DrumxSongScoreChecks.swift" \
  -o "$DRUMX_SCORE_BUILD/DrumxSongScoreChecks"
"$DRUMX_SCORE_BUILD/DrumxSongScoreChecks"
xcrun clang++ -target "$(uname -m)-apple-macosx15.0" -std=c++17 -O2 -Wall -Wextra -pedantic -c \
  "$DRUMX_ROOT/native/core/drumx_core.cpp" -o "$DRUMX_SCORE_BUILD/drumx_core.o"
xcrun swiftc -target "$(uname -m)-apple-macosx15.0" -swift-version 5 -O -parse-as-library \
  -import-objc-header "$DRUMX_ROOT/native/core/drumx_core.h" \
  "$DRUMX_ROOT/native/macos/DrumxSongScores.swift" \
  "$DRUMX_ROOT/native/macos/tests/DrumxSongScoreCoreChecks.swift" \
  "$DRUMX_SCORE_BUILD/drumx_core.o" -Xlinker -lc++ \
  -o "$DRUMX_SCORE_BUILD/DrumxSongScoreCoreChecks"
"$DRUMX_SCORE_BUILD/DrumxSongScoreCoreChecks"
