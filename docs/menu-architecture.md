# A menu that can grow with the player

Drumx opens into a game, with a clear place to continue, explore, or adjust the setup. The current Mac app has **Continue, Learn, and Settings**. Future destinations enter when they support a complete activity. There is no Practice, song library, store, or unavailable-course button in the current main menu.

This document describes navigation and its expansion boundaries. The [native guide](native-lab.md) explains the controls; [learning milestones](learning-milestones.md) define the evidence required to call the product or a learner ready. **M1 remains active.** A commercial-quality game suitable for Steam is the experience target. Pricing, a Steam launch, distribution, and a project-wide source license remain undecided.

## The current journey

| Place | Player's purpose | Current behavior |
| --- | --- | --- |
| Welcome | Establish a starting point | Name a local player, try the keyboard, or connect a kit. Let's play opens the main menu. |
| Main menu | Choose what to do now | Continue opens the saved lesson; Learn explores Foundations; Settings opens preferences. The player name identifies whose progress is active. |
| Learn | See the path ahead | A 12-node path groups the lessons into five chapters. Selecting any node, including a locked step, updates one featured lesson. Its play action opens preparation only when available. |
| Lesson | Understand and prepare | Objective, counts, original staff study, demonstration, and a lesson check. Start playing uses the saved plan; collapsed Practice options holds tempo, phrase length, and assistance. |
| Practice stage | Settle into the pattern | A four-beat count-in leads into a finite block, with one musical timeline, stable kit positions, selected aids, and captured input. New lessons default to 16 bars at their suggested tempo. |
| Review | Choose the next useful action | Inspect the take, retry, slow down, isolate a bar, reduce help, answer a reading check, or open the next available lesson. |
| Settings | Make the shared setup comfortable | Four sections cover kit, sound, playing preferences, and players/progress. |

**Continue means the saved selected lesson.** It opens preparation with that player's saved tempo, guidance, live timing, and phrase length. It does not automatically start playback, jump to a newly unlocked lesson, or resume an interrupted bar. Choosing another available lesson changes that saved destination.

The responsive main menu carries the return-to-practice action. Learn presents one featured step and a compact path so exploration has a clear destination. Its five-star display shows the player's best saved result for the current lesson version across any conditions; review keeps condition-matched personal bests. Actual staff notation remains in the lesson.

The default 16-bar block lasts about 53–80 seconds at the unit's 48–72 BPM starting tempos, plus count-in. It gives a player more uninterrupted repetition before review. One-, four-, and eight-bar choices remain available in Practice options; one-bar repair is still a finite take. The cadence is a product hypothesis, not a learning gate or an endless automatic loop. See the [practice-loop note](first-practice-loop.md).

## Navigation and interruption rules

**Back** follows the local hierarchy: review to lesson, lesson to chapter journey, course to main menu. Settings remembers the page that opened it. **Main menu** gives a direct way home.

After welcome, **Esc** closes an open lesson-check or player sheet first. During a count-in, take, or demonstration it stops the phrase and opens pause. Elsewhere it returns to the main menu; it has no further destination on the main menu itself.

The current pause page offers **Restart with count-in**, **Review this take** for practice, and **Main menu**. A paused demonstration offers restart or main menu. Restart begins the entire phrase again. There is no mid-bar transport resume. If the phrase already finished when Escape arrives, the completed review remains visible. An unfinished phrase does not become a completed archive record, personal best, or lesson clearance.

Keep these controls predictable as screens grow. A new overlay must dismiss before navigation acts behind it. A new transport mode must define exactly what pause, restart, and completion mean before inheriting the existing labels.

**Navigate with my drums** is opt-in under Settings → Playing. With a MIDI source selected, hi-hat selects previous, snare selects next, and two quick kick hits activate the highlighted action. The current scope is the main menu, lesson preparation, review, and pause; it is inactive during transport, mapping, and open sheets. Learn, Settings, player management, and detailed options retain keyboard/mouse navigation. Do not advertise this as a complete hands-free setup or browsing flow.

## Identity and settings have different jobs

The player name on the main menu answers **who is playing**. It opens the same player manager as Settings → Players & progress. Switching or adding a player selects a separate lesson position, practice archive, and learning checks. Renaming preserves those records. There are no accounts, profile deletion, or cloud synchronization.

Settings answers **how this setup should work**:

| Section | Stable responsibility |
| --- | --- |
| Your kit | Visual instrument selection, input source, note aliases, and raw note/velocity receipts, including unmapped input. |
| Sound | App monitoring, drum/demo volume, and listening-route explanation. |
| Playing | Optional drum-menu controls, sticking suggestions, scoring offset, and guidance about accessibility and lesson controls. |
| Players & progress | Manage local identities and understand what is saved. |

