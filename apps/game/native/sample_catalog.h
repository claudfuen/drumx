#pragma once
#include <array>
#include <cstddef>
#include <string>

namespace drumx {
// Sample IDs are independent of the three scored lesson pads. Keep the first
// three stable so a learned alias and keyboard input retain their lesson sound.
inline constexpr std::array<const char *, 10> sample_instruments{{
  "hihat", "snare", "kick", "tom_high", "tom_mid", "tom_floor", "crash", "ride", "hihat_open", "hihat_pedal"
}};
inline constexpr size_t sample_layers = 4, sample_round_robins = 2;
inline constexpr size_t sample_count = sample_instruments.size() * sample_layers * sample_round_robins;
inline constexpr int sample_open_hat = 8, sample_pedal_hat = 9;

inline std::string sample_relative_path(size_t index) {
  const size_t instrument = index / (sample_layers * sample_round_robins);
  const size_t layer = (index / sample_round_robins) % sample_layers + 1;
  const size_t robin = index % sample_round_robins + 1;
  return std::string(sample_instruments.at(instrument)) + "/v" + std::to_string(layer) + "_rr" + std::to_string(robin) + ".flac";
}

inline int sample_for_midi(int note, int lesson_pad) {
  if (lesson_pad >= 0 && lesson_pad < 3) {
    if (lesson_pad == 0 && note == 46) return sample_open_hat;
    if (lesson_pad == 0 && note == 44) return sample_pedal_hat;
    return lesson_pad;
  }
  // Full-kit monitoring never creates lesson aliases. Core notes removed from
  // the user's mapping stay silent; only additional GM kit pieces fall back.
  switch (note) {
    case 48: case 50: return 3;
    case 45: case 47: return 4;
    case 41: case 43: return 5;
    case 49: case 57: return 6;
    case 51: case 59: return 7;
    case 46: return sample_open_hat;
    case 44: return sample_pedal_hat;
    default: return -1;
  }
}
}
