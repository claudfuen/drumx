#pragma once
#include "drumx_core.h"
#include <array>
#include <atomic>
#include <cstdint>
#include <deque>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

namespace drumx {
double host_time();
struct Source { std::string id, name; };
struct Hit {
  int pad = -1, note = -1, velocity = 0;
  double host_time = 0;
  std::string source_id;
  DXHitResult result{};
  bool mapping_changed = false;
};
struct State {
  DXSnapshot score{};
  bool running = false, completed = false, naturally_completed = false;
  bool audio_ready = false, samples_ready = false, audio_interrupted = false;
  bool source_lost = false;
  double practice_start = 0, stop_time = 0;
  int pending_pad = -1;
  uint64_t dropped_hits = 0, dropped_audio = 0;
  std::string source_id, lost_source_id, error;
};
// Device lifecycle state only. It does not estimate callback or output latency.
enum class AudioDeviceEvent { started, stopped, rerouted };
class AudioDeviceStatus {
public:
  void reset() { armed.store(false); active.store(false); interruption.store(false); }
  void begin_open() { reset(); armed.store(true); }
  void confirm_started(bool started) { active.store(started); if (!started) interruption.store(true); }
  void notify(AudioDeviceEvent event) {
    if (event == AudioDeviceEvent::started) active.store(true);
    if (event == AudioDeviceEvent::stopped) active.store(false);
    if (event != AudioDeviceEvent::started && armed.load()) interruption.store(true);
  }
  bool ready() const { return armed.load() && active.load() && !interruption.load(); }
  bool interrupted() const { return interruption.load(); }
private:
  std::atomic<bool> armed{false}, active{false}, interruption{false};
};
class Audio {
public:
  Audio(); ~Audio();
  bool load(const std::string &directory, bool open_device = true);
  bool load_memory(const std::vector<std::vector<uint8_t>> &files, bool open_device = true);
  bool open();
  bool ready() const; bool samples_ready() const; bool interrupted() const;
  void monitoring(bool enabled); void volume(float value);
  void hit(int pad, int velocity);
  void click(double first, double bpm, double last);
  void stop_click();
  uint64_t dropped() const;
  std::string error() const;
private:
  friend struct BackendTestAccess;
  AudioDeviceStatus &device_status();
  // The private friend check renders the same mixer without opening hardware.
  void render(float *output, uint32_t frames);
  struct Impl; std::unique_ptr<Impl> p;
};
class Backend;
class MIDI {
public:
  explicit MIDI(Backend &owner); ~MIDI();
  std::vector<Source> sources();
  bool connect(const std::string &id, uint64_t generation);
  void disconnect();
private:
  struct Impl; std::unique_ptr<Impl> p;
};
class Backend {
public:
  explicit Backend(bool enable_devices = true); ~Backend();
  bool load_chart(double bpm, int bars, const std::vector<DXChartEvent> &events);
  double start(int count_in_beats = 4);
  void stop();
  State snapshot();
  std::vector<DXEvent> events();
  std::vector<Hit> poll_hits();
  std::vector<Source> sources();
  bool connect_source(const std::string &id);
  bool set_mapping(const std::array<std::vector<int>, 3> &mapping);
  std::array<std::vector<int>, 3> mapping();
  bool learn_pad(int pad); void cancel_learning();
  bool load_samples(const std::string &path, bool open_device = true);
  bool load_sample_data(const std::vector<std::vector<uint8_t>> &files, bool open_device = true);
  void set_monitoring(bool enabled); void set_volume(float value);
  void keyboard_hit(int pad, int velocity);
  // Called with the driver's original capture timestamp, never Godot's frame time.
  void midi_hit(int note, int velocity, double captured, uint64_t generation);
  uint64_t source_generation() const { return generation.load(); }
private:
  friend struct BackendTestAccess;
  void receive(int note, int pad, int velocity, double captured, bool midi);
  void advance(double now);
  void stop_locked(double now);
  std::mutex mutex;
  DXCore *core = nullptr;
  std::vector<DXChartEvent> chart;
  double bpm = 72; int bars = 4;
  State state;
  std::array<std::vector<int>, 3> maps{{{42,44,46},{38,40},{35,36}}};
  std::deque<Hit> hits;
  double learn_started = 0;
  std::atomic<uint64_t> generation{0};
  std::atomic<bool> quitting{false};
  std::unique_ptr<Audio> audio;
  std::unique_ptr<MIDI> midi;
  std::thread worker;
};
}
