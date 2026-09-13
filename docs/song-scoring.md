# Song scores and personal bests

Drumx song scoring version 1 gives each matched drum note 100 points, multiplied
by the current combo level. The first ten consecutive hits earn 1x, the next ten
2x, the next ten 3x, and subsequent hits 4x. A missed note or an extra strike resets
the combo. Every mapped pad uses the same base value. Timing precision is shown
separately; early and late hits inside the native matching window earn a match.

Stars measure earned points against the score for playing the entire selected
chart perfectly under those same rules:

| Stars | Required fraction of the perfect chart score |
| --- | --- |
| 1 | 20% |
| 2 | 40% |
| 3 | 60% |
| 4 | 80% |
| 5 | 95% |

Thresholds include the exact boundary. A full combo additionally requires a
completed take, every charted note matched, and no extra strikes. Five stars do
not by themselves mean a full combo. Accuracy includes extra strikes in its
denominator. During play, the stars always use the whole chart's maximum score.
For example, a perfect 40-note chart earns 10,000 points.

The score is recalculated from the native core's resolved notes in chart-time
order when the judgments change. Extra strikes use their captured song times;
an extra at exactly a note's target time breaks combo before that note. This lets
a delayed MIDI packet correct a previously expired miss without counting the
same note twice. Rendering frequency and scroll speed do not award points.

Only complete takes enter the personal score archive. Comparisons stay within one
player UUID, imported song identity, difficulty, and scoring version. Higher points
win, then higher hit rate, then higher best combo. An exact tie retains the earlier
record. A lower-scoring take still counts as a completed play without replacing
the personal best. Corrections use the original attempt UUID and an increasing
revision, and never add a duplicate play. A newer authoritative result replaces
that take even when delayed extras lower its score. The archive then recomputes
the best across all takes. Older revisions are ignored, conflicting equal
revisions are rejected, and the first completion date is retained.

Private archives live below
`~/Library/Application Support/Drumx/SongScores/<player UUID>/`. Files use a hashed
song/difficulty key and atomic replacement protected by a write lock. A malformed
or unsupported archive blocks writes to that archive and remains untouched. A
note-count change cannot silently mix incompatible charts. These records are
separate from lesson history and curriculum progress.

Completed results are saved on a background queue and shown as saved only after
the archive is read back successfully. A failed save stays pending while browsing
or starting another song, with a visible Retry save action. Closing Drumx waits
for pending writes; if a real save failure remains, the app stays open so the
result can be retried. Stopped or partial songs never enter this queue.

## What the YARG reference informed

[YARG's engine](https://github.com/YARC-Official/YARG.Core/blob/master/YARG.Core/Engine/BaseEngine.cs)
separates combo multipliers and star-power multipliers. Its
[drum engine](https://github.com/YARC-Official/YARG.Core/blob/master/YARG.Core/Engine/Drums/DrumsEngine.cs)
awards notes through judgment events and resets combo on misses; additional drum
mechanics include dynamics and special phrases. Its
[star calculation](https://github.com/YARC-Official/YARG.Core/blob/master/YARG.Core/Engine/BaseEngine.Generic.cs)
uses chart-derived score thresholds rather than percentage of notes alone.
[YARG's score records](https://github.com/YARC-Official/YARG/blob/master/Assets/Script/Scores/ScoreContainer.cs)
distinguish player, instrument, difficulty, score, and hit percentage.

Drumx uses the simpler documented rules above. Its points and stars are not
interchangeable with Clone Hero or YARG leaderboard scores. It currently has no
energy activation, dynamic-hit point bonuses, sustain scoring, or freestyle-fill
bonuses. Native audio time, chart interpretation, and visual presentation remain
separate responsibilities.

## Verification

```sh
bash scripts/test-song-scores.sh
```

The checks cover multiplier boundaries, star thresholds, simultaneous notes,
misses and extras, complete-take requirements, isolated personal bests, deterministic
ties, duplicate attempts, late corrections, corrupt and unsupported files, unsafe
paths, and preservation after rejected writes.
