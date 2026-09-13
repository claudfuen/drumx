# Changelog

A record of playable milestones and product decisions. These entries describe repository changes, not published binary releases.

## 2026-09-12

### Play songs through their recorded drum performance

- Make Follow my playing the normal recorded-drum mode: chart misses mute separate drum stems, successful hits restore them, and backing recordings continue on the same clock. Keep Always on and Off choices, full-mix previews, and an honest fallback for embedded drums.
- Suppress live hit samples during recorded-performance modes without changing the user's lesson monitoring preference. Restore their sound behavior on leaving Songs or choosing Off.
- Derive the gate from authoritative captured hits and native miss deadlines, including dense same-pad notes, partial chords, and delayed input corrections. Fade gain changes without rescheduling audio or resetting playback.

### Browse large libraries and play for a personal best

- Load lightweight song summaries off the main thread, retain note arrays only for play, and reuse unchanged reference imports through source fingerprints. Repair missing intensity metadata in the background with visible loading and failure states.
- Add arrow-key browsing, search, sorting, chart filters, cached artwork, and cancellable previews from authored excerpts or the middle of a song. Display authored or estimated intensity separately from chart difficulty.
- Route table-focused arrow, Return, and Space keys through the song controls, while retaining normal search-field text editing.
- Preserve a long, narrow perspective highway across window sizes. Smooth raised note shells, center their visible silhouettes on one timing row, and draw musical beat and bar lines from the chart's tempo and meter maps.
- Add recent rushing/dragging feedback, combo multipliers, five-star progress, and per-player song/difficulty personal bests. Persist complete attempts with retryable saves and revision-safe corrections from captured input timestamps.
- Integrate live recorded-drum stem controls and restore lesson MIDI mappings when leaving Songs. Keep private media and score archives outside the repository.

### Complete kit monitoring and separate recorded song drums

- Expand the pinned CC0 Big Rusty bank from 24 to 80 unchanged recordings. Add distinct high, mid, and floor toms, crash, ride, open hi-hat, and pedal hi-hat, each with four dynamic layers and two recorded takes. Verify every source hash and preserve the original starter samples.
- Load the full kit in both native audio engines. Monitor standard additional MIDI pads without changing the three-pad lesson scoring contract. Preserve learned aliases, stop open-hat tails on closure, and retain bounded voice pools.
- Add practice/reference stem mixing and tests. Separate recorded drums can be silent throughout practice while backing audio and the scoring timeline continue. Full mixes remain audible when their drums cannot be separated. Record the distinction from YARG's continuous hit/miss-gated recording in `docs/song-audio.md`.
- Pass 14 asset validation regressions, 218 native mixer checks under sanitizers, 44 real AVAudioEngine stem transport checks, full-kit Swift decode/MIDI checks, and 10,880 checks in the exported Mac shared app. Build the native Mac app. Physical kit balance and end-to-end latency remain to be auditioned.

### Clarify menu hierarchy and install the native app

- Group Continue with its progress, separate Settings from play choices, and make the selected lesson's availability or checkpoint state explicit. Keep native and shared menu presentation aligned for supported routes.
- Replace duplicate exits with destination-specific navigation and put keyboard focus on visible actions. Return activates once; MIDI navigation follows the same visible selection and excludes hidden controls.
- Use compact Settings sections, functional headings, quieter rows, and readable controls. Add viewport, scrolling, primary-focus, and locked-lesson checks.
- Add a signature-verified local installer for `/Applications/Drumx.app` that preserves the library/progress identity and retains the previous bundle. Define the menu and large-library acceptance gate separately from full M1 completion.

### Index large song collections without duplicating media

- Add reference imports for unpacked song directories, with atomic lightweight library summaries and lazy-play metadata. Keep managed single-song imports available and preserve identity when switching modes.
- Read authored preview start/end times. Tolerate a narrowly identified unused MIDI release-velocity quirk, and fall back from invalid declared duration tags while retaining the two-hour bound on real charts.
- Pass 31 importer tests. Validate a private 1,948-song collection: 1,942 songs have playable drums across four difficulties, and six have no drum track. Song media stays outside the repository.

### Give each desktop release a visible version

- Introduce a shared product VERSION and numbered `0.1.0-preview.N` GitHub releases. Embed the same version, workflow run, commit, and source state in both desktop packages; expose copyable build details in the native and shared main menus.
- Require the source and exported applications to report the exact packaged identity. Stamp OS metadata in a disposable export project, preserving a clean source checkout and signing the final resources.
- Add README build/release/download/license badges and update its download links automatically after verified publication. Preserve concurrent documentation edits and prevent older runs from replacing newer links. Include generated release notes.
- Make the native chord fixture use captured timestamps so CI scheduler delays cannot turn two simultaneous hits into false misses; retain separate checks for public keyboard timestamps and the live transport worker.
- Pass 87 Python tests, 126 native control checks, and 10,824 local source/exported shared checks. Hosted paired publication remains part of the release gate.

