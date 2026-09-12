# drumx

A free desktop drum trainer for MIDI electronic drum kits, starting on macOS with a future Windows version in mind. The direction combines structured learning, satisfying rhythm-game play and practice that gradually removes the visible guide.

The repository now contains a **native Mac engineering lab**: a four-bar hi-hat, snare and kick exercise with a click count-in, MIDI mapping, keyboard input, optional drum-sample playback and timestamp-based scoring. Guided, Hidden bars and From memory use the same exercise and scoring core. Optional sticking hints and live timing feedback help explore how much assistance to show.

The lab uses Swift/AppKit, CoreMIDI and AVAudioEngine with a portable C++17 scoring core. It establishes the first playable direction; it does not select the production renderer or demonstrate measured latency. The full-kit visual study and this engineering lab are different prototypes.

## Run the Mac lab

Requires macOS 15 or later and a full Xcode installation. The build uses Swift 5 language mode and targets the architecture of the current Mac.

```bash
bash scripts/build-macos-lab.sh
open .build/DrumxLab.app
```

Choose a MIDI source, or use **A** for hi-hat, **S** for snare and **Space** for kick. Hold **Shift** for a softer keyboard strike. **Esc** stops the take. See [the lab guide](docs/native-lab.md) for mapping, audio, feedback conditions and current limitations.

Run the native checks separately:

```bash
bash scripts/test-native.sh
```

These checks cover software behavior; they do not measure pad-to-sound or pad-to-display latency.

## Product work still ahead

Separate player profiles, a course and lesson library, saved progression, backing tracks, full-kit exercises, Windows support and public release packaging are still planned. Velocity is retained as input data in the lab, rather than graded as technique. Free public distribution remains the intended product model.

- [Product pitch: keep the groove when the notes disappear](docs/pitch.md)
- [Native lab: run, connect and evaluate](docs/native-lab.md)
- [Product approaches, shipped precedents and stack research](docs/product-research.md)
- [Architecture options and latency validation plan](docs/architecture-options.md)
- [Introductory curriculum draft](docs/curriculum.md)
- [Framework-independent lesson data draft](docs/lessons-draft.json)
