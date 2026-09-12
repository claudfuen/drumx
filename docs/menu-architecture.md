# A menu that can grow with the player

Drumx opens into a game, with a clear place to continue, explore, or adjust the setup. The current Mac app has **Continue, Learn, and Settings**. Future destinations enter when they support a complete activity. There is no Practice, song library, store, or unavailable-course button in the current main menu.

This document describes navigation and its expansion boundaries. The [native guide](native-lab.md) explains the controls; [learning milestones](learning-milestones.md) define the evidence required to call the product or a learner ready. **M1 remains active.** A commercial-quality game suitable for Steam is the experience target. Pricing, a Steam launch, distribution, and a project-wide source license remain undecided.

## The current journey

| Place | Player's purpose | Current behavior |
| --- | --- | --- |
| Welcome | Establish a starting point | Name a local player, try the keyboard, or connect a kit. Let's play opens the main menu. |
| Main menu | Choose what to do now | Continue opens the saved lesson; Learn explores Foundations; Settings opens preferences. The player name identifies whose progress is active. |
| Learn | See the path ahead | Three illustrated chapter cards reveal four lesson steps each. Future chapters are inspectable. Available cards start lesson preparation; locked cards explain a prerequisite and cannot start. |
| Lesson | Understand and prepare | Objective, counts, original staff study, demonstration, tempo, phrase length, guidance, and a lesson check. |
| Practice stage | Play the phrase | Count-in, one musical timeline, stable kit positions, selected aids, and captured input. |
| Review | Choose the next useful action | Inspect the take, retry, slow down, isolate a bar, reduce help, answer a reading check, or open the next available lesson. |
| Settings | Make the shared setup comfortable | Four sections cover kit, sound, playing preferences, and players/progress. |

**Continue means the saved selected lesson.** It opens preparation with that player's saved tempo, guidance, live timing, and phrase length. It does not automatically start playback, jump to a newly unlocked lesson, or resume an interrupted bar. Choosing another available lesson changes that saved destination.

The main menu carries the return-to-practice action. The chapter journey spends its space on chapters, sequence, and access rather than repeating a large resume panel. Its original rhythm graphics distinguish chapters; actual staff notation remains in the lesson.

## Navigation and interruption rules

**Back** follows the local hierarchy: review to lesson, lesson to chapter journey, course to main menu. Settings remembers the page that opened it. **Main menu** gives a direct way home.

After welcome, **Esc** closes an open lesson-check or player sheet first. During a count-in, take, or demonstration it stops the phrase and opens pause. Elsewhere it returns to the main menu; it has no further destination on the main menu itself.

The current pause page offers **Restart with count-in**, **Review this take** for practice, and **Main menu**. A paused demonstration offers restart or main menu. Restart begins the entire phrase again. There is no mid-bar transport resume. If the phrase already finished when Escape arrives, the completed review remains visible. An unfinished phrase does not become a completed archive record, personal best, or lesson clearance.

Keep these controls predictable as screens grow. A new overlay must dismiss before navigation acts behind it. A new transport mode must define exactly what pause, restart, and completion mean before inheriting the existing labels.

## Identity and settings have different jobs

The player name on the main menu answers **who is playing**. It opens the same player manager as Settings → Players & progress. Switching or adding a player selects a separate lesson position, practice archive, and learning checks. Renaming preserves those records. There are no accounts, profile deletion, or cloud synchronization.

Settings answers **how this setup should work**:

| Section | Stable responsibility |
| --- | --- |
| Your kit | Input source, pad mappings, and evidence that the selected source is reaching the expected instruments. |
| Sound | App monitoring, drum/demo volume, and listening-route explanation. |
| Playing | Sticking suggestions, scoring offset, and guidance about accessibility and lesson controls. |
| Players & progress | Manage local identities and understand what is saved. |

Kit mappings, source preference, sound, volume, sticking suggestions, and scoring offset are shared on the Mac. Lesson tempo, phrase length, and assistance belong to the player's current practice. Keep those decisions near the lesson rather than duplicating them in global settings. Settings changes save automatically; leaving Settings or quitting commits an edited offset. Unreadable profile/archive data is preserved and practice-storage errors appear in the status.

## Unlocks invite another step

The current foundation policy is deliberately small. A valid completed take of **at least four bars**, with **80% of expected notes matched**, clears a step. A chapter transition also needs a correct reading response for the preceding chapter's final lesson. One-bar repair work remains available but does not clear the step. Every locked lesson names its prerequisite.

Matching uses the ordinary instrument/timing window. The tighter on-time grade, star tiers, and extra-hit penalty belong to the game score; they do not set this unlock ratio. Neither click-only recall nor the technique checkbox is required by the current access rule. **Step complete** and **lessons cleared** are game progression labels, not mastery claims.

Saved positions and earlier practice preserve existing players' access when this policy is introduced. Older lesson revisions can retain access without passing the current revision's checks. Keep access, current-version clearance, reading, recall, and technique evidence distinct when content changes.

The four-bar/80% rule is a **starting hypothesis not yet validated with beginners**. Observe whether it provides useful challenge and momentum, then refine it using learner evidence. Broader readiness needs counts, reading, reduced-aid performance, later recall, transfer, and appropriate technique observation. Do not quietly replace that evidence with stars or a higher speed target.

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

The current interface is a custom **Swift/AppKit Mac shell**. AppKit controls do not become a Windows interface because they are drawn differently. The **C++ scoring core and C interface are portable**; authored content, progression, and presentation are separated conceptually, but the current lesson and progress models are Swift. They need extraction or porting. Windows also needs its own input, audio, packaging, and hardware validation.

Choose the production renderer/engine **before large content expansion**. Carry this navigation and learning contract into that decision, then prove a representative launch → lesson → play → review → return slice with authoritative native timing, accessible controls, and reliable saves. See the [rendering plan](rendering-plan.md). Physical-kit latency, sustained frame pacing, and a real beginner's complete journey remain unverified.

Implementation references: [main menu](../native/macos/DrumxMainMenuView.swift), [chapter journey](../native/macos/DrumxCourseViews.swift), [navigation and transport](../native/macos/DrumxLab.swift), [settings and pause](../native/macos/DrumxSettingsController.swift), [lesson journey](../native/macos/DrumxJourneyController.swift), and [unlock policy](../native/macos/DrumxUnlocks.swift).
