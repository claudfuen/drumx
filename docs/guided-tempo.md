# Guided tempo and meaningful progression

**Status: first pulse slice implemented in the native Mac and experimental shared apps.** Find the pulse uses the shared C policy for coached preparation, review, independent guided/free-practice resume, and its 72 BPM unlock. The other lessons retain their existing rules. End-to-end learner testing, visual acceptance, and physical-kit measurements remain open M1 gates.

## Who decides the tempo?

The lesson author defines its starting pace, checkpoint pace, and optional stretch challenges. Drumx recommends the next practice condition from the selected player's evidence. The player can repeat, ask for more time, or choose a clearly identified challenge. Free practice retains direct tempo control.

A beginner should see a useful next action, such as **Build a steady pulse · 60 BPM**, rather than needing to decide what number makes a productive lesson. The preparation page explains why that pace was chosen. Review recommends one next action with its reason; alternatives remain secondary.

### Example: Find the pulse

The implemented values below are initial product hypotheses for testing, not validated teaching standards.

| Moment | Suggested pace | Player-facing meaning |
| --- | --- | --- |
| Begin | 60 BPM | One click and one stroke. Learn the count and settle in. |
| Build control | 66 BPM | Your complete phrase was steady. Try a little more pace. |
| Lesson checkpoint | 72 BPM | Demonstrate this lesson's defined timing/coverage goal. |
| Reduce help | 72 BPM | Keep the pace while some notes disappear, then try click-only recall. |
| Optional challenges | 84 or 96 BPM | Broaden your comfortable range after the next lesson is available. |

These are not mandatory rungs. An experienced player can choose **Try the checkpoint** directly; a convincing opening take can recommend it without forcing every intermediate speed. Sixty BPM remains a gentle first-pulse hypothesis. Compare it with a 72 BPM opening during learner testing before changing the default. Keep 60 available through **More time** if the higher opening works better.

Author each lesson deliberately. At 60 quarter-note BPM, quarter notes mean one stroke per second and eighth notes mean two. Adding the foot, rests, another limb, or a new sticking changes the task again. A player's pulse tempo is not automatically an appropriate starting tempo for coordination or rudiments.

## How coaching chooses the next action

Keep the current uninterrupted 16-bar default. Hold tempo and scoring conditions fixed throughout the take. A recommended change applies to the next take, with a fresh count-in; it never accelerates the current phrase or adds a stop every few bars.

| Evidence | Recommended response |
| --- | --- |
| A strong complete opening phrase | Offer the next authored pace or a checkpoint probe. A recommendation is not an earned checkpoint. |
| Repeatable control at the current pace | Confirm that pace; offer the next lesson-defined challenge. |
| Good guided playing, recall untested | Keep the pace and reduce visual help. |
| Notes mostly correct but timing uneven | Repeat the pace with one specific timing focus. |
| Repeated difficulty with a coordination pattern | Offer a slower pace, restored cues, or one-bar repair, according to the error pattern. |
| No input, lost source, or an interrupted take | Resolve input or restart. Do not infer that the player needs a slower tempo. |
| Return after a break | Resume the saved comfortable pace; offer a check before assuming retained skill. |

Change one demand at a time. A new lesson restores guidance and uses its own starting plan. A successful recall check can lead to a tempo variation, but must not silently add both a higher pace and a denser pattern.

The first evaluator records an **earned steady pace** when any historical window has two qualifying takes among three comparable completed takes. A later difficult take does not erase this evidence, but a corrected attempt is reevaluated. A candidate qualifying take has at least 16 bars, at least 95% of expected notes matched, at least 90% of expected notes inside the existing timing band, and extras no greater than 2% of expected notes. This first policy covers snare pulse only. Before extending it to coordination lessons, check each required instrument so a strong hi-hat cannot conceal a weak kick. Use integer comparisons without rounding a near miss into a pass. These thresholds and the repeat count are tunable hypotheses; they do not redefine stars or certify technique.

One qualifying full phrase at 60 or 66 BPM can suggest the next pace without granting a repeatability achievement. Short takes never qualify; the direct checkpoint action is available without grinding through the opening paces. This distinction gives an experienced player a quick route through easy material while requiring repeatability for the recorded claim. Avoid treating slower as the universal remedy: consistently shifted timing warrants checking the listening/input conditions and coaching context, not blindly ratcheting BPM down.

The first evaluator can use recorded aggregate evidence. A claim that timing stayed steady through the final bars requires additional per-bar evidence; the current archives do not establish that. Add and verify that evidence before making the claim. Likewise, comfortable grip, rebound, and hand choice remain player/teacher observations because MIDI does not verify them.

## What progression means

