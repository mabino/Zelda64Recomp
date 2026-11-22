#ifndef ZELDA64_MACOS_SETTINGS_H
#define ZELDA64_MACOS_SETTINGS_H

#ifdef __APPLE__
#include <cstddef>
#include "recomp_input.h"
namespace zelda64 {
    void initialize_macos_settings();
    void refresh_macos_settings();
    void refresh_macos_controls();
    void begin_macos_control_binding_scan(recomp::InputDevice device, recomp::GameInput input, size_t binding_index);
    void complete_macos_control_binding_scan();
}
#endif

#endif
