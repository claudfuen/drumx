# drumx

**Learn the groove. Keep it when the notes disappear.**

Drumx is a desktop trainer for real MIDI drum kits: the pull of a rhythm game, built around listening, counting, and learning to play without the screen.

The first playable lesson is **Your first backbeat**. Read its drum notation, hear the groove, then play four short bars. Keep the hi-hat moving, put the snare on 2 and 4, and gradually remove the guide.

**Current build:** one playable native macOS lesson. Free public distribution is the goal; the larger course, production renderer, and Windows version are still ahead.

[Run it](#quick-start) · [Current milestone](#current-milestone) · [Lesson guide](docs/native-lab.md) · [Changelog](CHANGELOG.md)

## Current milestone

**M0 achieved: the game mechanics and UI concept. M1 active: one complete beginner learning journey.**

The prototype established the shared timing line, stable kit layout, capture feedback, sound, guidance modes, and practice/review loop. We have an accepted concept to build on. Physical-kit latency, sustained frame pacing, and release readiness still need evidence.

Our next milestone is a player outcome: **a new drummer can connect their kit, learn a small foundation unit, try it with less help, and return knowing what to practise next.** The menu, settings, curriculum, and saved progress should make that journey feel like one focused experience.

**Quality bar: a small, finished game that could belong on Steam.** The first unit should feel deliberately designed from launch through the return visit: clear onboarding, cohesive visuals and sound, responsive play, satisfying feedback, and dependable recovery. This is an experience target, not a claim of Steam availability; free public distribution remains the goal.

| Milestone | Status | What the player gains |
| --- | --- | --- |
| **M0 · Mechanics and UI concept** | Achieved | Hear, play, capture, review, and retry a short backbeat on a consistent highway. |
| **M1 · Complete beginner journey** | **Working towards** | Set up, find a starting point, learn pulse/counts/backbeat in small steps, review, and resume. |
| **M2 · Rudiments and reading** | Planned | Learn named singles, doubles, and paradiddles through counts, notation, and coordination. |
| **M3 · Retention and independence** | Planned | Build on early memory checks with later revisits, targeted practice, and variations. |
| **M4 · Musical application** | Planned | Use the vocabulary in grooves, fills, dynamics, and intermediate coordination. |

### What closes M1

- [ ] **A confident first setup:** verify the kit's pads, sound route, and basic timing; recover clearly from a disconnected input.
- [ ] **A starting point for each player:** two local players can share a kit while keeping separate baselines and progress.
- [ ] **One coherent foundation unit:** teach pulse and counts, build the backbeat in manageable steps, and connect the sounds to real drum notation.
- [ ] **A useful learning checkpoint:** check counting/reading, repeat the pattern, and attempt it with less guidance. Keep technique self-checks separate from MIDI evidence.
- [ ] **An intentional next step:** review explains one useful adjustment and recommends practice or progression from the player's evidence.
- [ ] **A complete return journey:** close and reopen, resume the right player's work, and retain comparable attempts with their exercise version and aids.
- [ ] **A polished complete experience:** inspect launch, setup, lesson selection, count-in, play, review, retry, and return as one flow, including empty states, interruptions, readable feedback, reduced motion, and supported window sizes.
- [ ] **A reusable lesson foundation:** add the unit's exercises as versioned content using shared teaching, audio, notation, scoring, and progress systems. Verify their agreement without bespoke controller logic for every lesson.
- [ ] **An observed end-to-end run:** a beginner completes setup → lesson → practice → review → next step → return without developer intervention, including a documented real-kit session.

These checkboxes are acceptance criteria, not completed features. A bigger lesson list or five-star run alone does not close the milestone. Stars reward a take; learning gates describe readiness using timing, reading, recall, and the evidence MIDI cannot provide.

[Learning definitions and gates](docs/learning-milestones.md) specify the shared terms, evidence, and boundaries behind this roadmap. Reliability, accessibility, and distribution run alongside the learning milestones; a free public preview need not wait for the intermediate course. We close each milestone with a demonstrated journey, relevant checks, known limitations, and an updated README and changelog.

## A small lesson worth repeating

| You can do this now | What it teaches |
| --- | --- |
| **Hear the groove** | Listen to an acoustic drum demonstration and count `1 & 2 & 3 & 4 &`. |
| **Read, then play** | Connect a one-bar staff study and sticking suggestions to a shared timing line. |
| **Hide a phrase** | Alternate guided and hidden bars, then try a click-only take. |
| **Catch the note** | Fixed bottom receptors react to every strike, capture matched notes, and distinguish extra hits when live feedback is on. |
| **Make one adjustment** | Review hits, misses, extras, and recent early/late tendencies; retry slower or work on one bar. |
| **Beat a comparable result** | Complete takes are saved locally; personal bests compare matching settings and aids. |
| **Use your own kit** | Select a MIDI input, learn pad mappings, and choose app sounds or your module's sounds. |

The lesson plays **hi-hat, snare, and kick**. Seven stable hand-instrument positions and a full-width kick bar establish the visual layout; the other kit positions are reserved for future exercises.

## Quick start

Requires **macOS 15+**, **full Xcode**, and **Python 3** as `python3`. The script selects `/Applications/Xcode.app` when present and builds for your Mac's architecture. Command Line Tools alone are not supported.

```sh
git clone https://github.com/claudfuen/drumx.git
cd drumx
bash scripts/build-macos-lab.sh
open .build/DrumxLab.app
```

No MIDI kit is required to try the lesson:

1. Choose **Hear the groove** and count along.
2. Select a comfortable tempo, choose **Start playing**, and come in after the four-beat count-in.
3. Read the review. Try **Play again**, **Slow it down**, or **Work on one bar**.
4. When the groove feels familiar, choose **Hide a phrase**, then **Try click-only**.

Spend five minutes repeating these short takes. This is not a timed five-minute lesson: a four-bar take lasts ten seconds at the default 96 BPM, plus the count-in.

| Control | Action |
| --- | --- |
| **A** | Hi-hat |
| **S** | Snare |
| **Space** | Kick |
| **Shift + key** | Softer strike |
| **Enter** | Start or retry a take |
| **Esc** | Stop playing or listening; close setup |
| **Kit & sound** | MIDI input, pad mapping, sound, volume, sticking hints, and input offset |

For a physical kit, open **Kit & sound**, choose its MIDI source, and check each pad before playing. The [lesson guide](docs/native-lab.md) covers setup and sound routing.

## Sound and timing

The acoustic kit has **24 recorded hits: four velocity layers and two alternate takes per instrument**, from Karoryfer's Big Rusty Drums, bundled under CC0 with [license and provenance](native/assets/BigRusty/README.md).

Audio and grading follow captured time. Drawing presents the result.

```mermaid
flowchart LR
  MIDI[CoreMIDI hit timestamps] --> Score[C++ scoring core]
  Keys[AppKit key timestamps] --> Score
  MIDI --> Sampler[Native acoustic sampler]
  Keys --> Sampler
  Clock[Shared host-time reference] --> Audio[Native click and demo]
  Clock --> View[AppKit lesson and rail]
  Score --> View
```

The click and demo use native audio scheduling. MIDI monitoring bypasses the UI thread. Scoring retains captured timestamps, so a slow frame can delay feedback without becoming the player's timing error.

The stack is **Swift/AppKit + CoreMIDI + AVAudioEngine**, with a **portable C++17 core and C interface**. Physical latency and sustained frame pacing still need hardware measurements. See the [rendering plan](docs/rendering-plan.md) for the next experiment; the production engine remains undecided.

## Development

```sh
bash scripts/test-native.sh
```

The native checks exercise scoring boundaries, simultaneous notes, late input, MIDI parsing and virtual input, sample integrity, audio/demo behavior, projection and count-in continuity, and comparable lesson history. They validate software behavior, not physical pad-to-sound latency.

Start with the [scoring interface](native/core/drumx_core.h), [lesson controller](native/macos/DrumxLab.swift), [practice drawing](native/macos/PracticeView.swift), or [review/history model](native/macos/DrumxLesson.swift).

See [troubleshooting](docs/native-lab.md#troubleshooting) for setup help. Builds are locally ad-hoc signed; quit and reopen after rebuilding. There is no notarized release download yet.

## Where this goes next

The active focus is **M1, the complete beginner journey**, using the accepted mechanics as its foundation. Real-kit validation and rendering work support that journey. The broader course remains a draft.

- [Learning definitions and gates](docs/learning-milestones.md): the milestone contract and evidence for progression.
- [Product pitch](docs/pitch.md): the learning experience and its scope.
- [Curriculum](docs/curriculum.md) and [lesson data draft](docs/lessons-draft.json): real drum language and planned progression.
- [Product research](docs/product-research.md): learning tools, rhythm games, and their tradeoffs.
- [Architecture options](docs/architecture-options.md) and [rendering plan](docs/rendering-plan.md): engineering choices and experiments.

See [working instructions](AGENTS.md) for the milestone and documentation workflow. Prefer small, playable milestones with relevant checks. Bug reports should include macOS version, input/module, settings, and reproduction steps. Timing proposals should explain what was measured and how.

## Licensing

A project-wide source-code license has not been selected yet. The bundled Big Rusty samples have their own **CC0** license, retained with the assets. External research links and PAS references do not grant redistribution rights to their charts, recordings, or song content.
