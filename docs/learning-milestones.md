# Learning definitions and product milestones

Drumx should help a player hear, count, read, play, recall, and use a rhythm. These definitions connect that promise to the product we build and the evidence we collect. They define product acceptance and proposed learning gates, not a certification standard. The implementation status below is separate from those gates.

**Current milestone: M0 done, mechanics/UI prototype accepted as a concept. M1 active, complete beginner learning loop. M2 through M4 planned.** Hardware latency and sustained frame pacing remain unmeasured; accepting the concept does not close those quality questions.

The current macOS build connects welcome and local player profiles to a 12-step foundation path, visual kit setup, shared notation/audio/scoring events, reading checks, technique self-checks, assistance, review, and versioned resume. New lessons use a 16-bar practice block with detailed options initially collapsed. These are M1 implementation progress, not evidence that a real beginner has completed the intended journey successfully. See [current behavior](native-lab.md), [authored course](../native/macos/DrumxCourse.swift), and the separate [rudiment curriculum proposals](curriculum.md). This document owns definitions and milestone acceptance; the lesson guide owns implementation details.

## Shared learning language

| Term | Meaning and relationship |
| --- | --- |
| Player / player profile | A person and their local goals, preferences, learning evidence, and resume position. Different players can use the same kit without sharing progress. A profile's chosen experience level is a starting preference, not a demonstrated skill level. |
| Kit / input profile | The musical setup and a saved description of how a device reports it: source, mappings, available articulations, monitoring route, and fixed timing offset. A player may use several setups; several players may share one. |
| Skill | A specific ability, such as maintaining eighth notes, reading a rest, controlling doubles, or returning to beat one after a fill. A skill can appear in many lessons and require several kinds of evidence. |
| Exercise | A versioned musical task: events, meter, counts, notation, suggested sticking, articulations, and intended skills. Its identity is separate from today's tempo and assistance. A rudiment is not a tempo preset. |
| Lesson | A teaching sequence around a clear outcome: explanation, listening, one or more exercises, practice, review, and a suggested next step. Opening a lesson does not complete it. |
| Practice condition | The exact circumstances of an attempt: exercise version, tempo, phrase length, input profile, monitoring, offset, click/backing track, and enabled aids. It defines which performances are comparable. |
| Guidance / scaffold | An aid supplied before or during playing: upcoming targets, counts, staff, sticking hints, beat animation, or a demonstration. Live correctness feedback is a separate aid. Removing targets does not necessarily remove every cue. |
| Attempt | One bounded performance by one player of one exercise under one condition. Record completion or interruption; demonstrations are not attempts. Preserve captured results without treating an interrupted take as a completed achievement. |
| Evidence | A dated observation tied to its source and conditions: MIDI timing, omissions/extras, a reading response, a recall attempt, or a self/teacher technique check. Missing evidence remains unknown. |
| Learning gate | A stated readiness decision for a next task, based on specified evidence. It recommends suitable practice and explains gaps; it does not certify the whole skill from one score. |
| Course checkpoint | A small bundle of related learning gates that makes an outcome visible, such as counting, reading, and recalling a basic backbeat. A product milestone delivers the ability to teach and assess such checkpoints. |

A player takes a lesson, performs its exercises under recorded conditions, and accumulates evidence. Learning gates use that evidence to recommend a next step. Course checkpoints combine those gates; product milestones deliver usable parts of this experience.

### Musical identity and physical input are different

- **Instrument:** the musical destination, such as bass drum, snare, or hi-hat. It determines the staff/kit identity, not the limb that played it.
- **Physical control and zone:** the actual pad, head/rim zone, cymbal bow/edge, or pedal. An input profile maps their reported events to musical meaning when the hardware distinguishes them.
- **Articulation:** the intended way an instrument sounds, such as a closed hi-hat strike, open strike, or pedal chick. Preserve distinctions an exercise needs instead of flattening every event into a generic hi-hat hit.
- **Continuous state:** a module may report hi-hat openness through MIDI control changes. That state is distinct from a note event and needs a supported, module-specific interpretation.
- **Input alias:** different incoming notes accepted as one current target. The lab's broad hi-hat group is an alias convenience, not proof that it distinguishes pedal technique or open/closed playing.
- **Limb:** a suggested hand or foot belongs to instruction. A double bass-drum pedal can produce the same MIDI note from either foot; that stream cannot identify the foot. Two distinct reported inputs can retain their identity without proving physical technique.

