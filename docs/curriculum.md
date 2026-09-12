# Drumx starting curriculum

This is a **proposed curriculum**, recorded in [lessons-draft.json](lessons-draft.json), extending foundations into named rudiments and further reading practice. The native app has a separate 12-lesson foundation unit in [DrumxCourse.swift](../native/macos/DrumxCourse.swift), with notation, demonstrations, and scoring drawn from the same authored events. See the [native guide](native-lab.md) for its three chapters, local players, assistance modes, checks, and review. The app does not load this JSON draft or implement its full lesson sequence. **M1 remains active** under the [learning milestones](learning-milestones.md).

The proposed course starts with a steady pulse, introduces three useful rudimental stickings, then applies timing to a basic drum-set groove. The learner should leave able to name, count, read, and explain what they played to a drum teacher. This is an original introductory practice sequence, not the full PAS curriculum or a substitute for a teacher observing technique.

## Lesson sequence

All patterns use 4/4. BPM always refers to the quarter-note beat. A subdivision of 1, 2, or 4 means one quarter note, two eighth notes, or four sixteenth notes per beat. Every step has the same duration, including any future empty steps used for rests.

| Lesson | Pattern | Length | Starting BPM | Suggested target BPM |
| --- | --- | --- | --- | --- |
| Find the pulse | Alternating snare quarter notes | 1 bar, 4 steps | 60 | 90 |
| Single Stroke Roll | R L throughout, in eighth notes | 1 bar, 8 steps | 65 | 100 |
| Double Stroke Open Roll | R R L L throughout, in sixteenth notes | 1 bar, 16 steps | 45 | 80 |
| Single paradiddle | R L R R L R L L, in sixteenth notes | 1 bar, 16 steps | 45 | 80 |
| Accent control | Alternating sixteenths, accent each beat | 1 bar, 16 steps | 50 | 85 |
| Your first groove | Eighth-note hi-hat, kick on 1 and 3, snare on 2 and 4 | 1 bar, 8 steps | 60 | 100 |
| Kick on the & | Add a kick on the & of 3 to the first groove | 1 bar, 8 steps | 60 | 95 |
| Groove into a fill | Basic groove, then four snare eighth notes on beats 3 and 4 of bar 2 | 2 bars, 16 steps | 65 | 100 |

The starting and target tempos are product practice suggestions, not proficiency standards. A learner can lower the tempo. Increase speed only when the current pattern stays even and comfortable. Lessons stay available for review rather than implying that a single score proves mastery.

## One musical language across views

Use the conventional name prominently, with plain-language help underneath. A **rudiment** is a conventional stroke pattern; a **groove** is a repeating accompaniment pattern across the kit. A **fill** is a phrase used to connect or vary sections. Playing the starter backbeat is groove practice, not a completed rudiment. A rudiment can later supply material for a fill or groove.

Every planned lesson follows the same learning loop:

1. **Hear and name:** hear an original demonstration, identify the skill, and learn one or two terms.
2. **Count and play:** speak quarter notes as `1 2 3 4`, eighths as `1 & 2 & 3 & 4 &`, and sixteenths as `1 e & a 2 e & a 3 e & a 4 e & a`. Say `&` as “and.” The metronome still marks quarter-note beats.
3. **Read and connect:** pair the game lane with an original conventional percussion-staff rendering of the same events. Align counts below notes, optional R/L sticking below counts, and `>` accent marks above the intended notes. Teach the time signature, barlines, note values, rests, and beams as they appear. Display a drum-key legend because drum-set staff conventions vary between publishers.
4. **Reduce assistance:** remove sticking prompts, then the moving lane; keep the static staff available for a reading attempt. Reading-only and click-only recall are different tasks and should have separate labels.
5. **Recall and apply:** play a short click-only phrase, then use the skill in a small changed pattern or fill. In a strict recall attempt, hide the staff, counts, forthcoming hits, beat animation, and live evaluation; reveal feedback afterward. Personal input flashes or live timing are optional aids and recorded as such.
6. **Explain and review:** name the skill, count a bar, identify an accent or rest, and show the exercise to a teacher. Revisit it on another day and at another comfortable tempo.

The notation and game views must derive from one event sequence, including simultaneous kit voices and silent steps. A lane is an aid to reading and listening, not a second naming system to memorize. The JSON draft adds musical and teaching metadata without choosing a renderer or changing the scoring engine.

## Four concrete beginner skill examples

These are original exercises using three conventional rudiment stickings and one groove. Begin with the pulse lesson if subdivisions are unfamiliar.