Kit mappings, source preference, sound, volume, sticking suggestions, drum-menu preference, and scoring offset are shared on the Mac. Lesson tempo, phrase length, and assistance belong to the player's current practice. Keep those decisions near the lesson rather than duplicating them in global settings. Settings changes save automatically; leaving Settings or quitting commits an edited offset. Unreadable profile/archive data is preserved and practice-storage errors appear in the status.

Adding a MIDI note preserves the selected instrument's other aliases and moves a conflicting note from its former owner. Raw receipts help distinguish an unassigned note from absent input. This remains a three-instrument mapping surface, with physical-kit validation outstanding; it does not yet distinguish every drum zone or hi-hat articulation.

## Unlocks invite another step

The pulse step has a coached 72 BPM checkpoint. Every later step uses its authored tempo, 16 bars, and Guided notes, with two qualifying takes within three comparable attempts. Each required instrument needs 80% matched and 70% on time; total extras must stay within 10% of expected targets. A chapter transition also needs a correct reading response for the preceding final lesson. **Use checkpoint settings** prepares the required conditions without launching a take.

Short repair, manual tempo, and reduced-guidance practice remain useful without clearing that guided checkpoint. Scores and technique self-checks remain separate. Existing access is frozen on upgrade without treating old aggregate scores as the new per-instrument evidence. Later difficult practice does not erase an earned checkpoint; corrected attempts are reevaluated.

The rules are product hypotheses awaiting beginner observation. Broader readiness still needs counts, reading, reduced-aid performance, later recall, transfer, and technique observation. See the [curriculum review and gate](curriculum-review.md).

The path displays at most three chapters per page, with one featured lesson. Previous/next chapter-page controls and a visible range make the remaining chapters discoverable. Keyboard movement can cross page boundaries; resuming or recommending a lesson reveals its chapter. Keep lesson targets readable rather than compressing an expanding course into one diagram.

## Expansion without a larger front door

| When a complete experience exists | Route | Boundary to preserve |
| --- | --- | --- |
| A second course | Learn → course collection → chapter → lesson | Keep Learn as the entry point. Today it goes directly to Foundations because there is one course. |
| Named rudiments and deeper coordination | A course within Learn | Teach and validate its own vocabulary, notation, prerequisites, and hardware needs. Adding a title is not adding a course. |
| Free play or a useful drill tool | Main menu → Practice → activity | A separate, self-directed space. It can reuse instruments, timing, and scoring without implying completion of a taught lesson. Practice is not a current menu item. |
| Scheduled recall and targeted revision | Continue and relevant lesson/review prompts | Give the player a specific task and its reason before creating another navigation category. Preserve the option to revisit available lessons. |
| More player levels and course entry points | Course collection and course introduction | Explain expected skills and offer an evaluated starting route. The current app does not perform automatic placement. |

The lasting hierarchy is **Learn → course → chapter → lesson → practice → review**. With only one course, skip the collection screen. Add filtering or search only when a real collection makes browsing difficult. Do not add empty destinations to advertise possible future features.

## Visual system and platform boundary

Menus, cards, selectors, toggles, and sliders should share the game's typography, spacing, colors, and state treatments. Custom appearance must retain meaningful keyboard focus, value changes, readable disabled states, accessible labels, and reduced-motion behavior. Hover can reinforce an action; it must not be the only way to discover one. Locked steps need text, not color alone.

The current interface is a custom **Swift/AppKit Mac shell**. AppKit controls do not become a Windows interface because they are drawn differently. The **C++ scoring core and C interface pass hosted macOS/Windows contracts**. The experimental Godot app consumes verified JSON exported from the Swift lesson source and uses native input/audio adapters on both systems. Both exported executables run in CI. Presentation parity, full profile-feature parity, physical hardware, and release acceptance remain open. See the [cross-platform baseline](cross-platform.md#what-has-been-verified) for the actual CI evidence and its limits.

Choose the production renderer/engine **before large content expansion**. Carry this navigation and learning contract into that decision, then prove a representative launch → lesson → play → review → return slice with authoritative native timing, accessible controls, and reliable saves. See the [rendering plan](rendering-plan.md). Physical-kit latency, sustained frame pacing, and a real beginner's complete journey remain unverified.

Implementation references: [main menu](../native/macos/DrumxMainMenuView.swift), [chapter journey](../native/macos/DrumxCourseViews.swift), [navigation and transport](../native/macos/DrumxLab.swift), [settings and pause](../native/macos/DrumxSettingsController.swift), [lesson journey](../native/macos/DrumxJourneyController.swift), and [unlock policy](../native/macos/DrumxUnlocks.swift).
