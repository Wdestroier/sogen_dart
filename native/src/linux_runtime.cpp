#include "linux_runtime.hpp"

#include "app.hpp"
#include "error.hpp"

#include <algorithm>
#include <array>
#include <cstring>
#include <iomanip>
#include <limits>
#include <memory>
#include <sstream>
#include <stdexcept>

#include <disassembler.hpp>
#include <linux_emulator.hpp>

namespace {
sogen::linux_emulator &linux_app(sogen_dart_app *app) {
  if (!app || !app->linux || !app->linux_runtime) {
    throw std::invalid_argument("A valid Linux application is required");
  }
  return *static_cast<sogen::linux_emulator *>(app->linux);
}

sogen::dart::linux_runtime_registry &runtime(sogen_dart_app *app) {
  linux_app(app);
  return *app->linux_runtime;
}

template <typename Function> sogen_dart_status guarded(Function &&function) {
  try {
    sogen::dart::clear_error();
    function();
    return SOGEN_DART_OK;
  } catch (const std::invalid_argument &error) {
    return sogen::dart::fail(SOGEN_DART_INVALID_ARGUMENT, error.what());
  } catch (const std::logic_error &error) {
    return sogen::dart::fail(SOGEN_DART_BAD_STATE, error.what());
  } catch (const std::exception &error) {
    return sogen::dart::fail(SOGEN_DART_RUNTIME_ERROR, error.what());
  } catch (...) {
    return sogen::dart::fail(SOGEN_DART_RUNTIME_ERROR,
                             "Unknown native exception");
  }
}

void require_installable(const sogen_dart_app *app) {
  if (app->running) {
    throw std::logic_error(
        "Hooks cannot be added while the emulator is running");
  }
}

template <typename Function>
void run_emulator(sogen_dart_app &app, Function &&function) {
  if (app.running) {
    throw std::logic_error("The emulator is already running");
  }
  app.running = true;
  try {
    function();
  } catch (...) {
    app.running = false;
    throw;
  }
  app.running = false;
}

struct hook_callback_scope {
  sogen::dart::linux_runtime_registry *registry;
  sogen_dart_hook_id id;

  hook_callback_scope(sogen::dart::linux_runtime_registry &value,
                      const sogen_dart_hook_id hook)
      : registry(&value), id(hook) {
    registry->enter_hook(id);
  }

  ~hook_callback_scope() { registry->leave_hook(id); }
};

void set_buffer(sogen_dart_buffer &output, const void *data,
                const size_t length) {
  output = {};
  if (!length) {
    return;
  }
  auto bytes = std::make_unique<uint8_t[]>(length);
  std::memcpy(bytes.get(), data, length);
  output.data = bytes.release();
  output.length = length;
}

void set_buffer(sogen_dart_buffer &output, const std::string_view value) {
  set_buffer(output, value.data(), value.size());
}

void free_buffer(sogen_dart_buffer &buffer) {
  delete[] buffer.data;
  buffer = {};
}

std::string hex_address(const uint64_t address) {
  std::ostringstream stream{};
  stream << "0x" << std::hex << address;
  return stream.str();
}
} // namespace

