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
        std::vector<Event> events;
        events.reserve(static_cast<size_t>(bars) * 12);
        const double eighth = 30.0 / bpm;
        for (int step = 0; step < bars * 8; ++step) {
            auto append = [&](int pad) {
                Event event;
                event.view.id = static_cast<int>(events.size());
                event.view.pad = pad;
                event.view.time_seconds = step * eighth;
                event.deadline = event.view.time_seconds + kMatchWindow;
                events.push_back(event);
            };
            append(DX_HIHAT);
            if (step % 8 == 0 || step % 8 == 4) append(DX_KICK);
            if (step % 8 == 2 || step % 8 == 6) append(DX_SNARE);
        }
        for (size_t index = 0; index < events.size(); ++index) {
            for (size_t next = index + 1; next < events.size(); ++next) {
                if (events[next].view.pad == events[index].view.pad) {
                    events[index].deadline = std::min(events[index].deadline,
                        (events[index].view.time_seconds + events[next].view.time_seconds) / 2);
                    break;
                }
            }
        }
        core->events = std::move(events);
        core->extras.clear();
        core->bpm = bpm;
        core->duration = bars * 240.0 / bpm;
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
    if (!core || pad < 0 || pad >= DX_PAD_COUNT || !std::isfinite(time)
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
    std::array<double, DX_PAD_COUNT> sums{};
    std::array<double, DX_PAD_COUNT> absolutes{};
    std::vector<Outcome> outcomes;
    outcomes.reserve(core->events.size() + core->extras.size());
    for (const auto& event : core->events) {
        auto& metrics = output->pads[event.view.pad];
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
        ++output->pads[extra.pad].extra;
        outcomes.push_back({extra.time, -1, extra.pad, false});
    }
    std::sort(outcomes.begin(), outcomes.end(), [](const Outcome& a, const Outcome& b) {
        if (a.time != b.time) return a.time < b.time;
        return a.tie < b.tie;
    });
    for (const auto& outcome : outcomes) {
        auto& pad = output->pads[outcome.pad];
        output->total.streak = outcome.good ? output->total.streak + 1 : 0;
        pad.streak = outcome.good ? pad.streak + 1 : 0;
        output->total.best_streak = std::max(output->total.best_streak, output->total.streak);
        pad.best_streak = std::max(pad.best_streak, pad.streak);
    }
    double sum = 0, absolute = 0;
    for (int pad = 0; pad < DX_PAD_COUNT; ++pad) {
        auto& metrics = output->pads[pad];
        finish_metrics(metrics, sums[pad], absolutes[pad]);
        output->total.expected += metrics.expected;
        output->total.matched += metrics.matched;
        output->total.missed += metrics.missed;
        output->total.extra += metrics.extra;
        output->total.on_time += metrics.on_time;
        sum += sums[pad];
        absolute += absolutes[pad];
        output->bias[pad] = make_bias(*core, pad);
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
