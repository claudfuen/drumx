#pragma once
#include "backend.h"
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>

namespace godot {
class DrumxEngine : public RefCounted {
  GDCLASS(DrumxEngine, RefCounted)
  drumx::Backend backend;
protected:
  static void _bind_methods();
public:
  bool configure_window(int64_t native_handle);
  double get_host_time() const;
  bool load_chart(double bpm, int bars, const Array &events);
  double start(int count_in_beats = 4);
  void stop();
  Dictionary snapshot();
  Array get_events();
  Array poll_hits();
  Array sources();
  bool connect_source(const String &id);
  bool set_mapping(const Array &mapping);
  Array get_mapping();
  bool learn_pad(int pad);
  void cancel_learning();
  bool load_sample_bank(const String &directory, bool open_device = true);
  void set_monitoring(bool enabled);
  void set_volume(double value);
  void keyboard_hit(int pad, int velocity);
};
}
