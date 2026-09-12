#ifndef DRUMX_TEMPO_H
#define DRUMX_TEMPO_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Policy 1 is exclusively for find-the-pulse-v1. The adapter filters player
   and exact lesson version before calling. This evaluator changes no state. */
#define DX_TEMPO_POLICY_VERSION 1
#define DX_TEMPO_START_BPM 60
#define DX_TEMPO_CHECKPOINT_BPM 72
#define DX_TEMPO_STEP_BPM 6
#define DX_TEMPO_PHRASE_BARS 16
#define DX_TEMPO_STRETCH_BPM_1 84
#define DX_TEMPO_STRETCH_BPM_2 96

/* Guidance uses DX_FOLLOW=0, DX_FADE=1, DX_RECALL=2 from drumx_core.h.
   conditions_id identifies exact source, mapping, monitoring and calibration.
   Assign collision-free nonzero ordinal tokens to full identities within each
   evaluation; do not truncate or hash strings. Tempo/guidance/feedback remain
   separate comparison fields. Never pool different condition groups. */
typedef struct DXTempoAttempt {
    uint64_t attempt_id;
    uint64_t conditions_id;
    int policy_version;
    double bpm;
    int bars;
    int guidance;
    int live_feedback;
    int expected;
    int matched;
    int on_time;
    int missed;
    int extra;
    int complete; /* 1 only for a naturally completed uninterrupted phrase. */
    int valid; /* 1 only when the adapter validated identity and provenance. */
} DXTempoAttempt;

typedef struct DXTempoContext {
    uint64_t conditions_id;
    int policy_version;
    double bpm;
    int bars;
    int guidance;
    int live_feedback;
} DXTempoContext;

typedef enum DXTempoAction {
    DX_TEMPO_BEGIN = 0,
    DX_TEMPO_REPEAT = 1,
    DX_TEMPO_ADVANCE = 2,
    DX_TEMPO_HIDE_NOTES = 3,
    DX_TEMPO_TRY_RECALL = 4,
    DX_TEMPO_CONTINUE = 5,
    DX_TEMPO_EASE = 6,
    DX_TEMPO_CHECK_INPUT = 7,
    DX_TEMPO_RESTART = 8
} DXTempoAction;

typedef enum DXTempoReason {
    DX_TEMPO_STARTING_PULSE = 0,
    DX_TEMPO_ONE_STRONG_PHRASE = 1,
    DX_TEMPO_BUILD_REPEATABILITY = 2,
    DX_TEMPO_CHECKPOINT_EARNED = 3,
    DX_TEMPO_HIDDEN_EARNED = 4,
    DX_TEMPO_RECALL_EARNED = 5,
    DX_TEMPO_REPEATED_COVERAGE_DIFFICULTY = 6,
    DX_TEMPO_TIMING_NEEDS_REPEAT = 7,
    DX_TEMPO_NO_INPUT = 8,
    DX_TEMPO_INTERRUPTED = 9,
    DX_TEMPO_PHRASE_TOO_SHORT = 10,
    DX_TEMPO_CONDITIONS_NEED_REPEAT = 11
} DXTempoReason;

typedef struct DXTempoDecision {
    int recent_completed; /* Up to 3 valid comparable full-length attempts. */
    int recent_qualifying;
    int latest_qualifying;
    int current_earned; /* Any historical window of 2 qualifying among 3. */
    int checkpoint_earned; /* Exactly 72, follow, live feedback. */
    int hidden_earned; /* Exactly 72, fade, live feedback. */
    int recall_earned; /* Exactly 72, recall, live feedback OFF. */
    int action; /* DXTempoAction */
    int reason; /* DXTempoReason */
    double next_bpm;
    int next_bars;
    int next_guidance;
    int next_live_feedback;
} DXTempoDecision;

/* Input is chronological, oldest first. For duplicate attempt IDs the last
   correction wins, while the first occurrence retains chronological position.
   A corrected invalid/incomplete record removes that attempt's former evidence.
   Qualifying: current policy, valid=1, complete=1, bars>=16, expected=4*bars,
   matched>=95%, on_time>=90%, extras<=2%, using exact integer comparisons.
   Full comparable phrases have equal bars, exact bpm, guidance, feedback and
   conditions. Historical earned evidence survives subsequent unsuccessful takes
   but is recomputed after corrections. Checkpoint evidence allows >=16 bars,
   with each evidence window still restricted to one exact phrase length.
   Returns 1 on success; 0 leaves output untouched for invalid context/pointers
   or allocation failure. Invalid attempt records never grant evidence. */
int dx_tempo_evaluate(const DXTempoAttempt* attempts, size_t attempt_count,
                      const DXTempoContext* current, DXTempoDecision* output);

#ifdef __cplusplus
}
#endif
#endif
