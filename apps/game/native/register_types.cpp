#include "drumx_engine.h"
#include <godot_cpp/godot.hpp>

using namespace godot;
static void initialize_drumx(ModuleInitializationLevel level) {
  if (level == MODULE_INITIALIZATION_LEVEL_SCENE) ClassDB::register_class<DrumxEngine>();
}
static void uninitialize_drumx(ModuleInitializationLevel) {}
extern "C" {
GDExtensionBool GDE_EXPORT drumx_library_init(GDExtensionInterfaceGetProcAddress address,
  GDExtensionClassLibraryPtr library, GDExtensionInitialization *initialization) {
  GDExtensionBinding::InitObject init(address, library, initialization);
  init.register_initializer(initialize_drumx); init.register_terminator(uninitialize_drumx);
  init.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);
  return init.init();
}
}
