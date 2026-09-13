# Native I/O checks

`DrumxIOChecks.swift` compiles with `DrumxIO.swift` and `DrumxSampler.swift` as a separate test executable,
using Swift 6 with Swift 5 language mode and a macOS 15 minimum target. It does not
link the app UI or the scoring core.

The checks cover streaming MIDI parsing, running status, packet boundaries,
realtime and system messages, velocity-zero filtering, source discovery, a
300-byte CoreMIDI packet, multiple packets, original timestamps, main-thread
delivery, disconnect and coalesced device reconnection. Virtual sources belong
to the test process and are disposed before exit.

The audio smoke check schedules its first click two seconds in the future and
stops during silent preroll. It validates engine startup, not audible click
timing, physical latency, or a connected drum kit. A missing audio device is
reported separately. Use an actual kit and listening path for calibration.

Passing the BigRusty manifest as argument 1 also checks all 80 decoded recordings,
velocity boundaries, distinct round-robin alternatives, disabled monitoring,
MIDI learn and connection guards, stale-event rejection, overlapping voices and
the 32-voice cap. Sample scheduling tests set monitor volume to zero. A virtual
MIDI strike must reach the sampler while main-thread UI delivery is deliberately
stalled. The printed three-pad queue timing measures software scheduling only.

Run from the repository root through `scripts/test-native.sh`, or compile these
three Swift files directly with the same target and SDK as the app build.
