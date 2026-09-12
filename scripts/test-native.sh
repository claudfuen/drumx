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
xcrun clang++ -target "$DRUMX_TARGET" -std=c++17 -O1 -g \
  -Wall -Wextra -Werror -pedantic -fsanitize=address,undefined \
  "$DRUMX_ROOT/native/core/drumx_tempo.cpp" "$DRUMX_ROOT/native/core/tempo_tests.cpp" \
  -o "$DRUMX_BUILD/tempo-core-checks"
"$DRUMX_BUILD/tempo-core-checks"
xcrun clang++ -target "$DRUMX_TARGET" -std=c++17 -O1 -Wall -Wextra -Werror -pedantic \
  -c "$DRUMX_ROOT/native/core/drumx_tempo.cpp" -o "$DRUMX_BUILD/tempo-core.o"
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
  -import-objc-header "$DRUMX_ROOT/native/macos/DrumxBridging.h" \
  "$DRUMX_ROOT/native/macos/DrumxLesson.swift" \
  "$DRUMX_ROOT/native/macos/tests/DrumxLessonChecks.swift" \
  "$DRUMX_BUILD/lesson-core.o" "$DRUMX_BUILD/tempo-core.o" -Xlinker -lc++ -o "$DRUMX_BUILD/lesson-checks"
"$DRUMX_BUILD/lesson-checks"
xcrun swiftc -target "$DRUMX_TARGET" -swift-version 5 -warnings-as-errors -parse-as-library \
  "$DRUMX_ROOT/native/macos/DrumxProjection.swift" \
  "$DRUMX_ROOT/native/macos/tests/DrumxProjectionChecks.swift" \
  -o "$DRUMX_BUILD/projection-checks"
"$DRUMX_BUILD/projection-checks"
xcrun swiftc -target "$DRUMX_TARGET" -swift-version 5 -warnings-as-errors -parse-as-library \
  "$DRUMX_ROOT/native/macos/DrumxTakeWindow.swift" \
  "$DRUMX_ROOT/native/macos/tests/DrumxTakeWindowChecks.swift" \
  -o "$DRUMX_BUILD/take-window-checks"
"$DRUMX_BUILD/take-window-checks"
xcrun swiftc -target "$DRUMX_TARGET" -swift-version 5 -warnings-as-errors -parse-as-library \
  "$DRUMX_ROOT/native/macos/DrumxHitFeedback.swift" \
  "$DRUMX_ROOT/native/macos/tests/DrumxHitFeedbackChecks.swift" \
  -o "$DRUMX_BUILD/hit-feedback-checks"
"$DRUMX_BUILD/hit-feedback-checks"
for DRUMX_MODEL in Course Progress KitSetup MenuInput; do
  xcrun swiftc -target "$DRUMX_TARGET" -swift-version 5 -warnings-as-errors -parse-as-library \
    "$DRUMX_ROOT/native/macos/Drumx${DRUMX_MODEL}.swift" \
    "$DRUMX_ROOT/native/macos/tests/Drumx${DRUMX_MODEL}Checks.swift" \
    -o "$DRUMX_BUILD/${DRUMX_MODEL}-checks"
  "$DRUMX_BUILD/${DRUMX_MODEL}-checks"
done
xcrun swiftc -target "$DRUMX_TARGET" -swift-version 5 -warnings-as-errors -parse-as-library \
  -import-objc-header "$DRUMX_ROOT/native/macos/DrumxBridging.h" \
  "$DRUMX_ROOT/native/macos/DrumxLesson.swift" \
  "$DRUMX_ROOT/native/macos/DrumxCourse.swift" \
  "$DRUMX_ROOT/native/macos/DrumxProgress.swift" \
  "$DRUMX_ROOT/native/macos/DrumxUnlocks.swift" \
  "$DRUMX_ROOT/native/macos/DrumxTempoCoach.swift" \
  "$DRUMX_ROOT/native/macos/tests/DrumxUnlockChecks.swift" \
  "$DRUMX_BUILD/lesson-core.o" "$DRUMX_BUILD/tempo-core.o" -Xlinker -lc++ -o "$DRUMX_BUILD/unlock-checks"
"$DRUMX_BUILD/unlock-checks"
xcrun swiftc -target "$DRUMX_TARGET" -swift-version 5 -warnings-as-errors -parse-as-library \
  -import-objc-header "$DRUMX_ROOT/native/macos/DrumxBridging.h" \
  "$DRUMX_ROOT/native/macos/DrumxCourse.swift" \
  "$DRUMX_ROOT/native/macos/DrumxIO.swift" \
  "$DRUMX_ROOT/native/macos/DrumxSampler.swift" \
  "$DRUMX_ROOT/native/macos/tests/DrumxCourseIntegrationChecks.swift" \
  "$DRUMX_BUILD/lesson-core.o" "$DRUMX_BUILD/tempo-core.o" -Xlinker -lc++ \
  -framework AVFoundation -framework CoreMIDI -framework AudioToolbox \
  -o "$DRUMX_BUILD/course-integration-checks"
"$DRUMX_BUILD/course-integration-checks" "$DRUMX_ROOT/native/assets/BigRusty/manifest.json"

xcrun swiftc -target "$DRUMX_TARGET" -swift-version 5 -warnings-as-errors -parse-as-library \
  "$DRUMX_ROOT/native/macos/DrumxCourse.swift" \
  "$DRUMX_ROOT/native/macos/DrumxProgress.swift" \
  "$DRUMX_ROOT/native/macos/DrumxPracticePlan.swift" \
  "$DRUMX_ROOT/native/macos/tests/DrumxPracticePlanChecks.swift" \
  -o "$DRUMX_BUILD/practice-plan-checks"
"$DRUMX_BUILD/practice-plan-checks"

xcrun swiftc -target "$DRUMX_TARGET" -swift-version 5 -warnings-as-errors -parse-as-library \
  -import-objc-header "$DRUMX_ROOT/native/macos/DrumxBridging.h" \
  "$DRUMX_ROOT/native/macos/DrumxLesson.swift" \
  "$DRUMX_ROOT/native/macos/DrumxCourse.swift" \
  "$DRUMX_ROOT/native/macos/DrumxProgress.swift" \
  "$DRUMX_ROOT/native/macos/DrumxPracticePlan.swift" \
  "$DRUMX_ROOT/native/macos/DrumxTempoCoach.swift" \
  "$DRUMX_ROOT/native/macos/DrumxUnlocks.swift" \
  "$DRUMX_ROOT/native/macos/tests/DrumxTempoCoachChecks.swift" \
  "$DRUMX_BUILD/lesson-core.o" "$DRUMX_BUILD/tempo-core.o" -Xlinker -lc++ -o "$DRUMX_BUILD/tempo-coach-checks"
"$DRUMX_BUILD/tempo-coach-checks"

"$DRUMX_ROOT/scripts/test-settings-controls.sh"
