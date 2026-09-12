# Start the Windows track before the interface hardens

The portable baseline now builds the existing C++ scoring core through CMake and runs its contracts through CTest. A GitHub Actions matrix targets macOS and Windows in Debug and Release, with an additional macOS sanitizer job. This brings compiler and scoring differences into the feedback loop while the Mac experience continues to develop.

**This is a core portability baseline, not a Windows drum trainer.** The AppKit interface, CoreMIDI input, AVAudioEngine scheduling, Swift course models, and local progress store remain Mac implementations. There is no Windows MIDI/audio adapter, Godot native bridge, or exported Windows application in this change. M1 and the production-engine decision remain open.

## Build and test

Install [CMake 3.20 or newer](https://cmake.org/download/) and a C++17 compiler. On Windows, use Visual Studio Build Tools with the C++ desktop workload and run from its developer shell. On macOS, use Xcode's compiler. No samples, Swift compiler, Godot editor, account credentials, or network access are needed by this build once the tools and repository are present.

These commands work with both single-configuration and Visual Studio generators:

```sh
cmake -S . -B .build/portable -DBUILD_TESTING=ON -DCMAKE_BUILD_TYPE=Debug
cmake --build .build/portable --config Debug --parallel
ctest --test-dir .build/portable -C Debug --output-on-failure
```

Use a separate directory and `Release` for the optimized build. For Clang/GCC sanitizer checks:

```sh
cmake -S . -B .build/sanitized -DBUILD_TESTING=ON -DCMAKE_BUILD_TYPE=Debug -DDRUMX_ENABLE_SANITIZERS=ON
cmake --build .build/sanitized --parallel
ctest --test-dir .build/sanitized --output-on-failure
```

The reusable CMake target is **`Drumx::Core`**, backed by the static library `drumx_core`. Public headers come from `native/core`; the implementation requires C++17. Consumers use the existing [C interface](../native/core/drumx_core.h). This is a static-link boundary, not a finished Windows DLL or GDExtension API. The core requires serial access and receives externally timestamped song time; it does not own an audio device, MIDI transport, renderer, or independent clock.

CTest runs two contracts:

| Contract | Evidence |
| --- | --- |
| `core_contract` | The existing deterministic C++ suite: chart validation, matching, chords, duplicate hits, timing boundaries, delayed delivery, guidance, metrics, and completion. |
| `c_api_contract` | A source file compiled as C links against the C++ implementation and verifies a simultaneous hat/kick hit plus a missed snare through the public snapshot. |

The [portable workflow](../.github/workflows/portable-core.yml) runs on relevant pushes to main, pull requests, and manual dispatch. It uses a pinned checkout action, read-only repository permission, and no project secrets. A passing Windows job establishes compiler/linker and core-test behavior on that runner. It does not establish Windows graphics, MIDI, audible latency, or a successful physical-kit session.

## What was established locally

Local validation on September 12, 2026 used Apple Silicon macOS, Apple Clang 21.0.0, and CMake 4.4.3 installed only under the ignored `.build/portable-tools` directory. **Debug, Release, and address/undefined-behavior sanitizer builds each passed both CTest contracts.** The C++ suite reported 852 checks; the separate C consumer linked and verified its chord/miss snapshot. Hosted macOS/Windows job results remain pending until the workflow is committed and runs; link the actual run before describing Windows CI as passed.

Godot **4.7.2 stable**, released August 18, 2026, was verified against the [official release archive](https://godotengine.org/download/archive/4.7.2-stable/). The official Mac editor was downloaded into ignored `.build/godot-4.7.2`, checked against the release SHA-512 list, and reported `4.7.2.stable.official.ed1daf0bf`. No engine is selected for production. The replay scene and Windows export are deferred; no export-template package or scene implementation is included.

## The next bounded renderer experiment

Follow the [rendering plan](rendering-plan.md): one standalone Godot practice scene with a deterministic replay fixture, one camera and plane, seven stable hand-instrument slots, and a full-width kick bar meeting the same NOW line. Guided, hidden-bar, and memory states must share geometry. Own-hit feedback remains distinct from disclosed grading. Label the scene **replay** until a native bridge has passed timing-isolation tests.

Godot's Mobile renderer supports desktop use with Metal, Vulkan, or Direct3D 12; that makes it a candidate, not a measured performance result. A Windows export also requires matching export templates. Exporting an executable on a Mac is packaging evidence, not Windows execution. See the official [renderer overview](https://docs.godotengine.org/en/stable/tutorials/rendering/renderers.html) and [Windows export guide](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_windows.html).

Keep this spike separate from course navigation, profiles, and sample-library migration. First prove the same scene on both platforms; then decide whether to replace the practice renderer or expand the engine's ownership. Choose the production front end before large content expansion makes Mac-only presentation and Swift models expensive to unwind.

## Windows work that a portable renderer cannot solve

| Area | Required decision and evidence |
| --- | --- |
| MIDI availability and mapping | Select a supported Windows MIDI API and minimum OS/runtime. Test the actual module's notes, velocities, simultaneous hits, endpoint identity, hot-plug behavior, and re-enumeration. Port mapping semantics explicitly; do not assume a Mac source identifier exists on Windows. |
| Clock conversion | Map captured input and audio sample positions into one declared host-time domain. Windows MIDI Services exposes QPC-based timestamps; the adapter must use the correct frequency and units. Reconnect, sleep/wake, and output changes need explicit clock-generation invalidation. |
| Audio scheduling | Implement and measure a Windows audio path. WASAPI exposes device formats, buffer sizes, latency, and stream lifecycle; a low buffer setting alone does not prove low audible latency. Test shared listening, output changes, underruns, sample-rate changes, and the module's own audio route. |
| Thread ownership | Give the serial C++ core one owner. Pass bounded commands and timestamped hits to it, and publish immutable display snapshots. Stall the renderer deliberately and verify unchanged grades and audio scheduling, including queue-overflow behavior. |
| Rendering and scaling | Inspect the same chords, note sizes, labels, and NOW line at 1020×780, 16:9, 16:10, multiple DPI settings, and mixed-scale monitors. Measure presented frames separately from CPU/GPU work and requested refresh rate. |
| Keyboard and navigation | Verify focus, repeat suppression, simultaneous keys, Escape/pause, modifiers, and accessibility on Windows. Keyboard rollover and OS focus behavior are input limitations, not evidence of drum technique. |
| Content and saved progress | Extract or port Swift-authored lessons and progression without changing stable IDs, event timing, archive meaning, or unlock evidence. Test migration and failed writes before adding synchronization. |
| Packaging and support | Prove install, launch, update, signing/distribution decisions, and retained sample provenance on a real Windows machine. Steam eligibility, pricing, and a source license remain separate decisions. |

The Windows clock and audio boundaries above follow Microsoft's [MidiClock reference](https://microsoft.github.io/MIDI/sdk-reference/MidiClock/) and [WASAPI stream-management documentation](https://learn.microsoft.com/en-us/windows/win32/coreaudio/stream-management). These APIs require an implementation and measurements in Drumx; documentation is not a benchmark.

## Production gate

Keep the working Mac app until one representative launch → lesson → play → review → return journey works on both target platforms. Require matching geometry and core replay results, reliable native input/audio clocks under renderer stalls, durable player progress, readable controls at supported scales, and measured physical-kit timing. A clean CTest matrix is the first gate in that sequence, not a reason to declare the Windows application finished.
