#include "drumx_engine.h"
#include "drumx_tempo.h"
#include <godot_cpp/classes/file_access.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <cmath>
#include <map>
#include <string>
#if defined(__APPLE__)
#include "window_appearance.h"
#endif

namespace godot {
void DrumxEngine::_bind_methods() {
  ClassDB::bind_method(D_METHOD("configure_window", "native_handle"), &DrumxEngine::configure_window);
  ClassDB::bind_method(D_METHOD("acquire_progress_lock", "absolute_archive_path"), &DrumxEngine::acquire_progress_lock);
  ClassDB::bind_method(D_METHOD("pulse_tempo_plan"), &DrumxEngine::pulse_tempo_plan);
  ClassDB::bind_method(D_METHOD("evaluate_pulse_tempo", "attempts", "current"), &DrumxEngine::evaluate_pulse_tempo);
  ClassDB::bind_method(D_METHOD("get_host_time"), &DrumxEngine::get_host_time);
  ClassDB::bind_method(D_METHOD("load_chart", "bpm", "bars", "events"), &DrumxEngine::load_chart);
  ClassDB::bind_method(D_METHOD("start", "count_in_beats"), &DrumxEngine::start, DEFVAL(4));
  ClassDB::bind_method(D_METHOD("stop"), &DrumxEngine::stop);
  ClassDB::bind_method(D_METHOD("snapshot"), &DrumxEngine::snapshot);
  ClassDB::bind_method(D_METHOD("get_events"), &DrumxEngine::get_events);
  ClassDB::bind_method(D_METHOD("poll_hits"), &DrumxEngine::poll_hits);
  ClassDB::bind_method(D_METHOD("sources"), &DrumxEngine::sources);
  ClassDB::bind_method(D_METHOD("connect_source", "id"), &DrumxEngine::connect_source);
  ClassDB::bind_method(D_METHOD("set_mapping", "mapping"), &DrumxEngine::set_mapping);
  ClassDB::bind_method(D_METHOD("get_mapping"), &DrumxEngine::get_mapping);
  ClassDB::bind_method(D_METHOD("learn_pad", "pad"), &DrumxEngine::learn_pad);
  ClassDB::bind_method(D_METHOD("cancel_learning"), &DrumxEngine::cancel_learning);
  ClassDB::bind_method(D_METHOD("load_sample_bank", "directory", "open_device"), &DrumxEngine::load_sample_bank, DEFVAL(true));
  ClassDB::bind_method(D_METHOD("set_monitoring", "enabled"), &DrumxEngine::set_monitoring);
  ClassDB::bind_method(D_METHOD("set_volume", "value"), &DrumxEngine::set_volume);
  ClassDB::bind_method(D_METHOD("keyboard_hit", "pad", "velocity"), &DrumxEngine::keyboard_hit);
}
bool DrumxEngine::configure_window(int64_t native_handle) {
#if defined(__APPLE__)
  return native_handle > 0 && drumx::configure_window_appearance(uint64_t(native_handle));
#else
  (void)native_handle;
  return false;
#endif
}
bool DrumxEngine::acquire_progress_lock(const String &absolute_archive_path) {
  const CharString bytes = absolute_archive_path.utf8();
  return progress_lock.acquire(std::string(bytes.get_data(), size_t(bytes.length())));
}

namespace {
// Identity is compared using the entire UTF-8 string, including embedded zero
// bytes. Separate ID/condition tables assign collision-free per-call ordinals.
struct TempoTokens {
  std::map<std::string, uint64_t> entries;
  uint64_t token(const String &value) {
    const CharString bytes = value.utf8();
    const std::string key(bytes.get_data(), size_t(bytes.length()));
    const auto found = entries.find(key);
    if (found != entries.end()) return found->second;
    const uint64_t ordinal = uint64_t(entries.size()) + 1;
    entries.emplace(key, ordinal);
    return ordinal;
  }
};
bool tempo_string(const Dictionary &d, const char *key, String &out, int64_t maximum = 16384) {
  if (!d.has(key) || d[key].get_type() != Variant::STRING) return false;
  out = d[key];
  return !out.is_empty() && out.length() <= maximum;
}
bool tempo_number(const Dictionary &d, const char *key, double &out, double low, double high) {
  if (!d.has(key)) return false;
  const auto type = d[key].get_type();
  if (type != Variant::INT && type != Variant::FLOAT) return false;
  out = double(d[key]);
  return std::isfinite(out) && out >= low && out <= high;
}
bool tempo_integer(const Dictionary &d, const char *key, int &out, int low, int high) {
  double value = 0;
  if (!tempo_number(d, key, value, low, high) || value != std::floor(value)) return false;
  out = int(value);
  return true;
}
bool tempo_bool(const Dictionary &d, const char *key, int &out) {
  if (!d.has(key) || d[key].get_type() != Variant::BOOL) return false;
  out = bool(d[key]) ? 1 : 0;
  return true;
}
bool tempo_lesson(const Dictionary &d) {
  String lesson, version;
  return tempo_string(d, "lesson", lesson) && lesson == "find-the-pulse" &&
    tempo_string(d, "version", version) && version == "find-the-pulse-v1";
}
bool tempo_context(const Dictionary &d, TempoTokens &tokens, DXTempoContext &out) {
  String conditions;
  int monitoring = 0;
  double calibration = 0;
  if (!tempo_lesson(d) || !tempo_string(d, "conditions_key", conditions) ||
      !tempo_integer(d, "policy_version", out.policy_version, 0, 1000000) ||
      !tempo_number(d, "bpm", out.bpm, 30, 240) ||
      !tempo_integer(d, "bars", out.bars, 1, 64) ||
      !tempo_integer(d, "guidance", out.guidance, 0, 2) ||
      !tempo_bool(d, "live_feedback", out.live_feedback) ||
      !tempo_bool(d, "monitoring", monitoring) ||
      !tempo_number(d, "calibration_ms", calibration, -1000, 1000)) return false;
  // The frontend's complete source/mapping key is length-preserved. Include the
  // explicit output/calibration metadata too, so a mistaken reused key cannot
  // pool those different conditions. No formatting or rounding of calibration.
  const CharString bytes = conditions.utf8();
  std::string identity(bytes.get_data(), size_t(bytes.length()));
  identity.push_back(char(monitoring));
  if (calibration == 0) calibration = 0; // Treat negative zero as the same offset.
  identity.append(reinterpret_cast<const char *>(&calibration), sizeof(calibration));
  const auto found = tokens.entries.find(identity);
  if (found != tokens.entries.end()) out.conditions_id = found->second;
  else {
    out.conditions_id = uint64_t(tokens.entries.size()) + 1;
    tokens.entries.emplace(identity, out.conditions_id);
  }
  return true;
}
Dictionary tempo_error(const String &message, int64_t index = -1) {
  Dictionary out;
  out["ok"] = false;
  out["error"] = message;
  out["error_index"] = index;
  out["policy_version"] = DX_TEMPO_POLICY_VERSION;
  return out;
}
}

Dictionary DrumxEngine::pulse_tempo_plan() const {
  Dictionary out;
  out["ok"] = true;
  out["policy_version"] = DX_TEMPO_POLICY_VERSION;
  out["lesson"] = "find-the-pulse";
  out["version"] = "find-the-pulse-v1";
  out["start_bpm"] = DX_TEMPO_START_BPM;
  out["checkpoint_bpm"] = DX_TEMPO_CHECKPOINT_BPM;
  out["step_bpm"] = DX_TEMPO_STEP_BPM;
  out["phrase_bars"] = DX_TEMPO_PHRASE_BARS;
  out["start_guidance"] = 0;
  out["start_live_feedback"] = true;
  Array stretch; stretch.push_back(DX_TEMPO_STRETCH_BPM_1); stretch.push_back(DX_TEMPO_STRETCH_BPM_2);
  out["stretch_bpms"] = stretch;
  out["expected_per_bar"] = 4;
  out["minimum_matched_percent"] = 95;
  out["minimum_on_time_percent"] = 90;
  out["maximum_extra_percent"] = 2;
  out["advance_qualifying"] = 1;
  out["required_qualifying"] = 2;
  out["comparable_window"] = 3;
  return out;
}

Dictionary DrumxEngine::evaluate_pulse_tempo(const Array &attempts, const Dictionary &current) const {
  // A malformed late correction must not silently expose the older record's
  // evidence. Fail the whole request instead of filtering malformed rows.
  if (attempts.size() > 100000) return tempo_error("Too many pulse tempo attempts.");
    TempoTokens identities, conditions;
    DXTempoContext context{};
    if (!tempo_context(current, conditions, context) || context.policy_version != DX_TEMPO_POLICY_VERSION)
      return tempo_error("Current intent requires exact pulse lesson/version, policy 1 and complete valid conditions.");
    std::vector<DXTempoAttempt> records;
    records.reserve(size_t(attempts.size()));
    int legacy_count = 0;
    for (int64_t i = 0; i < attempts.size(); ++i) {
      if (attempts[i].get_type() != Variant::DICTIONARY) return tempo_error("Attempt must be a Dictionary.", i);
      Dictionary input = attempts[i];
      String id;
      if (!tempo_string(input, "id", id, 1024) || !tempo_lesson(input))
        return tempo_error("Attempt requires a full ID and exact find-the-pulse-v1 lesson identity.", i);
      DXTempoAttempt record{};
      record.attempt_id = identities.token(id);
      if (input.has("legacy")) {
        if (input["legacy"].get_type() != Variant::BOOL || !bool(input["legacy"]))
          return tempo_error("Legacy marker must be explicit true when present.", i);
        ++legacy_count;
        records.push_back(record); // Invalid correction deliberately removes prior evidence.
        continue;
      }
      DXTempoContext intent{};
      int natural = 0, uninterrupted = 0;
      if (!tempo_context(input, conditions, intent) ||
          !tempo_integer(input, "expected", record.expected, 0, 4096) ||
          !tempo_integer(input, "matched", record.matched, 0, 4096) ||
          !tempo_integer(input, "on_time", record.on_time, 0, 4096) ||
          !tempo_integer(input, "missed", record.missed, 0, 4096) ||
          !tempo_integer(input, "extra", record.extra, 0, 10000000) ||
          !tempo_bool(input, "naturally_completed", natural) ||
          !tempo_bool(input, "uninterrupted", uninterrupted))
        return tempo_error("Attempt requires complete captured intent, integer totals and explicit completion evidence.", i);
      if (record.on_time > record.matched || record.matched + record.missed > record.expected ||
          (natural && uninterrupted && record.matched + record.missed != record.expected))
        return tempo_error("Attempt score totals are inconsistent with completion evidence.", i);
      record.conditions_id = intent.conditions_id;
      record.policy_version = intent.policy_version;
      record.bpm = intent.bpm;
      record.bars = intent.bars;
      record.guidance = intent.guidance;
      record.live_feedback = intent.live_feedback;
      record.complete = natural && uninterrupted;
      record.valid = 1;
      records.push_back(record);
    }
    DXTempoDecision decision{};
    if (!dx_tempo_evaluate(records.data(), records.size(), &context, &decision))
      return tempo_error("Shared pulse tempo evaluator rejected the request.");
    Dictionary out;
    out["ok"] = true;
    out["policy_version"] = DX_TEMPO_POLICY_VERSION;
    out["input_count"] = int64_t(records.size());
    out["legacy_count"] = legacy_count;
    out["recent_completed"] = decision.recent_completed;
    out["recent_qualifying"] = decision.recent_qualifying;
    out["latest_qualifying"] = bool(decision.latest_qualifying);
    out["current_earned"] = bool(decision.current_earned);
    out["checkpoint_earned"] = bool(decision.checkpoint_earned);
    out["hidden_earned"] = bool(decision.hidden_earned);
    out["recall_earned"] = bool(decision.recall_earned);
    out["action"] = decision.action;
    out["reason"] = decision.reason;
    out["next_bpm"] = decision.next_bpm;
    out["next_bars"] = decision.next_bars;
    out["next_guidance"] = decision.next_guidance;
    out["next_live_feedback"] = bool(decision.next_live_feedback);
    return out;
}
double DrumxEngine::get_host_time() const { return drumx::host_time(); }
bool DrumxEngine::load_chart(double bpm, int bars, const Array &events) {
  if (events.is_empty() || events.size() > 4096) return false;
  std::vector<DXChartEvent> chart; chart.reserve(size_t(events.size()));
  for (int64_t i=0;i<events.size();++i) {
    if (events[i].get_type() != Variant::DICTIONARY) return false;
    Dictionary event = events[i];
    if (!event.has("pad") || !event.has("beat") || event["pad"].get_type() != Variant::INT) return false;
    const auto type = event["beat"].get_type();
    if (type != Variant::FLOAT && type != Variant::INT) return false;
    const int64_t pad = event["pad"];
    if (pad < 0 || pad > 2) return false;
    chart.push_back({int(pad), double(event["beat"])});
  }
  return backend.load_chart(bpm, bars, chart);
}
double DrumxEngine::start(int count) { return backend.start(count); }
void DrumxEngine::stop() { backend.stop(); }
Dictionary DrumxEngine::snapshot() {
  const auto state = backend.snapshot(); const auto &s = state.score; const auto &m = s.total;
  Dictionary d;
  d["running"]=state.running; d["completed"]=state.completed; d["naturally_completed"]=state.naturally_completed;
  d["progress_owned"]=progress_lock.owned();
  // Native paths and device strings are UTF-8; String(const char*) uses Latin-1.
  d["progress_archive_path"]=String::utf8(progress_lock.archive_path().c_str());
  d["progress_lock_error"]=String::utf8(progress_lock.error().c_str());
  d["practice_start"]=state.practice_start; d["elapsed_seconds"]=s.elapsed_seconds;
  d["duration_seconds"]=s.duration_seconds; d["bpm"]=s.bpm;
  d["expected"]=m.expected; d["matched"]=m.matched; d["missed"]=m.missed; d["extra"]=m.extra;
  d["on_time"]=m.on_time; d["streak"]=m.streak; d["best_streak"]=m.best_streak;
  d["hit_rate_percent"]=m.hit_rate_percent; d["timing_accuracy_percent"]=m.timing_accuracy_percent;
  d["mean_offset_ms"]=m.mean_offset_ms; d["mean_absolute_offset_ms"]=m.mean_absolute_offset_ms;
  Array biases;
  for (int pad=0;pad<DX_PAD_COUNT;++pad) {
    const auto &bias=s.bias[pad];
    Dictionary entry;
    entry["state"]=bias.state; entry["sample_count"]=bias.sample_count;
    entry["offset_ms"]=bias.offset_ms; entry["spread_ms"]=bias.spread_ms;
    entry["age_seconds"]=bias.age_seconds;
    biases.push_back(entry);
  }
  d["bias"]=biases;
  d["audio_ready"]=state.audio_ready; d["samples_ready"]=state.samples_ready;
  d["audio_interrupted"]=state.audio_interrupted;
  d["source_id"]=String::utf8(state.source_id.c_str()); d["pending_pad"]=state.pending_pad;
  d["source_lost"]=state.source_lost; d["lost_source_id"]=String::utf8(state.lost_source_id.c_str());
  d["error"]=String::utf8(state.error.c_str()); d["dropped_hits"]=state.dropped_hits; d["dropped_audio"]=state.dropped_audio;
  return d;
}
Array DrumxEngine::get_events() {
  Array result;
  for (const auto &event : backend.events()) {
    Dictionary d; d["id"]=event.id; d["pad"]=event.pad; d["time_seconds"]=event.time_seconds;
    d["resolved"]=event.resolved; d["hit"]=event.hit; result.push_back(d);
  }
  return result;
}
Array DrumxEngine::poll_hits() {
  Array result;
  for (const auto &hit : backend.poll_hits()) {
    Dictionary d; d["pad"]=hit.pad; d["note"]=hit.note; d["velocity"]=hit.velocity; d["host_time"]=hit.host_time;
    d["source_id"]=String::utf8(hit.source_id.c_str()); d["judgment"]=hit.result.judgment;
    d["event_id"]=hit.result.judgment == 0 ? -1 : hit.result.event_id;
    d["offset_ms"]=hit.result.offset_ms; d["mapping_changed"]=hit.mapping_changed; result.push_back(d);
  }
  return result;
}
Array DrumxEngine::sources() {
  Array result;
  for (const auto &source : backend.sources()) { Dictionary d; d["id"]=String::utf8(source.id.c_str()); d["name"]=String::utf8(source.name.c_str()); result.push_back(d); }
  return result;
}
bool DrumxEngine::connect_source(const String &id) { return backend.connect_source(id.utf8().get_data()); }
bool DrumxEngine::set_mapping(const Array &mapping) {
  if (mapping.size() != 3) return false;
  std::array<std::vector<int>,3> maps;
  for (int pad=0;pad<3;++pad) {
    if (mapping[pad].get_type() != Variant::ARRAY) return false;
    Array notes = mapping[pad]; if (notes.size() > 16) return false;
    for (int64_t i=0;i<notes.size();++i) {
      if (notes[i].get_type() != Variant::INT) return false;
      int64_t note = notes[i]; if (note < 0 || note > 127) return false; maps[pad].push_back(int(note));
    }
  }
  return backend.set_mapping(maps);
}
Array DrumxEngine::get_mapping() {
  Array result;
  for (const auto &map : backend.mapping()) { Array notes; for (int note : map) notes.push_back(note); result.push_back(notes); }
  return result;
}
bool DrumxEngine::learn_pad(int pad) { return backend.learn_pad(pad); }
void DrumxEngine::cancel_learning() { backend.cancel_learning(); }
bool DrumxEngine::load_sample_bank(const String &directory, bool open_device) {
  std::vector<std::vector<uint8_t>> files;
  for (const char *pad : {"hihat", "snare", "kick"}) for (int layer=1;layer<=4;++layer) for (int rr=1;rr<=2;++rr) {
    const String path = directory.path_join(String(pad)).path_join(String(("v" + std::to_string(layer) + "_rr" + std::to_string(rr) + ".flac").c_str()));
    const auto bytes = FileAccess::get_file_as_bytes(path);
    if (bytes.is_empty()) return false;
    files.emplace_back(bytes.ptr(), bytes.ptr() + bytes.size());
  }
  return backend.load_sample_data(files, open_device);
}
void DrumxEngine::set_monitoring(bool enabled) { backend.set_monitoring(enabled); }
void DrumxEngine::set_volume(double value) { if (std::isfinite(value)) backend.set_volume(float(value)); }
void DrumxEngine::keyboard_hit(int pad, int velocity) { backend.keyboard_hit(pad, velocity); }
}