These are future capability boundaries, not claims that the lab implements pedal articulation, continuous hi-hat control, separate feet, or an editable full kit. An exercise must declare the distinctions it needs; unsupported distinctions require an explicit adaptation or an unassessed outcome. They must not silently receive a passing grade.

## Readiness is separate from the game score

Stars, streaks, percentages, and personal bests reward a performance under stated conditions. They are not a learner's overall level. Preserve separate evidence for:

| Evidence | Readiness question |
| --- | --- |
| Timing and coverage | Can the player repeat the complete pattern at a comfortable tempo without relying on omitted or extra strokes? |
| Counts and reading | Can they name the pattern, explain its counts, and read the relevant note values or rests without the highway? |
| Recall | Can they play the phrase without upcoming-note guidance? Record whether live evaluation, staff, counts, and a click remain. |
| Revisit | Can they recall it in a later session before hearing or seeing it again? |
| Transfer | Can they use it in a changed phrase, at another comfortable tempo, or in a groove? Record which change was tested. |
| Technique and dynamics | What was self-checked, heard, or observed by a teacher? Ordinary MIDI does not verify sticking, grip, rebound, posture, or foot technique. Module velocity is contextual evidence, not an automatic technique grade. |

Suggested gate labels are **needs practice**, **ready to try the next task**, **recalled later**, and **applied in a variation**. Each names the evidence and any unresolved dimension. A next-task recommendation can coexist with an unobserved technique check; it must not label that check passed.

The implemented course keeps **Practised**, **Reading checked**, and **Recall tried** as separate evidence. A correct reading response and explicit technique self-check are different records. The first completed pulse attempt is a baseline comparison, not automatic skill placement. Scheduled revisits and adaptive readiness decisions remain planned.

