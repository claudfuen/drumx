# Architecture exploration

Status: proposal, September 12, 2026. No application stack selected and no hardware performance measured. Read [the product research](product-research.md) for the current product hypothesis and shipped-product evidence.

## Product constraints

Build a visually distinctive drum trainer for MIDI electronic drum kits. Start on macOS and preserve a practical Windows path. Support several players with separate profiles and progress, different starting abilities, configurable note mappings, and a progression from fundamentals to more challenging rudiments and coordination.

Responsiveness means three separate things: accurate timing feedback, prompt audible response when the app generates drum sounds, and prompt visible feedback. Graphics must support custom animated practice scenes rather than constrain the product to ordinary form controls.

## Options

These effort and fit assessments are engineering judgments, not comparative benchmarks.

| Candidate | Strength | Cost or uncertainty |
| --- | --- | --- |
| Flutter + native Rust or C++ engine | Coherent native application rendering, layout and motion; custom practice scene; Mac and Windows path | Native integration, original visual design, separate audio/device engine |
| Unity + native MIDI/audio engine | Complete game authoring environment with polished shipped rhythm-game and restrained visual precedents | Conventional desktop UI work, engine overhead, clear ownership of audio clocks |
| Electron + React + PixiJS + native Rust engine | Flexible lesson/profile UI, GPU practice graphics, native MIDI/audio/scoring isolated from rendering, Mac and Windows path | Chromium footprint, two languages, native packaging and IPC |
| Rust + egui/eframe + wgpu + midir + CPAL | Native GPU application with one language and no browser runtime; engine reusable independently | More bespoke consumer UI work and audio/device integration |
| C++ + JUCE | Integrated audio device management, MIDI, DSP, desktop UI and Mac/Windows support | C++ development and maintenance, visual design effort, licensing choice |
| Godot + native MIDI/audio timing extension | Strong fit for a game-like practice world with animated scenes and effects | Product/settings UI work; authoritative timing needs care beyond frame-based input handling |

SwiftUI/AppKit with CoreMIDI/CoreAudio and Metal is also viable for a dedicated Mac product, but requires replacement platform/UI layers for Windows. Tauri can host a native engine too; its use of different system WebViews introduces additional graphics compatibility testing. Neither is ruled out by latency alone.

## Provisional recommendation

The product hypothesis is a rhythm-game practice loop that progressively removes the visible track while continuing to score. Unity and Flutter, each with a native timing/audio engine, are the initial front-end candidates. C++/JUCE remains the integrated music-software alternative. Review [the pitch](pitch.md) and conceptual mockups before accepting the idea, then compare the same exercise and timing workload before selecting a stack. The supporting shipped-product evidence and tradeoffs are in [the product research](product-research.md).

Electron/Pixi remains a technically possible architecture, described below to preserve the comparison. It is not a selected implementation or the default recommendation.

