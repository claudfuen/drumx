#include "drumx_core.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <limits>
#include <new>
#include <vector>

namespace {
constexpr double kMatchWindow = 0.125;
constexpr double kCenteredMs = 25.0;
constexpr double kOnTimeMs = 50.0;
constexpr double kEpsilon = 1e-9;
constexpr double kDuplicateBeatEpsilon = 1e-9;
constexpr int kBiasSamples = 8;
constexpr int kBiasWarmup = 4;
constexpr double kBiasHorizon = 12.0;

struct Event {
    DXEvent view{};
    double deadline = 0;
    double offset_ms = 0;
    double input_time = 0;
    uint64_t input_id = 0;
};
struct Extra {
    int pad;
    double time;
};
struct Outcome {
    double time;
    int tie;
    int pad;
    bool good;
};

double median(std::vector<double> values) {
    std::sort(values.begin(), values.end());
    const auto middle = values.size() / 2;
    return values.size() % 2 ? values[middle]
                            : (values[middle - 1] + values[middle]) / 2;
}
double deviation(const std::vector<double>& values, double center) {
    std::vector<double> distances;
    distances.reserve(values.size());
    for (double value : values) distances.push_back(std::abs(value - center));
    return median(std::move(distances));
}
DXHitResult ignored(int pad, double time, double velocity) {
    DXHitResult result{};
    result.pad = pad;
    result.judgment = DX_IGNORED;
    result.event_id = -1;
    result.time_seconds = std::isfinite(time) ? time : 0;
    result.velocity = std::isfinite(velocity) ? std::clamp(velocity, 0.0, 1.0) : 0;
    return result;
}
void finish_metrics(DXMetrics& metrics, double offset_sum, double absolute_sum) {
    const int attempts = metrics.matched + metrics.missed + metrics.extra;
    metrics.has_accuracy = attempts > 0;
    metrics.has_timing = metrics.matched > 0;
    if (attempts) {
        metrics.hit_rate_percent = 100.0 * metrics.matched / attempts;
        metrics.timing_accuracy_percent = 100.0 * metrics.on_time / attempts;
    }
    if (metrics.matched) {
        metrics.mean_offset_ms = offset_sum / metrics.matched;
        metrics.mean_absolute_offset_ms = absolute_sum / metrics.matched;
    }
}
}

struct DXCore {
    double bpm = 96;
    double duration = 10;
    double now = 0;
    double cutoff = 10;
    bool finished = false;
    int guidance = DX_FOLLOW;
    int pad_count = DX_PAD_COUNT;
    uint64_t next_id = 1;
    std::vector<Event> events;
    std::vector<Extra> extras;
    DXHitResult last_hit = ignored(-1, 0, 0);
};

namespace {
DXBias make_bias(const DXCore& core, int pad) {
    DXBias result{};
    result.state = DX_BIAS_WARMUP;
    result.age_seconds = -1;
    std::vector<const Event*> matches;
    for (const auto& event : core.events) {
        if (event.view.pad == pad && event.view.hit) matches.push_back(&event);
    }
    if (matches.empty()) return result;
    std::sort(matches.begin(), matches.end(), [](const Event* left, const Event* right) {
        return left->input_time > right->input_time;
    });
    result.age_seconds = std::max(0.0, core.now - matches.front()->input_time);
    std::vector<double> offsets;
    offsets.reserve(kBiasSamples);
    for (const auto* event : matches) {
        if (core.now - event->input_time > kBiasHorizon) break;
        offsets.push_back(event->offset_ms);
        if (offsets.size() == kBiasSamples) break;
    }
    result.sample_count = static_cast<int>(offsets.size());
    const double stale_after = std::clamp(4.0 * 60.0 / core.bpm, 3.0, 8.0);
    if (result.age_seconds > stale_after) {
        result.state = DX_BIAS_STALE;
        return result;
    }
    if (offsets.size() < kBiasWarmup) return result;
    const double raw_median = median(offsets);
    const double raw_mad = deviation(offsets, raw_median);
    const double fence = std::max(30.0, 3.0 * 1.4826 * raw_mad);
    offsets.erase(std::remove_if(offsets.begin(), offsets.end(), [&](double offset) {
        return std::abs(offset - raw_median) > fence;
    }), offsets.end());
    result.sample_count = static_cast<int>(offsets.size());
    if (offsets.size() < kBiasWarmup) return result;
    result.offset_ms = median(offsets);
    result.spread_ms = deviation(offsets, result.offset_ms);
    if (result.spread_ms > 25.0) result.state = DX_BIAS_UNEVEN;
    else if (result.offset_ms < -20.0) result.state = DX_BIAS_EARLY;
    else if (result.offset_ms > 20.0) result.state = DX_BIAS_LATE;
    else result.state = DX_BIAS_CENTERED;
    return result;
}
}