namespace sogen::dart {
linux_runtime_registry::linux_runtime_registry(sogen_dart_app &app,
                                               linux_emulator &emulator)
    : app_(&app), emulator_(&emulator) {
  module_load_id_ = emulator_->on_module_load.add(
      [this](linux_mapped_module &) { refresh_symbols(); });
}

linux_runtime_registry::~linux_runtime_registry() {
  clear_symbols();
  for (const auto &[_, hook] : breakpoints_) {
    emulator_->emu().delete_hook(hook);
  }
  breakpoints_.clear();
  for (auto &[_, state] : hooks_) {
    if (state.remover) {
      state.remover();
    } else if (state.hook) {
      emulator_->emu().delete_hook(state.hook);
    }
  }
  hooks_.clear();
  emulator_->on_module_load.remove(module_load_id_);
}

sogen_dart_hook_id
linux_runtime_registry::add_emulator_hook(emulator_hook *hook) {
  const auto id = app_->next_low_hook_id++;
  hooks_.emplace(id, hook_state{.hook = hook});
  return id;
}

sogen_dart_hook_id
linux_runtime_registry::add_observer(std::function<void()> remover) {
  const auto id = app_->next_low_hook_id++;
  hooks_.emplace(id, hook_state{.remover = std::move(remover)});
  return id;
}

void linux_runtime_registry::erase_hook(const sogen_dart_hook_id id) {
  const auto found = hooks_.find(id);
  if (found == hooks_.end()) {
    return;
  }
  auto state = std::move(found->second);
  hooks_.erase(found);
  if (state.remover) {
    state.remover();
  } else if (state.hook) {
    emulator_->emu().delete_hook(state.hook);
  }
}

void linux_runtime_registry::remove_hook(const sogen_dart_hook_id id) {
  const auto found = hooks_.find(id);
  if (found == hooks_.end()) {
    return;
  }
  if (is_current_hook(id)) {
    found->second.pending_removal = true;
    return;
  }
  if (app_->running) {
    throw std::logic_error(
        "A low-level hook can only remove itself while running");
  }
  erase_hook(id);
}

bool linux_runtime_registry::is_current_hook(
    const sogen_dart_hook_id id) const {
  return !callback_stack_.empty() && callback_stack_.back() == id;
}

void linux_runtime_registry::enter_hook(const sogen_dart_hook_id id) {
  callback_stack_.push_back(id);
}

void linux_runtime_registry::leave_hook(const sogen_dart_hook_id id) {
  if (!callback_stack_.empty()) {
    callback_stack_.pop_back();
  }
  const auto found = hooks_.find(id);
  if (found != hooks_.end() && found->second.pending_removal) {
    erase_hook(id);
  }
}

void linux_runtime_registry::clear_entry_hooks(symbol_entry &entry) {
  for (auto *hook : entry.hooks) {
    emulator_->emu().delete_hook(hook);
  }
  entry.hooks.clear();
}

void linux_runtime_registry::set_symbol(
    const std::string &key, const size_t parameter_count,
    const sogen_dart_linux_symbol_callback callback, void *user_data) {
  if (key.empty() || key.ends_with('!')) {
    throw std::invalid_argument("Symbol hook key must contain a symbol name");
  }
  const auto separator = key.find('!');
  symbol_entry replacement{};
  if (separator == std::string::npos) {
    replacement.name = key;
  } else {
    replacement.module_filter = key.substr(0, separator);
    replacement.name = key.substr(separator + 1);
  }
  replacement.parameter_count = parameter_count;
  replacement.callback = callback;
  replacement.user_data = user_data;
  if (const auto found = symbols_.find(key); found != symbols_.end()) {
    clear_entry_hooks(found->second);
    found->second = std::move(replacement);
  } else {
    symbols_.emplace(key, std::move(replacement));
  }
  refresh_symbols();
}

void linux_runtime_registry::remove_symbol(const std::string &key) {
  const auto found = symbols_.find(key);
  if (found == symbols_.end()) {
    return;
  }
  clear_entry_hooks(found->second);
  symbols_.erase(found);
  refresh_symbols();
}

void linux_runtime_registry::clear_symbols() {
  for (auto &[_, entry] : symbols_) {
    clear_entry_hooks(entry);
  }
  symbols_.clear();
}

void linux_runtime_registry::refresh_symbols() {
  for (auto &[_, entry] : symbols_) {
    clear_entry_hooks(entry);
  }
  for (auto &[_, module] : emulator_->mod_manager.get_modules()) {
    for (auto &[key, entry] : symbols_) {
      add_symbol_for_module(key, entry, module);
    }
  }
}

void linux_runtime_registry::add_symbol_for_module(
    const std::string &key, symbol_entry &entry, linux_mapped_module &module) {
  if (entry.module_filter && *entry.module_filter != module.name &&
      *entry.module_filter != module.path.stem().string()) {
    return;
  }
  for (const auto &symbol : module.exports) {
    if (symbol.name != entry.name || symbol.address == 0) {
      continue;
    }
    auto *hook = emulator_->emu().hook_memory_execution(
        symbol.address,
        [this, key, symbol](cpu_interface &, const uint64_t address) {
          try {
            auto &backend = emulator_->emu();
            uint64_t return_address{};
            if (!backend.try_read_memory(
                    backend.reg<uint64_t>(x86_register::rsp), &return_address,
                    sizeof(return_address))) {
              return;
            }
            auto *module = emulator_->mod_manager.find_by_address(address);
            if (module) {
              invoke_symbol(key, *module, symbol, return_address);
            }
          } catch (...) {
            return;
          }
        });
    entry.hooks.push_back(hook);
  }
}

void linux_runtime_registry::invoke_symbol(const std::string &key,
                                           linux_mapped_module &module,
                                           const linux_exported_symbol &symbol,
                                           const uint64_t return_address) {
  const auto found = symbols_.find(key);
  if (found == symbols_.end()) {
    return;
  }
  const auto parameter_count = found->second.parameter_count;
  std::vector<uint64_t> parameters(parameter_count);
  auto &backend = emulator_->emu();
  static constexpr std::array argument_registers{
      x86_register::rdi, x86_register::rsi, x86_register::rdx,
      x86_register::rcx, x86_register::r8,  x86_register::r9,
  };
  const auto stack_pointer = backend.reg<uint64_t>(x86_register::rsp);
  for (size_t index = 0; index < parameter_count; ++index) {
    if (index < argument_registers.size()) {
      parameters[index] = backend.reg<uint64_t>(argument_registers[index]);
    } else if (!backend.try_read_memory(
                   stack_pointer + sizeof(uint64_t) +
                       (index - argument_registers.size()) * sizeof(uint64_t),
                   &parameters[index], sizeof(uint64_t))) {
      throw std::runtime_error(
          "Failed to read Linux symbol hook stack argument");
    }
  }

  sogen_dart_linux_symbol_call call{
      symbol.address,
      return_address,
      0,
      reinterpret_cast<const uint8_t *>(symbol.name.data()),
      symbol.name.size(),
  };
  const auto callback = found->second.callback;
  const auto user_data = found->second.user_data;
  const auto result =
      callback(user_data, &call, parameters.data(), parameters.size());
  if (result == SOGEN_DART_API_ACTION_INTERCEPT) {
    backend.reg<uint64_t>(x86_register::rax, call.return_value);
    backend.reg<uint64_t>(x86_register::rsp, stack_pointer + sizeof(uint64_t));
    backend.reg<uint64_t>(x86_register::rip, return_address);
  }
  (void)module;
}

void linux_runtime_registry::handle_breakpoint(const uint64_t address) const {
  emulator_->record_stop(stop_reason::breakpoint,
                         "address=" + hex_address(address));
  emulator_->emu().reg<uint64_t>(x86_register::rip, address);
  emulator_->stop();
}

void linux_runtime_registry::install_breakpoint(const uint64_t address) {
  breakpoints_[address] = emulator_->emu().hook_memory_execution(
      address, [this, address](cpu_interface &, uint64_t) {
        handle_breakpoint(address);
      });
}

bool linux_runtime_registry::set_breakpoint(const uint64_t address) {
  if (!breakpoints_.contains(address)) {
    install_breakpoint(address);
  }
  return true;
}

bool linux_runtime_registry::clear_breakpoint(const uint64_t address) {
  const auto found = breakpoints_.find(address);
  if (found == breakpoints_.end()) {
    return false;
  }
  if (found->second) {
    emulator_->emu().delete_hook(found->second);
  }
  breakpoints_.erase(found);
  return true;
}

std::vector<uint64_t> linux_runtime_registry::breakpoints() const {
  std::vector<uint64_t> result{};
  for (const auto &[address, hook] : breakpoints_) {
    if (hook) {
      result.push_back(address);
    }
  }
  return result;
}

bool linux_runtime_registry::suppress_current_breakpoint_once() {
  const auto address = emulator_->emu().reg<uint64_t>(x86_register::rip);
  const auto found = breakpoints_.find(address);
  if (found == breakpoints_.end() || !found->second) {
    return false;
  }
  emulator_->emu().delete_hook(found->second);
  found->second = nullptr;
  try {
    emulator_->start(1);
  } catch (...) {
    install_breakpoint(address);
    throw;
  }
  install_breakpoint(address);
  return true;
}

void linux_runtime_registry::step_into() {
  if (!suppress_current_breakpoint_once()) {
    emulator_->start(1);
  }
}

void linux_runtime_registry::step_over() { step_into(); }

void linux_runtime_registry::step_out() {
  auto &backend = emulator_->emu();
  const auto frame_pointer = backend.reg<uint64_t>(x86_register::rbp);
  if (!frame_pointer) {
    throw std::runtime_error(
        "step_out cannot find a caller because RBP is zero; use "
        "run_to(address) when the target return address is known");
  }
  const auto location = frame_pointer + sizeof(uint64_t);
  uint64_t return_address{};
  if (!emulator_->memory.try_read_memory(location, &return_address,
                                         sizeof(return_address))) {
    throw std::runtime_error(
        "step_out cannot read the saved return address at " +
        hex_address(location) +
        "; use run_to(address) if frame pointers are unavailable");
  }
  if (!return_address) {
    throw std::runtime_error(
        "step_out found a zero saved return address at " +
        hex_address(location) +
        "; use run_to(address) for an explicit destination");
  }
  run_to(return_address);
}

void linux_runtime_registry::run_to(const uint64_t address) {
  auto *hook = emulator_->emu().hook_memory_execution(
      address, [this, address](cpu_interface &, uint64_t) {
        handle_breakpoint(address);
      });
  try {
    emulator_->start();
  } catch (...) {
    emulator_->emu().delete_hook(hook);
    throw;
  }
  emulator_->emu().delete_hook(hook);
}

void linux_runtime_registry::continue_execution() {
  if (suppress_current_breakpoint_once() &&
      emulator_->last_stop_reason() != stop_reason::instruction_limit) {
    return;
  }
  emulator_->start();
}

void linux_runtime_registry::pause() const { emulator_->stop(); }
} // namespace sogen::dart

