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
        && a.on_time == b.on_time && a.expected == b.expected
        && a.streak == b.streak && a.best_streak == b.best_streak
        && a.has_accuracy == b.has_accuracy && a.has_timing == b.has_timing
        && near(a.hit_rate_percent, b.hit_rate_percent)
        && near(a.timing_accuracy_percent, b.timing_accuracy_percent)
        && near(a.mean_offset_ms, b.mean_offset_ms)
        && near(a.mean_absolute_offset_ms, b.mean_absolute_offset_ms), label);
}

void same_snapshot(const DXSnapshot& a, const DXSnapshot& b, const std::string& label) {
    check(a.bpm == b.bpm && a.duration_seconds == b.duration_seconds
        && a.elapsed_seconds == b.elapsed_seconds && a.finished == b.finished
        && a.guidance == b.guidance, label + ": take state");
    same_metrics(a.total, b.total, label + ": total metrics");
    for (int pad = 0; pad < DX_PAD_COUNT; ++pad) {
        same_metrics(a.pads[pad], b.pads[pad], label + ": pad metrics");
        check(a.bias[pad].state == b.bias[pad].state
            && a.bias[pad].sample_count == b.bias[pad].sample_count
            && a.bias[pad].offset_ms == b.bias[pad].offset_ms
            && a.bias[pad].spread_ms == b.bias[pad].spread_ms
            && a.bias[pad].age_seconds == b.bias[pad].age_seconds, label + ": bias");
    }
    check(a.last_hit.id == b.last_hit.id && a.last_hit.pad == b.last_hit.pad
        && a.last_hit.judgment == b.last_hit.judgment
        && a.last_hit.event_id == b.last_hit.event_id
        && a.last_hit.time_seconds == b.last_hit.time_seconds
        && a.last_hit.offset_ms == b.last_hit.offset_ms
        && a.last_hit.velocity == b.last_hit.velocity, label + ": last input");
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

void custom_sparse_and_reset() {
    auto engine = core();
    dx_core_set_guidance(engine.get(), DX_RECALL);
    dx_core_input(engine.get(), DX_HIHAT, 0, .8);
    dx_core_finish(engine.get(), .1);
    const DXChartEvent chart[] = {{DX_SNARE, 3}};
    check(dx_core_load_chart(engine.get(), 120, 7.5, chart, 1) == 1,
        "sparse chart with fractional duration loads");
    auto result = snapshot(engine);
    check(result.guidance == DX_RECALL && !result.finished && result.elapsed_seconds == 0
        && result.total.expected == 1 && !result.total.has_accuracy
        && result.last_hit.id == 0, "successful load clears take and preserves guidance");
    check(near(dx_core_duration(engine.get()), 3.75), "quarter-note duration converts at chart tempo");
    const auto targets = events(engine);
    check(targets[0].pad == DX_SNARE && near(targets[0].time_seconds, 1.5),
        "a chart may begin with silence");
    check(dx_core_input(engine.get(), DX_SNARE, -.03, .8).judgment == DX_IGNORED,
        "sparse first note does not open a count-in scoring window");
    dx_core_advance(engine.get(), 1.3);
    check(snapshot(engine).total.missed == 0, "rest before first target is not an omission");
    check(dx_core_input(engine.get(), DX_HIHAT, 1.5, .8).judgment == DX_EXTRA,
        "pad absent from custom chart still counts as an extra during play");
    const auto hit = dx_core_input(engine.get(), DX_SNARE, 1.47, .8);
    check(hit.judgment == DX_EARLY && near(hit.offset_ms, -30),
        "custom chart retains signed calibrated timing");
    dx_core_advance(engine.get(), 3.75);
    result = snapshot(engine);
    check(result.finished && result.total.matched == 1 && result.total.missed == 0
        && result.total.extra == 1 && near(result.total.timing_accuracy_percent, 50),
        "custom duration completes with extras included in score");
    check(dx_core_reset(engine.get(), 96, 4) == 1 && dx_core_event_count(engine.get()) == 48
        && near(dx_core_duration(engine.get()), 10), "legacy reset restores built-in groove after custom chart");
    check(snapshot(engine).guidance == DX_RECALL && !snapshot(engine).total.has_accuracy,
        "legacy reset preserves guidance and clears custom scores");
}

void custom_sort_chords_and_ownership() {
    auto engine = core();
    DXChartEvent chart[] = {{DX_KICK, 2}, {DX_SNARE, 0}, {DX_HIHAT, 2},
                           {DX_KICK, 0}, {DX_HIHAT, 0}};
    check(dx_core_load_chart(engine.get(), 60, 4, chart, 5) == 1,
        "unsorted custom chart allows simultaneous distinct pads");
    const auto targets = events(engine);
    const int pads[] = {DX_HIHAT, DX_SNARE, DX_KICK, DX_HIHAT, DX_KICK};
    for (int index = 0; index < 5; ++index) {
        check(targets[index].id == index && targets[index].pad == pads[index]
            && near(targets[index].time_seconds, index < 3 ? 0 : 2),
            "custom event IDs sort deterministically by beat then pad");
    }
    check(chart[0].pad == DX_KICK && chart[0].beat == 2, "load does not reorder caller memory");
    chart[0].beat = 100;
    chart[1].pad = -1;
    check(events(engine)[0].pad == DX_HIHAT && events(engine)[4].time_seconds == 2,
        "loaded chart owns its event copy");
    for (int pad = 0; pad < DX_PAD_COUNT; ++pad) {
        const auto hit = dx_core_input(engine.get(), pad, -.03, .8);
        check(hit.event_id == pad && hit.judgment == DX_EARLY,
            "all members of custom opening chord retain early window");
    }
    dx_core_input(engine.get(), DX_KICK, 2, .8);
    dx_core_input(engine.get(), DX_HIHAT, 2, .8);
    dx_core_advance(engine.get(), 4);
    check(snapshot(engine).total.on_time == 5 && snapshot(engine).total.best_streak == 5
        && snapshot(engine).total.missed == 0, "custom chord strikes retain full streak and score");
}

void custom_dense_and_delayed() {
    std::vector<DXChartEvent> chart;
    for (int step = 0; step < 16; ++step) chart.push_back({DX_SNARE, step * .25});
    auto immediate = core(), delayed = core(), windows = core();
    for (DXCore* engine : {immediate.get(), delayed.get(), windows.get()}) {
        check(dx_core_load_chart(engine, 240, 4, chart.data(), static_cast<int>(chart.size())) == 1,
            "dense sixteenth-note chart loads");
    }
    dx_core_set_guidance(delayed.get(), DX_RECALL);
    dx_core_input(windows.get(), DX_SNARE, 0, .8);
    check(dx_core_input(windows.get(), DX_SNARE, .020, .8).judgment == DX_EXTRA,
        "dense chart repeat cannot steal an adjacent target");
    const auto next = dx_core_input(windows.get(), DX_SNARE, .032, .8);
    check(next.event_id == 1 && near(next.offset_ms, -30.5),
        "dense windows partition at nearest same-pad midpoint");
    dx_core_advance(windows.get(), .157);
    check(snapshot(windows).total.missed == 1,
        "dense missed note expires at midpoint before broad match-window end");
    for (const auto& target : chart) {
        dx_core_input(immediate.get(), target.pad, target.beat * .25 + .005, .8);
    }
    dx_core_advance(immediate.get(), 1);
    dx_core_advance(delayed.get(), 1);
    check(snapshot(delayed).total.missed == 16, "dense targets expire when renderer reaches end");
    std::reverse(chart.begin(), chart.end());
    for (const auto& target : chart) {
        dx_core_input(delayed.get(), target.pad, target.beat * .25 + .005, .8);
    }
    same_metrics(snapshot(immediate).total, snapshot(delayed).total,
        "dense reverse-delivered capture timestamps restore identical score and streak");
    check(snapshot(delayed).total.on_time == 16 && snapshot(delayed).total.missed == 0
        && snapshot(delayed).total.best_streak == 16, "dense delayed hits correct every omission");
}

void custom_invalid_is_atomic() {
    auto engine = core(), control = core();
    const DXChartEvent initial[] = {{DX_HIHAT, 0}, {DX_SNARE, 1}, {DX_KICK, 2}, {DX_HIHAT, 3}};
    for (DXCore* target : {engine.get(), control.get()}) {
        check(dx_core_load_chart(target, 96, 4, initial, 4) == 1, "atomic-test chart loads");
        dx_core_set_guidance(target, DX_FADE);
        dx_core_input(target, DX_HIHAT, 0, .8);
        dx_core_input(target, DX_HIHAT, .01, .8);
        dx_core_input(target, DX_SNARE, .650, .7);
        dx_core_advance(target, 1.4);
    }
    const auto before = snapshot(engine);
    const auto before_events = events(engine);
    auto reject = [&](double bpm, double duration, const DXChartEvent* chart, int count,
                      const std::string& label) {
        check(dx_core_load_chart(engine.get(), bpm, duration, chart, count) == 0, label);
        same_snapshot(snapshot(engine), before, label + " preserves take");
        const auto after_events = events(engine);
        check(after_events.size() == before_events.size(), label + " preserves chart count");
        for (size_t index = 0; index < before_events.size(); ++index) {
            const auto& a = after_events[index];
            const auto& b = before_events[index];
            check(a.id == b.id && a.pad == b.pad && a.time_seconds == b.time_seconds
                && a.resolved == b.resolved && a.hit == b.hit, label + " preserves target state");
        }
    };
    const double nan = std::numeric_limits<double>::quiet_NaN();
    const double infinity = std::numeric_limits<double>::infinity();
    const DXChartEvent valid[] = {{DX_HIHAT, 0}};
    for (double bpm : {29.999, 240.001, nan, infinity}) {
        reject(bpm, 4, valid, 1, "invalid custom tempo rejected");
    }
    for (double duration : {0.0, -1.0, 256.001, nan, infinity}) {
        reject(96, duration, valid, 1, "invalid custom duration rejected");
    }
    reject(96, 4, nullptr, 1, "null chart rejected");
    reject(96, 4, valid, 0, "empty chart rejected");
    reject(96, 4, valid, -1, "negative event count rejected");
    reject(96, 4, valid, 4097, "oversized count rejected before reading events");
    for (int pad : {-1, static_cast<int>(DX_PAD_COUNT)}) {
        const DXChartEvent invalid[] = {{pad, 0}};
        reject(96, 4, invalid, 1, "invalid chart pad rejected");
    }
    for (double beat : {-.0001, 4.0, 5.0, nan, infinity}) {
        const DXChartEvent invalid[] = {{DX_SNARE, beat}};
        reject(96, 4, invalid, 1, "invalid event beat rejected");
    }
    const DXChartEvent duplicate[] = {{DX_KICK, 1}, {DX_HIHAT, 0}, {DX_KICK, 1}};
    reject(96, 4, duplicate, 3, "unsorted same-pad duplicate rejected");
    const DXChartEvent close_duplicate[] = {{DX_SNARE, 1 + 5e-10}, {DX_KICK, 1}, {DX_SNARE, 1}};
    reject(96, 4, close_duplicate, 3, "near-duplicate rejected across interleaved chord pad");
    const DXChartEvent late_invalid[] = {{DX_SNARE, 0}, {DX_HIHAT, 1}, {DX_KICK, nan}};
    reject(96, 4, late_invalid, 3, "late invalid event does not partially install chart");
    check(dx_core_load_chart(nullptr, 96, 4, valid, 1) == 0, "null core rejected");
    const auto continued = dx_core_input(engine.get(), DX_HIHAT, 1.875, .6);
    const auto reference = dx_core_input(control.get(), DX_HIHAT, 1.875, .6);
    check(continued.id == reference.id && continued.judgment == reference.judgment,
        "rejected charts preserve next input ID and live matching state");
    dx_core_advance(engine.get(), 2.5);
    dx_core_advance(control.get(), 2.5);
    same_snapshot(snapshot(engine), snapshot(control), "rejected charts preserve eventual completed take");
    dx_core_reset(engine.get(), 96, 4);
    dx_core_finish(engine.get(), -.2);
    check(dx_core_load_chart(engine.get(), 96, 4, nullptr, 0) == 0
        && dx_core_input(engine.get(), DX_HIHAT, -.03, .8).judgment == DX_IGNORED,
        "invalid load cannot reopen canceled count-in cutoff");
}

void custom_chart_limits() {
    auto engine = core();
    std::vector<DXChartEvent> chart;
    chart.reserve(4096);
    for (int index = 4095; index >= 0; --index) chart.push_back({DX_HIHAT, index / 16.0});
    check(dx_core_load_chart(engine.get(), 30, 256, chart.data(), 4096) == 1,
        "inclusive chart size, duration and slow-tempo limits accepted");
    check(dx_core_event_count(engine.get()) == 4096 && near(dx_core_duration(engine.get()), 512),
        "maximum chart has exact duration and expected count");
    DXEvent first{}, last{};
    check(dx_core_event(engine.get(), 0, &first) == 1 && first.time_seconds == 0
        && dx_core_event(engine.get(), 4095, &last) == 1 && near(last.time_seconds, 511.875),
        "maximum reverse-authored chart sorts all target times");
    dx_core_advance(engine.get(), 512);
    check(snapshot(engine).total.missed == 4096 && snapshot(engine).finished,
        "maximum chart resolves every omission");
    const DXChartEvent separated[] = {{DX_SNARE, 0}, {DX_SNARE, 2e-9}};
    check(dx_core_load_chart(engine.get(), 240, .5, separated, 2) == 1,
        "same-pad beats beyond duplicate tolerance remain valid authored events");
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
    custom_sparse_and_reset();
    custom_sort_chords_and_ownership();
    custom_dense_and_delayed();
    custom_invalid_is_atomic();
    custom_chart_limits();
    std::cout << "Drumx scoring core: " << checks << " checks passed.\n";
}
