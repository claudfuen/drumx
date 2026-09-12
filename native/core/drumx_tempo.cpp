#include "drumx_tempo.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <unordered_map>
#include <vector>

namespace {
bool settings_valid(const DXTempoContext& value) {
    return value.conditions_id != 0 && value.policy_version == DX_TEMPO_POLICY_VERSION
        && std::isfinite(value.bpm) && value.bpm >= 30 && value.bpm <= 240
        && value.bars >= 1 && value.bars <= 64
        && value.guidance >= 0 && value.guidance <= 2
        && (value.live_feedback == 0 || value.live_feedback == 1);
}

DXTempoContext context_of(const DXTempoAttempt& value) {
    return {value.conditions_id, value.policy_version, value.bpm, value.bars,
            value.guidance, value.live_feedback};
}

bool valid(const DXTempoAttempt& value) {
    if (value.attempt_id == 0 || value.valid != 1 || !settings_valid(context_of(value))
        || (value.complete != 0 && value.complete != 1)
        || value.expected != value.bars * 4 || value.matched < 0
        || value.matched > value.expected || value.on_time < 0
        || value.on_time > value.matched || value.missed < 0
        || value.missed > value.expected || value.extra < 0) return false;
    const int resolved = value.matched + value.missed;
    return value.complete ? resolved == value.expected : resolved <= value.expected;
}

bool full_phrase(const DXTempoAttempt& value) {
    return valid(value) && value.complete == 1 && value.bars >= DX_TEMPO_PHRASE_BARS;
}

bool qualifies(const DXTempoAttempt& value) {
    return full_phrase(value)
        && int64_t(value.matched) * 100 >= int64_t(value.expected) * 95
        && int64_t(value.on_time) * 100 >= int64_t(value.expected) * 90
        && int64_t(value.extra) * 100 <= int64_t(value.expected) * 2;
}

bool same_settings(const DXTempoAttempt& value, const DXTempoContext& current) {
    return value.conditions_id == current.conditions_id
        && value.policy_version == current.policy_version && value.bpm == current.bpm
        && value.bars == current.bars && value.guidance == current.guidance
        && value.live_feedback == current.live_feedback;
}

struct Evidence {
    std::array<const DXTempoAttempt*, 3> recent{};
    int count = 0;
    int qualifying = 0;
    bool earned = false;

