#pragma once

#include <cstdint>

#include <sogen_dart.h>

namespace sogen {
class linux_emulator;
}

struct sogen_dart_app;

namespace sogen::dart {
class linux_callback_registry {
public:
  linux_callback_registry(sogen_dart_app &app, linux_emulator &emulator);
  ~linux_callback_registry();

  void set(const sogen_dart_linux_callbacks *callbacks);

private:
  void refresh_memory_violate_observer();
  void replay_modules() const;

  sogen_dart_app *app_{};
  linux_emulator *emulator_{};
  sogen_dart_linux_callbacks callbacks_{};
  uint64_t memory_violate_observer_id_{};
  uint64_t signal_observer_id_{};
  uint64_t memory_allocate_observer_id_{};
  uint64_t memory_protect_observer_id_{};
  uint64_t memory_release_observer_id_{};
  uint64_t module_load_observer_id_{};
  uint64_t thread_create_observer_id_{};
  uint64_t thread_terminated_observer_id_{};
  uint64_t thread_switch_observer_id_{};
};
} // namespace sogen::dart
