#define MINIAUDIO_IMPLEMENTATION
#define MA_NO_ENCODING
#define MA_NO_MP3
#define MA_NO_ENGINE
#include "miniaudio.h"
#include "backend.h"
#include <algorithm>
#include <cmath>
#include <fstream>
#include <iterator>

namespace drumx {
struct Audio::Impl {
  static constexpr uint32_t rate = 48000, capacity = 256;
  struct Trigger { int pad, velocity; double at; };
  struct Voice { const std::vector<float>* pcm = nullptr; size_t cursor = 0; uint64_t age = 0; float gain = 1; };
  std::array<std::vector<float>,24> samples;
  std::array<Voice,32> voices{};
  std::array<Trigger,capacity> queue{};
  std::array<unsigned,12> robin{};
  std::atomic<uint32_t> read{0}, write{0};
  std::mutex producers;
  std::atomic<bool> monitoring{false}, loaded{false}, opened{false};
  std::atomic<float> volume{.7f};
  std::atomic<uint64_t> dropped{0}, click_generation{0};
  std::atomic<double> click_first{0}, click_bpm{72}, click_last{0};
  ma_device device{};
  bool initialized = false;
  std::string error;
  uint64_t age = 0, seen_click_generation = 0;
  double next_click = -1, buffer_time = 0;
  int click_index = 0, click_sample = 10000;
  bool accent = false;
  void trigger(const Trigger &hit) {
    const int layer = std::min(3, hit.velocity / 32);
    const int group = hit.pad * 4 + layer;
    const int index = group * 2 + int(robin[size_t(group)]++ % 2);
    if (samples[size_t(index)].empty()) return;
    auto voice = std::find_if(voices.begin(), voices.end(), [](const Voice &v) { return v.pcm == nullptr; });
    if (voice == voices.end()) voice = std::min_element(voices.begin(), voices.end(), [](const Voice&a,const Voice&b){return a.age < b.age;});
    *voice = {&samples[size_t(index)], 0, ++age, .55f + .45f * (hit.velocity / 127.0f)};
  }
  static void callback(ma_device *device, void *output, const void *, ma_uint32 frames) {
    auto &self = *static_cast<Impl*>(device->pUserData);
    auto *out = static_cast<float*>(output);
    std::fill(out, out + size_t(frames) * 2, 0.0f);
    const double now = host_time();
    if (self.buffer_time == 0 || std::abs(self.buffer_time - now) > .1) self.buffer_time = now;
    const uint64_t gen = self.click_generation.load(std::memory_order_acquire);
    if (gen != self.seen_click_generation) {
      self.seen_click_generation = gen; self.next_click = self.click_first.load(); self.click_index = 0;
      self.click_sample = 10000;
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
        sample += (*voice.pcm)[voice.cursor++] * voice.gain * volume;
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
  for (const char *pad : {"hihat", "snare", "kick"}) for (int layer=1;layer<=4;++layer) for(int rr=1;rr<=2;++rr) {
    std::ifstream file(directory + "/" + pad + "/v" + std::to_string(layer) + "_rr" + std::to_string(rr) + ".flac", std::ios::binary);
    if (!file) { p->error = "A bundled drum sample is missing."; return false; }
    files.emplace_back(std::istreambuf_iterator<char>(file), std::istreambuf_iterator<char>());
  }
  return load_memory(files, open_device);
}
bool Audio::load_memory(const std::vector<std::vector<uint8_t>> &files, bool open_device) {
  if (files.size() != 24) { p->error = "The sample bank requires all 24 recordings."; return false; }
  std::array<std::vector<float>,24> decoded;
  auto config = ma_decoder_config_init(ma_format_f32, 1, Impl::rate);
  for (size_t i=0;i<files.size();++i) {
    void *pcm = nullptr; ma_uint64 frames = 0;
    if (files[i].empty() || ma_decode_memory(files[i].data(), files[i].size(), &config, &frames, &pcm) != MA_SUCCESS || !pcm || frames == 0 || frames > Impl::rate * 30) {
      if (pcm) ma_free(pcm, nullptr);
      p->error = "A bundled FLAC sample could not be decoded."; return false;
    }
    decoded[i].assign(static_cast<float*>(pcm), static_cast<float*>(pcm) + frames); ma_free(pcm, nullptr);
  }
  if (p->initialized) { ma_device_uninit(&p->device); p->initialized = false; p->opened.store(false); }
  { std::lock_guard<std::mutex> lock(p->producers);
    p->loaded.store(false); p->samples = std::move(decoded); p->voices = {}; p->robin = {};
    p->read.store(0); p->write.store(0); p->loaded.store(true); }
  p->error.clear();
  return !open_device || open();
}
bool Audio::open() {
  if (p->opened.load()) return true;
  auto config = ma_device_config_init(ma_device_type_playback);
  config.playback.format = ma_format_f32; config.playback.channels = 2; config.sampleRate = Impl::rate;
  config.periodSizeInFrames = 128; config.periods = 2;
  config.dataCallback = Impl::callback; config.pUserData = p.get();
  if (ma_device_init(nullptr, &config, &p->device) != MA_SUCCESS) { p->error = "No native audio output could be opened."; return false; }
  p->initialized = true;
  if (ma_device_start(&p->device) != MA_SUCCESS) { p->error = "Native audio output could not start."; ma_device_uninit(&p->device); p->initialized = false; return false; }
  p->opened.store(true); return true;
}
bool Audio::ready() const { return p->opened.load(); }
bool Audio::samples_ready() const { return p->loaded.load(); }
void Audio::monitoring(bool value) { p->monitoring.store(value); }
void Audio::volume(float value) { p->volume.store(value); }
void Audio::hit(int pad, int velocity) {
  if (pad < 0 || pad >= 3 || velocity < 1 || velocity > 127 || !p->monitoring.load() || !p->loaded.load()) return;
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
std::string Audio::error() const { return p->error; }
}
