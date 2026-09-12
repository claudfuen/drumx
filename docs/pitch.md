# Drumx: keep the groove when the notes disappear

Design proposal, September 12, 2026. Prepared for discussion with interactive mockups. The product concept and implementation stack are not committed.

## The pitch

Drumx is a structured drum-learning app with the satisfying play feel of a rhythm game. Melodics is the main reference for the learning experience; YARG is the reference for musical momentum and responsive play. Playing without the track becomes one meaningful part of progression, alongside enjoying music with the track.

Each lesson has a clear skill objective, a short explanation or demonstration, adjustable tempo and focused phrase loops. Start with the anticipation and immediate response of a note highway. Learn a short groove, rudiment or coordination pattern, then use it in a musical phrase. As it becomes familiar, offer selected phrases without visual instructions. In a full memory attempt, the player keeps the groove with a click and their own drum sound, while the engine continues recording and scoring. One rewarding moment is realizing the pattern is now playable without watching the screen.

The intended balance is learning structure first, enjoyable repetition throughout, and brief independence checks when useful. A full visible track remains a legitimate way to learn and play. The app should not force every attempt to end with disappearing notes or make players earn permission to enjoy a familiar groove.

The product promise is an aspiration to validate: help players move from following notes to remembering and using musical patterns. It is not a claim of proven learning effectiveness.

## The Melodics balance

Melodics' documented practice tools provide a concrete standard: slow a passage down, isolate a loop, build tempo gradually and optionally wait for the correct note while discovering the pattern. Drumx should offer these tools around a clear course rather than dropping the learner into a song browser and a score. Note-by-note discovery should be labeled separately from continuous rhythm practice. [Melodics Practice Mode](https://support.melodics.com/en/articles/6777027-practice-mode).

The proposed product has two connected activities. **Learn** recommends the next useful skill, connects rudiments to grooves and fills, and occasionally revisits prior skills without a preview. **Play** lets the learner enjoy and repeat familiar material, with a full track whenever wanted. They share the same practice surface and progress record; this does not require two separate applications or a sprawling menu of modes.

Game rewards should celebrate musical achievements: a steady backbeat, a clean fill that returns on beat one, or a phrase recalled at a comfortable tempo. Responsive hits, satisfying sound and personal-best challenges make repetition appealing. The lesson review adds one specific next step. A beginner can keep substantial guidance; an experienced player can jump to a suitable challenge. No fixed percentage of session time is asserted as the right scientific balance.

## One complete practice loop

| Phase | What the player gets | What the app evaluates |
| --- | --- | --- |
| Follow | Full track, a brief demonstration and optional counts/sticking | Correct instruments, timing, omissions and extra hits; guidance is available |
| Fade | A visible phrase followed by a hidden repetition; assistance changes at an announced bar boundary | The same targets and scoring as Follow, with assistance recorded separately |
| Recall | A count-in, the quarter-note click and the player's drum sound; no upcoming notes or live correctness cues | The same musical phrase, scored internally and reviewed afterward |
| Review and repair | The completed phrase with actual hits overlaid, one clear observation and a focused retry | Where the error occurred, whether it concerns timing, missing/extra notes or instrument choice |
| Apply | A groove, backing track or modest variation that uses the skill | Performance in a different musical context, labeled separately from recall |
| Return | A brief attempt in the next session before the chart is revealed | Later recall at a comparable tempo, distinct from a guided personal best |

The first prototype only needs one short kick/snare/hi-hat groove and the Follow, Fade, Recall and Review screens. Its job is to establish whether losing guidance feels like gaining an ability. A full library, notation editor and song platform can wait until that experience works.

## What makes this different from a permanently visible highway

The curriculum develops several abilities: reading a pattern, remembering it, keeping it in time, controlling dynamics, coordinating the kit and applying the idea musically. Those abilities should not collapse into one high score.

In particular, passing with a visible chart is different from recalling today, and both differ from remembering in the next session. Progress should record those differences. A useful result is specific: a player recalled the groove at a given tempo with a given aid level and timing distribution. A large combo alone should not imply mastery.

Each player has their own progress, starting level, comfortable tempos and assistance history. More experienced players can enter at a suitable exercise and aid level. Difficulty can grow through musical complexity, dynamics, orchestration and phrase length as well as tempo.

## Recall must actually remove the help

