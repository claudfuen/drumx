# Experimental shared desktop port

**Status: internal engineering experiment. The shared interface has not been accepted.** The native [Mac app](native-lab.md) remains the primary experience and visual baseline. The first Godot port was rejected on visual quality; passing its build and smoke checks does not establish product parity or make it ready for public release.

The work in `apps/game` tests a shared Godot frontend and a native C++ extension on Apple Silicon macOS and x86_64 Windows. Keep its packaging and timing work available while improving the experience. There is no public shared-app release. The README links the latest verified CI artifacts for deliberate regression testing. **M1 remains active.**

## What the experiment establishes

The port uses the same 12 authored foundation patterns and 24 original Big Rusty recordings as the Mac lab. Shared JSON comes from the Swift course exporter. The extension owns MIDI capture, scoring, sample playback, and the click; Godot displays their results. The [native backend guide](../apps/game/native/README.md) records its clock, queue, and device boundaries.

| Area | Current shared-port behavior | Remaining gap against the Mac baseline |
| --- | --- | --- |
| Main menu and learning path | Continue, Learn, Settings, a featured lesson, and 12 selectable steps | Visual hierarchy, spacing, control treatment, and window behavior need acceptance against the native app. |
| Teaching | Original counts, five-line drum staff with upper/lower voices, rests, beams, sticking suggestions, and a separate lesson-check overlay | Audible lesson demonstration and persisted technique self-checks are missing. The newly restored teaching view still needs final visual inspection. |
| Practice | Coached pulse at 60/66/72 BPM with a repeatable checkpoint, optional 84/96 challenges, separate free practice, and comparable-take results; other lessons retain manual options | The shared tempo range and 32-bar option still differ. The restored review hierarchy needs final on-screen inspection. |
| Guidance | Follow the track, alternate guided/hidden bars, or click-only recall | The highway now uses the native per-target alternate-bar rule. Independent Live timing control is still absent. |
| Kit and sound | Three pads, raw MIDI/velocity receipts, additive aliases, native monitoring, and volume | Physical Windows input/audio remains untested. Native scoring offset and drum-operated menu navigation are absent. |
| Progress | One local save with selected lesson, completed attempts, matching-condition bests, reading, and basic sequential unlocks | Independent pulse coached/free-practice resume is implemented. Other-lesson practice conditions, separate named players, and AppKit save migration remain absent. Select and verify the MIDI route each launch. |
| Interruption | Escape opens pause with restart/review/home, or returns other pages home | Restart begins a fresh count-in; paused takes do not change records. Menu navigation and presentation need comparison. |

These are implementation differences to resolve or explicitly accept, not a revised product specification. A reader should not use the native guide to infer features in this port.

## Verification so far

