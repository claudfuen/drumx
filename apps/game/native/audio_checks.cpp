#include "backend.h"
#include <algorithm>
#include <cmath>
#include <iostream>

namespace drumx {
struct BackendTestAccess {
  static void pause_worker(Backend &backend) {
    backend.quitting.store(true);
    if (backend.worker.joinable()) backend.worker.join();
  }
  static uint64_t source(Backend &backend) {
    backend.state.source_id = "test-only:full-kit";
    return backend.generation.fetch_add(1) + 1;
  }
  static std::vector<float> render(Audio &audio, uint32_t frames = 64) {
    std::vector<float> result(size_t(frames) * 2);
    audio.render(result.data(), frames);
    return result;
  }
  static std::vector<float> render(Backend &backend, uint32_t frames = 64) { return render(*backend.audio, frames); }
};
}

namespace {
// Small PCM WAV fixtures keep the mixer checks independent of FLAC recordings,
// hardware, acoustic sample attack/silence and an operating-system scheduler.
std::vector<uint8_t> pcm_file(int16_t amplitude, uint32_t frames = 64) {
  std::vector<uint8_t> bytes;
  auto word = [&](uint32_t value, int count) { for (int i = 0; i < count; ++i) bytes.push_back(uint8_t(value >> (i * 8))); };
  auto tag = [&](const char *value) { bytes.insert(bytes.end(), value, value + 4); };
  tag("RIFF"); word(36 + frames * 2, 4); tag("WAVE"); tag("fmt "); word(16, 4);
  word(1, 2); word(1, 2); word(48000, 4); word(96000, 4); word(2, 2); word(16, 2);
  tag("data"); word(frames * 2, 4);
  for (uint32_t i = 0; i < frames; ++i) word(uint16_t(amplitude), 2);
  return bytes;
}
std::vector<std::vector<uint8_t>> bank(bool distinguish_recordings = false) {
  std::vector<std::vector<uint8_t>> files;
  for (int i = 0; i < 80; ++i) files.push_back(pcm_file(int16_t(distinguish_recordings ? (i + 1) * 100 : (i / 8 + 1) * 1024)));
  return files;
}
bool silent(const std::vector<float> &output) {
  return std::all_of(output.begin(), output.end(), [](float value) { return value == 0; });
}
bool near(float actual, float expected) { return std::abs(actual - expected) < .00001f; }
}

