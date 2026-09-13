#include "backend.h"
#include "sample_catalog.h"
#include <algorithm>
#include <chrono>
#include <cmath>
#if defined(__APPLE__)
#include <mach/mach_time.h>
#elif defined(_WIN32)
#include <windows.h>
#endif

namespace drumx {
namespace {
constexpr const char *source_lost_message = "Your MIDI input disconnected. Reconnect it in Settings, or explicitly choose Keyboard to continue.";
}
double host_time() {
#if defined(__APPLE__)
  static const double scale = [] { mach_timebase_info_data_t t{}; mach_timebase_info(&t); return double(t.numer) / double(t.denom) / 1e9; }();
  return double(mach_absolute_time()) * scale;
#elif defined(_WIN32)
  static const double frequency = [] { LARGE_INTEGER f{}; QueryPerformanceFrequency(&f); return double(f.QuadPart); }();
  LARGE_INTEGER n{}; QueryPerformanceCounter(&n); return double(n.QuadPart) / frequency;
#else
  return std::chrono::duration<double>(std::chrono::steady_clock::now().time_since_epoch()).count();
#endif
}
Backend::Backend(bool enable_devices) : core(dx_core_create()), audio(std::make_unique<Audio>()) {
  dx_core_reset(core, bpm, bars);
  for (int bar = 0; bar < bars; ++bar) {
    for (int i = 0; i < 8; ++i) chart.push_back({0, bar * 4.0 + i * .5});
    chart.push_back({1, bar * 4.0 + 1}); chart.push_back({1, bar * 4.0 + 3});
    chart.push_back({2, bar * 4.0}); chart.push_back({2, bar * 4.0 + 2});
  }
  if (enable_devices) midi = std::make_unique<MIDI>(*this);
  worker = std::thread([this] {
    while (!quitting.load()) { advance(host_time()); std::this_thread::sleep_for(std::chrono::milliseconds(2)); }
  });
}
Backend::~Backend() {
  quitting.store(true);
  if (worker.joinable()) worker.join();
  midi.reset(); audio.reset(); dx_core_destroy(core);
}
bool Backend::load_chart(double tempo, int count, const std::vector<DXChartEvent> &events) {
  std::lock_guard<std::mutex> lock(mutex);
  if (state.running || count < 1 || count > 64 || events.empty() || events.size() > 4096) return false;
  if (!dx_core_load_chart(core, tempo, count * 4.0, events.data(), int(events.size()))) return false;
  bpm = tempo; bars = count; chart = events;
  state.completed = false; state.naturally_completed = false; state.practice_start = 0;
  state.stop_time = 0; hits.clear(); return true;
}
double Backend::start(int count_in_beats) {
  std::lock_guard<std::mutex> lock(mutex);
  if (state.running || count_in_beats < 0 || count_in_beats > 16 || state.pending_pad >= 0) return -1;
  if (state.source_lost) { state.error = source_lost_message; return -1; }
  if (audio->interrupted()) { state.error = audio->error(); return -1; }
  if (midi && !audio->ready()) { state.error = "Native audio output is not ready. Check the system output and reload drum sounds."; return -1; }
  if (!dx_core_load_chart(core, bpm, bars * 4.0, chart.data(), int(chart.size()))) return -1;
  const double first_click = host_time() + .15;
  state.practice_start = first_click + count_in_beats * 60.0 / bpm;
  state.stop_time = 0; state.running = true; state.completed = false; state.naturally_completed = false;
  hits.clear();
  audio->click(first_click, bpm, state.practice_start + dx_core_duration(core));
  return state.practice_start;
}
void Backend::stop_locked(double now) {
  if (!state.running) return;
  const double elapsed = now - state.practice_start;
  state.naturally_completed = elapsed >= dx_core_duration(core);
  dx_core_finish(core, elapsed);
  state.running = false; state.completed = true; state.stop_time = now; audio->stop_click();
}
void Backend::stop() { std::lock_guard<std::mutex> lock(mutex); stop_locked(host_time()); }
void Backend::advance(double now) {
  std::lock_guard<std::mutex> lock(mutex);
  if (!state.running) return;
  if (audio->interrupted()) {
    stop_locked(now); state.naturally_completed = false; state.error = audio->error(); return;
  }
  dx_core_advance(core, now - state.practice_start);
  if (now - state.practice_start > dx_core_duration(core) + .15) stop_locked(now);
}
State Backend::snapshot() {
  std::lock_guard<std::mutex> lock(mutex);
  dx_core_snapshot(core, &state.score);
  state.audio_ready = audio->ready(); state.samples_ready = audio->samples_ready();
  state.audio_interrupted = audio->interrupted();
  if (state.audio_interrupted && !state.source_lost) state.error = audio->error();
  state.dropped_audio = audio->dropped();
  return state;
}
std::vector<DXEvent> Backend::events() {
  std::lock_guard<std::mutex> lock(mutex);
  std::vector<DXEvent> result(size_t(dx_core_event_count(core)));
  for (size_t i = 0; i < result.size(); ++i) dx_core_event(core, int(i), &result[i]);
  return result;
}
std::vector<Hit> Backend::poll_hits() {
  std::lock_guard<std::mutex> lock(mutex);
  std::vector<Hit> result(hits.begin(), hits.end()); hits.clear(); return result;
}
std::vector<Source> Backend::sources() {
  auto result = midi ? midi->sources() : std::vector<Source>{};
  bool disconnected = false;
  {
    std::lock_guard<std::mutex> lock(mutex);
    if (!state.source_id.empty() && std::none_of(result.begin(), result.end(), [&](const Source &s) { return s.id == state.source_id; })) {
      generation.fetch_add(1);
      if (state.running) {
        stop_locked(host_time());
        // Detection may arrive at the phrase boundary. An interrupted transport
        // must never acquire natural-completion evidence from that delay.
        state.naturally_completed = false;
      }
      state.source_lost = true; state.lost_source_id = state.source_id;
      state.source_id.clear(); state.pending_pad = -1; hits.clear();
      state.error = source_lost_message; disconnected = true;
    }
  }
  if (disconnected && midi) midi->disconnect();
  return result;
}
bool Backend::connect_source(const std::string &id) {
  const auto epoch = generation.fetch_add(1) + 1;
  {
    std::lock_guard<std::mutex> lock(mutex);
    stop_locked(host_time()); state.pending_pad = -1; state.source_id.clear(); hits.clear();
    if (!state.source_lost) state.error.clear();
  }
  if (midi) midi->disconnect();
  if (id.empty()) {
    std::lock_guard<std::mutex> lock(mutex);
    state.source_lost = false; state.lost_source_id.clear(); state.error.clear();
    return true;
  }
  // Publish identity before starting delivery; generation rejects previous connections.
  { std::lock_guard<std::mutex> lock(mutex); state.source_id = id; }
  const bool ok = midi && midi->connect(id, epoch);
  if (!ok) {
    std::lock_guard<std::mutex> lock(mutex);
    state.source_id.clear(); state.source_lost = true;
    if (state.lost_source_id.empty()) state.lost_source_id = id;
    state.error = "MIDI connection failed. Reconnect the module in Settings, or explicitly choose Keyboard to continue.";
  }
  if (ok) { std::lock_guard<std::mutex> lock(mutex); state.source_lost = false; state.lost_source_id.clear(); state.error.clear(); }
  return ok;
}
bool Backend::set_mapping(const std::array<std::vector<int>, 3> &mapping) {
  std::array<bool,128> seen{};
  for (const auto &pad : mapping) {
    if (pad.size() > 16) return false;
    for (int note : pad) { if (note < 0 || note > 127 || seen[size_t(note)]) return false; seen[size_t(note)] = true; }
  }
  std::lock_guard<std::mutex> lock(mutex);
  if (state.running) return false;
  maps = mapping; state.pending_pad = -1; if (!state.source_lost) state.error.clear(); return true;
}
std::array<std::vector<int>,3> Backend::mapping() { std::lock_guard<std::mutex> lock(mutex); return maps; }
bool Backend::learn_pad(int pad) {
  std::lock_guard<std::mutex> lock(mutex);
  if (state.running || state.source_id.empty() || pad < 0 || pad >= 3) return false;
  state.pending_pad = pad; learn_started = host_time(); state.error.clear(); return true;
}
void Backend::cancel_learning() { std::lock_guard<std::mutex> lock(mutex); state.pending_pad = -1; }
bool Backend::load_samples(const std::string &path, bool open_device) {
  { std::lock_guard<std::mutex> lock(mutex); if (state.running) return false; }
  const bool ok = audio->load(path, open_device);
  if (!ok) { std::lock_guard<std::mutex> lock(mutex); state.error = audio->error(); }
  else { std::lock_guard<std::mutex> lock(mutex); if (!state.source_lost) state.error.clear(); }
  return ok;
}
bool Backend::load_sample_data(const std::vector<std::vector<uint8_t>> &files, bool open_device) {
  { std::lock_guard<std::mutex> lock(mutex); if (state.running) return false; }
  const bool ok = audio->load_memory(files, open_device);
  if (!ok) { std::lock_guard<std::mutex> lock(mutex); state.error = audio->error(); }
  else { std::lock_guard<std::mutex> lock(mutex); if (!state.source_lost) state.error.clear(); }
  return ok;
}
void Backend::set_monitoring(bool enabled) { audio->monitoring(enabled); }
void Backend::set_volume(float value) { if (std::isfinite(value)) audio->volume(std::clamp(value, 0.0f, 1.0f)); }
void Backend::keyboard_hit(int pad, int velocity) {
  if (pad < 0 || pad >= 3 || velocity < 1 || velocity > 127) return;
  receive(-1, pad, velocity, host_time(), false);
}
void Backend::midi_hit(int note, int velocity, double captured, uint64_t epoch) {
  if (epoch != generation.load() || note < 0 || note > 127 || velocity < 1 || velocity > 127 || !std::isfinite(captured) || captured < 0) return;
  // Generation is checked again while holding the state lock in receive's source gate.
  std::lock_guard<std::mutex> lock(mutex);
  if (epoch != generation.load() || state.source_id.empty()) return;
  int pad = -1;
  for (int i = 0; i < 3; ++i) if (std::find(maps[i].begin(), maps[i].end(), note) != maps[i].end()) pad = i;
  Hit hit; hit.note = note; hit.velocity = velocity; hit.host_time = captured; hit.source_id = state.source_id;
  if (state.pending_pad >= 0 && captured >= learn_started) {
    const int target = state.pending_pad;
    const bool already = std::find(maps[target].begin(), maps[target].end(), note) != maps[target].end();
    if (already || maps[target].size() < 16) {
      for (int i = 0; i < 3; ++i) if (i != target) maps[i].erase(std::remove(maps[i].begin(), maps[i].end(), note), maps[i].end());
      if (!already) maps[target].push_back(note);
      pad = target; state.pending_pad = -1; hit.mapping_changed = true;
    } else state.error = "This pad already has 16 MIDI aliases.";
  } else if (state.pending_pad < 0) {
    audio->hit(sample_for_midi(note, pad), velocity);
    const double song = captured - state.practice_start;
    if (pad >= 0 && (state.running || state.completed) && state.practice_start > 0 && song >= -.125 &&
        song <= dx_core_duration(core) + .125 && (state.running || captured <= state.stop_time))
      hit.result = dx_core_input(core, pad, song, velocity / 127.0);
  }
  hit.pad = pad;
  if (hits.size() == 256) { hits.pop_front(); ++state.dropped_hits; }
  hits.push_back(std::move(hit));
}
void Backend::receive(int note, int pad, int velocity, double captured, bool) {
  std::lock_guard<std::mutex> lock(mutex);
  Hit hit; hit.note = note; hit.pad = pad; hit.velocity = velocity; hit.host_time = captured;
  audio->hit(pad, velocity);
  const double song = captured - state.practice_start;
  // Keyboard preview remains available, but a MIDI take cannot gain keyboard scores.
  if (!state.source_lost && state.source_id.empty() && (state.running || state.completed) && state.practice_start > 0 && song >= -.125 &&
      song <= dx_core_duration(core) + .125 && (state.running || captured <= state.stop_time))
    hit.result = dx_core_input(core, pad, song, velocity / 127.0);
  if (hits.size() == 256) { hits.pop_front(); ++state.dropped_hits; }
  hits.push_back(std::move(hit));
}
}