extern "C" {
sogen_dart_status sogen_dart_linux_hook_memory_execution(
    sogen_dart_app *app, const int32_t has_address, const uint64_t address,
    const sogen_dart_execution_callback callback, void *user_data,
    sogen_dart_hook_id *out_hook) {
  if (!callback || !out_hook) {
    return sogen::dart::fail(SOGEN_DART_INVALID_ARGUMENT,
                             "Callback and hook output pointer are required");
  }
  return guarded([&] {
    auto &registry = runtime(app);
    require_installable(app);
    const auto id = app->next_low_hook_id;
    const auto invoke = [&registry, id, callback,
                         user_data](sogen::cpu_interface &,
                                    const uint64_t hit_address) {
      const hook_callback_scope scope{registry, id};
      callback(user_data, id, hit_address);
    };
    auto *hook =
        has_address
            ? linux_app(app).emu().hook_memory_execution(address, invoke)
            : linux_app(app).emu().hook_memory_execution(invoke);
    *out_hook = registry.add_emulator_hook(hook);
  });
}

sogen_dart_status sogen_dart_linux_hook_memory_read(
    sogen_dart_app *app, const uint64_t address, const uint64_t size,
    const sogen_dart_memory_callback callback, void *user_data,
    sogen_dart_hook_id *out_hook) {
  if (!callback || !out_hook) {
    return sogen::dart::fail(SOGEN_DART_INVALID_ARGUMENT,
                             "Callback and hook output pointer are required");
  }
  return guarded([&] {
    auto &registry = runtime(app);
    require_installable(app);
    const auto id = app->next_low_hook_id;
    auto *hook = linux_app(app).emu().hook_memory_read(
        address, size,
        [&registry, id, callback,
         user_data](sogen::cpu_interface &, const uint64_t hit_address,
                    const void *data, const size_t length) {
          const hook_callback_scope scope{registry, id};
          callback(user_data, id, hit_address,
                   static_cast<const uint8_t *>(data), length);
        });
    *out_hook = registry.add_emulator_hook(hook);
  });
}

sogen_dart_status sogen_dart_linux_hook_memory_write(
    sogen_dart_app *app, const uint64_t address, const uint64_t size,
    const sogen_dart_memory_callback callback, void *user_data,
    sogen_dart_hook_id *out_hook) {
  if (!callback || !out_hook) {
    return sogen::dart::fail(SOGEN_DART_INVALID_ARGUMENT,
                             "Callback and hook output pointer are required");
  }
  return guarded([&] {
    auto &registry = runtime(app);
    require_installable(app);
    const auto id = app->next_low_hook_id;
    auto *hook = linux_app(app).emu().hook_memory_write(
        address, size,
        [&registry, id, callback,
         user_data](sogen::cpu_interface &, const uint64_t hit_address,
                    const void *data, const size_t length) {
          const hook_callback_scope scope{registry, id};
          callback(user_data, id, hit_address,
                   static_cast<const uint8_t *>(data), length);
        });
    *out_hook = registry.add_emulator_hook(hook);
  });
}

sogen_dart_status sogen_dart_linux_hook_instruction(
    sogen_dart_app *app, const int32_t instruction,
    const sogen_dart_instruction_callback callback, void *user_data,
    sogen_dart_hook_id *out_hook) {
  if (!callback || !out_hook || instruction < 0 || instruction > 4) {
    return sogen::dart::fail(
        SOGEN_DART_INVALID_ARGUMENT,
        "Valid instruction, callback, and output are required");
  }
  return guarded([&] {
    auto &registry = runtime(app);
    require_installable(app);
    const auto id = app->next_low_hook_id;
    auto *hook = linux_app(app).emu().hook_instruction(
        static_cast<sogen::x86_hookable_instructions>(instruction),
        [&registry, id, callback, user_data](sogen::cpu_interface &,
                                             const uint64_t data) {
          const hook_callback_scope scope{registry, id};
          const auto result = callback(user_data, id, data);
          return result >= 0 && result <= 2
                     ? static_cast<sogen::instruction_hook_continuation>(result)
                     : sogen::instruction_hook_continuation::run_instruction;
        });
    *out_hook = registry.add_emulator_hook(hook);
  });
}

sogen_dart_status
sogen_dart_linux_hook_interrupt(sogen_dart_app *app,
                                const sogen_dart_interrupt_callback callback,
                                void *user_data, sogen_dart_hook_id *out_hook) {
  if (!callback || !out_hook) {
    return sogen::dart::fail(SOGEN_DART_INVALID_ARGUMENT,
                             "Callback and hook output pointer are required");
  }
  return guarded([&] {
    auto &registry = runtime(app);
    require_installable(app);
    const auto id = app->next_low_hook_id;
    auto &emulator = linux_app(app);
    const auto observer = emulator.add_interrupt_observer(
        [&registry, id, callback, user_data](const int interrupt) {
          const hook_callback_scope scope{registry, id};
          callback(user_data, id, interrupt);
        });
    *out_hook = registry.add_observer([&emulator, observer] {
      emulator.remove_interrupt_observer(observer);
    });
  });
}

sogen_dart_status sogen_dart_linux_hook_memory_violation(
    sogen_dart_app *app, const sogen_dart_memory_violation_callback callback,
    void *user_data, sogen_dart_hook_id *out_hook) {
  if (!callback || !out_hook) {
    return sogen::dart::fail(SOGEN_DART_INVALID_ARGUMENT,
                             "Callback and hook output pointer are required");
  }
  return guarded([&] {
    auto &registry = runtime(app);
    require_installable(app);
    const auto id = app->next_low_hook_id;
    auto &emulator = linux_app(app);
    const auto observer = emulator.add_memory_violation_observer(
        [&registry, id, callback,
         user_data](const uint64_t address, const size_t size,
                    const sogen::memory_operation operation,
                    const sogen::memory_violation_type type) {
          const hook_callback_scope scope{registry, id};
          const auto result = callback(user_data, id, address, size,
                                       static_cast<int32_t>(operation),
                                       static_cast<int32_t>(type));
          return result >= 0 && result <= 2
                     ? static_cast<sogen::memory_violation_continuation>(result)
                     : sogen::memory_violation_continuation::stop;
        });
    *out_hook = registry.add_observer([&emulator, observer] {
      emulator.remove_memory_violation_observer(observer);
    });
  });
}

sogen_dart_status sogen_dart_linux_hook_basic_block(
    sogen_dart_app *app, const sogen_dart_basic_block_callback callback,
    void *user_data, sogen_dart_hook_id *out_hook) {
  if (!callback || !out_hook) {
    return sogen::dart::fail(SOGEN_DART_INVALID_ARGUMENT,
                             "Callback and hook output pointer are required");
  }
  return guarded([&] {
    auto &registry = runtime(app);
    require_installable(app);
    const auto id = app->next_low_hook_id;
    auto *hook = linux_app(app).emu().hook_basic_block(
        [&registry, id, callback, user_data](sogen::cpu_interface &,
                                             const sogen::basic_block &block) {
          const hook_callback_scope scope{registry, id};
          callback(user_data, id, block.address, block.instruction_count,
                   block.size);
        });
    *out_hook = registry.add_emulator_hook(hook);
  });
}

sogen_dart_status sogen_dart_linux_remove_hook(sogen_dart_app *app,
                                               const sogen_dart_hook_id hook) {
  return guarded([&] { runtime(app).remove_hook(hook); });
}

sogen_dart_status sogen_dart_linux_set_symbol_hook(
    sogen_dart_app *app, const char *key, const size_t parameter_count,
    const sogen_dart_linux_symbol_callback callback, void *user_data) {
  if (!key || !callback) {
    return sogen::dart::fail(SOGEN_DART_INVALID_ARGUMENT,
                             "Symbol key and callback are required");
  }
  return guarded([&] {
    runtime(app).set_symbol(key, parameter_count, callback, user_data);
  });
}

sogen_dart_status sogen_dart_linux_remove_symbol_hook(sogen_dart_app *app,
                                                      const char *key) {
  if (!key) {
    return sogen::dart::fail(SOGEN_DART_INVALID_ARGUMENT,
                             "Symbol key is required");
  }
  return guarded([&] { runtime(app).remove_symbol(key); });
}

sogen_dart_status sogen_dart_linux_clear_symbol_hooks(sogen_dart_app *app) {
  return guarded([&] { runtime(app).clear_symbols(); });
}

sogen_dart_status sogen_dart_linux_refresh_symbol_hooks(sogen_dart_app *app) {
  return guarded([&] { runtime(app).refresh_symbols(); });
}

sogen_dart_status sogen_dart_linux_debug_set_breakpoint(sogen_dart_app *app,
                                                        const uint64_t address,
                                                        int32_t *success) {
  if (!success) {
    return sogen::dart::fail(SOGEN_DART_INVALID_ARGUMENT,
                             "Breakpoint output pointer is required");
  }
  return guarded(
      [&] { *success = runtime(app).set_breakpoint(address) ? 1 : 0; });
}

sogen_dart_status sogen_dart_linux_debug_clear_breakpoint(
    sogen_dart_app *app, const uint64_t address, int32_t *success) {
  if (!success) {
    return sogen::dart::fail(SOGEN_DART_INVALID_ARGUMENT,
                             "Breakpoint output pointer is required");
  }
  return guarded(
      [&] { *success = runtime(app).clear_breakpoint(address) ? 1 : 0; });
}

sogen_dart_status
sogen_dart_linux_debug_list_breakpoints(sogen_dart_app *app,
                                        sogen_dart_buffer *output) {
  if (!output) {
    return sogen::dart::fail(SOGEN_DART_INVALID_ARGUMENT,
                             "Breakpoint list output pointer is required");
  }
  *output = {};
  return guarded([&] {
    const auto values = runtime(app).breakpoints();
    set_buffer(*output, values.data(), values.size() * sizeof(uint64_t));
  });
}

sogen_dart_status sogen_dart_linux_debug_step_into(sogen_dart_app *app) {
  return guarded([&] {
    linux_app(app);
    run_emulator(*app, [&] { runtime(app).step_into(); });
  });
}

sogen_dart_status sogen_dart_linux_debug_step_over(sogen_dart_app *app) {
  return guarded([&] {
    linux_app(app);
    run_emulator(*app, [&] { runtime(app).step_over(); });
  });
}

sogen_dart_status sogen_dart_linux_debug_step_out(sogen_dart_app *app) {
  return guarded([&] {
    linux_app(app);
    run_emulator(*app, [&] { runtime(app).step_out(); });
  });
}

sogen_dart_status sogen_dart_linux_debug_run_to(sogen_dart_app *app,
                                                const uint64_t address) {
  return guarded([&] {
    linux_app(app);
    run_emulator(*app, [&] { runtime(app).run_to(address); });
  });
}

sogen_dart_status
sogen_dart_linux_debug_continue_execution(sogen_dart_app *app) {
  return guarded([&] {
    linux_app(app);
    run_emulator(*app, [&] { runtime(app).continue_execution(); });
  });
}

sogen_dart_status sogen_dart_linux_debug_pause(sogen_dart_app *app) {
  return guarded([&] { runtime(app).pause(); });
}

sogen_dart_status sogen_dart_linux_debug_disassemble(
    sogen_dart_app *app, const uint64_t address, const size_t count_or_size,
    sogen_dart_linux_disassembled_instruction_list *output) {
  if (!output) {
    return sogen::dart::fail(SOGEN_DART_INVALID_ARGUMENT,
                             "Disassembly output pointer is required");
  }
  *output = {};
  return guarded([&] {
    auto &emulator = linux_app(app);
    if (!count_or_size) {
      return;
    }
    const auto count = std::min<size_t>(count_or_size, 4096);
    std::vector<uint8_t> bytes(count * 16);
    if (!emulator.memory.try_read_memory(address, bytes.data(), bytes.size())) {
      bytes.resize(std::min<size_t>(count_or_size, 4096));
      if (bytes.empty() || !emulator.memory.try_read_memory(
                               address, bytes.data(), bytes.size())) {
        return;
      }
    }
    sogen::disassembler disassembler{};
    const auto instructions = disassembler.disassemble(
        emulator.emu(), emulator.emu().reg<uint16_t>(sogen::x86_register::cs),
        std::span<const uint8_t>(bytes.data(), bytes.size()), count, address);
    auto values = std::make_unique<sogen_dart_linux_disassembled_instruction[]>(
        instructions.size());
    output->data = values.get();
    output->length = instructions.size();
    try {
      for (size_t index = 0; index < instructions.size(); ++index) {
        const auto &instruction = instructions[index];
        values[index].address = instruction.address;
        values[index].size = instruction.size;
        set_buffer(values[index].bytes, instruction.bytes, instruction.size);
        set_buffer(values[index].mnemonic_utf8,
                   std::string_view(instruction.mnemonic));
        set_buffer(values[index].operands_utf8,
                   std::string_view(instruction.op_str));
      }
    } catch (...) {
      sogen_dart_linux_disassembled_instruction_list_free(output);
      values.release();
      throw;
    }
    output->data = values.release();
  });
}

void sogen_dart_linux_disassembled_instruction_list_free(
    sogen_dart_linux_disassembled_instruction_list *list) {
  if (!list) {
    return;
  }
  for (size_t index = 0; index < list->length; ++index) {
    free_buffer(list->data[index].bytes);
    free_buffer(list->data[index].mnemonic_utf8);
    free_buffer(list->data[index].operands_utf8);
  }
  delete[] list->data;
  *list = {};
}

sogen_dart_status
sogen_dart_linux_debug_call_stack(sogen_dart_app *app,
                                  sogen_dart_linux_stack_frame_list *output) {
  if (!output) {
    return sogen::dart::fail(SOGEN_DART_INVALID_ARGUMENT,
                             "Call stack output pointer is required");
  }
  *output = {};
  return guarded([&] {
    auto &emulator = linux_app(app);
    auto &backend = emulator.emu();
    struct frame_value {
      uint64_t ip;
      uint64_t sp;
      std::string module;
    };
    const auto module_name = [&emulator](const uint64_t ip) {
      const auto *module = emulator.mod_manager.find_by_address(ip);
      return module ? module->name : std::string{};
    };
    std::vector<frame_value> frames{{
        backend.reg<uint64_t>(sogen::x86_register::rip),
        backend.reg<uint64_t>(sogen::x86_register::rsp),
        module_name(backend.reg<uint64_t>(sogen::x86_register::rip)),
    }};
    auto frame_pointer = backend.reg<uint64_t>(sogen::x86_register::rbp);
    for (size_t depth = 0; depth < 64 && frame_pointer; ++depth) {
      uint64_t saved_rbp{};
      uint64_t return_address{};
      if (!emulator.memory.try_read_memory(frame_pointer, &saved_rbp,
                                           sizeof(saved_rbp)) ||
          !emulator.memory.try_read_memory(frame_pointer + sizeof(uint64_t),
                                           &return_address,
                                           sizeof(return_address)) ||
          !return_address || saved_rbp <= frame_pointer) {
        break;
      }
      frames.push_back(
          {return_address, frame_pointer, module_name(return_address)});
      frame_pointer = saved_rbp;
    }
    auto values =
        std::make_unique<sogen_dart_linux_stack_frame[]>(frames.size());
    output->data = values.get();
    output->length = frames.size();
    try {
      for (size_t index = 0; index < frames.size(); ++index) {
        values[index].instruction_pointer = frames[index].ip;
        values[index].stack_pointer = frames[index].sp;
        set_buffer(values[index].module_utf8, frames[index].module);
      }
    } catch (...) {
      sogen_dart_linux_stack_frame_list_free(output);
      values.release();
      throw;
    }
    output->data = values.release();
  });
}

void sogen_dart_linux_stack_frame_list_free(
    sogen_dart_linux_stack_frame_list *list) {
  if (!list) {
    return;
  }
  for (size_t index = 0; index < list->length; ++index) {
    free_buffer(list->data[index].module_utf8);
  }
  delete[] list->data;
  *list = {};
}
}
