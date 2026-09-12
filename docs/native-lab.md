# Play the first backbeat

The current Mac prototype has one complete practice path: learn the counts, hear a demonstration, play a short take, review it, and choose what to try next. It is the first playable lesson, separate from the broader curriculum draft and future production renderer.

## Build and run

Use macOS 15 or newer, a full Xcode installation, and Python 3. From the repository root:

```sh
bash scripts/build-macos-lab.sh
open .build/DrumxLab.app
```

The script uses C++17 and Swift 5 language mode, builds for the current Mac's architecture, and creates an ad-hoc-signed local app. It does not produce a universal or notarized release. Quit and reopen the lab after rebuilding to use the new executable.

## Your first five minutes

1. **Learn the pattern.** The opening page shows one original bar of drum notation with counts: eighth-note hi-hat, snare on 2 and 4, kick on 1 and 3. Count `1 & 2 & 3 & 4 &`; say `&` as “and.” This is a backbeat groove, not a named rudiment.
2. **Hear the groove.** Listen to four bars at the selected tempo after a four-beat count-in. The demonstration is scheduled on the native audio path and is not scored or saved as your playing.
3. **Start playing.** Follow the same count-in, then play four scored bars. The default is 96 BPM; the lesson offers 48 to 144 BPM. At 96 BPM the scored phrase lasts ten seconds.
4. **Read the review.** See an on-time score, hits, misses, extras, and a short next step. Try again, reduce tempo, or isolate the repeated bar.
5. **Remove an aid.** Move from Guided to Hidden bars, then try a click-only phrase. Repeat for a few minutes rather than chasing a speed target.

There is no five-minute session timer. Each attempt is a short, finite phrase.

### Review actions

| Action | What happens |
| --- | --- |
| Play again | Repeat the current phrase length and conditions. |
| Slow it down | Reduce tempo by 8 BPM, down to the 48 BPM minimum, and begin a new take. |
| Work on one bar | Start one guided bar of the same repeating groove. This is a single attempt, not an endless loop or an automatically selected error bar. |
| Back to four bars | Return from one-bar practice to the full phrase. |
| Hide a phrase | Start four bars with alternate bars hidden. |
| Try click-only | Start From memory with live timing off. |
| Lesson | Return to the preparation page. |

### Keyboard controls

**A = hi-hat**, **S = snare**, **Space = kick**, **Shift + key = softer hit**, **Enter = start/retry**, **Esc = stop or close setup**. Normal strikes use MIDI velocity 108 and softer strikes use 48. If a text field has focus, finish editing and close the setup sheet before playing.

With a MIDI source selected, keyboard keys preview sounds but do not contribute to the kit’s score. Choose Keyboard / no MIDI input to score keyboard practice.

Keyboard practice exercises the interaction and scoring path. A physical kit also introduces its own trigger scanning and MIDI transport.

## Connect your kit

Open **Kit & sound** before a take. Choose the kit's CoreMIDI source, then play each pad to confirm its identity and sound. Settings stay out of the playing screen.

The starter groups are hi-hat notes **42/44/46**, snare **38/40**, and kick **35/36**. These are general starting mappings, not a certified profile for any particular drum module. They collapse those articulations into three surfaces and three sounds.

To learn a mapping, click the instrument's mapping button and strike that pad once. This replaces its current group with the learned note and removes that note from other groups. Mapping changes stay inside Drumx; they do not reconfigure the module.

The rail reserves stable positions for hi-hat, crash, snare, tom 1, tom 2, floor tom, and ride. Kick uses a full-width bar on the same timing plane. Only **hi-hat, snare, and kick** currently generate scored targets and app sounds. The other positions are reserved, and an editable kit layout remains future work.

### Input offset

The signed input offset in milliseconds is subtracted from captured input timestamps before scoring. Positive values shift recorded hits earlier; negative values shift them later. It stays fixed throughout a take. Use it for a known alignment difference, not to compensate automatically for a player's tendency to rush or drag.

An offset does not measure physical latency or remove jitter. Mapping, input offset, and the drum-sound preference are saved locally.

## Listen through the app or your module

**Drum sound** enables the app's acoustic monitoring. Use its volume control for monitoring and the lesson demonstration. Disable Drum sound if you listen to the drum module's own sounds; the explicit **Hear the groove** demonstration remains available.

To use the module's sounds, arrange a listening route that lets you hear both the module and Drumx's click. USB MIDI alone does not carry the module's audio.

