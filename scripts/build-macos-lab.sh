#!/bin/bash
set -euo pipefail
DRUMX_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [ -d /Applications/Xcode.app/Contents/Developer ]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
DRUMX_BUILD="${DRUMX_BUILD_DIR:-$DRUMX_ROOT/.build}"
DRUMX_APP="$DRUMX_BUILD/DrumxLab.app"
DRUMX_TARGET="$(uname -m)-apple-macosx15.0"
python3 "$DRUMX_ROOT/scripts/fetch-samples.py" --check
mkdir -p "$DRUMX_APP/Contents/MacOS"
mkdir -p "$DRUMX_APP/Contents/Resources"
mkdir -p "$DRUMX_APP/Contents/Resources/Drumx licensing"
for DRUMX_NOTICE in LICENSE NOTICE LICENSE-GUIDE.md; do
  test -s "$DRUMX_ROOT/$DRUMX_NOTICE"
  cp "$DRUMX_ROOT/$DRUMX_NOTICE" "$DRUMX_APP/Contents/Resources/Drumx licensing/$DRUMX_NOTICE"
done
cp -R "$DRUMX_ROOT/native/assets/BigRusty" "$DRUMX_APP/Contents/Resources/"
cp "$DRUMX_ROOT/scripts/import_song.py" "$DRUMX_APP/Contents/Resources/import_song.py"
xcrun clang++ -target "$DRUMX_TARGET" -std=c++17 -O2 -Wall -Wextra -pedantic -c "$DRUMX_ROOT/native/core/drumx_core.cpp" -o "$DRUMX_BUILD/drumx_core.o"
xcrun clang++ -target "$DRUMX_TARGET" -std=c++17 -O2 -Wall -Wextra -pedantic -c "$DRUMX_ROOT/native/core/drumx_tempo.cpp" -o "$DRUMX_BUILD/drumx_tempo.o"
xcrun swiftc -target "$DRUMX_TARGET" -swift-version 5 -O -parse-as-library \
  -import-objc-header "$DRUMX_ROOT/native/macos/DrumxBridging.h" \
  "$DRUMX_ROOT/native/macos/DrumxIO.swift" \
  "$DRUMX_ROOT/native/macos/DrumxSampler.swift" \
  "$DRUMX_ROOT/native/macos/DrumxLesson.swift" \
  "$DRUMX_ROOT/native/macos/DrumxCourse.swift" \
  "$DRUMX_ROOT/native/macos/DrumxProgress.swift" \
  "$DRUMX_ROOT/native/macos/DrumxUnlocks.swift" \
  "$DRUMX_ROOT/native/macos/DrumxTempoCoach.swift" \
  "$DRUMX_ROOT/native/macos/DrumxTempoController.swift" \
  "$DRUMX_ROOT/native/macos/DrumxTempoView.swift" \
  "$DRUMX_ROOT/native/macos/DrumxKitSetup.swift" \
  "$DRUMX_ROOT/native/macos/DrumxMenuInput.swift" \
  "$DRUMX_ROOT/native/macos/DrumxSettingsViews.swift" \
  "$DRUMX_ROOT/native/macos/DrumxPracticePlan.swift" \
  "$DRUMX_ROOT/native/macos/DrumxKitController.swift" \
  "$DRUMX_ROOT/native/macos/DrumxControls.swift" \
  "$DRUMX_ROOT/native/macos/DrumxMainMenuView.swift" \
  "$DRUMX_ROOT"/native/macos/DrumxSong*.swift \
  "$DRUMX_ROOT/native/macos/DrumxSettingsController.swift" \
  "$DRUMX_ROOT/native/macos/DrumxCourseViews.swift" \
  "$DRUMX_ROOT/native/macos/DrumxNotationView.swift" \
  "$DRUMX_ROOT/native/macos/DrumxJourneyController.swift" \
  "$DRUMX_ROOT/native/macos/DrumxScoreViews.swift" \
  "$DRUMX_ROOT/native/macos/DrumxTakeWindow.swift" \
  "$DRUMX_ROOT/native/macos/DrumxHitFeedback.swift" \
  "$DRUMX_ROOT/native/macos/DrumxProjection.swift" \
  "$DRUMX_ROOT/native/macos/PracticeView.swift" \
  "$DRUMX_ROOT/native/macos/DrumxLab.swift" \
  "$DRUMX_BUILD/drumx_core.o" "$DRUMX_BUILD/drumx_tempo.o" -Xlinker -lc++ \
  -framework AppKit -framework AVFoundation -framework AVFAudio \
  -framework CoreMIDI -framework CoreAudio -framework AudioToolbox \
  -o "$DRUMX_BUILD/DrumxLab.new"
# Replace the executable atomically so an older running lab keeps its original
# executable inode until it is quit. Reopen the app to use the newly built code.
mv "$DRUMX_BUILD/DrumxLab.new" "$DRUMX_APP/Contents/MacOS/DrumxLab"
cat > "$DRUMX_APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>DrumxLab</string>
<key>CFBundleIdentifier</key><string>org.drumx.timing-lab</string>
<key>CFBundleName</key><string>DrumxLab</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>LSMinimumSystemVersion</key><string>15.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
codesign --force --sign - "$DRUMX_APP"
echo "$DRUMX_APP"