    void add(const DXTempoAttempt& attempt) {
        if (count == 3) {
            qualifying -= qualifies(*recent[0]) ? 1 : 0;
            recent[0] = recent[1];
            recent[1] = recent[2];
        } else {
            ++count;
        }
        recent[static_cast<size_t>(count - 1)] = &attempt;
        qualifying += qualifies(attempt) ? 1 : 0;
        earned = earned || qualifying >= 2;
    }
};

bool severe(const DXTempoAttempt& value) {
    // Zero matched notes may be an input/mapping problem, not a pace problem.
    return value.matched > 0 && int64_t(value.matched) * 100 < int64_t(value.expected) * 70;
}

double easier_authored_pace(double bpm) {
    if (bpm <= DX_TEMPO_START_BPM) return bpm;
    double easier = DX_TEMPO_START_BPM;
    for (double pace : {60.0, 66.0, 72.0, 84.0, 96.0}) {
        if (pace < bpm) easier = pace;
    }
    return easier;
}

void recommend(DXTempoDecision& result, int action, int reason, double bpm,
               int guidance, int live_feedback) {
    result.action = action;
    result.reason = reason;
    result.next_bpm = bpm;
    result.next_bars = DX_TEMPO_PHRASE_BARS;
    result.next_guidance = guidance;
    result.next_live_feedback = live_feedback;
}

DXTempoDecision evaluate(const std::vector<DXTempoAttempt>& attempts, const DXTempoContext& current) {
    Evidence current_evidence;
    std::array<Evidence, 65> checkpoint, hidden, recall;
    const DXTempoAttempt* latest = nullptr;
    for (const auto& attempt : attempts) {
        if (same_settings(attempt, current)) {
            latest = &attempt;
            if (full_phrase(attempt)) current_evidence.add(attempt);
        }
        if (!full_phrase(attempt) || attempt.conditions_id != current.conditions_id
            || attempt.bpm != DX_TEMPO_CHECKPOINT_BPM) continue;
        auto index = static_cast<size_t>(attempt.bars);
        if (attempt.guidance == 0 && attempt.live_feedback == 1) checkpoint[index].add(attempt);
        if (attempt.guidance == 1 && attempt.live_feedback == 1) hidden[index].add(attempt);
        if (attempt.guidance == 2 && attempt.live_feedback == 0) recall[index].add(attempt);
    }

    DXTempoDecision result{};
    result.recent_completed = current_evidence.count;
    result.recent_qualifying = current_evidence.qualifying;
    result.current_earned = current_evidence.earned ? 1 : 0;
    result.latest_qualifying = latest && qualifies(*latest) ? 1 : 0;
    for (size_t bars = DX_TEMPO_PHRASE_BARS; bars < checkpoint.size(); ++bars) {
        result.checkpoint_earned |= checkpoint[bars].earned ? 1 : 0;
        result.hidden_earned |= hidden[bars].earned ? 1 : 0;
        result.recall_earned |= recall[bars].earned ? 1 : 0;
    }
    recommend(result, latest ? DX_TEMPO_REPEAT : DX_TEMPO_BEGIN,
              latest ? DX_TEMPO_BUILD_REPEATABILITY : DX_TEMPO_STARTING_PULSE,
              current.bpm, current.guidance, current.live_feedback);

    // An interrupted, missing-input or invalid latest phrase cannot trigger a
    // speed reduction, even when older history contains difficult attempts.
    if (latest && !valid(*latest)) {
        result.reason = DX_TEMPO_CONDITIONS_NEED_REPEAT;
        return result;
    }
    if (latest && latest->complete == 0) {
        result.action = DX_TEMPO_RESTART;
        result.reason = DX_TEMPO_INTERRUPTED;
        return result;
    }
    if (latest && latest->matched == 0) {
        result.action = DX_TEMPO_CHECK_INPUT;
        result.reason = latest->extra == 0 ? DX_TEMPO_NO_INPUT : DX_TEMPO_CONDITIONS_NEED_REPEAT;
        return result;
    }
    if (latest && latest->bars < DX_TEMPO_PHRASE_BARS) {
        result.reason = DX_TEMPO_PHRASE_TOO_SHORT;
        return result;
    }
    if (current_evidence.count >= 2
        && severe(*current_evidence.recent[static_cast<size_t>(current_evidence.count - 1)])
        && severe(*current_evidence.recent[static_cast<size_t>(current_evidence.count - 2)])) {
        const bool restore = current.guidance != 0 || current.live_feedback != 1;
        recommend(result, DX_TEMPO_EASE, DX_TEMPO_REPEATED_COVERAGE_DIFFICULTY,
                  restore ? current.bpm : easier_authored_pace(current.bpm),
                  0, 1);
        return result;
    }

    if (current.bpm < DX_TEMPO_CHECKPOINT_BPM) {
        if (result.latest_qualifying) {
            recommend(result, DX_TEMPO_ADVANCE, DX_TEMPO_ONE_STRONG_PHRASE,
                      std::min(72.0, current.bpm + DX_TEMPO_STEP_BPM),
                      current.guidance, current.live_feedback);
        } else if (latest) {
            result.reason = DX_TEMPO_TIMING_NEEDS_REPEAT;
        }
        return result;
    }
    // Stretch challenges never substitute for the exact checkpoint and are
    // selected by the player. This evaluator does not auto-escalate them.
    if (current.bpm > DX_TEMPO_CHECKPOINT_BPM) {
        if (latest && !result.latest_qualifying) result.reason = DX_TEMPO_TIMING_NEEDS_REPEAT;
        return result;
    }

    if (!result.checkpoint_earned) {
        if (current.guidance != 0 || current.live_feedback != 1) {
            recommend(result, DX_TEMPO_REPEAT, DX_TEMPO_CONDITIONS_NEED_REPEAT, 72, 0, 1);
        } else if (latest && !result.latest_qualifying) {
            result.reason = DX_TEMPO_TIMING_NEEDS_REPEAT;
        }
    } else if (!result.hidden_earned) {
        recommend(result, current.guidance == 1 && current.live_feedback == 1 ? DX_TEMPO_REPEAT : DX_TEMPO_HIDE_NOTES,
                  DX_TEMPO_CHECKPOINT_EARNED, 72, 1, 1);
    } else if (!result.recall_earned) {
        recommend(result, current.guidance == 2 && current.live_feedback == 0 ? DX_TEMPO_REPEAT : DX_TEMPO_TRY_RECALL,
                  DX_TEMPO_HIDDEN_EARNED, 72, 2, 0);
    } else {
        recommend(result, DX_TEMPO_CONTINUE, DX_TEMPO_RECALL_EARNED, 72, 2, 0);
    }
    return result;
}
} // namespace

extern "C" int dx_tempo_evaluate(const DXTempoAttempt* attempts, size_t attempt_count,
                                  const DXTempoContext* current, DXTempoDecision* output) {
    if (!current || !output || (!attempts && attempt_count != 0) || !settings_valid(*current)) return 0;
    try {
        std::vector<DXTempoAttempt> corrected;
        std::unordered_map<uint64_t, size_t> positions;
        corrected.reserve(attempt_count);
        positions.reserve(attempt_count);
        for (size_t index = 0; index < attempt_count; ++index) {
            const auto& attempt = attempts[index];
            if (attempt.attempt_id == 0) continue;
            const auto position = positions.emplace(attempt.attempt_id, corrected.size());
            if (position.second) corrected.push_back(attempt);
            else corrected[position.first->second] = attempt;
        }
        const DXTempoDecision result = evaluate(corrected, *current);
        *output = result;
        return 1;
    } catch (...) {
        return 0;
    }
}