React would own navigation, lessons, profiles, history and settings. PixiJS would draw the animated notation, practice lane, hit markers and kit feedback. It renders into a GPU canvas, so the practice surface need not consist of DOM elements. Current Pixi documentation recommends WebGL for production and treats WebGPU as experimental due to implementation inconsistencies. Newer graphics APIs do not themselves establish faster rendering. [Pixi renderers](https://pixijs.com/8.x/guides/components/renderers), [render loop](https://pixijs.com/8.x/guides/concepts/render-loop).

For the native engine, a packaged Rust executable launched by the Electron main process is one concrete option. Commands and timestamped display snapshots travel over bounded IPC outside the audio callback. The engine owns MIDI capture, clock alignment, metronome generation and authoritative scoring. A standalone engine allows a later native frontend to reuse the same training behavior. Electron's `utilityProcess.fork` instead launches a Node script; using that route requires a native addon, not passing it a Rust executable. [Node subprocess API](https://nodejs.org/api/child_process.html), [Electron utility process](https://www.electronjs.org/docs/latest/api/utility-process).

Native Rust has a documented GPU rendering route through eframe/wgpu with custom drawing. JUCE offers integrated audio, MIDI and native desktop graphics. Godot documents audio clock compensation and the ways mixing, display and device delays affect rhythm applications. [eframe](https://docs.rs/crate/eframe/latest), [wgpu](https://wgpu.rs/), [JUCE features](https://juce.com/features/), [JUCE licensing](https://juce.com/legal/), [Godot audio synchronization](https://docs.godotengine.org/en/stable/tutorials/audio/sync_with_audio.html).

## Timing architecture

1. Receive MIDI in a native callback. Preserve the backend's event timestamp and record callback arrival separately for diagnostics. Do not timestamp a strike when the UI finally handles it.
2. Explicitly align MIDI, monotonic host and audio playback clocks. `midir` timestamps have a connection-specific origin. CPAL exposes callback and predicted playback timestamps. Raw values from different clock domains must not be directly subtracted. Validate clock behavior per backend and rebuild alignment after reconnect, sleep or audio device changes. [midir callback contract](https://docs.rs/midir/latest/midir/struct.MidiInput.html), [CPAL output timestamps](https://docs.rs/cpal/latest/cpal/struct.OutputStreamTimestamp.html).
3. Generate the metronome and optional monitored drum sounds in the native audio callback using the sample timeline. Use bounded work and preallocated memory. Avoid allocation, mutex waits, disk access, logging and IPC in that callback.
4. Transfer input and control data through bounded queues. Score on preserved timestamps. Keep the renderer outside the path that determines click timing and grades. Record overflow instead of silently losing strikes.
5. Send timestamped state to the practice renderer. Interpolate the upcoming timeline against the engine clock, while showing newly received strike feedback promptly. UI stalls can delay what the learner sees and must be measured even when grades remain correct.
6. Negotiate small audio buffers with the selected output device, report actual configuration, and increase buffers if underruns occur. A requested buffer size is not a guaranteed device setting or an end-to-end latency figure.

At 48 kHz, 64 and 128 frames represent approximately 1.33 and 2.67 ms of audio respectively. Those are block durations only. Drum trigger processing, MIDI transport, backend buffering, converters, headphones and display presentation contribute additional delay.

When using the kit's own sounds, direct monitoring through its module can keep app-generated drum audio out of the player's sound path. The app's metronome or backing track still needs an appropriate shared listening route. Kit connectivity and audio routing must be verified for each actual module; a USB MIDI connection does not establish USB audio capability.

Calibration must separate measured device offset from a player's habitual timing. A tap-along wizard can estimate perceived alignment but cannot prove physical input latency. Calibration corrects a stable offset; it cannot remove variable jitter or make a delayed sound arrive earlier.

## Prototype and acceptance evidence

First build one pad, one click track, one visual hit indicator and a timing trace. Do not build the full course before checking the input-to-feedback path.

- Compare the shared engine alone and the shortlisted visual frontends with identical workloads.
- Replay deterministic timestamped sequences to verify grading, simultaneous voices, misses, duplicate notes and clock conversions. Suspend or overload the renderer and verify the metronome and score remain stable.
- Test real and virtual MIDI separately. Virtual MIDI cannot establish physical strike latency or hardware trigger behavior.
- Measure MIDI receipt-to-score duration and its p50/p95/p99 tails, MIDI receipt-to-generated electrical audio output, and physical strike-to-visible feedback where suitable measurement equipment is available. Keep the measurement endpoints explicit.
- Use an audio loopback/recording setup for generated sound and a high-speed camera or equivalent for physical strike-to-display latency. Software frame counters alone do not measure when pixels appear.
- Record actual sample rate, buffer sizes, output device, refresh rate, underruns, dropped events, frame-time tails, CPU and memory. Test rapid rolls, simultaneous kick/snare/hi-hat, animated scenes, and sustained CPU/GPU load.
- Exercise device disconnect/reconnect, app switching, sleep/wake and long sessions. Test supported Windows audio/MIDI backends separately before claiming Windows responsiveness.

Initial proposed gates, subject to target-hardware validation: native receipt-to-score p99 below 1 ms; app-generated audio from MIDI receipt below 10 ms on a supported wired configuration; stable 120 Hz presentation on a 120 Hz display with a 60 Hz fallback; no lost input or audio underruns during the agreed stress run. These are proposed acceptance targets, not measured results or promises of total pad-to-ear latency.

No benchmark has been run yet. The final stack decision should follow this evidence, including the extra packaging and maintenance cost of the hybrid.
