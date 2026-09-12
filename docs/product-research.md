---
question: Which product approach and technical foundation should Drumx use to become a polished, responsive MIDI drum trainer?
date: 2026-09-12
updated: 2026-09-12
status: provisional
confidence: medium
tags: [drumx, drums, midi, product-design, desktop, game-engines, latency]
decays: 2026-12-12
---

# A polished MIDI drum trainer: product and engine research

## Bottom line

The current product hypothesis is a structured drum-learning app with a rhythm game's immediate appeal. Melodics is the main reference for its learning tools and progression, while YARG informs responsive, enjoyable play. Short guided exercises lead into musical application and occasional scored attempts without the visual track, including a later recall check. The full track remains available for learning and enjoyable performance; assistance removal is not the whole product or a requirement for every run. Unity and Flutter remain front-end candidates with an independent native timing/audio engine; neither the concept nor stack has been accepted or hardware-tested. The follow-up pitch is in `docs/pitch.md` in the Drumx repository.

## What we found

All current product and API observations below were checked on September 12, 2026. Product-fit judgments and the proposed learning experience are design inferences, not measured educational outcomes.

### The product choice comes before the renderer

| Direction | Main experience | Why it is attractive | What it needs to teach drums well |
| --- | --- | --- | --- |
| Performance game | Choose a song, follow a moving note highway, build a performance | Anticipation, musical momentum and replayability | Accurate musical parts, a deliberate skills curriculum, articulation support and useful feedback beyond a combo |
| Guided practice studio | A short lesson introduces a skill, focused repetition develops it, then a groove applies it | A clear next step and a reason for each exercise | Excellent explanations, adaptable difficulty and a practice surface that feels satisfying |
| Practice instrument | Choose or edit a pattern, set the tempo and play against precise feedback | Fast access, freedom, depth and a restrained interface | Enough guidance for a beginner and evidence of progress across sessions |

These approaches can share a musical engine, but trying to build three complete products at once would dilute the first version. The current pitch puts a structured learning path around one game-like practice surface, demonstrated through Follow, Fade, Recall and Review. It retains a musical model beneath the visual lane and a clear route to playing with less visual assistance. This refinement balances the request for Melodics-like learning quality with enjoyable YARG-style play and concern about dependence on the visible track.

### Melodics: the most directly relevant reference

