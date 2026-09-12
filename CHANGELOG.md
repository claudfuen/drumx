# Changelog

A record of playable milestones and product decisions. These entries describe repository changes, not published binary releases.

## 2026-09-12

### Share the first tempo-coaching policy

- Add one deterministic C evaluator for Find the pulse: 60/66/72 BPM preparation, an exact 72 BPM checkpoint, guided-to-hidden-to-click-only recommendations, and separate optional faster paces.
- Distinguish a suggested next pace from repeatable evidence. Qualifying takes require at least 16 bars, 95% coverage, 90% on-time targets, and at most 2% extras; two qualifying among three comparable takes earn a checkpoint. These are initial product rules for learner testing.
- Keep source, mapping, monitoring, calibration, phrase length, and assistance groups separate. Recompute corrected attempts without discarding earned evidence after an ordinary difficult take.
- Verify 244 tempo checks under sanitizers, 852 existing scoring checks, the C consumer, and 34 Godot binding checks. UI integration and visual acceptance follow separately.

### Define guided tempo as part of learning

- Document a proposed M1 coaching slice: lesson-authored starting paces and checkpoints, bounded recommendations, optional tempo challenges, and manual free practice.
- Separate a suggested next pace from earned repeatable control, tempo-specific lesson evidence from stars, and guided performance from recall. Preserve existing access and avoid changing tempo during a phrase.
- Record current any-tempo unlock limitations, cross-platform evaluator requirements, evidence gaps, and learner-testing hypotheses. No runtime tempos, scores, unlocks, or saves change in this milestone.

### Restore the lesson-screen hierarchy

- Carry the original featured lesson and connected path into the shared interface, with distinct recorded-star and future-goal states plus specific practice/reading lock requirements.
- Replace the hit grid with the original five-line drum staff, upper/lower voices, rests, beams, counts, and instrument key. Verify 206 event/voice semantics checks across all 12 lessons and unsupported inputs.
- Collapse practice controls, restore one-bar repair, show compact result stars and recent comparable takes, and move reading questions into a separate focus-contained overlay. Keep new lessons guided at 16 bars and prevent hidden-bar labels on a fully visible one-bar repair.
- Match the original Mac window's dark appearance without changing its content geometry. Keep platform-specific appearance outside the shared game layout.
- Pass 7,717 source and exported-app checks on both macOS and Windows in hosted CI, including live per-page polling, minimum-size layout, quiz focus isolation, and partial-take progression boundaries. Verify the clean same-commit pair and link test artifacts from the README. Learn and dark chrome were inspected in the exported Mac app; final inspection of restored preparation/review remains pending.

### Recover the shared presentation before release

- Correct physical-pixel versus logical-point sizing on Retina displays; preserve the original Mac menu composition, typography, and detailed percussion artwork in the shared renderer.
- Restore the native four-beat projection, stable seven-slot layout, note silhouettes, horizon fade, capture rail, and compact scoring. Compare 4,305 geometry and shape values against fixtures generated from the original Swift implementation, including inside exported release builds.
- Replace the experimental settings form with custom kit, sound, playing, and progress sections. Keep missing platform features explicit rather than substituting unimplemented controls.
- Add paired Mac/Windows build, native checks, package execution, asset/license verification, and artifact integrity checks to CI. Disable automatic public publication while the shared experience remains under review.
- Inspect the corrected exported Mac menu, settings, count-in, gameplay, and Escape pause. Keep the native Mac app primary; lesson preparation, review, physical Windows MIDI/audio, and complete visual acceptance remain open.

### Deterministic Windows resource checkout

- The first hosted Mac export passed. The Windows job caught checkout newline conversion in the pinned font license before packaging. Preserve LF text resources and decode engine logs as UTF-8 on both hosts; keep exact-byte verification enabled.

### Native foundations for a shared desktop app

- Add an experimental Godot native bridge around the existing scorer, with CoreMIDI and WinMM capture, native sample playback, a metronome independent of rendering, bounded observations, and explicit connection generations.
- Keep the same 24 recorded samples, velocity layers, and original capture-time scoring. Include pinned dependency licenses and document timestamp resolution, audio-clock assumptions, and unmeasured physical latency.
- Verify the Mac native build with 46 backend checks and a real CoreMIDI software-loopback test. Windows application execution remains pending.
- Retain the committed Mac interface as the visual baseline. The first shared presentation failed review; a native build passing its checks does not establish visual parity or authorize public release.

