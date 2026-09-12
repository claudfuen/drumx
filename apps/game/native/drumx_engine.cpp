#include "drumx_engine.h"
#include <godot_cpp/classes/file_access.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <cmath>

namespace godot {
void DrumxEngine::_bind_methods() {
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
  d["practice_start"]=state.practice_start; d["elapsed_seconds"]=s.elapsed_seconds;
  d["duration_seconds"]=s.duration_seconds; d["bpm"]=s.bpm;
  d["expected"]=m.expected; d["matched"]=m.matched; d["missed"]=m.missed; d["extra"]=m.extra;
  d["on_time"]=m.on_time; d["streak"]=m.streak; d["best_streak"]=m.best_streak;
  d["hit_rate_percent"]=m.hit_rate_percent; d["timing_accuracy_percent"]=m.timing_accuracy_percent;
  d["mean_offset_ms"]=m.mean_offset_ms; d["mean_absolute_offset_ms"]=m.mean_absolute_offset_ms;
  d["audio_ready"]=state.audio_ready; d["samples_ready"]=state.samples_ready;
  d["source_id"]=String(state.source_id.c_str()); d["pending_pad"]=state.pending_pad;
  d["error"]=String(state.error.c_str()); d["dropped_hits"]=state.dropped_hits; d["dropped_audio"]=state.dropped_audio;
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
    d["source_id"]=String(hit.source_id.c_str()); d["judgment"]=hit.result.judgment;
    d["event_id"]=hit.result.judgment == 0 ? -1 : hit.result.event_id;
    d["offset_ms"]=hit.result.offset_ms; d["mapping_changed"]=hit.mapping_changed; result.push_back(d);
  }
  return result;
}
Array DrumxEngine::sources() {
  Array result;
  for (const auto &source : backend.sources()) { Dictionary d; d["id"]=String(source.id.c_str()); d["name"]=String(source.name.c_str()); result.push_back(d); }
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