The lesson path also has a prototype access rule: finish at least four bars with 80% of expected notes matched to clear a step; entering the next chapter additionally requires the preceding chapter's final reading check. Every step remains inspectable, while a locked step explains its prerequisite and disables its play action. Existing saved positions and earlier practice preserve access; old revisions do not pass new checks. **Step complete** and **lessons cleared** describe this game progression rule, not broader readiness or mastery. Learn's stars show the best saved result for the current lesson version across any conditions; review compares matching conditions. Stars, tighter on-time grades, recall, and technique remain separate. See [menu architecture](menu-architecture.md#unlocks-invite-another-step) for the current route and policy boundaries.

Use repeated comparable attempts rather than only a best take. Retain supported and less-supported performances separately. A reading attempt with a staff is not a memory attempt. A click-only attempt tests recall against an external pulse; maintaining tempo through missing-click bars is a separate, later test.

Timing windows and numerical star boundaries are **prototype score policy**, not learner gates. The implemented four-bar/80% access rule, and any future learning cutoff, repetition count, tempo target, or revisit interval, are **untested starting hypotheses** until evaluated with learners. Keep their meaning explicit when versioning content or policy. No research-backed mastery percentage or automatic certification is specified here.

The default **16-bar practice block** is a separate cadence hypothesis: about a minute of uninterrupted playing before review at the authored starting tempos. It does not raise the minimum unlock length, establish retention, or promise that one minute is an optimal learning dose. Evaluate whether players settle into the pattern and understand when to stop, repeat, shorten, or reduce assistance.

## M0: Mechanics and UI concept

**Status: done.**

- **Player promise:** experience a short backbeat lesson and understand how the highway, shared timing line, capture rail, sound, assistance, and review fit together.
- **Acceptance evidence:** an accepted playable concept with listen, count-in, play, review, and retry; a readable original staff study; guided, hidden-bar, and click-only conditions; software checks supporting the documented behavior.
- **What does not count:** proof of learning, a complete beginner course, a production renderer decision, a release-ready installer, or measured physical latency. Keyboard/virtual MIDI checks do not establish real-kit performance.
- **Boundary carried forward:** characterize hardware timing and rendering under stated conditions rather than treating concept acceptance as a performance benchmark.

## M1: One complete beginner learning loop

**Status: active.**

- **Player promise:** a new drummer can set up, find a comfortable starting point, learn a small coherent foundation unit, understand their result, and know where to resume.
- **Scope:** setup and baseline; pulse and counts; the current backbeat built in manageable steps; one checkpoint connecting listening, reading, guided playing, and an attempt with less help. This is one unit, not the entire curriculum.
- **Experience bar:** a small, finished game that could belong on Steam. Inspect the entire launch/setup/select/play/review/return flow for cohesive visuals and audio, clear language, satisfying response, accessible feedback, empty states, and graceful interruptions. A possible paid release is an aspiration to evaluate; pricing, distribution, Steam availability, and the source-code license remain undecided.
- **Extensibility evidence:** build the unit from versioned exercise content with shared teaching, playback, notation, scoring, review, and progress systems. Demonstrate that adding an exercise preserves agreement between heard, seen, and assessed rhythms without writing a separate controller path for each lesson.
- **Acceptance evidence:** demonstrate the full setup → baseline → lesson → practice → review → next step → reopen/resume path without developer intervention. Two local players keep independent baselines and progress while sharing a kit. Saved evidence records the exercise and aids; a representative real-kit session confirms mappings, simultaneous hits, and recovery from a disconnected input under documented conditions.
- **Learning gate:** the player can count the unit's pattern, recognize its basic notation, repeat it comfortably, and attempt it with less guidance. The review distinguishes measured performance from the learner's technique self-check and recommends a concrete next action.
- **What does not count:** a longer lesson menu, automatic advancement from stars, a single polished screen, or treating keyboard success as physical-kit evidence.

### M1 progress and remaining evidence

| Work | Implementation progress | Acceptance still needed |
| --- | --- | --- |
| Coherent foundation unit | Twelve authored lessons in three chapters cover pulse/counts, a layered backbeat, rests, variations, and a short fill. All 12 passed scoring/audio event and sample-frame checks; their generated notation was visually inspected. | Observe learner comprehension and the musical experience on a physical kit. |
| Welcome, setup, and local players | Welcome, a fresh second player, separate reading evidence, and course navigation were checked in the app. Models verify independent history keys and archive migration. Visual kit setup now exposes raw MIDI/velocity and adds aliases without discarding the selected instrument's existing mappings. | Observe physical-kit setup, confirm reported notes against actual pads, and exercise missing/disconnected inputs across players. |
| Baseline and resume | Close/reopen preserved the selected player, final lesson, eight-bar settings, and completed takes; switching back restored the first player's separate reading check. Durable archives and versioned resume have model coverage. Practice-plan checks cover the once-only legacy four-bar migration, explicit length choices, recommended tempo, and valid guidance combinations. | Validate the first pulse as a useful learner baseline, observe the longer default on return, and exercise changed-device recovery. |
| Understand, practice, review | Lesson objectives, counts, three-choice reading questions, explicit technique self-checks, scores/PBs, and explained lesson unlocks are available. The responsive path features one lesson; practice defaults to 16 bars with detailed options collapsed. Estimated repetition time totals 96 suggested minutes, not recorded-content duration. | Observe a beginner understanding the task, sustaining a useful practice block, interpreting feedback, and choosing a next action without developer intervention. |
| Early recall | Hidden-bar and click-only attempts are available; course evidence records that recall was tried separately from supported practice. | Verify cue suppression and honest evidence labels in the integrated experience; do not infer later retention. |
| Reliability and experience | Native checks cover custom charts, shared course audio, local profiles, durable archives, delayed corrections, and unlock sequencing. Main menu, course navigation, settings persistence, pause, and locked review states have prior app inspections. Optional drum-menu gestures now cover the main menu, preparation, review, and pause; setup and browsing still require keyboard/mouse. | Observe the revised flow and gestures on a physical kit. Physical latency, sustained frame measurements, broader interruption/accessibility coverage, and the full finished-game experience bar remain open. |

**M1 is still active.** Available controls and passing content/model tests do not by themselves complete these acceptance checks. Record integrated verification separately from the untested real-beginner and hardware outcomes, then update this checklist as evidence arrives.

## M2: Rudiments, reading, and coordination

**Status: planned.**

- **Player promise:** connect named rudiments to real counts and notation, then use their timing in beginner-to-intermediate kit coordination.
- **Scope:** Single Stroke Roll (`R L`), Double Stroke Open Roll (`R R L L`), and Single Paradiddle (`R L R R L R L L`); quarter/eighth/sixteenth values, rests, accents, suggested sticking, and basic coordination variations. Use [PAS's canonical reference](https://pas.org/rudiments/) and [official chart](https://pas.org/wp-content/uploads/2024/04/pas-rudiments.pdf), with original exercise notation.
- **Acceptance evidence:** lessons teach and assess naming/counting, staff reading, playable patterns, and a small application. The notation, audible demonstration, and game targets agree. Prerequisites and a return-to-practice route work across the unit.
- **Learning gate:** a player distinguishes singles, doubles, and paradiddles, counts their chosen subdivision, and demonstrates the task under recorded conditions. Sticking and controlled double-stroke technique remain self/teacher observations, separately labeled.
- **What does not count:** three identical snare timelines with different titles, higher BPM alone, the full PAS list presented as completed teaching, or unsupported grace notes approximated as ordinary grid hits.

## M3: Retention, transfer, and independence

**Status: planned.**

- **Player promise:** discover what remains when visual help disappears, and revisit it until it is useful beyond the last guided run.
- **Scope:** deepen M1's short check with less guidance through scheduled revisits, adaptive practice recommendations, and explicit transfer tasks. Memory practice starts in the first unit; it is not withheld until this milestone.
- **Acceptance evidence:** reversible assistance reduction; reading-only and strict click-only checks; evaluation after a strict recall phrase; a scheduled later-session first attempt before preview; and a controlled variation at another tempo or in another phrase. History distinguishes each condition and recommends a targeted repair when recall breaks down.
- **Learning gate:** document recall, later recall, and the specific transfer demonstrated, rather than combining them into one mastery number. Optional missing-click work separately assesses maintaining pulse without continuous pacing.
- **What does not count:** hidden targets with unreported live error cues, repeating immediately from short-term memory as evidence of later retention, or treating a high guided score as independence.
- **Evaluation boundary:** cue fading is a product hypothesis to test against actual retention and learner experience. More difficulty is not automatically better teaching.

## M4: Musical application and intermediate growth

**Status: planned.**

- **Player promise:** turn the learned vocabulary into musical playing and choose productive next work at their own level.
- **Scope:** short groove-and-fill phrases, returning to one, dynamic contrast, orchestration, and progressively richer coordination; original or appropriately licensed accompaniment. Advanced topics enter as bounded units with explicit prerequisites and hardware requirements.
- **Acceptance evidence:** a player can select an appropriate unit, hear and read its musical role, practice a difficult part, rejoin the phrase, apply a variation, and receive a recommendation grounded in their own history. A more experienced player can start beyond the beginner unit without changing another player's path.
- **Learning gate:** demonstrate the named musical application across complete phrases and a variation. Keep timing/coverage evidence distinct from expressive choices and observed technique; an exact-match score is not a general measure of musicality.
- **What does not count:** speed challenges alone, a song catalog without teaching, an “advanced” label on a denser pattern, or promising comprehensive advanced instruction from a small exercise set.

## Quality gates run alongside the learning milestones

The macOS app leads while portable-core validation runs on macOS and Windows in parallel. Platform delivery is not a musical level or a reason to restart a player's progress. A public preview can open after M1 when the parallel usability, reliability, and distribution gates below are satisfied; it need not wait for the intermediate course. Pricing and a Steam release remain separate decisions.

- **Input and timing:** document tested modules, input/monitoring paths, calibration, latency measurement methods, and frame behavior. Test device interruption and unsupported input distinctions. Publish measured boundaries without inventing a universal latency target.
- **Progress and accessibility:** verify independent local profiles, reliable resume, evidence versioning, readable notation, stable kit positions, reduced motion, and comprehensible feedback without depending on color alone.
- **Production engine and portability:** choose the renderer/engine before large content expansion and validate a representative complete journey. The current custom AppKit shell is Mac-only. The C++ core and C consumer passed hosted Debug/Release contracts on both operating systems, plus Mac sanitizers; see [verified platform evidence](cross-platform.md#what-has-been-verified). Swift lesson/progression models need extraction or porting, and Windows needs interface/input/audio layers. Core CI and custom styling do not establish a Windows app, shared UI portability, or measured frame performance.
- **Distribution:** prove a repeatable build/install/launch/update path on the supported platform, with truthful setup instructions and retained asset provenance. Windows gets its own input, audio, installer, and performance validation.
- **Teaching quality:** review musical examples and their explanations, observe learners using the intended loop, and revise gates when outcomes contradict the proposal. Keep checkpoint scope explicit instead of promising certification.

Close a product milestone with a reproducible player journey, the relevant checks, observed limitations, and an updated status. Update the README and changelog with that outcome; adding content or passing unrelated tests does not close its learning acceptance criteria.
