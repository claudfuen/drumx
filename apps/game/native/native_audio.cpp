#define MINIAUDIO_IMPLEMENTATION
#define MA_NO_ENCODING
#define MA_NO_MP3
#define MA_NO_ENGINE
#define MA_NO_NULL // A silent fallback must never satisfy the scored-audio gate.
#include "miniaudio.h"
#include "backend.h"
#include "sample_catalog.h"
#include <algorithm>
#include <cmath>
#include <fstream>
#include <iterator>

namespace drumx {
struct Audio::Impl {
  static constexpr uint32_t rate = 48000, capacity = 256, choke_frames = 240;
  struct Trigger { int pad, velocity; double at; };
  struct Voice {
    const std::vector<float>* pcm = nullptr;
    size_t cursor = 0;
    uint64_t age = 0;
    float gain = 1;
    int pad = -1;
    uint32_t release = 0;
  };
  std::array<std::vector<float>,sample_count> samples;
  std::array<Voice,32> voices{};
  std::array<Trigger,capacity> queue{};
  std::array<unsigned,sample_instruments.size() * sample_layers> robin{};
  std::atomic<uint32_t> read{0}, write{0};
  std::mutex producers;
  std::atomic<bool> monitoring{false}, loaded{false};
  AudioDeviceStatus status;
  std::atomic<float> volume{.7f};
  std::atomic<uint64_t> dropped{0}, click_generation{0};
  std::atomic<double> click_first{0}, click_bpm{72}, click_last{0};
  ma_device device{};
  bool initialized = false;
  mutable std::mutex error_mutex;
  std::string error;
  void set_error(std::string message) { std::lock_guard<std::mutex> lock(error_mutex); error = std::move(message); }
  std::string load_error() const { std::lock_guard<std::mutex> lock(error_mutex); return error; }
  uint64_t age = 0, seen_click_generation = 0;
  double next_click = -1, buffer_time = 0;
  int click_index = 0, click_sample = 10000;
  bool accent = false;
  static void notification(const ma_device_notification *notification) {
    auto &self = *static_cast<Impl*>(notification->pDevice->pUserData);
    switch (notification->type) {
      case ma_device_notification_type_started: self.status.notify(AudioDeviceEvent::started); break;
      case ma_device_notification_type_stopped:
      case ma_device_notification_type_interruption_began: self.status.notify(AudioDeviceEvent::stopped); break;
      case ma_device_notification_type_rerouted: self.status.notify(AudioDeviceEvent::rerouted); break;
      default: break;
    }
  }
  void trigger(const Trigger &hit) {
    const size_t layer = std::min(sample_layers - 1, size_t(hit.velocity / 32));
    const size_t group = size_t(hit.pad) * sample_layers + layer;
    const size_t index = group * sample_round_robins + robin[group]++ % sample_round_robins;
    if (samples[size_t(index)].empty()) return;
    if (hit.pad == 0 || hit.pad == sample_pedal_hat) {
      // A short fade chokes an open hat without a discontinuous sample cutoff.
      // Voice mutation stays entirely on the consumer audio thread.
      for (auto &active : voices)
        if (active.pcm && active.pad == sample_open_hat && active.release == 0) active.release = choke_frames;
    }
    auto voice = std::find_if(voices.begin(), voices.end(), [](const Voice &v) { return v.pcm == nullptr; });
    if (voice == voices.end()) voice = std::min_element(voices.begin(), voices.end(), [](const Voice&a,const Voice&b){return a.age < b.age;});
    *voice = {&samples[index], 0, ++age, .55f + .45f * (hit.velocity / 127.0f), hit.pad, 0};
  }
  static void callback(ma_device *device, void *output, const void *, ma_uint32 frames) {
    auto &self = *static_cast<Impl*>(device->pUserData);
    self.render(static_cast<float*>(output), frames);
  }
  void render(float *out, uint32_t frames) {
    auto &self = *this;
    std::fill(out, out + size_t(frames) * 2, 0.0f);
    const double now = host_time();
    if (self.buffer_time == 0 || std::abs(self.buffer_time - now) > .1) self.buffer_time = now;
    const uint64_t gen = self.click_generation.load(std::memory_order_acquire);
    if (gen != self.seen_click_generation) {
      self.seen_click_generation = gen; self.next_click = self.click_first.load(); self.click_index = 0;
      self.click_sample = 10000;
    }
    if (!self.monitoring.load(std::memory_order_relaxed)) {
      // Long cymbal tails must not keep ringing after monitoring is disabled.
      // Retire them on this thread; the click remains independent.
      for (auto &voice : self.voices)
        if (voice.pcm && voice.release == 0) voice.release = choke_frames;
    }
    uint32_t r = self.read.load(std::memory_order_relaxed);
    const uint32_t w = self.write.load(std::memory_order_acquire);
    while (r != w) {
      const auto hit = self.queue[r % capacity];
      if (now - hit.at <= .1 && self.monitoring.load(std::memory_order_relaxed)) self.trigger(hit);
      else ++self.dropped;
      ++r;
    }
    self.read.store(r, std::memory_order_release);
    const double last = self.click_last.load();
    const double step = 60.0 / self.click_bpm.load();
    const float volume = self.volume.load();
    for (ma_uint32 frame = 0; frame < frames; ++frame) {
      const double time = self.buffer_time + double(frame) / rate;
      if (self.next_click > 0 && self.next_click < last && time >= self.next_click) {
        // A stalled device drops old beats; it never releases a catch-up burst.
        if (time - self.next_click < .03) { self.click_sample = 0; self.accent = self.click_index % 4 == 0; }
        self.next_click += step; ++self.click_index;
      }
      float sample = 0;
      for (auto &voice : self.voices) {
        if (!voice.pcm) continue;
        const float release_gain = voice.release > 0 ? float(voice.release) / choke_frames : 1.0f;
        sample += (*voice.pcm)[voice.cursor++] * voice.gain * volume * release_gain;
        if (voice.release > 0 && --voice.release == 0) voice.pcm = nullptr;
        if (!voice.pcm) continue;
        if (voice.cursor >= voice.pcm->size()) voice.pcm = nullptr;
      }
      if (self.click_sample < 1200) {
        const double t = double(self.click_sample++) / rate;
        sample += float(std::sin(t * (self.accent ? 1800 : 1200) * 6.283185307179586) * std::exp(-t * 210)) * .22f;
      }
      // Gentle bounded saturation keeps simultaneous kick/snare/cymbal peaks finite.
      sample = std::clamp(sample, -1.0f, 1.0f);
      out[frame * 2] = sample; out[frame * 2 + 1] = sample;
    }
    self.buffer_time += double(frames) / rate;
  }
};
Audio::Audio() : p(std::make_unique<Impl>()) {}
Audio::~Audio() { if (p->initialized) ma_device_uninit(&p->device); }
bool Audio::load(const std::string &directory, bool open_device) {
  std::vector<std::vector<uint8_t>> files;
  files.reserve(sample_count);
  for (size_t i = 0; i < sample_count; ++i) {
    std::ifstream file(directory + "/" + sample_relative_path(i), std::ios::binary);
    if (!file) { p->set_error("A bundled drum sample is missing."); return false; }
    files.emplace_back(std::istreambuf_iterator<char>(file), std::istreambuf_iterator<char>());
  }
  return load_memory(files, open_device);
}
bool Audio::load_memory(const std::vector<std::vector<uint8_t>> &files, bool open_device) {
  if (files.size() != sample_count) { p->set_error("The sample bank requires all " + std::to_string(sample_count) + " recordings."); return false; }
  std::array<std::vector<float>,sample_count> decoded;
  auto config = ma_decoder_config_init(ma_format_f32, 1, Impl::rate);
  for (size_t i=0;i<files.size();++i) {
    void *pcm = nullptr; ma_uint64 frames = 0;
    if (files[i].empty() || ma_decode_memory(files[i].data(), files[i].size(), &config, &frames, &pcm) != MA_SUCCESS || !pcm || frames == 0 || frames > Impl::rate * 30) {
      if (pcm) ma_free(pcm, nullptr);
      p->set_error("A bundled FLAC sample could not be decoded."); return false;
    }
    decoded[i].assign(static_cast<float*>(pcm), static_cast<float*>(pcm) + frames); ma_free(pcm, nullptr);
  }
  // Closing for an explicit reload is intentional. A newly opened device must
  // establish its own lifecycle state after the previous callbacks have ended.
  p->status.reset();
  if (p->initialized) { ma_device_uninit(&p->device); p->initialized = false; }
  p->status.reset();
  { std::lock_guard<std::mutex> lock(p->producers);
    p->loaded.store(false); p->samples = std::move(decoded); p->voices = {}; p->robin = {};
    p->read.store(0); p->write.store(0); p->loaded.store(true); }
  p->set_error("");
  return !open_device || open();
}
bool Audio::open() {
  if (p->status.ready()) return true;
  if (p->initialized) { p->status.reset(); ma_device_uninit(&p->device); p->initialized = false; }
  p->status.reset();
  auto config = ma_device_config_init(ma_device_type_playback);
  config.playback.format = ma_format_f32; config.playback.channels = 2; config.sampleRate = Impl::rate;
  config.periodSizeInFrames = 128; config.periods = 2;
  config.dataCallback = Impl::callback; config.notificationCallback = Impl::notification; config.pUserData = p.get();
  if (ma_device_init(nullptr, &config, &p->device) != MA_SUCCESS) { p->set_error("No native audio output could be opened."); return false; }
  p->initialized = true;
  p->status.begin_open();
  if (ma_device_start(&p->device) != MA_SUCCESS) { p->set_error("Native audio output could not start."); ma_device_uninit(&p->device); p->initialized = false; return false; }
  p->status.confirm_started(ma_device_is_started(&p->device) == MA_TRUE);
  if (!p->status.ready()) { p->set_error("Native audio output did not stay active. Choose Retry audio in Settings."); return false; }
  return true;
}
AudioDeviceStatus &Audio::device_status() { return p->status; }
void Audio::render(float *output, uint32_t frames) { p->render(output, frames); }
bool Audio::ready() const { return p->status.ready(); }
bool Audio::interrupted() const { return p->status.interrupted(); }
bool Audio::samples_ready() const { return p->loaded.load(); }
void Audio::monitoring(bool value) { p->monitoring.store(value); }
void Audio::volume(float value) { p->volume.store(value); }
void Audio::hit(int pad, int velocity) {
  if (pad < 0 || size_t(pad) >= sample_instruments.size() || velocity < 1 || velocity > 127 || !p->monitoring.load() || !p->loaded.load()) return;
  std::lock_guard<std::mutex> lock(p->producers);
  const auto w = p->write.load(std::memory_order_relaxed), r = p->read.load(std::memory_order_acquire);
  if (w - r >= Impl::capacity) { ++p->dropped; return; }
  p->queue[w % Impl::capacity] = {pad, velocity, host_time()}; p->write.store(w + 1, std::memory_order_release);
}
void Audio::click(double first, double bpm, double last) {
  p->click_bpm.store(bpm); p->click_last.store(last); p->click_first.store(first);
  p->click_generation.fetch_add(1, std::memory_order_release);
}
void Audio::stop_click() { p->click_first.store(-1); p->click_last.store(-1); p->click_generation.fetch_add(1, std::memory_order_release); }
uint64_t Audio::dropped() const { return p->dropped.load(); }
std::string Audio::error() const {
  return p->status.interrupted() ? "Audio output changed or stopped. Choose Retry audio in Settings, then start a fresh take." : p->load_error();
}
}