### Settle into practice and play from the kit

- Make the main menu and lesson path respond to the available window size, with one featured lesson, a connected 12-step path, and personal-best stars.
- Start lessons at their suggested tempo with 16 bars of continuous practice. Keep tempo, length, and guidance in optional practice controls; migrate the old four-bar default without replacing explicitly saved new choices.
- Replace the mapping form with a visual three-pad kit, live MIDI note/velocity feedback, additive articulation mapping, and per-connection input checks. Unmapped notes and disconnects have explicit recovery paths.
- Add opt-in drum navigation for the main menu, preparation, review, and pause: hi-hat previous, snare next, double kick choose. Preserve original MIDI capture timestamps and guard against stale hits and accidental repeats.
- Validate the complete native suite, responsive geometry at five window sizes, and the isolated app with a virtual CoreMIDI source, including additive aliases, disconnect recovery, welcome routing, and Escape during practice.

### A portable core checked on both platforms

- Add CMake builds, a true C-language API consumer, and CTest contracts for the existing scoring engine.
- Run Debug/Release builds on macOS and Windows in GitHub Actions, with a separate Mac sanitizer job. All five hosted jobs pass the scoring and C-consumer contracts.
- Document clock, MIDI, audio, rendering, storage, display scaling, and packaging risks before committing the production interface. The current app remains Mac-only.

### A game menu and an explorable foundation journey

- Give the app a distinct main menu with Continue, Learn, Settings, keyboard selection, and original percussion artwork. Replace the chapter tabs with illustrated chapter cards and connected lesson steps.
- Show lesson locks and their requirements, keep future chapters browsable, and connect qualifying practice and reading checks to the next-lesson action. Existing players retain their reached lessons.
- Add a full settings page for kit mapping, sound, playing preferences, and local players/progress. Give sliders, toggles, and selectors a consistent Drumx appearance while retaining AppKit input and accessibility behavior.
- Make Back and Main menu explicit. Escape returns home from lesson/menu pages and opens a pause menu during practice; interrupted takes restart with a count-in and never set records. A take that already finished keeps its completed review.
- Commit pending timing edits when leaving settings or quitting, and prevent setup navigation from replacing unreadable progress with a fallback profile.
- Document a durable menu hierarchy and a production-engine decision gate before broader curriculum expansion. Swift/AppKit remains the Mac shell; it is not a shared Windows UI.

### Evidence-based beginner unlock model

- Add a tested progression model: four or more bars with at least 80% of notes matched opens the next lesson; chapter boundaries also require the preceding reading check. Timing stars remain a separate challenge.
- Preserve previously reached lessons without converting old practice into new clearance. Keep player and content-version evidence separate, reject invalid attempts, and exclude stopped takes and demonstrations through archive admission.
- Verify all 12 lesson transitions, exact thresholds, reading gates, migration, and profile isolation in 104 dedicated checks.

### A playable foundation journey

- Connect a first-launch welcome, local player selection, a focused three-chapter course menu, and all 12 foundation lessons to the existing practice stage.
- Generate notation and authored R/L hints from each lesson's events. Offer listening, 1/4/8-bar takes, tempo and guidance choices, a reading question, and an explicit technique self-check.
- Save the selected player's lesson and practice settings, show separate practice/reading/recall evidence, and add a next-lesson route from review.
- Remember the selected MIDI source when available and show receipt checks for the selected input's pads.
- Archive all completed takes per player, preserve retained legacy scores, and keep dated course checkpoints. Invalid archives remain intact with saving paused.

### A reusable foundation course and local player model

- Author 12 original lessons in three chapters, with shared event data, explanations, counts, reading questions, and technique tips.
- Extend the portable core with validated custom charts and the native demo renderer with authored patterns. Verify event and sample timing agreement across the full unit.
- Add separate local players, versioned practice resume, welcome state, and explicit reading/technique evidence while preserving legacy history ownership.
- Give perfect sparse one-bar takes positive coaching. Add core, course, player, and audio/scoring integration checks.

### Stars, combos, and comparable runs