extern "C" {

DXCore* dx_core_create(void) {
    DXCore* core = new (std::nothrow) DXCore;
    if (core && !dx_core_reset(core, 96, 4)) {
        delete core;
        return nullptr;
    }
    return core;
}

void dx_core_destroy(DXCore* core) { delete core; }

int dx_core_reset(DXCore* core, double bpm, int bars) {
    if (!core || !std::isfinite(bpm) || bpm < 30 || bpm > 240 || bars < 1 || bars > 64) {
        return 0;
    }
    try {
        std::vector<DXChartEvent> chart;
        chart.reserve(static_cast<size_t>(bars) * 12);
        for (int step = 0; step < bars * 8; ++step) {
            chart.push_back({DX_HIHAT, step * 0.5});
            if (step % 8 == 0 || step % 8 == 4) chart.push_back({DX_KICK, step * 0.5});
            if (step % 8 == 2 || step % 8 == 6) chart.push_back({DX_SNARE, step * 0.5});
        }
        return dx_core_load_chart(core, bpm, bars * 4.0, chart.data(),
                                  static_cast<int>(chart.size()));
    } catch (...) {
        return 0;
    }
}

int dx_core_load_chart(DXCore* core, double bpm, double duration_beats,
                       const DXChartEvent* source, int event_count) {
    if (!core || !std::isfinite(bpm) || bpm < 30 || bpm > 240
        || !std::isfinite(duration_beats) || duration_beats <= 0 || duration_beats > 256
        || !source || event_count < 1 || event_count > 4096) return 0;
    const double seconds_per_beat = 60.0 / bpm;
    const double duration = duration_beats * seconds_per_beat;
    // A positive authoring duration must also be representable in the song clock.
    if (duration <= 0) return 0;
    for (int index = 0; index < event_count; ++index) {
        const auto& event = source[index];
        if (event.pad < 0 || event.pad >= DX_PAD_COUNT || !std::isfinite(event.beat)
            || event.beat < 0 || event.beat >= duration_beats) return 0;
    }
    try {
        std::vector<DXChartEvent> chart(source, source + event_count);
        std::sort(chart.begin(), chart.end(), [](const DXChartEvent& a, const DXChartEvent& b) {
            return a.beat < b.beat || (a.beat == b.beat && a.pad < b.pad);
        });
        std::array<double, DX_PAD_COUNT> last_beats{};
        std::array<bool, DX_PAD_COUNT> seen{};
        std::vector<Event> events;
        events.reserve(chart.size());
        for (const auto& authored : chart) {
            if (seen[authored.pad]
                && authored.beat - last_beats[authored.pad] <= kDuplicateBeatEpsilon) return 0;
            seen[authored.pad] = true;
            last_beats[authored.pad] = authored.beat;
            Event event;
            event.view.id = static_cast<int>(events.size());
            event.view.pad = authored.pad;
            event.view.time_seconds = authored.beat * seconds_per_beat;
            event.deadline = event.view.time_seconds + kMatchWindow;
            events.push_back(event);
        }
        // Nearest-target matching splits overlapping windows at the midpoint
        // of consecutive notes on the same pad, including dense authored charts.
        std::array<double, DX_PAD_COUNT> next_times;
        next_times.fill(std::numeric_limits<double>::infinity());
        for (auto event = events.rbegin(); event != events.rend(); ++event) {
            const int pad = event->view.pad;
            event->deadline = std::min(event->deadline,
                (event->view.time_seconds + next_times[pad]) / 2);
            next_times[pad] = event->view.time_seconds;
        }
        // All validation and allocation precede this nonthrowing replacement.
        core->events.swap(events);
        core->extras.clear();
        core->bpm = bpm;
        core->pad_count = DX_PAD_COUNT;
        core->duration = duration;
        core->cutoff = core->duration;
        core->now = 0;
        core->finished = false;
        core->next_id = 1;
        core->last_hit = ignored(-1, 0, 0);
        return 1;
    } catch (...) {
        return 0;
    }
}

int dx_core_load_song(DXCore* core, double duration_seconds,
                      const DXSongEvent* source, int event_count) {
    if (!core || !std::isfinite(duration_seconds) || duration_seconds <= 0
        || duration_seconds > 7200 || !source || event_count < 1
        || event_count > 200000) return 0;
    for (int index = 0; index < event_count; ++index) {
        const auto& event = source[index];
        if (event.pad < 0 || event.pad >= DX_SONG_PAD_COUNT
            || !std::isfinite(event.time_seconds) || event.time_seconds < 0
            || event.time_seconds >= duration_seconds) return 0;
    }
    try {
        std::vector<DXSongEvent> chart(source, source + event_count);
        std::sort(chart.begin(), chart.end(), [](const DXSongEvent& a, const DXSongEvent& b) {
            return a.time_seconds < b.time_seconds
                || (a.time_seconds == b.time_seconds && a.pad < b.pad);
        });
        std::array<double, DX_SONG_PAD_COUNT> last_times;
        last_times.fill(-std::numeric_limits<double>::infinity());
        std::vector<Event> events;
        events.reserve(chart.size());
        for (const auto& authored : chart) {
            if (authored.time_seconds - last_times[authored.pad] <= kEpsilon) return 0;
            last_times[authored.pad] = authored.time_seconds;
            Event event;
            event.view.id = static_cast<int>(events.size());
            event.view.pad = authored.pad;
            event.view.time_seconds = authored.time_seconds;
            event.deadline = authored.time_seconds + kMatchWindow;
            events.push_back(event);
        }
        std::array<double, DX_SONG_PAD_COUNT> next_times;
        next_times.fill(std::numeric_limits<double>::infinity());
        for (auto event = events.rbegin(); event != events.rend(); ++event) {
            const int pad = event->view.pad;
            event->deadline = std::min(event->deadline,
                (event->view.time_seconds + next_times[pad]) / 2);
            next_times[pad] = event->view.time_seconds;
        }
        core->events.swap(events);
        core->extras.clear();
        core->bpm = 120;
        core->pad_count = DX_SONG_PAD_COUNT;
        core->duration = duration_seconds;
        core->cutoff = duration_seconds;
        core->now = 0;
        core->finished = false;
        core->guidance = DX_FOLLOW;
        core->next_id = 1;
        core->last_hit = ignored(-1, 0, 0);
        return 1;
    } catch (...) {
        return 0;
    }
}

void dx_core_set_guidance(DXCore* core, int guidance) {
    if (core && guidance >= DX_FOLLOW && guidance <= DX_RECALL) core->guidance = guidance;
}

double dx_core_duration(const DXCore* core) { return core ? core->duration : 0; }

void dx_core_advance(DXCore* core, double time) {
    if (!core || !std::isfinite(time) || core->cutoff < 0) return;
    core->now = std::max(core->now, std::clamp(time, 0.0, core->cutoff));
    for (auto& event : core->events) {
        if (!event.view.resolved && event.deadline + kEpsilon < core->now) {
            event.view.resolved = 1;
        }
    }
    if (time >= core->duration) {
        core->finished = true;
        for (auto& event : core->events) {
            if (event.view.time_seconds <= core->cutoff) event.view.resolved = 1;
        }
    }
}

DXHitResult dx_core_input(DXCore* core, int pad, double time, double velocity) {
    DXHitResult result = ignored(pad, time, velocity);
    if (!core || pad < 0 || pad >= core->pad_count || !std::isfinite(time)
        || !std::isfinite(velocity) || velocity <= 0 || core->cutoff < 0
        || time < -kMatchWindow - kEpsilon
        || time >= core->duration || time > core->cutoff) return result;
    Event* nearest = nullptr;
    double distance = std::numeric_limits<double>::infinity();
    for (auto& event : core->events) {
        if (event.view.pad != pad) continue;
        const double candidate = std::abs(event.view.time_seconds - time);
        if (candidate + kEpsilon < distance) {
            nearest = &event;
            distance = candidate;
        }
    }
    // Only an actual target on the opening beat has an early window in the
    // count-in. Other pads must not manufacture extras or anticipate later notes.
    if (time < 0 && (!nearest || nearest->view.time_seconds != 0)) return result;
    dx_core_advance(core, time);
    result.id = core->next_id++;
    if (!nearest || distance > kMatchWindow + kEpsilon
        || (nearest->view.hit && time >= nearest->input_time)) {
        result.judgment = DX_EXTRA;
        core->extras.push_back({pad, time});
    } else {
        // Preserve chronological first-hit behavior if callbacks arrive out of
        // order. The previously credited, later input becomes the extra hit.
        if (nearest->view.hit) {
            core->extras.push_back({pad, nearest->input_time});
            if (core->last_hit.id == nearest->input_id) {
                core->last_hit.judgment = DX_EXTRA;
                core->last_hit.event_id = -1;
                core->last_hit.offset_ms = 0;
            }
        }
        nearest->view.resolved = 1;
        nearest->view.hit = 1;
        nearest->offset_ms = (time - nearest->view.time_seconds) * 1000.0;
        nearest->input_time = time;
        nearest->input_id = result.id;
        result.event_id = nearest->view.id;
        result.offset_ms = nearest->offset_ms;
        result.judgment = std::abs(result.offset_ms) <= kCenteredMs + kEpsilon
            ? DX_CENTERED : (result.offset_ms < 0 ? DX_EARLY : DX_LATE);
    }
    if (core->last_hit.id == 0 || result.time_seconds >= core->last_hit.time_seconds) {
        core->last_hit = result;
    }
    return result;
}

void dx_core_finish(DXCore* core, double time) {
    if (!core || !std::isfinite(time) || core->finished) return;
    const double cutoff = std::clamp(time, 0.0, core->duration);
    dx_core_advance(core, cutoff);
    core->cutoff = cutoff;
    core->finished = true;
    if (time < 0) {
        core->cutoff = -1;
        core->now = 0;
        core->extras.clear();
        core->last_hit = ignored(-1, 0, 0);
        core->next_id = 1;
        for (auto& event : core->events) {
            event.view.resolved = 0;
            event.view.hit = 0;
            event.offset_ms = 0;
            event.input_time = 0;
            event.input_id = 0;
        }
        return;
    }
    for (auto& event : core->events) {
        if (event.view.time_seconds <= cutoff) event.view.resolved = 1;
    }
}

void dx_core_snapshot(const DXCore* core, DXSnapshot* output) {
    if (!output) return;
    *output = DXSnapshot{};
    if (!core) return;
    output->bpm = core->bpm;
    output->duration_seconds = core->duration;
    output->elapsed_seconds = core->now;
    output->finished = core->finished;
    output->guidance = core->guidance;
    output->last_hit = core->last_hit;
    std::array<DXMetrics, DX_SONG_PAD_COUNT> pad_metrics{};
    std::array<double, DX_SONG_PAD_COUNT> sums{};
    std::array<double, DX_SONG_PAD_COUNT> absolutes{};
    std::vector<Outcome> outcomes;
    outcomes.reserve(core->events.size() + core->extras.size());
    for (const auto& event : core->events) {
        auto& metrics = pad_metrics[event.view.pad];
        ++metrics.expected;
        if (!event.view.resolved) continue;
        const bool good = event.view.hit && std::abs(event.offset_ms) <= kOnTimeMs + kEpsilon;
        if (event.view.hit) {
            ++metrics.matched;
            metrics.on_time += good;
            sums[event.view.pad] += event.offset_ms;
            absolutes[event.view.pad] += std::abs(event.offset_ms);
        } else ++metrics.missed;
        outcomes.push_back({event.view.time_seconds, event.view.id, event.view.pad, good});
    }
    for (const auto& extra : core->extras) {
        ++pad_metrics[extra.pad].extra;
        outcomes.push_back({extra.time, -1, extra.pad, false});
    }
    std::sort(outcomes.begin(), outcomes.end(), [](const Outcome& a, const Outcome& b) {
        if (a.time != b.time) return a.time < b.time;
        return a.tie < b.tie;
    });
    for (const auto& outcome : outcomes) {
        auto& pad = pad_metrics[outcome.pad];
        output->total.streak = outcome.good ? output->total.streak + 1 : 0;
        pad.streak = outcome.good ? pad.streak + 1 : 0;
        output->total.best_streak = std::max(output->total.best_streak, output->total.streak);
        pad.best_streak = std::max(pad.best_streak, pad.streak);
    }
    double sum = 0, absolute = 0;
    for (int pad = 0; pad < core->pad_count; ++pad) {
        auto& metrics = pad_metrics[pad];
        finish_metrics(metrics, sums[pad], absolutes[pad]);
        output->total.expected += metrics.expected;
        output->total.matched += metrics.matched;
        output->total.missed += metrics.missed;
        output->total.extra += metrics.extra;
        output->total.on_time += metrics.on_time;
        sum += sums[pad];
        absolute += absolutes[pad];
        if (pad < DX_PAD_COUNT) {
            output->pads[pad] = metrics;
            output->bias[pad] = make_bias(*core, pad);
        }
    }
    finish_metrics(output->total, sum, absolute);
}

int dx_core_event_count(const DXCore* core) {
    return core ? static_cast<int>(core->events.size()) : 0;
}

int dx_core_event(const DXCore* core, int index, DXEvent* output) {
    if (!core || !output || index < 0 || index >= static_cast<int>(core->events.size())) return 0;
    *output = core->events[static_cast<size_t>(index)].view;
    return 1;
}

}
