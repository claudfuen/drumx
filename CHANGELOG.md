# Changelog

A record of playable milestones and product decisions. These entries describe repository changes, not published binary releases.

## 2026-09-12

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
