# Drumx curriculum

The playable course contains **20 original lessons in five chapters**, moving from pulse and a first backbeat into named rudiments and further three-instrument coordination. [DrumxCourse.swift](../native/macos/DrumxCourse.swift) owns the authored content; the shared Mac and Windows app consumes its verified [course export](../apps/game/data/course.json). Demonstrations, notation, and targets describe the same events.

This is an introductory course, not a complete beginner-to-intermediate education or the full PAS rudiment curriculum. **M1 and the premium quality gate remain open.** The [curriculum review](curriculum-review.md) defines the current expansion gate and its limitations; [learning milestones](learning-milestones.md) owns the broader learning outcomes.

The earlier [eight-lesson JSON draft](lessons-draft.json) is historical design material. The app does not load it. Its sixteenth-note exercises, accent work, and two-bar fill are not the current course.

## The playable path

Every exercise is one bar of 4/4, repeated for the selected take. BPM refers to quarter-note beats. The current notation supports quarters, eighths, rests, and simultaneous hi-hat, snare, and kick voices. `&` means the halfway point between numbered beats and is spoken as “and.”

| Chapter | Lesson | Musical task | Starting BPM |
| --- | --- | --- | ---: |
| 1. Pulse and counts | 01 Find the pulse | Snare quarter notes; count through the barline | 60 |
| | 02 Find the and | Closed hi-hat eighth notes | 60 |
| | 03 Give silence its beat | Snare on 2 and 4; count the rests | 60 |
| | 04 Bring in the bass drum | Kick on 1 and 3 | 60 |
| 2. Build your backbeat | 05 Hand meets foot | Hi-hat eighths with kick on 1 and 3 | 60 |
| | 06 Add the backbeat | Hi-hat eighths with snare on 2 and 4 | 60 |
| | 07 Your first backbeat | Combine all three instruments | 72 |
| | 08 Give the groove more space | Keep the backbeat, change hi-hat to quarters | 72 |
| 3. Read, vary, and remember | 09 Single Stroke Roll | Snare eighths with suggested `R L R L R L R L` | 60 |
| | 10 Kick on the and | Add kick on the & of 3 to the basic groove | 60 |
| | 11 Keep counting through a gap | Leave the final hi-hats out; return to one | 60 |
| | 12 Groove into a fill | Two beats of groove, then four snare eighths | 60 |
| 4. Hands and rudiments | 13 Double Stroke Open Roll | Slow snare eighths with `R R L L R R L L` | 60 |
| | 14 Move the doubles | Place the suggested R strokes on hat and L strokes on snare | 60 |
| | 15 Single Paradiddle | Slow snare eighths with `R L R R L R L L` | 60 |
| | 16 Move the paradiddle | Distribute that sticking between hat and snare | 60 |
| 5. Make the groove your own | 17 Foot beneath the paradiddle | Add kick on 1 and 3 to the orchestrated study | 60 |
| | 18 Four on the floor | Hi-hat eighths and snare backbeat over four quarter-note kicks | 60 |
| | 19 Lead into one | Add kick on the & of 4; preserve its distance to the next 1 | 60 |
| | 20 Between the beats | Hi-hat on each &; kick 1/3 and snare 2/4 remain | 48 |

The eight new lessons preserve the original 12 IDs, versions, order, and musical events. Lesson 09 now uses its conventional rudiment name; it is the existing alternating-eighths exercise, not an extra duplicate lesson.

The displayed suggestions total **174 minutes across repeated practice**, including 78 minutes for the expansion. These estimates are planning prompts, not unique content duration, a required dose, or a promise of proficiency. A default 16-bar take gives uninterrupted time to settle into the pattern; repeat, shorten, or take a break as useful.

## Learn a vocabulary, then use it

A **rudiment** is a conventional stroke pattern. A **groove** is a repeating accompaniment pattern across the kit. A **fill** varies or connects a musical phrase. **Orchestration** places a rhythm on different instruments. The first backbeat is groove practice; moving a paradiddle between surfaces is a coordination study, not automatically a song-ready accompaniment.

