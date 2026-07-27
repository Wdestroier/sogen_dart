#pragma once

#include <cstdint>
#include <map>
#include <optional>
#include <string>
#include <vector>

#include <sogen_dart.h>
#include <utils/function.hpp>

namespace sogen {
class windows_emulator;
struct emulator_hook;
struct mapped_module;
} // namespace sogen

namespace sogen::dart {
struct api_hook_target {
  std::optional<std::string> module{};
  std::string name{};
};

struct api_hook_entry {
  sogen_dart_hook_id id{};
  std::optional<std::string> module_filter{};
  std::string name{};
  int32_t calling_convention{};
  size_t parameter_count{};
  sogen_dart_api_callback callback{};
  void *user_data{};
};

struct api_hook_hit {
  std::string key{};
  sogen_dart_hook_id id{};
  std::string module_name{};
  std::string export_name{};
  uint64_t address{};
};

class api_hook_registry {
public:
  explicit api_hook_registry(windows_emulator &emulator);
  ~api_hook_registry();

  api_hook_registry(const api_hook_registry &) = delete;
  api_hook_registry &operator=(const api_hook_registry &) = delete;

  sogen_dart_hook_id set(const std::string &key, int32_t calling_convention,
                         size_t parameter_count,
                         sogen_dart_api_callback callback, void *user_data);
  void remove(sogen_dart_hook_id id);
  void clear();
  void refresh();
  bool in_callback() const;

private:
  windows_emulator *emulator_{};
  std::map<std::string, api_hook_entry, std::less<>> entries_{};
  std::map<uint64_t, std::vector<api_hook_hit>> address_index_{};
  emulator_hook *execution_hook_{};
  utils::callback_id_type module_load_id_{};
  utils::callback_id_type module_unload_id_{};
  sogen_dart_hook_id next_id_{1};
  bool in_callback_{};

  void ensure_execution_hook();
  void remove_execution_hook();
  void add_entry_for_module(const std::string &key, const api_hook_entry &entry,
                            const mapped_module &module);
  void dispatch_address(uint64_t address);
  void invoke_hook(const api_hook_hit &hit, uint64_t return_address,
                   uint64_t stack_pointer, bool is_32_bit);
};
} // namespace sogen::dart