**Course access:** completing the authored checkpoint opens the next concept, with reading requirements where the lesson specifies them. The maximum stretch tempo is not a prerequisite. Preserve existing access when introducing the policy; show new checkpoint evidence separately instead of forcing old players back behind locks.

**Recorded control:** use specific labels such as **Steady at 72 BPM**, **Recalled at 72 BPM**, and **Tried at 84 BPM**. Never collapse those into an unqualified mastered badge. Reading, immediate recall with a click, later retention, physical technique, and musical application remain separate evidence.

**Stars:** keep five stars as the existing challenge for a complete, perfectly timed take. Show the pace and assistance beside the stars. A five-star 60 BPM guided take remains a valid result; it does not complete an unattempted 72 BPM checkpoint. The course browser shows the pace and assistance beside its best-across-all-conditions stars; these do not establish the lesson's checkpoint.

**Free practice:** allow manual tempo, length, and guidance. Keep those attempts and their personal bests. A free-practice take can count toward a checkpoint only when it satisfies that checkpoint's exact versioned conditions and the UI identifies it as eligible before play. Arbitrary higher BPM does not automatically prove control at a specified lower pace.

**Independence:** offer reduced guidance at an already controlled pace. Immediate click-only recall and recalling the pattern on another day are different observations. A later lesson may explicitly require recall, but speed alone never stands in for it.

## Implemented boundary

- Policy 1 applies only to `find-the-pulse-v1`. New takes capture policy and monitoring intent before play. Legacy attempts remain visible but cannot acquire missing checkpoint evidence retroactively.
- Guided and free practice keep separate saved choices. Existing players return to their prior manual context; new players start coached. Course access earned before this change is preserved independently of the new badge.
- Evidence stays within an exact device, mapping, monitoring, calibration, length, tempo, and assistance group. A checkpoint earned on one kit keeps course access after unplugging; a new setup receives its own coaching. A changed source on review forces preparation to reevaluate before starting a recommended challenge.
- Optional 84/96 BPM challenges become available after the checkpoint. Repeated severe coverage difficulty can restore guidance or offer the previous authored pace, 96 → 84 → 72 → 66 → 60. No-input and interrupted takes do not lower tempo.
- Source, packaged-app, C-interface, Swift-adapter, migration, and correction checks protect the shared behavior. Automated geometry and fit checks support visual review; they do not establish visual acceptance.

## Implementation and acceptance

1. Author a versioned tempo plan for the first pulse lesson: starting pace, checkpoint pace, optional challenge paces, permitted step sizes, phrase length, assistance, and qualifying policy. Extend to the other lessons only after the first coached loop is useful.
2. Implement a deterministic evaluator shared by the Mac and Windows paths, with common content and fixture cases. It returns the current evidence, one recommended action, and a plain-language reason. It does not run the transport or mutate raw scores.
3. Key evidence by player, lesson/content version, policy version, tempo, assistance, input conditions, and phrase requirements. Upsert corrected attempts by the same ID; recompute derived evidence without counting the correction as another repetition. Keep raw history and existing course access intact.
4. Persist the chosen guided plan and the free-practice choice separately. Reopening returns to that player's plan. Legacy history is preserved, but missing policy/assistance evidence cannot be invented for a new checkpoint.
5. Reuse the restored preparation/review hierarchy. Show the recommended pace, its purpose, and a primary **Play next** action. Put **More time**, **Repeat**, and **Free practice** in secondary routes. Preserve the highway geometry and input timing while refining its visual treatment. This slice adds restrained catcher shading and contact lighting, with the same projected vertices.
6. Verify that a sparse perfect one-bar take, extra-hit spam, a single lucky result, missing input, mismatched assistance, or another player's history cannot grant a checkpoint. Test deliberate checkpoint attempts, changing instruments, late corrections, restart/resume, and both desktop builds.
7. Observe a beginner and an already-playing tester. Each should understand who chose the tempo, why the next pace was suggested, what opens the next lesson, and why a slower clean result is still worthwhile. Check whether the first pulse feels welcoming or tedious. Complete the remaining shared-port visual checks before increasing scope.

## Basis and limits

[Melodics Practice Mode](https://support.melodics.com/en/articles/6777027-practice-mode) provides an Auto BPM precedent: increase pace as performance improves toward the track's normal tempo. That is product precedent, not validation of Drumx's thresholds. Melodics' help pages describe differing step increments, so this proposal does not copy a supposed universal number.

The Percussive Arts Society's [Fast and Slow guidance](https://pas.org/pas-blog/tuesday-tips-fast-and-slow/) recommends building comfortable, consistent execution before gradual tempo increases. Its [rudiment guidance](https://pas.org/rudiments/) also includes slow-to-fast-to-slow practice and moderate tempo. These support control across paces; they do not establish the proposed 60/66/72 BPM example, percentages, or automatic readiness rule. Validate those with actual learners and percussion educators.
