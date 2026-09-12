#!/bin/bash
set -euo pipefail
DRUMX_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [ -d /Applications/Xcode.app/Contents/Developer ]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
DRUMX_BUILD="$DRUMX_ROOT/.build/tests"
DRUMX_TARGET="$(uname -m)-apple-macosx15.0"
python3 "$DRUMX_ROOT/scripts/fetch-samples.py" --check
mkdir -p "$DRUMX_BUILD"
xcrun clang++ -target "$DRUMX_TARGET" -std=c++17 -O1 -g \
  -Wall -Wextra -Werror -pedantic -fsanitize=address,undefined \
  "$DRUMX_ROOT/native/core/drumx_core.cpp" "$DRUMX_ROOT/native/core/tests.cpp" \
  -o "$DRUMX_BUILD/core-checks"
"$DRUMX_BUILD/core-checks"
xcrun swiftc -target "$DRUMX_TARGET" -swift-version 5 -parse-as-library \
  "$DRUMX_ROOT/native/macos/DrumxIO.swift" \
  "$DRUMX_ROOT/native/macos/DrumxSampler.swift" \
  "$DRUMX_ROOT/native/macos/tests/DrumxIOChecks.swift" \
  -framework AVFoundation -framework CoreMIDI -framework AudioToolbox \
  -o "$DRUMX_BUILD/io-checks"
"$DRUMX_BUILD/io-checks" "$DRUMX_ROOT/native/assets/BigRusty/manifest.json"
xcrun clang++ -target "$DRUMX_TARGET" -std=c++17 -O1 -Wall -Wextra -Werror -pedantic \
  -c "$DRUMX_ROOT/native/core/drumx_core.cpp" -o "$DRUMX_BUILD/lesson-core.o"
xcrun swiftc -target "$DRUMX_TARGET" -swift-version 5 -warnings-as-errors -parse-as-library \
  -import-objc-header "$DRUMX_ROOT/native/core/drumx_core.h" \
  "$DRUMX_ROOT/native/macos/DrumxLesson.swift" \
  "$DRUMX_ROOT/native/macos/tests/DrumxLessonChecks.swift" \
  "$DRUMX_BUILD/lesson-core.o" -Xlinker -lc++ -o "$DRUMX_BUILD/lesson-checks"
"$DRUMX_BUILD/lesson-checks"