The bundled [Big Rusty Drums](https://shop.karoryfer.com/pages/free-big-rusty-drums) starter set contains 24 original mono 44.1 kHz/16-bit FLAC files: four recorded velocity layers and two alternate takes each for closed hi-hat, snare, and kick. Source files are unchanged and released under CC0. The [asset guide](../native/assets/BigRusty/README.md), [license](../native/assets/BigRusty/LICENSE), and [provenance](../native/assets/BigRusty/provenance.json) travel with the sounds.

The sampler preloads the recordings. Live MIDI monitoring bypasses the main thread and uses a dedicated serial queue with a 32-voice pool. The four-bar demonstration is prepared as audio and scheduled on the native audio clock, rather than triggering its notes from display frames. These are implementation choices to test on hardware, not published latency results.

## Choose your assistance

| Condition | Guidance while playing |
| --- | --- |
| Guided | All target notes and the beat scaffold are visible. |
| Hidden bars | Alternate bars lose their targets; the beat scaffold continues. |
| From memory | No target notes or moving beat scaffold. |
| From memory + Live timing off | Click-only attempt with evaluation shown after the phrase. |

Live timing displays a recent early/late tendency for each instrument after enough matching hits. Old or uneven evidence is labeled instead of claiming a steady tendency. An incoming-hit flash acknowledges your own action; it does not reveal an upcoming target. The listening demonstration shows the groove even when a memory mode is selected.

R/L prompts are sticking suggestions. A normal snare MIDI note identifies an instrument or zone, not which hand played it. Module velocity helps choose a sound layer; it does not verify grip, rebound, posture, accents, or foot technique. See the [curriculum](curriculum.md) for how timing, reading, recall, and technique checks fit together.

## Scores and saved attempts

The **on-time score** counts matched hits within ±50 ms, divided by matched hits plus misses plus extras. An additional strike can lower the score. Targets must match the expected instrument; simultaneous hi-hat and kick are independent targets.

The maximum matching window is ±125 ms. Opening hi-hat and kick targets also accept the 125 ms early window before the first scored beat; the earlier count-in remains unscored. The core's tighter centered judgment is ±25 ms, separate from the on-time percentage.

Natural completions are saved locally, up to **200 attempts**. Takes stopped before the phrase ends and canceled count-ins do not set personal bests. One-bar and four-bar attempts are separate comparisons. Other matching conditions include tempo, guidance mode, live feedback, hand hints, fixed calibration, input identity, pad mapping, and lesson version. Ranking uses on-time percentage, then hit rate, then mean absolute timing error.

Captured MIDI can arrive after a display update or the end of a take. The core can correct an expired miss using the original timestamp, and history updates the existing attempt instead of creating a duplicate. There are no separate player profiles or cloud synchronization yet.

## Troubleshooting

| Symptom | Check |
| --- | --- |
| Build cannot find the SDK or Swift modules | Install and open full Xcode. The script automatically selects `/Applications/Xcode.app`; for another location, run it with `DEVELOPER_DIR=/path/to/Xcode.app/Contents/Developer`. |
| Samples are missing | Run `python3 scripts/fetch-samples.py`, then rebuild. The fetcher restores missing originals and verifies pinned hashes. It refuses altered files rather than silently replacing them. |
| The app looks unchanged after building | Quit the running app and reopen `.build/DrumxLab.app`. |
| MIDI input is absent | Confirm that macOS sees the module, check its cable and power, then reopen Kit & sound and select the source. |
| The wrong instrument responds | Learn that pad's MIDI note in Kit & sound. The starter groups are broad aliases. |
| MIDI lights respond but you hear no drums | Enable Drum sound and check volume and the Mac output. If using module audio, check its separate listening route. |
| You hear two drum sounds per strike | Choose app monitoring or module monitoring rather than hearing both paths. |
| A take stops when a device changes | Check the selected input and audio output, then start a fresh count-in. |
| Timing looks consistently shifted | Check the listening route and fixed input offset. Compare a repeatable setup before changing calibration. |

For timing or audio reports, include macOS version, module and connection, output device, monitoring choice, tempo, offset, and a repeatable example. Physical pad-to-sound and pad-to-display measurements are especially useful.

## Verify and explore

```sh
bash scripts/test-native.sh
```

The checks cover the portable scoring core, MIDI parsing and virtual input, sample integrity, native audio/demo behavior, lesson review/history, signed count-in travel, shared projection, and capture-time boundaries. Audio startup is not a measurement of audible output timing. Test output establishes what passed in a particular environment.

The current renderer is AppKit. The [rendering plan](rendering-plan.md) describes the next experiment; [architecture options](architecture-options.md) and [product research](product-research.md) retain the rationale. Scoring currently runs on the main thread with preserved input timestamps. That protects timestamp-based grading after a stall, while visible feedback can still arrive late.

Still ahead: the expanded course, retained-skill progression, profiles, full-kit scoring and articulation, musical backing tracks, production rendering, Windows platform layers, and public release packaging. The current first lesson is a groove; the named-rudiment course remains a [draft](curriculum.md).
