# Give the player time to settle in

Four bars were a useful mechanics check, but sending a beginner back to review every few seconds interrupts the practice itself. The new standard is **one uninterrupted 16-bar block at the lesson's suggested tempo**, followed by review. The selected lesson's authored bar repeats throughout that block. This is a finite phrase, not an endless or automatically restarting session.

At the current course's suggested tempos, 16 bars last **64 seconds at 60 BPM** or **about 53 seconds at 72 BPM**. A four-beat count-in and the transport's brief startup lead come first. The duration describes playing time, not the lesson's suggested total practice minutes or a promise about learning speed.

## A simple first choice

The normal lesson route should make its objective, demonstration, playing duration, and start action clear. The authored tempo is a starting recommendation. Detailed tempo, length, and guidance controls belong under **Practice options**, so a new player can start without configuring a session.

Keep **1, 4, 8, and 16 bars** available. One bar isolates a pattern; four or eight bars provide a short check; sixteen give the player time to establish a repeating rhythm. Hidden bars needs more than one bar. A restored one-bar Hidden bars combination becomes four bars; one-bar From memory remains possible. Live evaluation is independent of guidance and must remain off during a strict click-only check.

Review remains a deliberate boundary. The player can repeat, slow down, repair a bar, change assistance, or continue to an available lesson. A longer phrase does not change the score, unlock, or evidence definitions. Pause still stops the phrase; restarting uses a fresh count-in. Continuous sessions, between-phrase coaching, and navigation from a drum pad need separate interaction and completion rules before implementation.

## Preserve choices when upgrading

[DrumxPracticePlan](../native/macos/DrumxPracticePlan.swift) is a pure value that restores tempo, bar count, guidance, and live feedback. It never schedules audio, writes progress, awards evidence, or starts another phrase. The controller owns those actions.

| Saved condition | Restored plan |
| --- | --- |
| New player or a newly selected lesson | Recommended tempo, 16 bars, Guided, live feedback on. |
| Old save with no session-format marker and four bars | Upgrade to 16 bars once, preserving its tempo and assistance. Old saves cannot distinguish an intentionally selected four bars from the old default. |
| Old one-, eight-, or sixteen-bar choice | Preserve it, subject to valid guidance and the current playable tempo range. |
| Session format 1 with an explicit length | Preserve any supported choice, including four bars. |
| Different lesson identity or changed lesson revision | Use the supplied lesson's recommended standard plan. |
| Invalid tempo, length, guidance, or session format | Bound tempo to 48–144 BPM or use the recommended tempo; fall back to supported settings. Invalid session-format markers are rejected by the progress store. |

Saving the restored plan with `sessionFormatVersion: 1` makes the migration one-time. The optional field leaves older JSON readable. Current-version reading and technique checks remain separate records and are neither awarded nor erased by this migration.

## What still needs observation

The one-minute default is a **product hypothesis** in response to overly frequent interruptions. It is not a research-backed optimal practice duration. Observe a beginner completing repeated blocks: can they count, recover after an error, maintain comfortable motion, understand when review will appear, and choose a useful next action? Check fatigue and whether a shorter block would help. Validate the experience on a physical kit as well as with keyboard input.

Model checks cover legacy migration, explicit-choice preservation, finite duration, tempo bounds, guidance invariants, and independence from learning evidence. Controller integration still needs an uninterrupted 16-bar count-in/play/review run, pause/restart, saved options after reopen, and comparison separation by phrase length. These checks advance M1 without closing its real-beginner or hardware acceptance gates.