int main() {
  int checks = 0, failures = 0;
  auto check = [&](bool ok, const char *name) { ++checks; if (!ok) { ++failures; std::cerr << "FAIL " << name << '\n'; } };
  using Access = drumx::BackendTestAccess;
  drumx::Audio audio;
  const auto recordings = bank(true);
  check(audio.load_memory(recordings, false), "80-recording bank decodes without hardware");
  check(audio.samples_ready() && !audio.ready(), "sample decode does not imply output readiness");
  audio.volume(1); audio.monitoring(true);
  // Exercise every instrument, both round robins, and every layer edge through
  // the actual queue and callback mixer, rather than inspecting array sizes.
  for (int pad = 0; pad < 10; ++pad) {
    unsigned robin[4]{};
    for (int velocity : {1, 31, 32, 63, 64, 95, 96, 127}) for (int repeat = 0; repeat < 2; ++repeat) {
      const int layer = std::min(3, velocity / 32);
      const int index = (pad * 4 + layer) * 2 + int(robin[layer]++ % 2);
      audio.hit(pad, velocity);
      const auto output = Access::render(audio);
      const float expected = float((index + 1) * 100) / 32768 * (.55f + .45f * (velocity / 127.0f));
      check(near(output.front(), expected) && output.front() == output[1], "all instruments select the correct velocity layer and round robin in stereo");
    }
  }
  for (int pad : {-1, 10, 127}) audio.hit(pad, 100);
  for (int velocity : {0, 128, -1}) audio.hit(0, velocity);
  check(silent(Access::render(audio)), "invalid audio IDs and velocities remain silent");
  audio.monitoring(false); audio.hit(6, 127);
  check(silent(Access::render(audio)), "monitoring disabled rejects cymbal playback");
  audio.monitoring(true); audio.hit(7, 127); audio.monitoring(false);
  check(silent(Access::render(audio)), "disabling monitoring before callback suppresses queued samples");
  audio.monitoring(true);
  check(!audio.load_memory(std::vector<std::vector<uint8_t>>(recordings.begin(), recordings.begin() + 24), false), "obsolete 24-recording bank is rejected");
  auto broken = recordings; broken.back().clear();
  check(!audio.load_memory(broken, false) && audio.samples_ready(), "missing final articulation is rejected without losing loaded samples");
  broken.back() = {1, 2, 3};
  check(!audio.load_memory(broken, false), "corrupt final articulation is rejected");
  audio.hit(9, 127);
  check(!silent(Access::render(audio)), "prior full bank remains playable after rejected reload");

  // Open hats outlive a short strike. Closed and pedal hats each release the
  // open tail over 240 samples, while unrelated drums leave it ringing.
  for (int closer : {0, 9}) {
    auto sustained = bank();
    for (int i = 64; i < 72; ++i) sustained[size_t(i)] = pcm_file(12000, 2048);
    check(audio.load_memory(sustained, false), "sustained open-hat fixture loads");
    audio.hit(8, 127); Access::render(audio);
    audio.hit(1, 127); Access::render(audio);
    check(near(Access::render(audio)[0], 12000.0f / 32768), "snare does not choke an open hi-hat");
    audio.hit(closer, 127);
    const auto fade = Access::render(audio, 240);
    check(fade[128] > fade[400] && fade[400] > 0, "closing hi-hat fades the open tail within its callback");
    check(silent(Access::render(audio)), "closed and pedal articulations fully choke an open hi-hat");
  }
  auto sustained_cymbal = bank();
  for (int i = 48; i < 56; ++i) sustained_cymbal[size_t(i)] = pcm_file(12000, 2048);
  check(audio.load_memory(sustained_cymbal, false), "sustained crash fixture loads");
  audio.hit(6, 127); Access::render(audio);
  audio.monitoring(false); Access::render(audio, 240);
  check(silent(Access::render(audio)), "turning monitoring off also retires an already ringing cymbal tail");
  audio.monitoring(true);
  check(audio.load_memory(bank(), false), "reload clears active voices and round robins");
  for (int i = 0; i < 300; ++i) audio.hit(i % 10, 127);
  check(audio.dropped() >= 44, "full-kit trigger queue is bounded");
  const auto dense = Access::render(audio);
  check(std::all_of(dense.begin(), dense.end(), [](float value) { return std::isfinite(value) && value >= -1 && value <= 1; }), "full-kit simultaneous peaks and voice stealing remain finite and bounded");

  drumx::Backend backend(false);
  Access::pause_worker(backend);
  const auto epoch = Access::source(backend);
  backend.set_volume(1); backend.set_monitoring(true);
  check(backend.load_sample_data(bank(), false), "backend full-kit fixture loads");
  check(backend.load_chart(240, 1, {{0, 0}, {0, 1}, {2, 0}}), "lesson chart retains three scored pad IDs");
  const double first = backend.start(0);
  // Extra GM pieces are audible receipts with pad -1, never lesson matches or
  // extras. The supplied capture time is valid for scoring if routing leaks.
  for (const auto &entry : std::vector<std::pair<int, int>>{{48,3},{50,3},{45,4},{47,4},{41,5},{43,5},{49,6},{57,6},{51,7},{59,7}}) {
    backend.midi_hit(entry.first, 127, first, epoch);
    const auto output = Access::render(backend);
    const auto hits = backend.poll_hits();
    check(near(output[0], float(entry.second + 1) / 32), "unmapped GM tom or cymbal plays its own sample");
    check(hits.size() == 1 && hits[0].pad == -1 && !hits[0].mapping_changed && hits[0].result.judgment == DX_IGNORED, "full-kit preview leaves the scored lesson mapping untouched");
  }
  check(backend.snapshot().score.total.matched == 0 && backend.snapshot().score.total.extra == 0, "unmapped full-kit strikes never alter lesson score");
  backend.midi_hit(46, 127, first, epoch);
  check(near(Access::render(backend)[0], 9.0f / 32), "mapped open hi-hat keeps its own articulation");
  backend.midi_hit(44, 127, first + .25, epoch);
  check(near(Access::render(backend)[0], 10.0f / 32), "mapped pedal hi-hat keeps its own articulation");
  check(backend.snapshot().score.total.matched == 2, "open and pedal hi-hats still score on the lesson hi-hat lane");
  backend.stop(); backend.poll_hits();

  check(backend.learn_pad(1), "MIDI learning still arms a lesson pad");
  backend.midi_hit(49, 127, drumx::host_time() - 1, epoch);
  check(silent(Access::render(backend)) && backend.snapshot().pending_pad == 1, "queued pre-arm full-kit strike neither monitors nor learns");
  backend.poll_hits();
  backend.midi_hit(49, 127, drumx::host_time(), epoch);
  auto hits = backend.poll_hits();
  check(silent(Access::render(backend)) && hits.size() == 1 && hits[0].mapping_changed && hits[0].result.judgment == DX_IGNORED, "learning a cymbal alias is silent and unscored");
  backend.midi_hit(49, 127, drumx::host_time(), epoch);
  check(near(Access::render(backend)[0], 2.0f / 32), "learned lesson alias takes precedence over GM crash sound");
  auto mapping = backend.mapping(); mapping[0] = {42}; mapping[1] = {38}; mapping[2] = {36};
  check(backend.set_mapping(mapping), "custom lesson aliases replace defaults");
  backend.midi_hit(46, 127, drumx::host_time(), epoch);
  check(near(Access::render(backend)[0], 9.0f / 32), "unmapped open hi-hat remains available for monitoring");
  backend.midi_hit(44, 127, drumx::host_time(), epoch);
  check(near(Access::render(backend)[0], 10.0f / 32), "unmapped pedal hi-hat remains available for monitoring");
  mapping[0] = {68}; backend.set_mapping(mapping);
  for (int note : {35, 40, 42, 53, 80}) backend.midi_hit(note, 127, drumx::host_time(), epoch);
  check(silent(Access::render(backend)), "removed core aliases and unsupported percussion do not gain fallback sounds");
  backend.midi_hit(51, 127, drumx::host_time(), epoch - 1);
  backend.midi_hit(51, 0, drumx::host_time(), epoch);
  backend.keyboard_hit(3, 127);
  check(silent(Access::render(backend)), "stale MIDI, note-offs and out-of-range keyboard input cannot trigger full-kit audio");
  backend.set_monitoring(false);
  backend.midi_hit(51, 127, drumx::host_time(), epoch);
  check(silent(Access::render(backend)), "backend monitoring setting gates the additional GM kit");
  std::cout << checks << " native sample mixer and full-kit routing checks, " << failures << " failures\n";
  return failures ? 1 : 0;
}
