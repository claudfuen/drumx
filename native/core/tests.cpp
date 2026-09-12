#include "drumx_core.h"

#include <algorithm>
#include <cmath>
#include <cstdlib>
#include <iostream>
#include <limits>
#include <memory>
#include <string>
#include <vector>

namespace {
int checks = 0;
void check(bool condition, const std::string& message) {
    ++checks;
    if (!condition) {
        std::cerr << "FAIL: " << message << '\n';
        std::exit(1);
    }
}
bool near(double actual, double expected, double tolerance = 1e-6) {
    return std::abs(actual - expected) < tolerance;
}
using Core = std::unique_ptr<DXCore, decltype(&dx_core_destroy)>;
Core core(double bpm = 96, int bars = 4) {
    Core result(dx_core_create(), dx_core_destroy);
    check(result != nullptr, "core creation");
    check(dx_core_reset(result.get(), bpm, bars) == 1, "valid reset");
    return result;
}
DXSnapshot snapshot(const Core& engine) {
    DXSnapshot result{};
    dx_core_snapshot(engine.get(), &result);
    return result;
}
std::vector<DXEvent> events(const Core& engine, int pad = -1) {
    std::vector<DXEvent> result;
    for (int index = 0; index < dx_core_event_count(engine.get()); ++index) {
        DXEvent event{};
        check(dx_core_event(engine.get(), index, &event) == 1, "event accessor");
        if (pad < 0 || event.pad == pad) result.push_back(event);
    }
    return result;
}
void same_metrics(const DXMetrics& a, const DXMetrics& b, const std::string& label) {
    check(a.matched == b.matched && a.missed == b.missed && a.extra == b.extra
        && a.on_time == b.on_time && a.streak == b.streak && a.best_streak == b.best_streak
        && near(a.timing_accuracy_percent, b.timing_accuracy_percent)
        && near(a.mean_offset_ms, b.mean_offset_ms)
        && near(a.mean_absolute_offset_ms, b.mean_absolute_offset_ms), label);
}

void phrase_and_validation() {
    auto engine = core();
    check(dx_core_event_count(engine.get()) == 48, "four bars contain 48 independent pad targets");
    check(near(dx_core_duration(engine.get()), 10), "four bars at 96 BPM last ten seconds");
    check(snapshot(engine).total.has_accuracy == 0, "no fabricated accuracy before playing");
    check(dx_core_reset(engine.get(), 0, 4) == 0, "invalid BPM rejected");
    check(dx_core_reset(engine.get(), std::numeric_limits<double>::quiet_NaN(), 4) == 0,
        "NaN BPM rejected");
    check(dx_core_reset(engine.get(), 96, 0) == 0, "invalid bar count rejected");
    check(dx_core_event_count(engine.get()) == 48, "invalid reset preserves phrase");
    const auto chord_hat = dx_core_input(engine.get(), DX_HIHAT, 0, .8);
    const auto chord_kick = dx_core_input(engine.get(), DX_KICK, 0, .8);
    check(chord_hat.judgment == DX_CENTERED && chord_kick.judgment == DX_CENTERED,
        "simultaneous hat and kick score independently");
    check(chord_hat.event_id != chord_kick.event_id, "chord notes have distinct IDs");
}

void matching_and_spam() {
    auto engine = core(240, 1);
    dx_core_input(engine.get(), DX_HIHAT, 0, .8);
    auto duplicate = dx_core_input(engine.get(), DX_HIHAT, .040, .8);
    check(duplicate.judgment == DX_EXTRA, "duplicate cannot consume future target inside broad window");
    check(duplicate.event_id == -1, "extra does not invent target offset");
    auto next = dx_core_input(engine.get(), DX_HIHAT, .100, .8);
    check(next.judgment == DX_CENTERED && near(next.offset_ms, -25), "nearest next target matches");
    dx_core_advance(engine.get(), 1);
    auto result = snapshot(engine);
    check(result.total.matched == 2 && result.total.extra == 1 && result.total.missed == 10,
        "extras and omissions both recorded");
    check(near(result.total.timing_accuracy_percent, 200.0 / 13), "spam lowers accuracy denominator");
    check(dx_core_input(engine.get(), DX_HIHAT, 1.1, .8).judgment == DX_IGNORED,
        "post-phrase input ignored");
}

void signed_and_absolute_timing() {
    auto engine = core();
    auto hats = events(engine, DX_HIHAT);
    const auto early = dx_core_input(engine.get(), DX_HIHAT, hats[1].time_seconds - .060, .8);
    const auto late = dx_core_input(engine.get(), DX_HIHAT, hats[2].time_seconds + .060, .8);
    check(early.judgment == DX_EARLY && near(early.offset_ms, -60), "early is negative");
    check(late.judgment == DX_LATE && near(late.offset_ms, 60), "late is positive");
    auto result = snapshot(engine);
    check(near(result.pads[DX_HIHAT].mean_offset_ms, 0), "opposing offsets cancel signed mean");
    check(near(result.pads[DX_HIHAT].mean_absolute_offset_ms, 60), "absolute error does not cancel");
    check(result.pads[DX_HIHAT].on_time == 0, "60 ms offsets are outside on-time threshold");
}

void delayed_delivery_and_guidance() {
    auto immediate = core();
    auto delayed = core();
    dx_core_set_guidance(delayed.get(), DX_RECALL);
    auto chart = events(immediate);
    for (const auto& event : chart) {
        dx_core_input(immediate.get(), event.pad, event.time_seconds + .010, .8);
    }
    dx_core_advance(immediate.get(), 10);
    dx_core_advance(delayed.get(), 10);
    check(snapshot(delayed).total.missed == 48, "expired targets initially reported as misses");
    std::reverse(chart.begin(), chart.end());
    for (const auto& event : chart) {
        dx_core_input(delayed.get(), event.pad, event.time_seconds + .010, .8);
    }
    const auto a = snapshot(immediate), b = snapshot(delayed);
    same_metrics(a.total, b.total, "delayed delivery and hidden guidance preserve final grade and streak");
    check(b.finished == 1 && b.total.missed == 0 && b.total.matched == 48,
        "late captured events correct misses after automatic finish");
    check(near(b.total.timing_accuracy_percent, 100), "complete in-time take scores 100 percent");
    for (int pad = 0; pad < DX_PAD_COUNT; ++pad) {
        same_metrics(a.pads[pad], b.pads[pad], "per-pad delivery-independent grade");
        check(a.bias[pad].state == b.bias[pad].state
            && near(a.bias[pad].offset_ms, b.bias[pad].offset_ms), "bias uses original capture order");
    }
}

void out_of_order_duplicate() {
    auto immediate = core(), delayed = core();
    constexpr double target = .3125;
    dx_core_input(immediate.get(), DX_HIHAT, target - .060, .8);
    dx_core_input(immediate.get(), DX_HIHAT, target, .8);
    dx_core_input(delayed.get(), DX_HIHAT, target, .8);
    dx_core_input(delayed.get(), DX_HIHAT, target - .060, .8);
    dx_core_advance(immediate.get(), .5);
    dx_core_advance(delayed.get(), .5);
    same_metrics(snapshot(immediate).total, snapshot(delayed).total,
        "reordered duplicate credits chronological first strike, not best strike");
    check(snapshot(delayed).last_hit.judgment == DX_EXTRA, "later credited input corrected to extra");
}

void bias_warmup_robustness_and_staleness() {
    auto engine = core(60, 8);
    auto hats = events(engine, DX_HIHAT);
    for (int i = 1; i <= 3; ++i) dx_core_input(engine.get(), DX_HIHAT, hats[i].time_seconds - .040, .8);
    check(snapshot(engine).bias[DX_HIHAT].state == DX_BIAS_WARMUP, "three hits do not imply a trend");
    dx_core_input(engine.get(), DX_HIHAT, hats[4].time_seconds - .040, .8);
    check(snapshot(engine).bias[DX_HIHAT].state == DX_BIAS_EARLY, "four consistent early hits establish bias");
    dx_core_input(engine.get(), DX_HIHAT, hats[5].time_seconds + .110, .8);
    auto result = snapshot(engine);
    check(result.bias[DX_HIHAT].sample_count == 4 && near(result.bias[DX_HIHAT].offset_ms, -40),
        "isolated timing outlier does not reverse recent bias");
    check(result.pads[DX_HIHAT].matched == 5
        && result.pads[DX_HIHAT].mean_absolute_offset_ms > 40, "outlier still affects honest scoring");
    check(result.bias[DX_SNARE].state == DX_BIAS_WARMUP, "other pad does not inherit hat bias");
    dx_core_advance(engine.get(), 7);
    check(snapshot(engine).bias[DX_HIHAT].state == DX_BIAS_STALE, "old instrument tendency becomes stale");
    for (int i = 20; i <= 27; ++i) dx_core_input(engine.get(), DX_HIHAT, hats[i].time_seconds + .035, .8);
    check(snapshot(engine).bias[DX_HIHAT].state == DX_BIAS_LATE
        && near(snapshot(engine).bias[DX_HIHAT].offset_ms, 35), "recent strikes replace old tendency");
    check(near(hats[27].time_seconds, 13.5), "bias tracking never changes target clock");
}

void uneven_is_not_centered() {
    auto engine = core(60, 4);
    auto hats = events(engine, DX_HIHAT);
    for (int i = 1; i <= 8; ++i) {
        dx_core_input(engine.get(), DX_HIHAT, hats[i].time_seconds + (i % 2 ? -.080 : .080), .8);
    }
    auto result = snapshot(engine);
    check(near(result.bias[DX_HIHAT].offset_ms, 0), "balanced timing has zero median");
    check(result.bias[DX_HIHAT].state == DX_BIAS_UNEVEN, "balanced large errors do not claim centered playing");
}

void count_in_and_partial_stop() {
    auto engine = core();
    check(dx_core_input(engine.get(), DX_HIHAT, -.126, .8).judgment == DX_IGNORED,
        "count-in input before the first target's early window is ignored");
    check(dx_core_input(engine.get(), 8, 0, .8).judgment == DX_IGNORED, "invalid pad ignored");
    check(dx_core_input(engine.get(), DX_HIHAT, 0, 0).judgment == DX_IGNORED, "zero-velocity note-off ignored");
    dx_core_input(engine.get(), DX_HIHAT, 0, .8);
    dx_core_finish(engine.get(), .100);
    auto result = snapshot(engine);
    check(result.finished && result.total.matched == 1 && result.total.missed == 1,
        "manual stop counts elapsed kick omission but not future targets");
    check(dx_core_input(engine.get(), DX_KICK, .020, .8).judgment == DX_CENTERED,
        "captured pre-stop hit can correct partial take");
    check(dx_core_input(engine.get(), DX_HIHAT, .3125, .8).judgment == DX_IGNORED,
        "input after partial stop cannot extend take");
    dx_core_finish(engine.get(), 10);
    check(near(snapshot(engine).elapsed_seconds, .100), "repeated finish cannot expand partial take");
    dx_core_reset(engine.get(), 96, 4);
    dx_core_finish(engine.get(), -.2);
    dx_core_advance(engine.get(), 20);
    check(snapshot(engine).total.has_accuracy == 0 && snapshot(engine).total.missed == 0,
        "count-in cancellation creates no scored attempt");
}

void first_target_early_window() {
    auto engine = core();
    check(dx_core_input(engine.get(), DX_HIHAT, -.125001, .8).judgment == DX_IGNORED,
        "input just before the opening early window is ignored");
    check(dx_core_input(engine.get(), DX_SNARE, -.030, .8).judgment == DX_IGNORED,
        "a pad without an opening target stays unscored during count-in");
    check(snapshot(engine).total.has_accuracy == 0, "ignored count-in does not affect accuracy");
    const auto hat = dx_core_input(engine.get(), DX_HIHAT, -.030, .8);
    const auto kick = dx_core_input(engine.get(), DX_KICK, -.125, .8);
    check(hat.judgment == DX_EARLY && near(hat.offset_ms, -30),
        "opening hi-hat can be matched thirty milliseconds early");
    check(kick.judgment == DX_EARLY && near(kick.offset_ms, -125),
        "opening kick includes the exact 125 millisecond boundary");
    check(hat.event_id != kick.event_id && snapshot(engine).total.matched == 2,
        "early opening chord members score independently");
    check(dx_core_input(engine.get(), DX_HIHAT, -.020, .8).judgment == DX_EXTRA,
        "repeated early strikes cannot inflate opening score");
    dx_core_advance(engine.get(), 10);
    check(snapshot(engine).total.matched == 2 && snapshot(engine).total.missed == 46,
        "accepted early targets are not later counted as omissions");

    auto delayed = core();
    dx_core_advance(delayed.get(), 10);
    check(dx_core_input(delayed.get(), DX_HIHAT, -.030, .8).judgment == DX_EARLY,
        "preserved early timestamp corrects an opening miss after delayed delivery");
    check(snapshot(delayed).total.matched == 1 && snapshot(delayed).total.missed == 47,
        "delayed opening match decrements the miss count");

    dx_core_reset(engine.get(), 96, 4);
    dx_core_input(engine.get(), DX_HIHAT, -.030, .8);
    dx_core_input(engine.get(), DX_HIHAT, -.020, .8);
    dx_core_finish(engine.get(), -.010);
    const auto canceled = snapshot(engine);
    check(canceled.total.matched == 0 && canceled.total.extra == 0
        && canceled.total.missed == 0 && !canceled.total.has_accuracy,
        "canceling before the opening beat discards provisional early hits and extras");
    check(canceled.last_hit.judgment == DX_IGNORED,
        "count-in cancellation clears provisional last-hit feedback");
    check(dx_core_input(engine.get(), DX_KICK, -.030, .8).judgment == DX_IGNORED,
        "negative cutoff blocks delayed early hits after count-in cancellation");
    check(dx_core_input(engine.get(), DX_KICK, 0, .8).judgment == DX_IGNORED,
        "negative cutoff also blocks subsequent opening hits");
}
}

int main() {
    phrase_and_validation();
    matching_and_spam();
    signed_and_absolute_timing();
    delayed_delivery_and_guidance();
    out_of_order_duplicate();
    bias_warmup_robustness_and_staleness();
    uneven_is_not_centered();
    count_in_and_partial_stop();
    first_target_early_window();
    std::cout << "Drumx scoring core: " << checks << " checks passed.\n";
}