- Add a compact live five-star score and combo, a 10,000-point complete-phrase target, and progress toward the next star.
- Review the take alongside the previous comparable best and up to six recent matching attempts; preserve hits, misses, extras, coaching, and best combo.
- Require a complete, all-on-time take with no misses or extras for five stars. Hide live scoring during count-in, demonstration, and feedback-off practice; stopped takes cannot claim personal bests.
- Preserve legacy local history and update the same saved take when captured MIDI corrects its result. Add score boundary, completion, history, and correction checks.

### A finished beginner experience as the quality bar

- Add a commercial-quality experience target to M1: cohesive launch, setup, lesson selection, play, review, and return, with clear feedback and graceful recovery.
- Require a reusable lesson foundation so the first unit's exercises share teaching, playback, notation, scoring, and progress systems. Free public distribution remains the goal.

### Learning milestones and the next product gate

- Mark M0, the mechanics and UI concept, achieved; make M1, a complete beginner learning journey, the active focus in the README.
- Define player, kit, skill, exercise, lesson, practice condition, evidence, and learning gate; separate game scores from readiness.
- Give M1 observable acceptance criteria for setup, individual progress, a small foundation unit, reduced guidance, review, and return/resume. Track later rudiments, retention, and musical application as planned milestones.
- Keep hardware reliability and public distribution as parallel quality gates; concept acceptance does not imply measured physical latency or a release-ready app.

### Bottom capture rail

- Add fixed drum/cymbal receptors and a full-width kick catcher on the shared NOW line.
- Acknowledge every strike; capture matched notes and distinguish extra hits with local effects when live timing feedback is enabled.
- Preserve simultaneous hits and neutral click-only feedback, animate unscored demo strikes, and respect Reduce Motion.


### First-lesson experience

[26b2ade](https://github.com/claudfuen/drumx/commit/26b2ade) delivers the focused native lesson and updated practice rail.

- Replace the engineering control surface with a focused preparation, playing, and review flow for **Your first backbeat**.
- Teach one original bar of percussion notation with aligned counting syllables, then connect it to the rhythm-game rail.
- Add review actions for retrying, reducing tempo, playing one guided bar, hiding alternate bars, and trying click-only recall.
- Save up to 200 complete local attempts and compare personal bests only under matching conditions. Apply delayed MIDI corrections to the same attempt.
- Project notes and the rail through one shared transform, carry notes through the count-in, and soften their arrival from the distance.
- Move MIDI mapping, monitoring, volume, sticking hints, and fixed offset into **Kit & sound**.
- Give the repository a single getting-started path and an updated lesson guide.

### Shared projection and distant note entry

[26cd661](https://github.com/claudfuen/drumx/commit/26cd661) defines the shared plane transform, signed count-in travel and smooth visibility envelope, with deterministic geometry and timeline checks.

### Comparable local lesson history

[824c5a0](https://github.com/claudfuen/drumx/commit/824c5a0) adds evidence-based review, comparable complete takes, and persistent personal bests with delayed-input corrections.

### Native audio demonstrations

[8e408b5](https://github.com/claudfuen/drumx/commit/8e408b5) adds acoustic groove demonstrations scheduled through the native audio path, with one-bar and four-bar plans and corresponding checks.

### Musical language and a shared timing axis

[e850390](https://github.com/claudfuen/drumx/commit/e850390) connects the curriculum draft to canonical rudiment terminology, counting, sticking, accents, reading, and teacher transfer, while preserving one visible timing axis.

### First playable Mac lab

[36d5450](https://github.com/claudfuen/drumx/commit/36d5450) introduces the native Swift/AppKit lab, CoreMIDI input, C++ scoring, count-in, keyboard practice, guidance modes, and a CC0 acoustic starter kit with velocity layers and recorded alternatives.

### Product and visual direction

[bf40072](https://github.com/claudfuen/drumx/commit/bf40072), [fab16f0](https://github.com/claudfuen/drumx/commit/fab16f0), and [62e7923](https://github.com/claudfuen/drumx/commit/62e7923) refine distinct kit identities, stable rail placement, sticking cues, continuous memory sections, focused practice, and the intended free public product model.

### Repository foundation

[91e044b](https://github.com/claudfuen/drumx/commit/91e044b) records the initial pitch, curriculum draft, and architecture research after the [initial repository commit](https://github.com/claudfuen/drumx/commit/886ddc8).