| Skill and teacher-facing name | Count one bar in 4/4 | Sticking / coordination | Reading and transfer task |
| --- | --- | --- | --- |
| Single Stroke Roll, PAS 1 | `1 & 2 & 3 & 4 &` | `R L R L R L R L`, snare eighth notes | Identify paired eighth-note beams; explain alternating hands; play the same rhythm starting with L. |
| Double Stroke Open Roll, PAS 6 | `1 e & a 2 e & a 3 e & a 4 e & a` | `R R L L R R L L R R L L R R L L`, snare sixteenths | Read four sixteenths per beat and hear two distinct strokes from each hand. Ask a teacher to check control and rebound. |
| Single Paradiddle, PAS 16 | `1 e & a 2 e & a 3 e & a 4 e & a` | `R L R R L R L L R L R R L R L L`; accent counts `1`, `2`, `3`, `4` | Read the `>` accents and explain why the leading hand alternates each beat in this exercise. Keep accents louder without shifting their timing. |
| Eighth-note backbeat groove, not a rudiment | `1 & 2 & 3 & 4 &` | Hi-hat on every count, kick on `1`/`3`, snare on `2`/`4`; suggested R hand on hat, L on snare, bass-drum foot on kick | Identify simultaneous voices on the staff; explain “backbeat”; play one bar from the staff and one from memory. |

The exact note values are exercise choices, not part of a rudiment's name. A Single Stroke Roll is still the same sticking when practiced at another subdivision. Reading a paradiddle correctly, keeping its timing, and physically executing its doubles are separate achievements.

## Evidence of progress

The [learning definitions and milestones](learning-milestones.md) are the canonical reference for readiness gates, evidence, and product acceptance. The examples below apply that policy to this proposed curriculum.

Keep separate records for timing, instrument coverage, count/term recognition, reading, recall, and the learner's or teacher's technique check. A proposed checkpoint combines a repeatable comfortable performance, a reading attempt without the lane, an explanation of the counts, and a later recall or variation attempt. These are product hypotheses to evaluate, not validated mastery thresholds.

Never unlock a “mastered” badge solely because a target BPM or timing percentage was reached. A score should identify the phrase, tempo, selected aids, misses, extras, and timing error. Sticking and physical technique remain unverified by ordinary MIDI, even after a perfect timing score. Relative velocity feedback is useful only with its module-dependent limits made clear.

## Reading the exercises

- R and L suggest right and left hand. The first groove assumes right hand on hi-hat and left on snare; a learner can mirror the setup.
- Several voices in one step mean simultaneous hits. For example, a groove downbeat requires both kick and hi-hat. There is no single hand label for a multi-limb step.
- An accent asks for a stronger note relative to surrounding taps. It does not change note duration or add a note.
- The paradiddle accents begin each four-note group. The separate accent drill uses right-led singles with downbeat accents. A mirrored or left-led variation is a future exercise.
- The basic groove and fill are original teaching exercises, not named PAS rudiments.

## What MIDI can establish

A standard snare pad usually sends the same MIDI note regardless of the striking hand. R/L labels are instructions to follow and self-check, not evidence that the app verified sticking. Even a pad with separate head and rim zones identifies zones rather than hands. The same qualification applies to grip, posture, rebound and foot technique.

Note-on timing can support feedback about arrival time and whether the expected instrument was struck. Velocity can help display relative hit strength, but depends on drum-module trigger settings and playing surface. A timing score alone does not establish accent quality. Audio-output latency and MIDI arrival latency also affect apparent alignment and should be considered when interpreting small timing differences.

The slow double-stroke lesson schedules two distinct, evenly spaced notes per hand. It does not teach a buzz roll or establish that the learner used controlled rebound. Do not describe every rapid pair as an adequately performed double-stroke roll.

## Sources and scope

The rudiment names and conventional sticking sequences were checked against the [Percussive Arts Society International Drum Rudiments](https://pas.org/rudiments/) and its [official rudiment chart](https://pas.org/wp-content/uploads/2024/04/pas-rudiments.pdf): single-stroke roll, double-stroke open roll, and single paradiddle. The exercises use those standard stickings at fixed, beginner-friendly note values. The app does not reproduce PAS notation artwork or recordings and does not imply PAS endorsement.

The user-supplied [Moises introduction to drum rudiments](https://moises.ai/blog/tips/drum-rudiments/) motivates connecting sticking practice to musical use. PAS provides the canonical names used here. Drumx's lesson order, practice lengths, suggested tempos, coordination patterns, literacy loop, and coaching copy are original product choices. Link to the PAS reference rather than bundling its complete chart, copyrighted notation artwork, or audio; create original notation from Drumx's own exercise events.

Sources checked September 12, 2026.

## Intentionally deferred

- Flams and drags need distinct grace-note timing and a scoring model that distinguishes ornament spacing from ordinary subdivisions.
- Buzz rolls, measured roll endings and advanced open-roll technique need richer articulation and teaching support. No identical-step approximation is presented as one of those techniques.
- Triplets, swing and compound meter need explicit timing support rather than relabeling a straight pattern.
- Open hi-hat control, pedal articulation, cymbal choking and multi-zone technique need controller and module-specific mapping.
- Hand verification needs an independently validated sensing method. Ordinary single-zone snare MIDI cannot supply it.
- Adaptive progression and technique assessment need evidence beyond a timing percentage, including consistency across sessions and learner or teacher checks.
- Additional lead-hand variations, fills, musical backing tracks and an expanded rudiment library can follow this proposed introductory course. The native foundation unit already pairs notation with its practice events; extending that teaching to this draft's named rudiments and full reading sequence remains planned.