Melodics documents structured progression, MIDI feedback, rudiments, adjustable tempo and looping. Its Practice Mode supports waiting for the correct note and automatically increasing tempo after successful playing. The important reusable interaction is the movement between a difficult passage and the whole performance. [Drum product page](https://melodics.com/drums), [Practice Mode](https://support.melodics.com/en/articles/6777027-practice-mode), [learning structure](https://melodics.com/how-it-works).

Product inference: Drumx should preserve that learning backbone through clear objectives, a brief demonstration, adjustable tempo, focused loops and musical application. The proposed Learn activity recommends the next useful skill; Play revisits familiar material with the full track if desired. Memory checks can add information about progress without replacing those tools or making assistance feel like a failure. A note-by-note discovery aid should not be scored as continuous rhythm performance.

Its setup documentation includes manual instrument mapping and velocity-related troubleshooting. This supports treating kit setup as a central experience in Drumx. The documented ability to restart through the instrument is also relevant: a drummer holding sticks should not need to reach for the mouse after every attempt. [Getting started](https://support.melodics.com/en/articles/6777061-get-started-with-melodics), [settings](https://support.melodics.com/en/articles/6777096-melodics-app-settings).

The public drum page and its screen imagery were viewed in a browser. The imagery shows instrument feedback, session results, and practice/performance concepts. This was inspection of the public website, not a hands-on test of the installed app. No claim about its actual latency follows from that inspection.

Do not claim that Melodics lacks notation based on old reviews. Its official settings already describe traditional drum ordering; search also surfaced reports of a newer Drum Chart view, whose precise behavior was not independently verified through current official documentation. Its current desktop implementation stack was likewise not confirmed from primary sources. A mirrored historical Qt/QML job advertisement is not adequate proof of today's stack.

### Other learning references add different strengths

| Reference | Verified emphasis | What Drumx can learn from it |
| --- | --- | --- |
| Drumeo / Musora | Teacher instruction, a structured method, rudiment demonstrations, notation and song practice controls | Explain the physical movement and musical purpose, alongside timing feedback. [Rudiments](https://www.drumeo.com/beat/rudiments/), [song tools](https://help.musora.com/article/1293-what-are-songs) |
| Upbeat Studio: Drum Coach and Drum Notes | A practice-planning product and a separate rhythm editor with sticking, accents and notation | Keep the guided daily session simple, while giving experienced players a way to explore and author exercises. [Coach](https://upbeat.studio/drum-coach/), [Notes](https://upbeat.studio/drum-notes/) |
| Groove Scribe | Editable patterns, subdivisions, sticking, metronome variations, playback and printable notation | Make a pattern understandable and editable, with one musical variable changed at a time. [Public tool](https://www.mikeslessons.com/groove/) |

These pages establish the documented features, not the effectiveness of their teaching. Live MIDI grading was not established for these comparators from the inspected pages. Drumap currently leads to Upbeat Studio, so its older product identity should not be treated as the current full offering.

### Rock Band-style play can use a real kit, but the chart is still an abstraction

YARG and Clone Hero support MIDI electronic drum kits. YARG's source identifies Unity and separates gameplay logic into YARG.Core. Clone Hero documents MIDI mapping, velocity thresholds, Pro Drums and section practice with speed control. They are relevant technical precedents for the game direction. [YARG repository](https://github.com/YARC-Official/YARG), [YARG.Core](https://github.com/YARC-Official/YARG.Core), [Clone Hero mapping](https://wiki.clonehero.net/books/guitars-drums-controllers/page/drum-mapping-guide), [practice controls](https://wiki.clonehero.net/books/clone-hero-manual/page/how-to-play).

A concrete simplification matters: Clone Hero's MIDI setup maps both open and closed hi-hat to the same yellow cymbal. Drumx should retain those articulations where the kit reports them. A visually similar lane could still carry a richer musical model. [Clone Hero MIDI setup](https://wiki.clonehero.net/books/guitars-drums-controllers/page/midi-drums).

Design inference: song momentum and immediate feedback are useful, but completing a chart cannot by itself establish good sticking, grip, rebound, phrasing or the ability to play without visual cues. Training needs moments where support is reduced and the learner reproduces or applies the idea independently.

### What polished shipped products actually use

These are technology precedents. Describing their design as relevant is an aesthetic judgment; their success does not constitute a benchmark for Drumx.

| Technology | Primary-source precedent | What the example establishes |
| --- | --- | --- |
| Unity | Beat Saber in Unity's official showcase; the Monument Valley 3 team describes its Unity art/design workflow | A full game engine can support both expressive rhythm interaction and restrained, art-directed visuals. [Games](https://unity.com/games), [Monument Valley workflow](https://unity.com/resources/monument-valley-3-blurring-art-and-design) |
| Flutter | Official Superlist and Rive case studies; Superlist's Mac release and Rive's Mac/Windows downloads | A coherent application framework has shipped in consumer productivity and graphics-heavy creation tools. [Superlist](https://flutter.dev/showcase/superlist), [Superlist download](https://help.superlist.com/en/articles/10068-download-superlist), [Rive case](https://flutter.dev/showcase/rive), [Rive downloads](https://www.rive.app/downloads) |
| JUCE with additional UI layers | Output's engineer describes JUCE use in Arcade and explicitly discusses a web UI layer | A native audio engine and web-facing UI can coexist in professional music products; this is not evidence that all Arcade visuals are stock JUCE widgets. [Output engineering interview](https://juce.com/made-with-juce/jennifer-from-output/) |
| Qt / QML / C++ | MuseScore's current build source and its announced Qt 6 transition | A substantial notation application uses a native cross-platform toolkit. This is a relevant music-software precedent, not evidence that Melodics uses the same current stack. [Build source](https://github.com/musescore/MuseScore/blob/main/CMakeLists.txt), [Qt transition](https://musescore.org/en/comment/1231852) |

The Output example is a useful check against an overly simple native-versus-web conclusion. The real decision is which complete authoring and runtime system gives this product the most reliable route to its desired experience. A rendering library alone does not supply scene design, a motion language, curriculum tooling or a timing engine.

### Stack shortlist

1. **Flutter + native Rust or C++ engine** is the first candidate for a restrained practice studio. Flutter provides its own rendering, layout and animation machinery, native desktop builds and a native-code integration boundary. Use a custom visual system and a purpose-built practice scene. Standard Material styling is not the art direction. Keep the audio/MIDI path on native threads. [Flutter architecture](https://docs.flutter.dev/resources/architectural-overview), [native integration](https://docs.flutter.dev/platform-integration/bind-native-code).
2. **Unity + native MIDI/audio engine** is the first candidate if playing should feel like entering an authored rhythmic scene. It brings integrated animation, assets, shaders and game authoring. Native plugins provide the hardware boundary. Input scoring must not wait for a frame's `Update()`. Either Unity's DSP timeline or the native engine owns audio, with explicit clock alignment. [Desktop native plugins](https://docs.unity3d.com/6000.3/Documentation/Manual/plug-ins-for-desktop.html), [scheduled audio](https://docs.unity3d.com/6000.3/Documentation/ScriptReference/AudioSource.PlayScheduled.html).
3. **C++ + JUCE** remains the integrated music-software alternative. It reduces the number of independently assembled audio/device subsystems, with more C++ and custom interface work. Its licensing needs to fit the eventual distribution model. [Features](https://juce.com/features/), [licensing](https://juce.com/legal/).

Electron with a native engine remains technically viable, but it is not the default recommendation for this exploration. PixiJS is a GPU scene renderer, not a complete answer to the requested engine and design workflow. Fully native Rust with egui/wgpu and Godot were also considered; they are not the initial shortlist because the former needs more consumer-interface construction and the latter adds another engine candidate without stronger evidence of fit than Unity for the present brief. Those are effort judgments, not performance findings.

### Proposed first experience

The following is a product hypothesis to test, not a feature commitment:

1. **Arrive:** select a player and connect the kit. Hit highlighted pads to confirm mapping, then hear a click through the chosen listening route. Save separate player progress and reusable kit configurations.
2. **Understand:** a short visual demonstration introduces one idea, with spoken counts and optional sticking. A developing player can skip to a harder variation.
3. **Repeat:** practice that idea on one calm, readable surface. Loop a beat or bar, adjust tempo, and inspect one useful feedback signal at a time.
4. **Apply:** use the same idea in an original groove or short musical challenge. The presentation becomes more expressive while preserving the same timeline and scoring model.
5. **Retain:** briefly reduce visual guidance or ask for an unprompted repeat. End with one actionable next step and a record of repeatable performance.

For example: learn the single paradiddle, repeat it evenly, place accents deliberately, then move selected strokes around the kit in a groove. Higher levels should add musical dimensions such as dynamics, articulation, orchestration, coordination, subdivision and phrasing. Merely raising BPM or tightening a hit window is not a complete advanced curriculum.

The eight lesson drafts in this repository are introductory material only. They are not a finished curriculum for every level. The underlying model will need explicit beat positions, instrument/articulation, dynamics and optional sticking, including support for rests, tuplets and grace-note relationships. A fixed equal-step grid is insufficient for the whole rudiment vocabulary.

### What makes the presentation feel finished

The proposed acceptance criteria are concrete:

- One typography and spacing system, a small deliberate palette, clear focus and a stable hit line.
- Timing feedback that communicates early, centered and late without covering the next notes.
- Predictable scene transitions, paced animation and feedback that remains readable from the kit.
- A responsive direct-play path, large controls, keyboard support and an optional instrument-based restart gesture.
- Consistent sound levels and intentional sound design; decorative effects remain secondary to reading and playing.
- Smooth delivery on the actual target display, including frame-time tails, not just an average frame-rate counter.

The interactive design mockup renders the same short exercise through Follow, Fade, Recall and Review, with studio and stage treatments for comparison. It is a concept preview with illustrative results, not a MIDI implementation or latency benchmark. Test the real implementation for readability, enjoyment and perceived responsiveness before building a full lesson library.

### Pedagogy refinement: remove assistance and measure what remains

The proposed loop distinguishes future instructions from immediate performance feedback. A genuine no-chart memory attempt removes both the upcoming notes and live correctness displays, retains the player's sound and a quarter-note click, and reveals results after the phrase. Guided, immediate recall, later recall and transfer should be recorded separately.

Experiments on bimanual coordination show that dependence on augmented visual feedback can occur, while a complex movement-task experiment shows that frequent feedback can also improve retention. This supports a testable, reversible assistance policy rather than a universal rule to remove help quickly. Neither study establishes this exact drum-chart design. [Ronsse et al., 2011](https://pubmed.ncbi.nlm.nih.gov/21030486/), [Wulf et al., 1998](https://www.tandfonline.com/doi/abs/10.1080/00222899809601335).

Music-memory research supports retaining auditory information during learning and examining later recall. The proposed progression therefore includes a later no-chart check, plus musical application, rather than calling a same-session high score mastery. The cited piano findings have limited transfer to novice drum learning and do not determine the app's thresholds. [Finney and Palmer, 2003](https://link.springer.com/article/10.3758/BF03196082), [Duke et al., 2009](https://journals.sagepub.com/doi/10.1177/0022429408328851).

### Responsiveness and hardware boundaries

MIDI capture, authoritative scoring and metronome audio should operate independently of display work. Preserve input timestamps, align them with predicted audible output, generate clicks on the audio sample timeline, and send timestamped state to the renderer. The detailed measurement plan is in `docs/architecture-options.md` in the Drumx repository. CPAL and JUCE provide relevant native callback/timestamp infrastructure, but neither guarantees a particular end-to-end delay. [CPAL timestamps](https://docs.rs/cpal/latest/cpal/struct.OutputStreamTimestamp.html), [JUCE callback](https://docs.juce.com/master/classjuce_1_1AudioIODeviceCallback.html).

Alesis documents USB MIDI for the Turbo module. Its general connection guide distinguishes MIDI from USB audio and flags beginner-module limitations around remapping the pedal. Drumx should adapt its mapping rather than require module edits. The exact kit model and its observed events still need a hardware check. [Turbo manual](https://www.alesis.com/rscdn/1937/documents/Turbo%20Drum%20Module%20-%20User%20Guide%20-%20v1.3.pdf), [Alesis computer connection guide](https://support.alesis.com/support/solutions/articles/69000822838-alesis-drums-connecting-your-kit-to-a-computer).

Standard Note On data identifies channel, note and velocity. If both hands produce the same snare message, hand attribution cannot be recovered from those fields. Sticking can be taught, but should not be labeled verified. Velocity can help evaluate relative dynamics after kit setup; it is not a universal physical-force measurement. [MIDI messages](https://midi.org/about-midi-part-3midi-messages).

Commercial song access is its own workstream. YARG explicitly advertises licensed official songs; that does not make those permissions transferable to Drumx. Original exercises and permission-cleared backing tracks allow the core experience to stand on its own while song-content options are investigated. [YARG](https://yarg.in/).

## Method

The research question was: which product approach and technical foundation can deliver a polished, responsive desktop MIDI drum trainer that teaches transferable skills? A useful answer required distinct product choices, verified shipped technology precedents, a provisional recommendation and a testable latency plan.

Searched prior Assistant research notes for drums, MIDI, Melodics and rhythm games; no direct relevant note was found. Compared official product/support pages for Melodics, Drumeo/Musora, Upbeat Studio and Groove Scribe; official repositories/docs for YARG and Clone Hero; official case studies and API documentation for Unity, Flutter, JUCE, Qt, Electron, PixiJS, egui/wgpu, CPAL and midir; and Alesis hardware documentation. Independent bounded research lanes covered learning products, game/MIDI precedents and shipped UI frameworks. Viewed Melodics' public drum page and screen imagery in Chrome. A follow-up pass checked primary motor-learning and music-memory studies to refine cue removal, feedback timing and retention checks. Interactive conceptual mockups were prepared for review; their illustrative scores are not measurements.

Excluded app-store efficacy slogans, anonymous performance claims and old forum complaints as grounds for ranking. A historical mirrored Melodics Qt/QML vacancy and community reports about its newer Drum Chart were treated as unconfirmed leads. No accounts were created, trials started, software purchased, competitor apps installed, personal data submitted or hardware benchmarks run. No third-party screenshots or recordings were copied into the repository.

## Confidence and limits

High confidence in the documented product features and cited technology examples within the scope each source supports. Medium confidence in the product and stack recommendation, which is an engineering/design judgment before a prototype or learner trial. No confidence claim is made about the relative measured latency, memory use or frame stability of candidate implementations because none has been built or benchmarked.

The product comparison uses public documentation and selected website imagery, not full installed-app testing. The benefits claimed by vendors are not independent evidence of learning outcomes. Software versions, features and licensing change, so final selection requires checking the versions and terms actually adopted. A teacher should review the curriculum, particularly technique guidance and advanced rudiments.

## Open threads

- Compare a minimal practice treatment with an expressive performance treatment using the same short exercise.
- Validate the native MIDI/audio path and audio routing with an actual entry-level kit, then a second module.
- Choose Flutter or Unity based on the interaction test and maintainability, not screenshots alone.
- Determine how notation, reduced guidance and musical application support learning outside the app.
- Set a realistic first course for several ability levels, with original backing material and separate player progress.

## Sources

The direct links beside each claim are the evidence trail. The main anchors are [Melodics practice](https://support.melodics.com/en/articles/6777027-practice-mode), [Drumeo rudiments](https://www.drumeo.com/beat/rudiments/), [Groove Scribe](https://www.mikeslessons.com/groove/), [YARG source](https://github.com/YARC-Official/YARG), [Clone Hero MIDI](https://wiki.clonehero.net/books/guitars-drums-controllers/page/midi-drums), [Flutter's Rive case](https://flutter.dev/showcase/rive), [Unity's games](https://unity.com/games), [Output's JUCE interview](https://juce.com/made-with-juce/jennifer-from-output/), and [Alesis hardware guidance](https://support.alesis.com/support/solutions/articles/69000822838-alesis-drums-connecting-your-kit-to-a-computer).
