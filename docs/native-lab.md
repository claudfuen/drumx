# Native Mac engineering lab

The first lab makes the timing path and focused practice loop playable on a Mac. It is a development prototype for one exercise, separate from the full-kit design study and the eventual production game renderer.

## Build and run

Use macOS 15 or later with a full Xcode installation. From the repository root:

```bash
bash scripts/build-macos-lab.sh
open .build/DrumxLab.app
```

The script builds for the current Mac's architecture, uses C++17 and Swift 5 language mode, and creates an ad-hoc-signed local application. This is not notarized public release packaging or a universal Mac binary.

If the lab is already open during a rebuild, quit it and reopen it to use the new executable.

Run the software checks with:

```bash
bash scripts/test-native.sh
```

The check runner exercises the C++ scoring core and native I/O behavior, including virtual MIDI. Its audio startup check does not measure audible click timing or physical drum latency. Test output, rather than this guide, establishes which checks passed in a particular environment.

## Play the exercise

1. Select a MIDI source, or leave the keyboard input selected.
2. Set a comfortable tempo. The lab starts at 96 BPM and offers 48 to 144 BPM.
3. Select Guided, Hidden bars or From memory, and choose whether to display L/R hints and Live timing.
4. Press Play. A one-bar click count-in precedes the four scored bars.
5. Play the backbeat: eighth-note hi-hat, snare on beats 2 and 4, kick on beats 1 and 3. Use Play again to retry after completion, or Esc/Stop to end early.

Keyboard input uses **A = hi-hat**, **S = snare**, **Space = kick**. A normal key strike uses velocity 108/127; holding **Shift** uses 48/127 for a softer strike. Click the playing surface if a text field still has keyboard focus. Keyboard input is useful for interaction checks; it does not reproduce the electronic kit's trigger or MIDI behavior.

The native rail reserves seven hand-instrument slots from the beginning, with a full-width kick bar. The fixed starter layout is hi-hat, crash, snare, tom 1, tom 2, floor tom and ride. Unused surfaces keep their positions. The current exercise generates and scores only hi-hat, snare and kick; the visible tom, crash and ride slots do not mean those instruments are implemented in the scoring core. An editable visual kit layout is future work.

## Connect a kit

Select the kit's CoreMIDI input. The starter map accepts hi-hat notes 42/44/46, snare 38/40 and kick 35/36. These are broad starter groups rather than a verified profile for a particular Alesis module, and they collapse articulations within the three scored surfaces.

Before a take, click an instrument's mapping button and strike that pad once to learn its note. This replaces that instrument's starter group with the learned note and removes that note from the other groups. Mapping and the manual input offset are saved locally. Mapping does not change the drum module's own configuration.

The input offset is a signed number of milliseconds subtracted from captured input time before scoring. It corrects an assumed fixed alignment difference. It does not measure latency, remove jitter or establish that the player's habitual timing should be corrected.

## Audio

The app generates a native quarter-note click. Use the kit module for the instrument's sound when app monitoring is disabled, with an appropriate listening route for hearing both the module and the app. USB MIDI alone does not carry the module's audio.

The lab includes an optional native sampler for app-generated hi-hat, snare and kick monitoring. Enable **Drum sound** and set its **Volume** before a take. These controls are independent from the click and scoring; turn Drum sound off when listening to the module's own drum sounds.

The bundled starter set comes from [Big Rusty Drums](https://shop.karoryfer.com/pages/free-big-rusty-drums) under [CC0](https://github.com/sfzinstruments/karoryfer.big-rusty-drums/blob/f07ce00df34a46b6b08375be56fe116cf15782bc/LICENSE): 24 original mono 44.1 kHz/16-bit FLAC recordings of closed hi-hat, snare and kick, with four velocity layers and two recorded alternates per layer. See the retained [license](../native/assets/BigRusty/LICENSE), [manifest](../native/assets/BigRusty/manifest.json) and [provenance](../native/assets/BigRusty/provenance.json).

Keyboard and MIDI monitoring use the same sample selection and playback path. The MIDI module's reported velocity selects a sample layer; it is not a measurement of physical technique or a graded dynamics target. The two recorded takes alternate within each instrument's velocity layer. The samples are preloaded, with no file loading for each strike.

MIDI sound triggering bypasses the main/UI thread and uses a dedicated serial audio-control queue with a pool of 32 AVAudioPlayerNode voices. The sampler admits at most 128 queued trigger requests and discards requests that have waited longer than 100 ms. Those are bounded-load policies, not latency guarantees. Keyboard event delivery still begins on the AppKit main thread before entering this sampler.

The sampler is independent of the click engine. A reported latency estimate for the click does not measure the monitor's MIDI-to-output path. Sample loading and asset hash checks do not establish listening quality, acoustic balance or actual-kit responsiveness; those evaluations remain to be done.

The sampler does not add a backing track or an automatic drum demonstration. It is the sound of incoming strikes. Preserve the source and licensing records with any distributed sample assets.

## Assistance and independent checks

| Condition | Visible guidance |
| --- | --- |
| Guided | The full note highway |
| Hidden bars | Alternate bars with their targets removed, marked From memory; the beat scaffold continues |
| From memory | Static rail geometry with no target notes or moving beat scaffold |

Live timing is an optional teaching aid. With it enabled, the recent early/late display and live results provide correctness feedback, including during memory practice. For a stricter click-only check, choose **From memory** and turn **Live timing off** before starting. Results appear after the phrase; the app may still acknowledge an actual incoming strike without revealing whether it matched a target. Treat these aid conditions separately when comparing attempts.

L/R hints suggest a sticking pattern. They do not identify which hand actually struck the snare. Velocity is retained as normalized input data, not graded as physical technique. The lab does not yet maintain separate player profiles, a progression history or retained-skill records.

## Implementation and limits

- **Swift/AppKit** owns the Mac window and current practice drawing.
- **CoreMIDI** captures MIDI and preserves source timestamps. A missing source timestamp uses callback arrival time and is counted separately.
- **AVAudioEngine** owns the click's native audio render path. Its reported pipeline latency is an estimate, not a physical measurement.
- **C++17** owns the deterministic exercise and score through a C interface. Matching uses a maximum ±125 ms window and reports early/late offsets, omissions and extra strikes. An individual hit receives the centered judgment within ±25 ms; the separate timing-accuracy metric counts matches within ±50 ms. These are prototype rules, not scientific mastery thresholds.

Scoring is currently delivered on the main thread using preserved timestamps. That supports correct matching after a delay, but does not prove that feedback remains prompt during a UI stall. No measured end-to-end latency, frame-rate guarantee, actual-kit compatibility certification or Windows performance claim is made.

Still ahead: a lesson library, profiles and saved progression; full-kit scored exercises; backing tracks and demonstrations; the final game renderer; Windows platform layers; and release-quality packaging. The proposed two-floor cymbal/drum layout remains a comparison to evaluate. One shared timing plane is the current baseline.