### Play imported songs on the native perspective highway

- Add Songs to the Mac main menu with directory scanning, search, authored difficulty selection, drag-and-drop import, synchronized audio stems, and separate song results. Restore the established perspective road, projected drums and cymbals, hit effects, and one shared NOW line across eight drum parts.
- Preserve captured input timing through pause, resume, device interruption, and negative song offsets. Decode Opus/Vorbis audio into a private cache with FFmpeg; package the Python importer with the native app.
- Build and inspect The Kill in the running app. Pass 5,577 song timing/replay checks across its four MIDI difficulties and a separate .chart arrangement, plus the existing native and portable scoring checks. Song playback currently ships in the native Mac app; the shared desktop preview retains its existing course.

### Import Clone Hero and YARG drum song packages

- Read song folders, ZIPs, and SNG packages with MIDI or .chart notes, all authored drum difficulties, tempo maps, pro-drum cymbal/tom markers, metadata, and backing stems. Scan song directories, deduplicate packages, and keep copied media in a private library.
- Validate with 17 generated-fixture tests and an independent comparison of all 4,067 notes across The Kill's four Harmonix difficulties. A second .chart arrangement verifies 115 tempo markers; downloaded media stays outside Git.

### Keep the main-menu headline stable when clicked

- Make the native "Find your rhythm" heading static and keep its text-field font synchronized with its responsive typography. Clicking it no longer enters a small-font text-selection state.
- Add native control regression coverage for headline focus, selection, typography at three window sizes, and continued menu activation.

### Add a full-kit song scoring contract

- Accept imported tempo-map timestamps for up to eight drum parts and full-length songs through a portable song API. Preserve the lesson API and snapshot layout; total results include every song pad.
- Validate song boundaries, chords, dense charts, invalid-input rollback, and returning to three-pad lessons. All existing native contracts and the added song checks pass.

### Publish the first automated versioned desktop release

