#pragma once

#include <sogen_dart.h>

namespace sogen {
class windows_emulator;
}

namespace sogen::dart {
class windows_callback_registry {
public:
  explicit windows_callback_registry(windows_emulator &emulator);

  void set(const sogen_dart_windows_callbacks *callbacks);

private:
  windows_emulator *emulator_{};
  sogen_dart_windows_callbacks callbacks_{};
};
} // namespace sogen::dart