The Single Stroke Roll, Double Stroke Open Roll, and Single Paradiddle use conventional stickings from the [Percussive Arts Society reference](https://pas.org/rudiments/). Their eighth-note spacing is Drumx's introductory exercise choice. The slow doubles require distinct, even strokes, not a buzz. They do not establish controlled rebound or a fluent fast roll. The introductory paradiddle has no required accents.

The learning sequence is concrete:

1. Read the objective, name the pattern, and hear its demonstration.
2. Count `1 2 3 4` or `1 & 2 & 3 & 4 &`; connect the staff and instrument key to the same sounds.
3. Play at the authored starting pace. Use the lesson's listening focus, such as an even second stroke or kick and snare meeting on 3.
4. If it breaks down, follow the named repair exercise. Add the changed surface or foot only after the simpler pattern feels manageable.
5. Try less visual guidance at a familiar pace. Guided playing, hidden targets, and strict click-only recall remain separate conditions.
6. Explain the counts, self-check the suggested technique, and revisit the skill. An immediate repeat does not establish later retention.

Each new sticking study has an application on different surfaces. This gives the doubles and paradiddle distinct audible instrument sequences after their snare introductions. Yamaha's beginner material provides a useful precedent for moving a paradiddle between surfaces and then adding bass-drum coordination; Drumx's exercises and teaching copy are original. [Yamaha beginner practice exercises](https://hub.yamaha.com/drums/d-how-to/practice-exercises-for-the-beginning-drummer/)

## Pace and course access

Find the pulse retains its separate [guided-tempo policy](guided-tempo.md): authored 60/66/72 BPM coaching and optional later challenges. Its checkpoint is unchanged by this expansion.

For the other lessons, the current readiness policy looks for **two qualifying takes within a window of up to three comparable completed takes**. A qualifying take uses exactly 16 bars, Guided assistance, the lesson's authored BPM, and the current policy version. Every required instrument must match at least 80% of its authored notes, with at least 70% of its authored notes inside the existing on-time band. Extras across the take must not exceed 10% of all expected notes.

Attempts are compared under the same captured conditions, including input, mappings, monitoring, calibration, and assistance. A dense hi-hat part cannot compensate for omitting the kick. Once a qualifying historical window exists, later difficult practice does not erase that evidence; a correction to the original attempt is reevaluated. Previously earned access is preserved, without fabricating new checkpoint evidence. Chapter transitions also retain their reading requirement.

These numbers are **product hypotheses**, not validated mastery standards. They describe readiness to try another exercise, not sticking proficiency, musicality, or independent recall. A new coordination task uses its own starting pace; the app does not extrapolate a universal appropriate BPM from the first pulse. Manual free practice remains available, with its conditions and personal bests recorded separately.

## What the evidence means

| Evidence | What it supports | What it does not establish |
| --- | --- | --- |
| MIDI note timing and instrument coverage | Reported hits, omissions, extras, and timing under captured conditions | Physical sound-onset latency or general musical ability |
| Terminology/count response | Recognition of the particular question's concept | Unseen sight-reading proficiency |
| Strict click-only attempt | An attempt to recall the phrase against an external pulse | Retention on another day or keeping time without a click |
| Suggested R/L and technique self-check | An instruction and the player's own observation | Verified hands, grip, posture, rebound, or foot technique |
| Module velocity | Contextual information about reported hit strength | A calibrated acoustic dynamic level or automatic accent-quality grade |

Separate head/rim zones identify reported zones, not the hand that struck them. Mapping several hi-hat note numbers to the current target does not establish open/closed/pedal articulation. A double kick stream does not identify which foot played. Unsupported distinctions must remain unassessed.

## Next capability boundary

The next course gate is **phrasing and literacy**, defined in the [review](curriculum-review.md#c2-next-phrasing-and-literacy-gate): two- and four-bar musical phrases, returning to one after occasional fills, and correctly rendered sixteenth-note studies. These require shared content, notation, audio, scoring, and history changes before adding lessons that depend on them.

Triplets and swing, flams and drags, dynamics assessment, tom/cymbal orchestration, hi-hat articulation, and licensed accompaniment each need their own verified support. Twenty lessons do not make those capabilities present.

Sources checked September 12, 2026. PAS names are references, not endorsement; its artwork and recordings are not bundled. Drumx authors its own lesson order, events, notation, demonstrations, and coaching. Its pace and access policies require learner and educator evaluation. PAS's [Fast and Slow guidance](https://pas.org/pas-blog/tuesday-tips-fast-and-slow/) supports comfortable, consistent practice before gradual increases, not Drumx's particular BPM or percentage thresholds.