- Publish [preview-9ddcab48cd71](https://github.com/claudfuen/drumx/releases/tag/preview-9ddcab48cd71) automatically after both exported applications pass 10,781 checks and same-commit verification in [CI](https://github.com/claudfuen/drumx/actions/runs/34728349618). The Git tag resolves to the complete verified commit and both permanent download assets have verified hashes.
- Pass 446 native history, 57 tempo, 194 readiness, 99 settings/course-control checks, native Mac compilation, and 41 Python distribution/signing-contract tests in hosted CI.
- Download both public ZIPs and pass 48 integrity/license checks against release hashes; execute the downloaded Mac app with all 10,781 checks passing. Include licenses, checksums, and the build manifest in the downloads. Record Mac ad-hoc signing and unsigned Windows honestly; Leap Labs Developer ID credentials and real notarization remain pending.

### Expand the curriculum and strengthen checkpoints

- Expand from 12 to 20 lessons in five chapters, adding slow doubles, paradiddles, kit applications, and groove/coordination studies. Preserve every original lesson ID, version, and event; name the existing alternating-hands study Single Stroke Roll.
- Keep three chapter columns per page with keyboard traversal and automatic reveal. Add suggested sticking beneath the notation counts, explicit listening/repair guidance, and a curriculum review with open C1 and next C2 phrasing/literacy gates.
- Require repeated comparable non-pulse 16-bar takes at authored tempos, with coverage and timing on each required instrument. Preserve earlier access, validate per-pad archives, and withhold checkpoints until results save successfully.
- Pass 10,781 shared source and exported Mac checks, 1,748 authored course checks, 2,419 audio/scoring integration checks, 194 readiness checks, and the native regression suite. Full visual and physical-kit acceptance remain open.

### License noncommercial use and prepare versioned releases

- Add the unmodified PolyForm Noncommercial 1.0.0 license, required attribution, and a separate paid-commercial-license route. Preserve third-party licenses and include all project notices in desktop packages and the native Mac bundle.
- Automate immutable commit tags and experimental GitHub prereleases after paired Mac/Windows verification, including both ZIPs, manifests, hashes, and licensing files. Fail on conflicting existing tags or assets.
- Prepare Developer ID signing, notarization, stapling, and Gatekeeper checks for the selected Leap Labs account. Real signing remains pending the correct certificate and credentials; unsigned/ad-hoc status is explicit.
- Replace the README's promotional copy with gameplay images, a course overview, downloads, controls, and concise gate links. Label reproducible native render fixtures accurately.
- Pass 41 Python packaging, publisher, content, and signing-contract tests. Hosted execution and the first automatic release follow from the committed candidate.

### Verify and link the premium-polish desktop pair

- Both source and exported applications pass 8,027 checks at `1ce2060` in [paired CI](https://github.com/claudfuen/drumx/actions/runs/34718163923). Verify clean matching commits, archive checksums, sample/font provenance, backend recovery, and archive ownership on Mac and Windows.
- Pass 446 native history, 57 tempo adapter, and 20 settings-control checks in hosted Mac CI, plus native Mac compilation. Update README download links and the premium gate evidence ledger.
- Keep the gate open for whole-app visual/resize acceptance, sustained frame pacing, physical-kit/audio sessions, and learner observation. These remain test artifacts; public releases are still held.

### Open input recovery directly from review

- Send the coached review's **Check kit & sound** action directly to Settings even when its captured MIDI setup has changed, while preserving the return to review.
- Pass 8,027 checks in source and exported Mac application, including the disconnected-review route. Verify the same final candidate in paired CI.

### Refine controls and protect interrupted sessions

- Keep the existing menu and settings composition while improving pad focus/hover, readable volume values, keyboard section navigation, disabled actions, and body-only scrolling for shorter windows. Preserve an explicit return from shared Settings to the page that opened it.
- Retain complete failed-save results by take ID independently of the active transport, retry between takes, and publish records/checkpoints only after persistence succeeds. Preserve captured conditions and late corrections; protect unsaved results when quitting or switching native players.
- Stop shared practice explicitly after MIDI disappearance or audio-device interruption. Require a deliberate input choice or audio retry before starting again; do not silently switch a disconnected kit to keyboard scoring.
- Reserve the shared progress archive with an operating-system lock before loading it; a second running copy cannot overwrite that history. Keep save results queued separately until durable writes succeed.
- Verify native settings target/action and overflow without showing a window, and preserve a bitmap-only component fixture for review. Extend paired CI with native history recovery and settings-control checks.
- Pass 8,026 checks in source and exported Mac application, the full native regression suite, 446 history / 57 tempo adapter / 20 control checks, 82 backend / 17 virtual CoreMIDI / 27 process-ownership checks, and native app compilation. Correct an actual UTF-8 bridge bug exposed by the Unicode archive fixture.
- Keep full rendered-window acceptance, physical-kit/audio testing, and frame-pacing measurements open under the premium quality gate. Paired Windows execution follows in CI.

### Define the premium practice quality gate

- Make the next M1 gate a coherent 30-minute practice session across the existing menus, lesson, settings, gameplay, review, and return journey.
- Specify visual/control/navigation/recovery criteria, display and frame-pacing targets, real-kit and learner evidence, paired-build integrity, severity levels, and zero blocking/major issues for closure.
- Keep interactive visual review, actual frame measurements, and physical-kit sessions explicitly pending. Automated tests and offscreen component renders cannot close those checks.

### Verify the coached desktop pair and refine its cues

- Both exported apps passed 7,900 checks at `20f30fc` and the follow-up `21e709f` in hosted CI; the same run passed the 57 Swift adapter checks, compiled the native Mac app, and verified matching clean-commit packages. Link the verified test downloads from the README.
- Inspect an offscreen render of the native pace component, soften its accent to the shared palette, and avoid marking untested opening paces as earned after a direct checkpoint attempt. A no-input review now points to kit and sound settings.
- Keep the complete rendered-window review and physical MIDI session open; component inspection and packaged execution establish different things.

### Connect coached pulse and refine the playing experience

- Connect the shared tempo policy to native Mac and shared Mac/Windows preparation and review. Offer one recommended action, direct checkpoint attempts, optional faster challenges, and an explicit free-practice route with independent saved choices.
- Introduce the first versioned tempo unlock while retaining previously available lessons and legacy scores. Preserve immutable take settings, compare exact input conditions, reevaluate disconnected setups, and support same-ID corrections without double counting.
- Add a compact pace card, visible checkpoint criteria, contextual lesson-star labels, stronger button hierarchy, readable focus states, and restrained shaded catcher surfaces with a short neutral contact highlight. Keep the established timeline, perspective, and instrument positions.
- Pass 7,900 source and exported Mac checks, 57 native Swift tempo checks, and the full native regression suite. Extend CI with the pure Swift adapter checks and native Mac app compilation, alongside both shared desktop packages. The full visual acceptance and real-MIDI playtest remain open; a successful automated build is not a visual sign-off.

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
