#ifndef DRUMX_CORE_H
#define DRUMX_CORE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Serial use only. All times are seconds on the same externally calibrated
   song clock: 0 = first scored beat. Negative time is unscored count-in except
   the first target's 125 ms early window, for pads with a target at time 0.
   This core never shifts the clock to compensate for a player's timing. */
typedef struct DXCore DXCore;

typedef enum DXPad {
    DX_HIHAT = 0, DX_SNARE = 1, DX_KICK = 2, DX_PAD_COUNT = 3
} DXPad;

typedef enum DXJudgment {
    DX_IGNORED = 0, DX_CENTERED = 1, DX_EARLY = 2,
    DX_LATE = 3, DX_EXTRA = 4, DX_MISS = 5
} DXJudgment;

typedef enum DXBiasState {
    DX_BIAS_WARMUP = 0, DX_BIAS_CENTERED = 1, DX_BIAS_EARLY = 2,
    DX_BIAS_LATE = 3, DX_BIAS_UNEVEN = 4, DX_BIAS_STALE = 5
} DXBiasState;

typedef enum DXGuidance {
    DX_FOLLOW = 0, DX_FADE = 1, DX_RECALL = 2
} DXGuidance;

typedef struct DXEvent {
    int id;
    int pad;
    double time_seconds;
    int resolved;
    int hit;
} DXEvent;

/* Authoring times use quarter-note beats, independent of tempo. */
typedef struct DXChartEvent {
    int pad;
    double beat;
} DXChartEvent;

/* Song mode preserves the legacy first three pad IDs and adds the full kit.
   The lesson API and DXSnapshot layout remain unchanged. */
typedef enum DXSongPad {
    DX_SONG_HIHAT = 0, DX_SONG_SNARE = 1, DX_SONG_KICK = 2,
    DX_SONG_TOM1 = 3, DX_SONG_TOM2 = 4, DX_SONG_TOM3 = 5,
    DX_SONG_CRASH = 6, DX_SONG_RIDE = 7, DX_SONG_PAD_COUNT = 8
} DXSongPad;

typedef struct DXSongEvent {
    int pad;
    double time_seconds;
} DXSongEvent;

typedef struct DXHitResult {
    uint64_t id;
    int pad;
    int judgment;
    int event_id; /* -1 for ignored/extra. */
    double time_seconds;
    double offset_ms; /* Signed: negative early, positive late. Valid for matches. */
    double velocity; /* Normalized 0..1; retained, not graded. */
} DXHitResult;

typedef struct DXMetrics {
    int matched;
    int missed;
    int extra;
    int on_time; /* Matched within +/-50 ms. */
    int expected; /* Whole configured phrase, including future targets. */
    int streak;
    int best_streak;
    int has_accuracy;
    int has_timing;
    /* Both use (matched + missed + extra), never only successful attempts. */
    double hit_rate_percent;
    double timing_accuracy_percent;
    double mean_offset_ms;
    double mean_absolute_offset_ms;
} DXMetrics;

typedef struct DXBias {
    int state;
    int sample_count;
    double offset_ms; /* Robust recent signed median, not session-wide average. */
    double spread_ms; /* Median absolute deviation of recent matches. */
    double age_seconds; /* -1 when no matched input has been recorded. */
} DXBias;

typedef struct DXSnapshot {
    double bpm;
    double duration_seconds;
    double elapsed_seconds;
    int finished;
    int guidance;
    DXMetrics total;
    DXMetrics pads[DX_PAD_COUNT];
    DXBias bias[DX_PAD_COUNT];
    DXHitResult last_hit;
} DXSnapshot;

DXCore* dx_core_create(void);
void dx_core_destroy(DXCore* core);

/* Generates an eighth-note hi-hat groove, snare on 2/4 and kick on 1/3.
   Valid: 30..240 BPM, 1..64 bars. Returns 1 on success, 0 without changing
   the existing take on invalid input. reset does not select guidance. */
int dx_core_reset(DXCore* core, double bpm, int bars);
/* Loads and starts a fresh take, preserving guidance. Valid: 30..240 BPM,
   finite duration in (0, 256] quarter-note beats, 1..4096 events, pads 0..2,
   and finite event beats in [0, duration). Same-pad beats within 1e-9 beats
   are duplicates and rejected. Input may be unsorted; stored event IDs follow
   beat then pad order. Events are copied, so the caller retains ownership.
   Returns 1 on success, 0 with the entire existing take unchanged on invalid
   input or allocation failure. No audio or rendering work is performed. */
int dx_core_load_chart(DXCore* core, double bpm, double duration_beats,
                       const DXChartEvent* events, int event_count);
/* Absolute song times already include the chart's tempo map and offset.
   Valid: duration (0, 7200] seconds, 1..200000 events, pads 0..7, unique
   same-pad times in [0, duration). Invalid input leaves the take unchanged.
   Snapshot total covers the entire kit; legacy pads/bias cover IDs 0..2.
   bpm is reported as 120 in song mode; render with the imported tempo map. */
int dx_core_load_song(DXCore* core, double duration_seconds,
                     const DXSongEvent* events, int event_count);
void dx_core_set_guidance(DXCore* core, int guidance);
double dx_core_duration(const DXCore* core);

/* Feed original captured timestamps. Expired misses can be corrected by a
   delayed input with a valid timestamp, including after automatic finish.
   Duplicate strikes cannot claim an adjacent future event. No grading waits
   for rendering. +/-125 ms maximum matching window, partitioned by nearest
   target of the same pad (including already-hit targets). */
DXHitResult dx_core_input(DXCore* core, int pad, double song_time_seconds,
                          double velocity);
void dx_core_advance(DXCore* core, double song_time_seconds);
/* Manual stop: resolves elapsed targets only; future targets are not misses.
   Stopping during count-in leaves no scored results. */
void dx_core_finish(DXCore* core, double song_time_seconds);
void dx_core_snapshot(const DXCore* core, DXSnapshot* output);

int dx_core_event_count(const DXCore* core);
int dx_core_event(const DXCore* core, int index, DXEvent* output);

#ifdef __cplusplus
}
#endif

#endif
