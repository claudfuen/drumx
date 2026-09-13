# Shared native preview backend

`DrumxEngine` is a Godot GDExtension backed by the same C++17 scoring core as the Mac lab. GDScript polls immutable copies of hits, events and scores. It does not timestamp MIDI or start individual metronome sounds.

Build from the repository root:

```sh
cmake -S apps/game/native -B .build/game-native -DCMAKE_BUILD_TYPE=Release
cmake --build .build/game-native --config Release --parallel 4
ctest --test-dir .build/game-native -C Release --output-on-failure
```

The extension is emitted to `apps/game/bin/drumx_engine.dylib` on Mac or `drumx_engine.dll` on Windows. Windows builds use the static MSVC runtime. The initial release targets Mac arm64 and Windows x86_64. Windows device behavior still requires the physical tester's first session; a successful cross-platform compile is not a hardware test.

## Timing and ownership

- CoreMIDI passes the packet's original Mach host timestamp to the scorer. A packet with timestamp zero uses callback arrival time because the driver supplied no original time.
- WinMM supplies driver capture milliseconds since `midiInStart`. The backend anchors that clock to `QueryPerformanceCounter` immediately before starting the input. Its timestamp resolution and start-call uncertainty are not a measured physical round-trip latency.
- A native worker advances the scorer every 2 ms and closes complete phrases independently of rendering. Manual stop retains the capture-time boundary so delayed pre-stop input can correct the closed take. This worker cadence is a requested interval, not a measured deadline guarantee.
- MIDI reception scores under a native mutex and places a receipt in a bounded 256-event observation queue. Overflow drops the oldest receipt and increments `dropped_hits`; it does not discard the already-applied score. Source generations reject callbacks from disconnected inputs.
- Sample triggers enter a bounded 256-item queue with serialized producers and an atomic consumer. The native audio callback performs no Godot calls, file I/O, scoring, or mutex acquisition. It owns 32 sample voices and steals the oldest voice when full. Queued triggers older than 100 ms are dropped and counted instead of producing delayed bursts.
- Closed and pedal hi-hat samples choke active open-hi-hat voices with a 5 ms fade on the audio thread. Other instruments leave the open tail ringing. MIDI CC4 continuous hat opening and cymbal aftertouch chokes are not implemented.
- Disabling monitoring retires active sample tails with the same short fade; it leaves the native metronome running.
- The metronome is synthesized in the native audio callback on its sample clock, anchored to host time when the output starts. It uses a nominal 48 kHz timeline and drops stale click beats after output stalls. The requested 128-frame period and two periods do not establish physical output latency; a driver can negotiate different buffering. Physical MIDI-to-speaker and click-to-input alignment are unmeasured.
- Audio output must open successfully before a real take can start. `load_sample_bank(directory, false)` decodes all samples without opening hardware for the packaged smoke check. It sets `samples_ready`, never `audio_ready`.

## Binding contract

`load_chart(bpm, bars, events)` accepts complete repeated phrase events `{pad, beat}` in quarter-note beats, with three pad IDs: 0 hi-hat, 1 snare, 2 kick. The core validates all events atomically. `start(count_in_beats=4)` returns the host time of the first scored beat or -1. `stop()` closes the take. `get_host_time()` exposes the same native clock for rendering.

`snapshot()` returns running/completion state, `practice_start`, core timing and totals, selected `source_id`, `pending_pad`, audio/sample readiness, drop counters and an error. `get_events()` returns `{id,pad,time_seconds,resolved,hit}`. `poll_hits()` drains `{pad,note,velocity,host_time,source_id,judgment,event_id,offset_ms,mapping_changed}` receipts. Unmapped MIDI has pad -1; keyboard preview has note -1 and an empty source ID.

`sources()` returns `{id,name}`. `connect_source(id)` connects one module; an empty ID selects keyboard. `set_mapping()`/`get_mapping()` use three arrays of disjoint MIDI note aliases, at most 16 per pad. `learn_pad(pad)` preserves existing aliases and removes a conflicting new note from its former pad; the learning strike is silent and unscored. `cancel_learning()` cancels explicitly. Original capture time prevents a queued pre-arm strike from becoming the mapping. Source changes cancel learning.

`keyboard_hit(pad,velocity)` is a preview and keyboard-input path for lesson pads 0 through 2. When a MIDI source is selected it cannot add keyboard scores. `set_monitoring(bool)` and `set_volume(0...1)` control optional Drumx sample playback independently from the click. `load_sample_bank(directory, open_device=true)` reads all 80 FLAC files through Godot FileAccess, including from an exported PCK, then decodes native PCM before playback. The backend filesystem loader and GDExtension share `sample_catalog.h`, with four velocity layers and two round robins per instrument.

