#pragma once
#include <cstdint>

namespace drumx {
// The caller supplies DisplayServer's WINDOW_HANDLE from the main thread.
// False means no current app window was changed.
bool configure_window_appearance(uint64_t native_handle);
}
