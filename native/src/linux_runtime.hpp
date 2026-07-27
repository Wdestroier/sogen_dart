#pragma once

#include <sogen_dart.h>

#include <functional>
#include <map>
#include <memory>
#include <optional>
#include <string>
#include <vector>

namespace sogen {
struct emulator_hook;
class linux_emulator;
struct linux_mapped_module;
struct linux_exported_symbol;
} // namespace sogen

namespace sogen::dart {
class linux_runtime_registry {
public:
  explicit linux_runtime_registry(sogen_dart_app &app,
                                  linux_emulator &emulator);
  ~linux_runtime_registry();

  linux_runtime_registry(const linux_runtime_registry &) = delete;
  linux_runtime_registry &operator=(const linux_runtime_registry &) = delete;

  sogen_dart_hook_id add_emulator_hook(emulator_hook *hook);
  sogen_dart_hook_id add_observer(std::function<void()> remover);
  void remove_hook(sogen_dart_hook_id id);
  bool is_current_hook(sogen_dart_hook_id id) const;
  void enter_hook(sogen_dart_hook_id id);
  void leave_hook(sogen_dart_hook_id id);

  void set_symbol(const std::string &key, size_t parameter_count,
                  sogen_dart_linux_symbol_callback callback, void *user_data);
  void remove_symbol(const std::string &key);
  void clear_symbols();
  void refresh_symbols();

  bool set_breakpoint(uint64_t address);
  bool clear_breakpoint(uint64_t address);
  std::vector<uint64_t> breakpoints() const;
  void step_into();
  void step_over();
  void step_out();
  void run_to(uint64_t address);
  void continue_execution();
  void pause() const;

private:
  struct hook_state {
    emulator_hook *hook{};
    std::function<void()> remover{};
    bool pending_removal{};
  };

  struct symbol_entry {
    std::optional<std::string> module_filter{};
    std::string name{};
    size_t parameter_count{};
    sogen_dart_linux_symbol_callback callback{};
    void *user_data{};
    std::vector<emulator_hook *> hooks{};
  };

  sogen_dart_app *app_{};
  linux_emulator *emulator_{};
  std::map<sogen_dart_hook_id, hook_state> hooks_{};
  std::vector<sogen_dart_hook_id> callback_stack_{};
  std::map<std::string, symbol_entry, std::less<>> symbols_{};
  std::map<uint64_t, emulator_hook *> breakpoints_{};
  uint64_t module_load_id_{};

  void erase_hook(sogen_dart_hook_id id);
  void clear_entry_hooks(symbol_entry &entry);
  void add_symbol_for_module(const std::string &key, symbol_entry &entry,
                             linux_mapped_module &module);
  void invoke_symbol(const std::string &key, linux_mapped_module &module,
                     const linux_exported_symbol &symbol,
                     uint64_t return_address);
  void handle_breakpoint(uint64_t address) const;
  bool suppress_current_breakpoint_once();
  void install_breakpoint(uint64_t address);
};
} // namespace sogen::dart
