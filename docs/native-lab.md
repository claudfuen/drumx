# Play the foundation course

The Mac prototype now connects welcome and local players to a 12-lesson foundation unit: hear, count, read, play, review, and resume. **M1 remains active.** The integrated experience needs validation with a real beginner and physical kit; hardware latency and sustained frame pacing are still unmeasured. See the [milestone checklist](learning-milestones.md#m1-one-complete-beginner-learning-loop).

## Build and run

Use macOS 15 or newer, a full Xcode installation, and Python 3. From the repository root:

```sh
bash scripts/build-macos-lab.sh
open .build/DrumxLab.app
```

The script uses C++17 and Swift 5 language mode, builds for the current Mac's architecture, and creates an ad-hoc-signed local app. It does not produce a universal or notarized release. Quit and reopen the lab after rebuilding to use the new executable.

## Your first five minutes

1. **Choose your player.** Enter a local player name on the welcome page. Set up a MIDI kit or use the keyboard; check the responding instruments in **Kit & sound**.
2. **Start with Find the pulse.** The course home groups the lessons into three chapters. **Continue** opens your selected lesson. Read its objective, original one-bar staff study, and counts, then hear the demonstration.
3. **Play a short take.** Choose a comfortable tempo between 48 and 144 BPM and a phrase of **1, 4, or 8 bars**. Each lesson repeats its authored bar after a four-beat count-in. The first completed pulse attempt supplies a baseline comparison; it does not automatically assign a skill level.
4. **Review and check understanding.** See points, stars, hits/misses/extras, and a next practice action. Answer the lesson's three-choice reading question and use the explicit technique self-check after considering its tip.
5. **Try less help, then return.** Choose Hidden bars or a click-only take when the pattern feels familiar. Use the next-lesson action or return to the course. Reopening resumes the selected player's lesson and saved practice settings.

There is no five-minute session timer. Each attempt is a short, finite phrase. Four bars at 60 BPM last 16 seconds, plus the count-in; at 96 BPM they last ten seconds.

## What is in this unit

| Chapter | Four original lessons |
| --- | --- |
| Pulse and counts | Find the pulse; Find the and; Give silence its beat; Bring in the bass drum. |
| Build your backbeat | Hand meets foot; Add the backbeat; Your first backbeat; Give the groove more space. |
| Read, vary, and remember | Let your hands take turns; Kick on the and; Keep counting through a gap; Groove into a fill. |

These lessons introduce quarter/eighth notes, rests, simultaneous instruments, a backbeat, a variation, and a short fill. They are all browsable. Scores and reading answers do not lock the next lesson. The named-rudiment course remains a [proposal](curriculum.md).

The estimates total **96 suggested practice minutes**, spread across repetitions, comfortable tempos, phrase lengths, and attempts with less guidance. They are not 96 minutes of unique recordings, a timed course, or a promise of how quickly a player will learn.

Each lesson's audio demonstration, scoring targets, and original notation use the same versioned events in [DrumxCourse.swift](../native/macos/DrumxCourse.swift). A bar always lasts four quarter-note beats, including its silent portions. The demonstration is not scored or saved as the player's performance.

### Local players and progress

Create or rename local players to keep each person's attempts, checks, and resume position separate. Renaming preserves their history. Profiles stay on this Mac; deletion and cloud synchronization are not provided. On upgrade, the first player adopts the original local history instead of copying it into every profile.

Resume records the lesson ID/version, tempo, guidance mode, live timing choice, and phrase length. The kit's input source is remembered when available; mappings, offset, drum sound, volume, and sticking-hint preferences are saved locally. Check the actual input before playing on a changed setup.

Course labels describe evidence for the current lesson version: **Practised** requires a saved completed attempt with at least one matched hit; **Reading checked** records a correct reading answer; **Recall tried** requires such an attempt in From memory with Live timing off. They do not mean mastered, recalled on another day, or technique verified. The technique checkbox is explicitly the player's self-report. [Learning gates](learning-milestones.md#readiness-is-separate-from-the-game-score) define the broader readiness questions.

### Review actions

| Action | What happens |
| --- | --- |
| Play again | Repeat the current phrase length and conditions. |
| Slow it down | Reduce tempo by 8 BPM, down to the 48 BPM minimum, and begin a new take. |
| Work on one bar | Start one guided bar of the selected exercise. This is a single attempt, not an endless loop or an automatically selected error bar. |
| Back to four bars | Start four guided bars after one-bar practice. |
| Hide a phrase | Start with alternate bars hidden, keeping the current four or eight bars. One-bar practice expands to four bars. |
| Try click-only | Start From memory with live timing off. |
| Lesson | Return to the preparation page. |
| Next lesson | Open the next exercise, or return to the course after the final lesson. |

### Keyboard controls

**A = hi-hat**, **S = snare**, **Space = kick**, **Shift + key = softer hit**, **Enter = start/retry**, **Esc = stop or close setup**. Normal strikes use MIDI velocity 108 and softer strikes use 48. If a text field has focus, finish editing and close the setup sheet before playing.

With a MIDI source selected, keyboard keys preview sounds but do not contribute to the kit’s score. Choose Keyboard / no MIDI input to score keyboard practice.

Keyboard practice exercises the interaction and scoring path. A physical kit also introduces its own trigger scanning and MIDI transport.

## Connect your kit

Open **Kit & sound** before a take. Choose the kit's CoreMIDI source, then play each pad to confirm its identity and sound. The source menu identifies the input route; each pad shows **waiting** or **received** for that selected input. Keyboard sound previews do not mark a pad received while a MIDI source is selected. Settings stay out of the playing screen.

The starter groups are hi-hat notes **42/44/46**, snare **38/40**, and kick **35/36**. These are general starting mappings, not a certified profile for any particular drum module. They collapse those articulations into three surfaces and three sounds.

To learn a mapping, click the instrument's mapping button and strike that pad once. This replaces its current group with the learned note and removes that note from other groups. Mapping changes stay inside Drumx; they do not reconfigure the module.

The rail reserves stable positions for hi-hat, crash, snare, tom 1, tom 2, floor tom, and ride. Kick uses a full-width bar on the same timing plane. Only **hi-hat, snare, and kick** currently generate scored targets and app sounds. The other positions are reserved, and an editable kit layout remains future work.

### Input offset

The signed input offset in milliseconds is subtracted from captured input timestamps before scoring. Positive values shift recorded hits earlier; negative values shift them later. It stays fixed throughout a take. Use it for a known alignment difference, not to compensate automatically for a player's tendency to rush or drag.

An offset does not measure physical latency or remove jitter. Mapping, input offset, and the drum-sound preference are saved locally.

## Listen through the app or your module

**Drum sound** enables the app's acoustic monitoring. Use its volume control for monitoring and the lesson demonstration. Disable Drum sound if you listen to the drum module's own sounds; the explicit **Hear the pattern** demonstration remains available.

To use the module's sounds, arrange a listening route that lets you hear both the module and Drumx's click. USB MIDI alone does not carry the module's audio.

The bundled [Big Rusty Drums](https://shop.karoryfer.com/pages/free-big-rusty-drums) starter set contains 24 original mono 44.1 kHz/16-bit FLAC files: four recorded velocity layers and two alternate takes each for closed hi-hat, snare, and kick. Source files are unchanged and released under CC0. The [asset guide](../native/assets/BigRusty/README.md), [license](../native/assets/BigRusty/LICENSE), and [provenance](../native/assets/BigRusty/provenance.json) travel with the sounds.

The sampler preloads the recordings. Live MIDI monitoring bypasses the main thread and uses a dedicated serial queue with a 32-voice pool. The selected lesson demonstration is prepared as audio and scheduled on the native audio clock, rather than triggering its notes from display frames. These are implementation choices to test on hardware, not published latency results.

## Choose your assistance

| Condition | Guidance while playing |
| --- | --- |
| Guided | All target notes and the beat scaffold are visible. |
| Hidden bars | Alternate bars lose their targets; the beat scaffold continues. |
| From memory | No target notes or moving beat scaffold. |
| From memory + Live timing off | Click-only attempt with evaluation shown after the phrase. |

Hidden bars uses four or eight bars. Selecting it during one-bar practice expands the phrase to four bars; choosing one bar while Hidden bars is selected switches to Guided.

### The bottom capture rail

Fixed receptors sit on the shared NOW line. Their shapes match the approaching drum and cymbal notes; the kick catcher spans the rail behind the hand targets. The kit shapes below this line remain spatial references, not additional targets.

Every mapped strike produces a local press/pulse, including unscored practice strikes. With Live timing on, a matched note disappears into its catcher and produces a brief capture effect. An extra hit produces a coral burst at that receptor. A capture means the note matched; it does not mean the hit was perfectly centered. The timing meter still shows early/late tendencies.

Simultaneous hits retain independent feedback. With Live timing off, all strikes use the same neutral response: capture and extra-hit effects cannot disclose the grade. Memory practice does not emit automatic missing-note effects. The audible demonstration animates unscored receptor presses in time with its scheduled notes. macOS Reduce Motion replaces traveling fragments with brief local illumination.

Live timing displays a recent early/late tendency for each instrument after enough matching hits. Old or uneven evidence is labeled instead of claiming a steady tendency. An incoming-hit flash acknowledges your own action; it does not reveal an upcoming target. The listening demonstration shows the exercise even when a memory mode is selected.

R/L prompts are sticking suggestions. A normal snare MIDI note identifies an instrument or zone, not which hand played it. Module velocity helps choose a sound layer; it does not verify grip, rebound, posture, accents, or foot technique. See the [curriculum](curriculum.md) for how timing, reading, recall, and technique checks fit together.

## Scores and saved attempts

The live header shows **points, five stars, current combo, and a previous comparable best**. It stays neutral during the count-in and demonstration. Turning Live timing off also hides points, stars, combo, and best until the review, so these cannot become extra correctness cues during click-only practice.

Points are `floor(10,000 × on-time hits / (whole-phrase targets + extra hits))`. On-time means within ±50 ms. Targets must match the expected instrument; simultaneous hi-hat and kick are independent targets. The denominator includes the whole phrase from its start, so one early hit cannot earn five stars. Extras can lower points; misses and off-time hits leave points unearned.

| Stars | Minimum points |
| --- | ---: |
| 1 | 4,000 |
| 2 | 6,000 |
| 3 | 7,500 |
| 4 | 9,000 |
| 5 | 10,000, after a validated complete take |

The fifth star requires every target on time, no misses or extras, and completion of the phrase. Live and interrupted scores stay below 10,000. This is perfection within the current timing band and practice condition, not literal zero timing error or demonstrated technique. These tiers are prototype game policy, separate from [learning gates](learning-milestones.md).

Combo counts consecutive on-time hits across instruments; an off-time hit, miss, or extra breaks it. There is no points multiplier. The review shows best combo, hits/misses/extras, previous best points, and up to six actual comparable takes in chronological order. Incomplete takes cannot claim a new or matched personal best and do not enter this comparison strip.

The maximum matching window is ±125 ms. Targets on the first scored beat also accept the 125 ms early window before it; the earlier count-in remains unscored. The core's tighter centered judgment is ±25 ms, separate from the on-time percentage.

Natural completions are archived locally per player, without the prototype's 200-take retention limit. The review displays only the last six comparable takes; personal bests use the whole archive. Takes stopped before the phrase ends and canceled count-ins do not set personal bests. One-, four-, and eight-bar attempts are separate comparisons. Other matching conditions include tempo, guidance mode, live feedback, hand hints, fixed calibration, input identity, pad mapping, and lesson version. Ranking uses on-time percentage, then hit rate, then mean absolute timing error.

The app stores its practice archives under `~/Library/Application Support/Drumx/org.drumx.timing-lab/History/`. First use adopts the retained legacy history while leaving the original preferences intact. Archive writes are atomic; an unreadable or invalid existing archive is preserved and saving is paused with an error, rather than replacing it. Profiles, resume settings, and dated course checks remain in local app preferences. None of this practice data is sent to GitHub or a cloud service.

Captured MIDI can arrive after a display update or the end of a take. The core can correct an expired miss using the original timestamp, and history updates the existing attempt instead of creating a duplicate, including corrections to points, stars, and best combo. Older saved backbeat attempts retain their lesson identity and receive points from their recorded counts; their missing best-combo data remains unknown. Dated practice/recall checkpoints persist separately from individual attempts and remain scoped to the player and lesson version.

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

The checks cover the portable scoring core, MIDI parsing and virtual input, sample integrity, native audio/demo behavior, lesson review/history, course-content contracts, local progress, course integration, signed count-in travel, shared projection, and capture-time boundaries. Audio startup is not a measurement of audible output timing. Test output establishes what passed in a particular environment; it does not substitute for an observed beginner using the whole app.

The current renderer is AppKit. The [rendering plan](rendering-plan.md) describes the next experiment; [architecture options](architecture-options.md) and [product research](product-research.md) retain the rationale. Scoring currently runs on the main thread with preserved input timestamps. That protects timestamp-based grading after a stall, while visible feedback can still arrive late.

Still ahead: validating the complete beginner journey and real-kit reliability, named rudiments, scheduled retention and transfer checks, full-kit scoring and articulation, musical backing tracks, production rendering, Windows platform layers, and public release packaging. Building the first foundation unit advances M1; it does not close the [remaining acceptance checks](learning-milestones.md#m1-one-complete-beginner-learning-loop).
