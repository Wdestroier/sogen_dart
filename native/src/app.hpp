#pragma once

#include <cstddef>
#include <map>
#include <memory>
#include <vector>

namespace sogen {
class windows_emulator;
}

namespace sogen::dart {
class api_hook_registry;
class linux_callback_registry;
class linux_runtime_registry;
class windows_callback_registry;
} // namespace sogen::dart

struct sogen_dart_app {
  std::unique_ptr<sogen::windows_emulator> windows{};
  std::unique_ptr<sogen::dart::windows_callback_registry> callbacks{};
  std::unique_ptr<sogen::dart::api_hook_registry> api_hooks{};
  void *linux{};
  std::unique_ptr<sogen::dart::linux_callback_registry> linux_callbacks{};
  std::unique_ptr<sogen::dart::linux_runtime_registry> linux_runtime{};
  std::vector<std::byte> linux_snapshot{};
  std::map<uint64_t, void *> low_hooks{};
  std::vector<uint64_t> deferred_hook_removals{};
  uint64_t next_low_hook_id{0x100000000ULL};
  bool in_low_hook_callback{};
  bool running{};
  size_t linux_callback_depth{};

  sogen_dart_app();
  ~sogen_dart_app();
};
