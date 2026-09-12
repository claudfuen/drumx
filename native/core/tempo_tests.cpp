#include "drumx_tempo.h"

#include <climits>
#include <cmath>
#include <cstdlib>
#include <cstring>
#include <iostream>
#include <limits>
#include <string>
#include <utility>
#include <vector>

namespace {
int checks = 0;
void check(bool condition, const std::string& message) {
    ++checks;
    if (!condition) { std::cerr << "FAIL: " << message << '\n'; std::exit(1); }
}

DXTempoContext context(double bpm = 72, int guidance = 0, int live = 1, int bars = 16, uint64_t group = 1) {
    return {group, 1, bpm, bars, guidance, live};
}

DXTempoAttempt take(uint64_t id, double bpm = 72, int guidance = 0, int live = 1, int bars = 16, uint64_t group = 1) {
    return {id, group, 1, bpm, bars, guidance, live, bars * 4, bars * 4, bars * 4, 0, 0, 1, 1};
}

DXTempoAttempt coverage(DXTempoAttempt value, int matched) {
    value.matched = matched;
    value.on_time = matched;
    value.missed = value.expected - matched;
    return value;
}

DXTempoAttempt timing(DXTempoAttempt value, int on_time) {
    value.on_time = on_time;
    return value;
}

DXTempoDecision evaluate(const std::vector<DXTempoAttempt>& attempts, DXTempoContext current = context()) {
    DXTempoDecision result{};
    check(dx_tempo_evaluate(attempts.data(), attempts.size(), &current, &result) == 1, "valid evaluation succeeds");
    check(result.recent_completed >= 0 && result.recent_completed <= 3
          && result.recent_qualifying >= 0 && result.recent_qualifying <= result.recent_completed,
          "recent evidence is bounded");
    check(result.next_bars == 16, "coached next phrase is sixteen bars");
    return result;
}

void initial_and_thresholds() {
    auto result = evaluate({}, context(60));
    check(result.action == DX_TEMPO_BEGIN && result.reason == DX_TEMPO_STARTING_PULSE
          && result.next_bpm == 60 && result.next_guidance == 0 && result.next_live_feedback == 1,
          "first pulse starts at sixty with guidance");
    check(!result.current_earned && !result.checkpoint_earned && result.recent_completed == 0,
          "empty history grants no evidence");
    result = evaluate({take(1, 60)}, context(60));
    check(result.action == DX_TEMPO_ADVANCE && result.next_bpm == 66 && !result.current_earned
          && result.latest_qualifying && result.recent_qualifying == 1, "one strong phrase offers pace, not earned status");
    result = evaluate({take(1, 66)}, context(66));
    check(result.next_bpm == 72 && result.action == DX_TEMPO_ADVANCE, "six-BPM step reaches checkpoint");
    result = evaluate({take(1)});
    check(result.action == DX_TEMPO_REPEAT && !result.checkpoint_earned, "one checkpoint take requires repetition");

    auto exact = coverage(take(1, 72, 0, 1, 25), 95);
    exact.on_time = 90;
    exact.extra = 2;
    result = evaluate({exact}, context(72, 0, 1, 25));
    check(result.latest_qualifying, "ninety-five/ninety/two-percent exact boundaries qualify");
    auto bad = exact;
    bad.matched = 94; bad.missed = 6;
    check(!evaluate({bad}, context(72, 0, 1, 25)).latest_qualifying, "one note below coverage threshold fails");
    bad = exact; bad.on_time = 89;
    check(!evaluate({bad}, context(72, 0, 1, 25)).latest_qualifying, "one note below timing threshold fails");
    bad = exact; bad.extra = 3;
    check(!evaluate({bad}, context(72, 0, 1, 25)).latest_qualifying, "one extra above threshold fails");
    bad = exact; bad.extra = INT_MAX;
    check(!evaluate({bad}, context(72, 0, 1, 25)).latest_qualifying, "large extras cannot overflow into qualification");

    auto fractional = coverage(take(1), 61);
    fractional.on_time = 58; fractional.extra = 1;
    check(evaluate({fractional}).latest_qualifying, "fractional percentages use integer inequalities");
    fractional.on_time = 57;
    check(!evaluate({fractional}).latest_qualifying, "89.0625 percent is not rounded to ninety");
    fractional.on_time = 58; fractional.extra = 2;
    check(!evaluate({fractional}).latest_qualifying, "3.125 percent extras is not rounded down");
    auto one_bar = take(1, 60, 0, 1, 1);
    result = evaluate({one_bar, take(2, 60, 0, 1, 1)}, context(60, 0, 1, 1));
    check(!result.current_earned && !result.latest_qualifying && result.recent_completed == 0
          && result.reason == DX_TEMPO_PHRASE_TOO_SHORT && result.next_bpm == 60, "perfect sparse one-bar takes cannot earn or advance");
}

void windows_and_corrections() {
    auto bad = timing(take(2), 40);
    auto result = evaluate({take(1), bad, take(3)});
    check(result.current_earned && result.checkpoint_earned && result.recent_qualifying == 2
          && result.recent_completed == 3 && result.action == DX_TEMPO_HIDE_NOTES,
          "two qualifying among three earn exact checkpoint");
    result = evaluate({take(1), bad, timing(take(3), 40), take(4)});
    check(!result.current_earned && !result.checkpoint_earned, "two qualifying separated by two misses do not form a window");
    result = evaluate({take(1), take(2), timing(take(3), 40), timing(take(4), 40), timing(take(5), 40)});
    check(result.current_earned && result.checkpoint_earned && result.recent_completed == 3
          && result.recent_qualifying == 0, "later bad days preserve historical earned evidence");
    result = evaluate({take(1), take(1), take(1)});
    check(result.recent_completed == 1 && !result.checkpoint_earned, "duplicate attempt never becomes repeated evidence");
    result = evaluate({take(1), take(2), timing(take(1), 40)});
    check(!result.checkpoint_earned && result.recent_completed == 2 && result.recent_qualifying == 1,
          "last correction removes previous qualification");
    result = evaluate({timing(take(1), 40), take(2), take(1)});
    check(result.checkpoint_earned && result.recent_completed == 2, "positive correction recomputes evidence once");
    result = evaluate({take(1), timing(take(2), 40), timing(take(3), 40), timing(take(4), 40), take(5), take(1)});
    check(!result.checkpoint_earned, "correction retains original chronology rather than appending a new good take");
    auto invalidated = take(1); invalidated.valid = 0;
    result = evaluate({take(1), take(2), invalidated});
    check(!result.checkpoint_earned && result.recent_completed == 1, "invalid correction is an evidence tombstone");
    auto interrupted = take(1); interrupted.complete = 0; interrupted.missed = 0; interrupted.matched = 20; interrupted.on_time = 20;
    check(!evaluate({take(1), take(2), interrupted}).checkpoint_earned, "partial correction removes complete evidence");
    auto old = take(1); old.policy_version = 0;
    check(!evaluate({take(1), take(2), old}).checkpoint_earned, "old-policy correction cannot leave stale earned evidence");
    result = evaluate({take(UINT64_C(9007199254740992)), take(UINT64_C(9007199254740993))});
    check(result.checkpoint_earned, "full uint64 identities remain distinct above double integer precision");
}

void comparability_and_phases() {
    check(!evaluate({take(1), take(2, 72, 0, 1, 16, 2)}).checkpoint_earned, "source or settings groups never pool");
    check(!evaluate({take(1, 72, 0, 1, 16, 2), take(2, 72, 0, 1, 16, 2)}).checkpoint_earned, "other-group earned evidence stays isolated");
    check(!evaluate({take(1), take(2, 72, 0, 1, 32)}).checkpoint_earned, "different phrase lengths never pool");
    check(evaluate({take(1, 72, 0, 1, 32), take(2, 72, 0, 1, 32)}).checkpoint_earned, "repeated longer phrases earn minimum-length checkpoint");
    check(!evaluate({take(1, 71.999999), take(2, 71.999999)}).checkpoint_earned, "nearby tempo is not exact checkpoint");
    for (double bpm : {60.0, 66.0, 84.0, 96.0}) {
        auto result = evaluate({take(1, bpm), take(2, bpm)}, context(bpm));
        check(result.current_earned && !result.checkpoint_earned, "other earned pace does not imply checkpoint");
        if (bpm > 72) check(result.next_bpm == bpm && result.action == DX_TEMPO_REPEAT, "optional challenge does not auto-escalate");
    }
    check(!evaluate({take(1, 72, 1), take(2, 72, 1)}).checkpoint_earned, "hidden notes are not guided checkpoint evidence");
    check(!evaluate({take(1, 72, 0, 0), take(2, 72, 0, 0)}).checkpoint_earned, "missing live feedback does not meet checkpoint conditions");
    check(!evaluate({take(1), take(2, 72, 0, 0)}).current_earned, "live feedback comparisons remain distinct");
    std::vector<DXTempoAttempt> history{take(1), take(2)};
    auto result = evaluate(history);
    check(result.next_bpm == 72 && result.next_guidance == 1 && result.next_live_feedback == 1
          && result.action == DX_TEMPO_HIDE_NOTES, "earned checkpoint reduces help at unchanged pace");
    history.push_back(take(3, 72, 1));
    result = evaluate(history, context(72, 1));
    check(!result.hidden_earned && result.action == DX_TEMPO_REPEAT, "one hidden phrase repeats before recall");
    history.push_back(take(4, 72, 1));
    result = evaluate(history, context(72, 1));
    check(result.hidden_earned && !result.recall_earned && result.action == DX_TEMPO_TRY_RECALL
          && result.next_bpm == 72 && result.next_guidance == 2 && !result.next_live_feedback,
          "earned hidden phrase offers strict recall with live grading hidden");
    history.push_back(take(5, 72, 2, 1)); history.push_back(take(6, 72, 2, 1));
    check(!evaluate(history, context(72, 2, 1)).recall_earned, "visible live grading cannot establish strict recall");
    history.push_back(take(7, 72, 2, 0)); history.push_back(take(8, 72, 2, 0));
    result = evaluate(history, context(72, 2, 0));
    check(result.checkpoint_earned && result.hidden_earned && result.recall_earned
          && result.action == DX_TEMPO_CONTINUE, "complete evidence sequence offers continuation");
    check(evaluate({take(1,72,2,0),take(2,72,2,0)},context(72,2,0)).action == DX_TEMPO_REPEAT,
          "standalone recall cannot silently bypass explicit guided checkpoint");
}

void difficulty_and_input() {
    std::vector<DXTempoAttempt> hard{coverage(take(1), 44), coverage(take(2), 44)};
    auto result = evaluate(hard);
    check(result.action == DX_TEMPO_EASE && result.next_bpm == 66
          && result.reason == DX_TEMPO_REPEATED_COVERAGE_DIFFICULTY, "two severe coverage failures offer one slower step");
    check(evaluate({hard[0]}).action == DX_TEMPO_REPEAT, "single difficult take does not lower tempo");
    auto boundary = coverage(take(1,72,0,1,25),70);
    auto boundary2 = boundary; boundary2.attempt_id = 2;
    check(evaluate({boundary,boundary2},context(72,0,1,25)).action == DX_TEMPO_REPEAT, "exact seventy-percent coverage is marginal, not severe");
    result = evaluate({coverage(take(1,72,1),44),coverage(take(2,72,1),44)},context(72,1));
    check(result.action == DX_TEMPO_EASE && result.next_bpm == 72 && result.next_guidance == 0
          && result.next_live_feedback == 1, "restore cues before changing tempo");
    result = evaluate({coverage(take(1,60),44),coverage(take(2,60),44)},context(60));
    check(result.next_bpm == 60, "guided starting pace is lower bound");
    for (const auto& pair : std::vector<std::pair<double,double>>{{66,60},{72,66},{84,72},{96,84}}) {
        result = evaluate({coverage(take(1,pair.first),44),coverage(take(2,pair.first),44)},context(pair.first));
        check(result.action == DX_TEMPO_EASE && result.next_bpm == pair.second,
              "easing selects previous authored rung, never seventy-eight or ninety");
    }
    result = evaluate({coverage(take(1,48),44),coverage(take(2,48),44)},context(48));
    check(result.next_bpm == 48, "an easier manually chosen context is never raised by easing");
    hard.push_back(coverage(take(3),0));
    result = evaluate(hard);
    check(result.action == DX_TEMPO_CHECK_INPUT && result.reason == DX_TEMPO_NO_INPUT && result.next_bpm == 72,
          "no-input latest phrase never reuses older failures to lower tempo");
    hard.back().extra = 100;
    result = evaluate(hard);
    check(result.action == DX_TEMPO_CHECK_INPUT && result.next_bpm == 72, "unmatched input asks for conditions check rather than tempo reduction");
    auto partial = take(3); partial.complete = 0; partial.matched = 12; partial.on_time = 12;
    hard.back() = partial;
    result = evaluate(hard);
    check(result.action == DX_TEMPO_RESTART && result.reason == DX_TEMPO_INTERRUPTED && result.next_bpm == 72,
          "interrupted phrase restarts without reducing pace");
    hard.back().valid = 0;
    result = evaluate(hard);
    check(result.action == DX_TEMPO_REPEAT && result.next_bpm == 72, "invalid latest data blocks inherited difficulty advice");
    result = evaluate({timing(take(1),45),timing(take(2),45)});
    check(result.action == DX_TEMPO_REPEAT && result.next_bpm == 72, "uneven timing alone never lowers tempo");
}

void invalid_data_and_purity() {
    std::vector<DXTempoAttempt> bad;
    auto add = [&](DXTempoAttempt attempt) { attempt.attempt_id = static_cast<uint64_t>(bad.size() + 1); bad.push_back(attempt); };
    auto value = take(1); value.policy_version = 0; add(value);
    value = take(1); value.valid = 0; add(value);
    value = take(1); value.complete = 2; add(value);
    value = take(1); value.conditions_id = 0; add(value);
    value = take(1); value.bpm = std::numeric_limits<double>::quiet_NaN(); add(value);
    value = take(1); value.bpm = std::numeric_limits<double>::infinity(); add(value);
    value = take(1); value.bars = 0; add(value);
    value = take(1); value.bars = INT_MAX; add(value);
    value = take(1); value.expected = 63; add(value);
    value = take(1); value.matched = -1; add(value);
    value = take(1); value.matched = 65; add(value);
    value = take(1); value.on_time = 65; add(value);
    value = take(1); value.on_time = -1; add(value);
    value = take(1); value.extra = -1; add(value);
    value = take(1); value.missed = 1; add(value);
    value = take(1); value.guidance = 3; add(value);
    value = take(1); value.live_feedback = 2; add(value);
    auto result = evaluate(bad);
    check(result.recent_completed == 0 && !result.current_earned && !result.checkpoint_earned,
          "malformed and legacy data grants no evidence");
    std::vector<DXTempoAttempt> attempts{take(1),take(2)};
    std::vector<unsigned char> bytes(attempts.size() * sizeof(DXTempoAttempt));
    std::memcpy(bytes.data(), attempts.data(), bytes.size());
    auto current = context();
    const auto original_context = current;
    check(dx_tempo_evaluate(attempts.data(),attempts.size(),&current,&result) == 1, "pure evaluation succeeds");
    check(std::memcmp(bytes.data(),attempts.data(),bytes.size()) == 0 && current.bpm == original_context.bpm
          && current.guidance == original_context.guidance, "evaluator never mutates attempts or settings");
    result.action = 999; result.next_bpm = 123;
    current.policy_version = 0;
    check(dx_tempo_evaluate(attempts.data(),attempts.size(),&current,&result) == 0
          && result.action == 999 && result.next_bpm == 123, "invalid context leaves output unchanged");
    current = context();
    check(dx_tempo_evaluate(nullptr,1,&current,&result) == 0, "null nonempty history rejected");
    check(dx_tempo_evaluate(nullptr,0,nullptr,&result) == 0, "null context rejected");
    check(dx_tempo_evaluate(nullptr,0,&current,nullptr) == 0, "null output rejected");
    for (double bpm : {std::numeric_limits<double>::quiet_NaN(),0.0,241.0}) {
        current = context(bpm);
        check(dx_tempo_evaluate(nullptr,0,&current,&result) == 0, "invalid context tempo rejected");
    }
}
} // namespace

int main() {
    initial_and_thresholds();
    windows_and_corrections();
    comparability_and_phases();
    difficulty_and_input();
    invalid_data_and_purity();
    std::cout << checks << " guided-tempo contract checks passed.\n";
}
