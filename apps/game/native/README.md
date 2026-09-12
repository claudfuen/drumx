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
- The metronome is synthesized in the native audio callback on its sample clock, anchored to host time when the output starts. It uses a nominal 48 kHz timeline and drops stale click beats after output stalls. The requested 128-frame period and two periods do not establish physical output latency; a driver can negotiate different buffering. Physical MIDI-to-speaker and click-to-input alignment are unmeasured.
- Audio output must open successfully before a real take can start. `load_sample_bank(directory, false)` decodes all samples without opening hardware for the packaged smoke check. It sets `samples_ready`, never `audio_ready`.

## Binding contract

`load_chart(bpm, bars, events)` accepts complete repeated phrase events `{pad, beat}` in quarter-note beats, with three pad IDs: 0 hi-hat, 1 snare, 2 kick. The core validates all events atomically. `start(count_in_beats=4)` returns the host time of the first scored beat or -1. `stop()` closes the take. `get_host_time()` exposes the same native clock for rendering.

`snapshot()` returns running/completion state, `practice_start`, core timing and totals, selected `source_id`, `pending_pad`, audio/sample readiness, drop counters and an error. `get_events()` returns `{id,pad,time_seconds,resolved,hit}`. `poll_hits()` drains `{pad,note,velocity,host_time,source_id,judgment,event_id,offset_ms,mapping_changed}` receipts. Unmapped MIDI has pad -1; keyboard preview has note -1 and an empty source ID.

`sources()` returns `{id,name}`. `connect_source(id)` connects one module; an empty ID selects keyboard. `set_mapping()`/`get_mapping()` use three arrays of disjoint MIDI note aliases, at most 16 per pad. `learn_pad(pad)` preserves existing aliases and removes a conflicting new note from its former pad; the learning strike is silent and unscored. `cancel_learning()` cancels explicitly. Original capture time prevents a queued pre-arm strike from becoming the mapping. Source changes cancel learning.

`keyboard_hit(pad,velocity)` is a preview and keyboard-input path. When a MIDI source is selected it cannot add keyboard scores. `set_monitoring(bool)` and `set_volume(0...1)` control optional Drumx sample playback independently from the click. `load_sample_bank(directory, open_device=true)` reads the 24 FLAC files through Godot FileAccess, including from an exported PCK, then decodes native PCM before playback.

The visual guidance mode is controlled by the frontend. This backend does not infer hand technique or mastery. It does not implement native demonstration playback, calibration, ASIO, audio device selection, or Windows hardware reconnection certification in this first preview.

## Third-party code

Build dependencies are pinned to official repositories:

- [godot-cpp](https://github.com/godotengine/godot-cpp/tree/e83fd0904c13356ed1d4c3d09f8bb9132bdc6b77), Godot 4.5 bindings, MIT. Notice: `licenses/godot-cpp-LICENSE.md`.
- [miniaudio](https://github.com/mackron/miniaudio/tree/f40cf03f80cdb7e741d43e53b7e706e8c1394bcf), 0.11.23, dual public-domain/MIT-0. Full upstream notice: `licenses/miniaudio-LICENSE`.

The unchanged Big Rusty FLAC bank and its CC0 provenance live in `native/assets/BigRusty` and are staged with the game. The third-party licenses do not select a license for Drumx's original application code.
