#!/bin/bash
set -euo pipefail
DRUMX_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [ -d /Applications/Xcode.app/Contents/Developer ]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
DRUMX_BUILD="$DRUMX_ROOT/.build/tests"
DRUMX_TARGET="$(uname -m)-apple-macosx15.0"
mkdir -p "$DRUMX_BUILD"
xcrun swiftc -target "$DRUMX_TARGET" -swift-version 5 -warnings-as-errors -parse-as-library \
  "$DRUMX_ROOT/native/macos/DrumxControls.swift" \
  "$DRUMX_ROOT/native/macos/DrumxSettingsViews.swift" \
  "$DRUMX_ROOT/native/macos/DrumxCourse.swift" \
  "$DRUMX_ROOT/native/macos/DrumxCourseViews.swift" \
  "$DRUMX_ROOT/native/macos/DrumxMainMenuView.swift" \
  "$DRUMX_ROOT/native/macos/tests/DrumxSettingsControlChecks.swift" \
  -framework AppKit -o "$DRUMX_BUILD/settings-control-checks"
# The fixture prohibits app activation and never orders its layout window.
# It tests native target/action and layout only, without showing application UI.
"$DRUMX_BUILD/settings-control-checks"
