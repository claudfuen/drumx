# M1 quality gate: a premium practice session

**Status: OPEN.** This is the active polish gate within M1. It covers the existing foundation experience before adding more lessons or systems.

**Player outcome:** a beginner can spend 30 minutes learning and practising, understand what to do next, take a break, and return with their work intact. Every screen should look and behave like part of the same deliberate game. Both desktop packages must meet the same standard for their declared scope.

The native Mac app remains the presentation baseline. The shared Mac/Windows port has documented feature gaps; a polished screen does not close those gaps or establish full product parity. Public shared releases remain behind the acceptance decision in [desktop-preview.md](desktop-preview.md).

## What must pass

| Gate | Pass criteria | Required evidence |
| --- | --- | --- |
| **Q1. Visual coherence** | One type, spacing, color, and control hierarchy across menu, Learn, preparation, settings, pause, gameplay, and review. Primary actions are obvious; secondary actions recede. No clipped essential text, stray native chrome, placeholder controls, crowded action rows, or misleading progress markers. | Rendered comparisons at the minimum 1020×780 logical size, 1440×900, and 1920×1080. Inspect focus, hover, pressed, disabled, empty, and error states. Windows at 100%, 150%, and 200% scaling; Mac Retina. |
| **Q2. Navigation and focus** | Enter activates the focused enabled action once. Escape pauses gameplay and returns menus to Main menu, closing an active modal first. Settings also provides an explicit return to where it was opened. Tab/Shift-Tab reach every actionable control; hidden and disabled controls do not take focus or activate. No keyboard strike accidentally activates a menu control during play. | Repeated mouse and keyboard journeys, including settings opened from preparation/review, the lesson-check modal, pause/restart, and locked lessons. Test equivalent routes where each platform supports them. |
| **Q3. Practice feel** | One shared timing line, stable perspective and instrument positions, a soft horizon, legible notes, and distinct physical-strike/matched/extra feedback. Click-only hides judgment until review. Effects are restrained, velocity-aware, and respect reduced motion. Tempo remains fixed through the phrase. | Side-by-side gameplay captures using the same authored chart and representative simultaneous/soft/extra hits. Existing projection/scoring contracts must remain green. |
| **Q4. Responsive execution** | Native capture and audio scheduling remain authoritative. At a stated 60 Hz test configuration, at least 95% of frame intervals are ≤20 ms, 99% ≤34 ms, and no steady-play frame stalls >100 ms in a warmed 10-minute run. No audible missing/doubled triggers, click drift, or output breakup during a 30-minute physical-kit session. | Real rendered frame-interval measurements with hardware, OS, window size, sample count, and test conditions recorded. Physical MIDI/audio observations on Mac and Windows. Headless throughput is not display frame pacing or pad-to-sound latency. |
| **Q5. Trust and recovery** | Input loss is clear and recoverable without granting a false completed take. Missing audio, unavailable inputs, and failed saves explain the next action in the right place. A settings visit or late score correction cannot alter captured take conditions. Interrupted takes do not grant records or checkpoints. | Disconnect/reconnect, no-input, pause, stopped take, save failure, invalid-save preservation, duplicate correction, and changed-source recommendation tests. Exercise recovery in the actual app. |
| **Q6. Learning and return** | A player can explain the chosen pulse pace, the checkpoint, and the next action. Stars display their practice conditions and do not imply mastery. Guided/free choices remain separate. Close/reopen retains valid scores, access, player identity where supported, and declared resume settings. | The [coached-pulse playtest](coached-pulse-playtest.md), one beginner and one experienced-player pass, plus isolated save/reload and migration checks. Keep technique observations separate from MIDI evidence. |
| **Q7. Distribution integrity** | Both exported applications execute their checks on their target OS from the same clean commit. Asset/license checks, native contracts, Swift adapter checks, and the Mac build pass. Download instructions and known limits match the packages. | Green paired CI run, clean-commit manifests/checksums, working download links, and retained verification logs. |

These frame budgets are acceptance targets, not measurements already achieved. Subjective latency reports are useful, but pad-to-sound/display latency needs a separate measurement method before a numerical claim.

## Severity and closure

- **Blocking:** crash, lost/corrupted progress, incorrect score/unlock, hidden or inaccessible primary action, clipped essential information, unintended input or transport action, or a major presentation regression.
- **Major:** recurring navigation confusion, an unreadable state, inconsistent controls, a recovery path requiring developer help, persistent frame/audio disruption, or a substantial Mac/Windows mismatch.
- **Minor:** a cosmetic detail that does not interfere with reading, control, learning, or trust.

The gate closes only with **zero open blocking or major issues**, all seven rows supported by evidence from the same candidate, and an explicit visual/playtest acceptance decision. Minor issues must be listed with their impact and next action. A passing test count, attractive single screenshot, or one successful take cannot close the gate by itself.

## Evidence ledger

| Area | Current state | Next proof |
| --- | --- | --- |
| Shared foundations and coached pulse | Both source and exported applications pass 8,027 checks at `1ce2060` in [paired CI](https://github.com/claudfuen/drumx/actions/runs/34718163923). | Observe the complete practice journey. |
| Native Mac models and controls | The full native suite passes locally. CI passes 446 history, 57 tempo adapter, and 20 settings-control checks and compiles the native Mac app. [Control detail](images/settings-controls-detail.png) was rendered directly from native views into a bitmap and inspected. It is a component fixture, not an app screenshot. | Inspect the complete app interactively. |
| Save and device recovery | 29 isolated shared save-recovery checks and 31 additional native history checks pass; native backend checks cover lost/failed inputs and audio interruption. | Verify UI recovery and quit choices in the actual applications. |
| Concurrent archive writers | 27 native ownership checks and 8 shared binding checks pass on both platforms in CI, including separate-process exclusion, abrupt-exit release, and Unicode paths. A second copy cannot practise or write that history. Native Mac and shared stores remain separate. | Exercise the protected-progress screen during the full app review. |
| Distribution integrity | Both packages use clean commit `1ce2060`; paired CI verifies archive hashes, assets, licenses, and actual exported execution. [Download manifest](https://github.com/claudfuen/drumx/actions/runs/34718163923/artifacts/10305291588). | Player download/launch and visual acceptance remain required before public release. |
| Complete rendered journey | **Pending.** The slides remain in the foreground at the user's request. Offscreen component inspection is available. | Interactive window review once the display is available, plus physical Windows graphics/scaling. |
| Frame pacing and physical kit/audio | **Pending.** No qualifying 10/30-minute measurement or observation recorded. | Run the stated sessions and attach concise results. |
| Beginner/experienced-player journey | **Pending.** | Observe the loop without developer intervention. |

Keep this ledger and the README current. Record failures as well as passes; preserve raw player history outside the repository. This gate strengthens M1 and does not mark the full beginner milestone complete by itself.