A note highway gives advance instructions. A miss flash, timing meter or combo update can provide immediate feedback that also helps reconstruct the pattern. During Recall, remove both the future notes and those live correctness cues. Do not leave ghost targets, an animated kit demonstration, a guide drum track or a scrolling playhead that discloses the phrase.

The player's own drum sound remains immediate. Delaying the results never means delaying the instrument. The click supplies a pulse, so this phase tests pattern memory while synchronizing to an external reference. Maintaining time through silent metronome bars is a separate later challenge, not something a click-only result proves.

Hints should be useful and non-punitive. Restore the chart for a short repair phrase, then offer another memory attempt. Mark the attempt as assisted rather than treating it as a failed independent score or erasing previous progress.

## Scoring that deserves trust

- Keep the same expected musical events, calibrated clocks and scoring rules across Follow, Fade and Recall.
- Retain source timestamps even if the renderer is slow. Audio and MIDI processing operate independently of animation.
- Report timing and completeness separately. Account for extra notes as well as omissions.
- Distinguish device calibration from the learner's own tendency to rush or drag.
- Teach sticking without claiming ordinary snare MIDI can identify the striking hand. Treat velocity as a kit-dependent dynamics signal, not proof of physical technique.
- Label open-ended improvisation separately; do not apply an exact-note grade when there is no exact-note target.

## Why the pedagogy is plausible, and what is still unproven

Ronsse and colleagues found dependence on visual augmented feedback in a laboratory bimanual coordination task, whereas their auditory-feedback group maintained performance when that feedback was removed. This motivates testing independence from visual support. It did not test drum games or establish a chart-fading schedule. [Ronsse et al., 2011](https://pubmed.ncbi.nlm.nih.gov/21030486/).

More guidance can also be useful for difficult skills. A ski-simulator experiment found a retained benefit from frequent feedback compared with none. The practical implication for this proposal is reversible assistance, adjusted to task difficulty, rather than assuming less feedback is always better. [Wulf, Shea and Matschiner, 1998](https://www.tandfonline.com/doi/abs/10.1080/00222899809601335).

Piano experiments found that hearing the instrument during learning helped later recall. A separate small observational study of advanced pianists linked practice accuracy, rather than raw practice time or repetition counts, to next-day retention rankings. These support retaining the player's sound and checking later performance, with clear limits when extrapolating to beginner drumming. [Finney and Palmer, 2003](https://link.springer.com/article/10.3758/BF03196082), [Duke, Simmons and Cash, 2009](https://journals.sagepub.com/doi/10.1177/0022429408328851).

The full Follow/Fade/Recall cycle is our product hypothesis. Its learning benefit, optimal assistance schedule and motivational effect remain to be tested. No arbitrary mastery percentage is presented as a scientific threshold.

## Visual and technical direction

The proposed mockups use one coherent desktop surface. Follow provides a precise, readable play lane; Fade keeps the same geometry as cues recede; Recall becomes visually quiet; Review reveals the completed performance. The design alternatives explore a restrained studio treatment and a more spatial stage treatment, sharing the same layout and learning model.

The desired quality comes from typography, readable note spacing, consistent motion, excellent sound response and a small set of deliberate effects. A large collection of particles, neon colors or generic dashboard cards would not establish that quality.

Unity and Flutter remain the two most relevant front-end candidates. Unity has the stronger integrated game-authoring workflow; Flutter fits a restrained native application. Either would need a separately designed native MIDI/audio/scoring path. The mockups do not commit the app to HTML or any production stack. They demonstrate the interaction and art direction only.

## What to validate before committing

1. Does a player understand the shift from Follow to Fade to Recall without explanation?
2. Does completing a hidden phrase feel rewarding enough to repeat?
3. Can a beginner recover gracefully with a hint, and can an experienced player remove help quickly?
4. Does Recall provide no unintended pattern cues, while preserving identical scoring targets?
5. Can the next-session check distinguish immediate repetition from retained ability?
6. Can the actual kit, audio route and renderer meet the measured latency and frame-stability gates in the architecture plan?

The first learner test should compare the hybrid against an always-visible version of the same exercise, including a later no-chart check. Record enjoyment and willingness to continue as well as performance; improved scores during a practice session alone are insufficient evidence.

Related: [product and competitor research](product-research.md), [architecture and latency plan](architecture-options.md), [introductory curriculum draft](curriculum.md).