The polish pair at `1ce2060` passed both operating systems in [run 34718163923](https://github.com/claudfuen/drumx/actions/runs/34718163923): 8,027 checks in each source run and exported executable, 446 native history checks, 57 tempo adapter checks, 20 settings-control checks, native Mac app compilation, and clean same-commit package verification. Both systems passed backend recovery and process-ownership contracts. [The paired manifest](https://github.com/claudfuen/drumx/actions/runs/34718163923/artifacts/10305291588) records both archive hashes and `dirty: false`. The README links these packages. The [native control fixture](images/settings-controls-detail.png) was inspected through a bitmap-only render; the complete updated window journey still needs interactive review.

Local Apple Silicon checks have passed for the native backend and the actual exported Mac app. The current local exported executable reported `DRUMX_SMOKE_OK 8027 ... native=true`, read all 24 original FLAC files from its packed resources, and exercised shared content, scoring, and isolated save/reload checks. Its main executable and native extension were verified as arm64, and its ad-hoc bundle signature passed strict verification. This includes the coached pulse, isolated persistence/migration checks, restored best-score comparisons, changed-source recommendation handling, and minimum-size preparation/review states.

The initial local inspection packages were marked `dirty: true` and were not release candidates. The [recovery pair at `7f15952`](https://github.com/claudfuen/drumx/actions/runs/34713689821) subsequently built both targets from a clean committed tree. Each source and exported executable passed 7,717 checks; the dependent job verified matching commits and archive hashes. The [first successful paired run](https://github.com/claudfuen/drumx/actions/runs/34713214121), at `aea06f2`, passed native backend checks and actual exported-app execution on both macOS and Windows, followed by same-commit package verification. The first Windows attempt caught newline conversion in a pinned license; deterministic LF checkout fixed it without relaxing verification. **Physical Windows graphics, MIDI, and audio remain untested.** Earlier [portable-core CI](cross-platform.md#what-has-been-verified) tested only the core and C consumer, not this interface or native device adapter.

Headless checks do not inspect graphics, readable layouts, audible latency, real MIDI triggers, or how a beginner uses the app. The first local visual review rejected the port despite passing software checks. Recovery restores the native menu composition and artwork, custom settings controls, a four-beat projective highway, stable instrument slots, original note silhouettes, far fade, capture effects, and compact scoring. A Swift-generated geometry fixture now runs 4,305 comparisons in both source and exported smoke checks. Density checks confirmed logical window sizing at 1×, 1.5×, and 2×. The corrected exported Mac menu, dark window chrome, Learn, locked lessons, kit/sound settings, count-in, play, and Escape pause have been inspected on screen. Preparation and review were then rebuilt from the original hierarchy; their final visual inspection is pending. The exported app additionally executes 206 notation semantics checks and live per-page polling checks, verifies minimum-size layouts, and checks modal keyboard-focus isolation. This is recovery evidence, not visual acceptance.

The premium pass retains the current visual composition and adds explicit Settings return routes, clearer focus and pad states, visible sound values, and a scrolling section body when a shorter window needs it. Keyboard practice pauses when its window loses focus; MIDI practice remains independent of keyboard focus. Unplugged or failed MIDI selection requires an explicit input choice. Audio-device changes stop an active take and require **Retry audio** in Settings. Neither recovery resumes an old transport.

Completed results that fail to save stay in an in-memory queue while the app remains open. Saving retries between takes; **Settings → Progress → Retry save** offers an explicit retry. New takes and late score corrections preserve each queued result's captured conditions. Quitting with actual unsaved results requires a choice to retry, keep playing, or exit without them. The shared app reserves its progress archive for one running copy. A second copy shows a protected-progress screen and cannot practise or write; close that copy and use the original, or close the original before reopening. The OS releases ownership after process exit. This is session recovery, not crash/power-loss persistence. A corrupt archive is preserved; restore a valid archive before explicitly retrying.

## Build and package for inspection

Use Python 3, CMake 3.20+, and a C++17 toolchain: Xcode on Apple Silicon Mac, or Visual Studio C++ Build Tools on x86_64 Windows. The fetcher downloads pinned official Godot **4.7.2** editor/templates, verifies SHA-256 hashes, caches downloads under ignored `.build/godot-4.7.2`, and installs the required desktop templates in Godot's export-template directory.

From the repository root, on either target host:

```sh
python3 scripts/fetch-godot.py
python3 scripts/verify-game-content.py
cmake -S apps/game/native -B .build/game-native -DCMAKE_BUILD_TYPE=Release
cmake --build .build/game-native --config Release --parallel 3
ctest --test-dir .build/game-native -C Release --output-on-failure
```

For the first configure on Mac, append `-DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_DEPLOYMENT_TARGET=13.0`. On Windows, append `-A x64` when using the Visual Studio generator. The Windows extension uses the static MSVC runtime.

Package on the matching operating system so the exported executable can be tested there:

```sh
# Apple Silicon Mac
python3 scripts/package-game.py --target macos-arm64 --allow-dirty

# x86_64 Windows
python3 scripts/package-game.py --target windows-x86_64 --allow-dirty
```

`--allow-dirty` is for local inspection. Omit it for a committed candidate; pair validation rejects dirty builds. Outputs go to `.build/preview`. Each ZIP contains the app, a commit manifest, and third-party notices. Extract the entire Windows package together so its EXE, PCK, and DLL stay alongside one another.

Godot's official Mac template contains a universal executable. Packaging exports it, removes its unsupported Intel slice, and re-signs the arm64 app ad-hoc. The Windows app is unsigned; the Mac app is not notarized. These are packaging boundaries, not installer or distribution acceptance. Official references: [Mac export](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_macos.html), [Windows export](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_windows.html), and [4.7.2 archive](https://godotengine.org/download/archive/4.7.2-stable/).

## CI artifacts, without automatic publication

The [experimental workflow](../.github/workflows/desktop-preview.yml) builds both targets at the same commit. Each job validates the course and original assets, runs the portable core/C interface contracts and native backend checks, then imports, exports, and runs a headless smoke test of the actual app. Mac also regenerates and compares the Swift course and visual baseline. Both exported executables compare the shared highway against the original Swift geometry.

Successful jobs retain `experimental-app-macos-arm64` and `experimental-app-windows-x86_64` as CI artifacts. A dependent job checks the pair's commit, engine version, sample manifest, and archive hashes, then retains a paired manifest/checksum artifact. Logs and packages expire after 14 days.

**There is no public-release job, release token, or `contents: write` permission in this workflow.** The retained publisher script is invoked only with `--verify-only`. Its publication branch remains unused. Re-enabling public publication requires a separate reviewed workflow change after the acceptance gate below; a green CI run cannot enable it automatically.

## The next acceptance gate

Use one candidate commit, a synthetic player, and equivalent lesson/input conditions. Keep the evidence small and directly comparable:

1. **Visual parity:** capture the native Mac baseline and equivalent shared Mac/Windows views for main menu, Learn, preparation, kit setup, count-in/play, and review at 1440×900. Then check resizing to the native baseline's 1020×780 minimum, 16:9, 16:10, and Windows display scaling. Accept typography, hierarchy, spacing, note alignment, kick width, focus, and disabled states. Fix clipping and inaccessible controls. Record every intentional difference rather than explaining it away as a framework limitation.
2. **One complete journey on both systems:** connect or choose keyboard, open a lesson, understand the pattern, start the default block, stop/retry, finish/review, inspect a locked step, and reopen saved progress. Exercise resizing and input loss. Confirm the feature gaps above have been resolved or explicitly accepted for this candidate.
3. **Physical Windows session:** on the user's PC and MIDI kit, confirm source discovery, pad identities, simultaneous hits, velocity, alias learning, sound/click routing, disconnection/reconnection, and a complete take. Record the OS, module, output route, and failures. Observe latency without claiming a measured result unless a measurement method was used.

**Decision:** explicitly accept the shared visual experience and the bounded feature scope before considering public release. Then rerun both packaged builds from that accepted commit and verify their manifests. The native Mac app stays primary until that decision; experimental artifacts and successful compilation do not replace it.
