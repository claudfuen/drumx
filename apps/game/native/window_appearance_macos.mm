#include "window_appearance.h"
#import <AppKit/AppKit.h>

namespace drumx {
bool configure_window_appearance(uint64_t native_handle) {
  if (!native_handle || ![NSThread isMainThread] || !NSApp) return false;
  @autoreleasepool {
    // Match a current, app-owned window before sending any message through the
    // supplied handle. Null, stale and arbitrary pointers remain safe no-ops.
    for (NSWindow *window in NSApp.windows) {
      if (reinterpret_cast<uintptr_t>((__bridge void *)window) != native_handle) continue;
      window.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
      window.backgroundColor = [NSColor colorWithCalibratedRed:0.047 green:0.063 blue:0.071 alpha:1.0];
      window.titlebarAppearsTransparent = YES;
      return true;
    }
  }
  return false;
}
}