Sample playback covers closed hi-hat, snare, kick, high/mid/floor tom, crash, ride, open hi-hat and pedal hi-hat. Lesson scoring remains on the three existing lanes. An unmapped GM full-kit note can sound while its receipt retains pad -1 and an ignored judgment; it never adds a lesson match or extra. Unmapped note pairs 48/50 share high tom, 45/47 share mid tom, 41/43 share floor tom, 49/57 share crash, and 51/59 share ride bow. Open hat 46 and pedal hat 44 retain distinct sounds both when mapped to the lesson hi-hat and when unmapped. These pairs use the same recorded instrument, not separate tom tunings or second cymbals. Ride bell 53 and other unsupported percussion have no fallback.

A learned lesson alias takes precedence over GM playback. For example, teaching note 49 as snare makes subsequent note 49 strikes sound and score as snare. Core kick/snare/closed-hat aliases removed from the user's mapping stay silent. Learning strikes and queued strikes captured before learning was armed remain silent and unscored, including full-kit notes.

`native_sample_mixer` renders the production audio mixer without opening an output device. It checks every instrument, layer boundary and round robin, GM monitoring versus lesson scoring, learning isolation, monitoring gates, open-hat chokes, malformed reloads, queue bounds and finite output under dense polyphony. `shared_native_backend` separately decodes all 80 bundled original FLAC recordings.

`pulse_tempo_plan()` returns policy 1 for `find-the-pulse-v1`: start at 60 BPM, steps of 6, checkpoint at 72, 16-bar phrases, and optional 84/96 stretch goals. One qualifying phrase can suggest a step below 72; repeated checkpoint evidence requires two qualifying takes among three comparable full phrases. Qualification uses at least 95% matched, 90% on time and at most 2% extras. These are practice recommendations, not technique or mastery claims.

`evaluate_pulse_tempo(attempts, current)` calls the shared C evaluator on both platforms without changing scores, files, audio, or progress. The caller filters the selected player and exact lesson, passes attempts oldest first, and constructs this normalized current intent:

```text
{lesson:"find-the-pulse", version:"find-the-pulse-v1", policy_version:1,
 conditions_key:String, bpm:number, bars:int, guidance:0|1|2,
 live_feedback:bool, monitoring:bool, calibration_ms:number}
```

Each attempt includes that same captured intent plus `{id:String, expected:int, matched:int, on_time:int, missed:int, extra:int, naturally_completed:bool, uninterrupted:bool}`. Capture policy, source/mapping conditions, monitoring, calibration, tempo, phrase length, guidance and live feedback when the take starts; never stamp new policy metadata onto old history. `conditions_key` must represent the complete source and mapping identity plus monitoring/calibration. The binding compares full strings with per-call ordinal tokens, never truncated IDs or hashes, and independently includes monitoring/calibration to prevent pooling if a caller reuses a key. Calibration is finite within ±1000 ms. IDs allow 1–1024 characters; condition keys allow 1–16384; evaluation accepts at most 100,000 rows. JSON whole-number floats are accepted for integer fields.

Legacy history without complete provenance may be represented only as `{id,lesson,version,legacy:true}`. It grants no evidence and removes earlier evidence for the same ID if it is a late correction. Valid old/future policy attempts remain ineligible. The last duplicate correction wins while its first chronological position is retained by the core. Malformed rows or wrong lesson versions fail the entire call with `{ok:false,error,error_index,policy_version}` instead of exposing an older duplicate's score. Success returns `ok:true`, `policy_version`, input/legacy counts and every `DXTempoDecision` field: recent counts, latest/current/checkpoint/hidden/recall evidence, action/reason enums, and complete `next_bpm`, `next_bars`, `next_guidance`, `next_live_feedback` intent. Boolean evidence fields are actual booleans.

The release-safe binding checks are `apps/game/tools/pulse_tempo_binding_checks.gd`, including a reusable `run_checks(engine)` for packaged smoke tests. Run the standalone script with Godot's headless runtime and `--path apps/game --script res://tools/pulse_tempo_binding_checks.gd`; editor import is not required once the project and extension are prepared.

The visual guidance mode is controlled by the frontend. This backend does not infer hand technique or mastery. It does not implement native demonstration playback, calibration, ASIO, audio device selection, or Windows hardware reconnection certification in this first preview.

## Third-party code

Build dependencies are pinned to official repositories:

- [godot-cpp](https://github.com/godotengine/godot-cpp/tree/e83fd0904c13356ed1d4c3d09f8bb9132bdc6b77), Godot 4.5 bindings, MIT. Notice: `licenses/godot-cpp-LICENSE.md`.
- [miniaudio](https://github.com/mackron/miniaudio/tree/f40cf03f80cdb7e741d43e53b7e706e8c1394bcf), 0.11.23, dual public-domain/MIT-0. Full upstream notice: `licenses/miniaudio-LICENSE`.

The unmodified Big Rusty FLAC recordings and their CC0 provenance live in `native/assets/BigRusty` and are staged with the game. The third-party licenses do not select a license for Drumx's original application code.

`configure_window(native_handle)` applies the original dark window appearance on macOS only. Call it on the main thread after Godot creates its window. It validates the handle against current app-owned windows before changing appearance; Windows, headless, invalid-handle, and background-thread calls do not mutate a window. This bridge does not alter content size, input coordinates, audio, or scoring.
