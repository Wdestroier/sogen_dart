#include "linux_callbacks.hpp"

#include "app.hpp"
#include "error.hpp"

#include <algorithm>
#include <filesystem>
#include <stdexcept>
#include <string>
#include <string_view>
#include <vector>

#include <linux_emulator.hpp>

namespace sogen::dart {
namespace {
class callback_scope {
public:
  explicit callback_scope(sogen_dart_app &app) : app_(&app) {
    ++this->app_->linux_callback_depth;
  }

  ~callback_scope() { --this->app_->linux_callback_depth; }

private:
  sogen_dart_app *app_;
};

const uint8_t *bytes(const std::string_view value) {
  return reinterpret_cast<const uint8_t *>(value.data());
}

sogen_dart_buffer buffer(const std::string_view value) {
  return {const_cast<uint8_t *>(bytes(value)), value.size()};
}

std::string path_to_utf8(const std::filesystem::path &value) {
  const auto utf8 = value.u8string();
  return {reinterpret_cast<const char *>(utf8.data()), utf8.size()};
}

void invoke_text(sogen_dart_app &app, const sogen_dart_text_callback callback,
                 void *user_data, const std::string_view text) {
  if (!callback) {
    return;
  }
  callback_scope scope{app};
  callback(user_data, bytes(text), text.size());
}

void invoke_module(sogen_dart_app &app,
                   const sogen_dart_linux_module_callback callback,
                   void *user_data, const linux_mapped_module &module) {
  if (!callback) {
    return;
  }

  const auto path = path_to_utf8(module.path);
  std::vector<sogen_dart_linux_exported_symbol> exports{};
  exports.reserve(module.exports.size());
  for (const auto &symbol : module.exports) {
    exports.push_back({buffer(symbol.name), symbol.rva, symbol.address});
  }

  std::vector<sogen_dart_buffer> needed_libraries{};
  needed_libraries.reserve(module.needed_libraries.size());
  for (const auto &library : module.needed_libraries) {
    needed_libraries.push_back(buffer(library));
  }

  std::vector<sogen_dart_linux_mapped_section> sections{};
  sections.reserve(module.sections.size());
  for (const auto &section : module.sections) {
    sections.push_back({buffer(section.name), section.start, section.length,
                        static_cast<int32_t>(section.permissions)});
  }

  const sogen_dart_linux_mapped_module value{
      buffer(module.name),
      buffer(path),
      module.image_base,
      module.size_of_image,
      module.entry_point,
      {exports.data(), exports.size()},
      {needed_libraries.data(), needed_libraries.size()},
      {sections.data(), sections.size()},
      buffer(module.rpath),
      buffer(module.runpath),
  };
  callback_scope scope{app};
  callback(user_data, &value);
}

sogen_dart_linux_thread_info thread_info(linux_emulator &emulator,
                                         const linux_thread &thread) {
  const auto current_ip =
      emulator.process.active_thread &&
              emulator.process.active_thread->tid == thread.tid
          ? emulator.emu().reg<uint64_t>(x86_register::rip)
          : thread.saved_regs.rip;
  return {
      thread.tid,
      thread.stack_base,
      thread.stack_size,
      thread.fs_base,
      current_ip,
      thread.saved_regs.rip,
      static_cast<int32_t>(thread.wait_state),
      1,
      thread.terminated ? 1 : 0,
      thread.exit_code,
      thread.executed_instructions,
  };
}

template <typename Function> sogen_dart_status guarded(Function &&function) {
  try {
    clear_error();
    function();
    return SOGEN_DART_OK;
  } catch (const std::invalid_argument &error) {
    return fail(SOGEN_DART_INVALID_ARGUMENT, error.what());
  } catch (const std::logic_error &error) {
    return fail(SOGEN_DART_BAD_STATE, error.what());
  } catch (const std::exception &error) {
    return fail(SOGEN_DART_RUNTIME_ERROR, error.what());
  } catch (...) {
    return fail(SOGEN_DART_RUNTIME_ERROR, "Unknown native exception");
  }
}
} // namespace

linux_callback_registry::linux_callback_registry(sogen_dart_app &app,
                                                 linux_emulator &emulator)
    : app_(&app), emulator_(&emulator) {
  this->emulator_->on_stdout = [this](const std::string_view text) {
    invoke_text(*this->app_, this->callbacks_.stdout_callback,
                this->callbacks_.user_data, text);
  };
  this->emulator_->on_stderr = [this](const std::string_view text) {
    invoke_text(*this->app_, this->callbacks_.stderr_callback,
                this->callbacks_.user_data, text);
  };
  this->emulator_->on_syscall = [this](const uint64_t id,
                                       const std::string_view name) {
    const auto callback = this->callbacks_.syscall;
    const auto user_data = this->callbacks_.user_data;
    if (!callback) {
      return instruction_hook_continuation::run_instruction;
    }
    callback_scope scope{*this->app_};
    const auto result = callback(user_data, id, bytes(name), name.size());
    if (result < static_cast<int32_t>(
                     instruction_hook_continuation::run_instruction) ||
        result >
            static_cast<int32_t>(
                instruction_hook_continuation::finalized_instruction_pointer)) {
      return instruction_hook_continuation::run_instruction;
    }
    return static_cast<instruction_hook_continuation>(result);
  };
  this->signal_observer_id_ = this->emulator_->on_signal.add(
      [this](const int signum, const uint64_t fault_address,
             const int signal_code) {
        const auto callback = this->callbacks_.signal;
        const auto user_data = this->callbacks_.user_data;
        if (callback) {
          callback_scope scope{*this->app_};
          callback(user_data, signum, fault_address, signal_code);
        }
      });
  this->memory_allocate_observer_id_ =
      this->emulator_->memory.add_memory_allocate_callback(
          [this](const uint64_t address, const size_t size,
                 const memory_permission permissions, const bool committed) {
            const auto callback = this->callbacks_.memory_allocate;
            const auto user_data = this->callbacks_.user_data;
            if (callback) {
              callback_scope scope{*this->app_};
              callback(user_data, address, size,
                       static_cast<int32_t>(permissions), committed ? 1 : 0);
            }
          });
  this->memory_protect_observer_id_ =
      this->emulator_->memory.add_memory_protect_callback(
          [this](const uint64_t address, const size_t size,
                 const memory_permission permissions) {
            const auto callback = this->callbacks_.memory_protect;
            const auto user_data = this->callbacks_.user_data;
            if (callback) {
              callback_scope scope{*this->app_};
              callback(user_data, address, size,
                       static_cast<int32_t>(permissions));
            }
          });
  this->memory_release_observer_id_ =
      this->emulator_->memory.add_memory_release_callback(
          [this](const uint64_t address, const size_t size) {
            const auto callback = this->callbacks_.memory_release;
            const auto user_data = this->callbacks_.user_data;
            if (callback) {
              callback_scope scope{*this->app_};
              callback(user_data, address, size);
            }
          });
  this->module_load_observer_id_ =
      this->emulator_->on_module_load.add([this](linux_mapped_module &module) {
        invoke_module(*this->app_, this->callbacks_.module_load,
                      this->callbacks_.user_data, module);
      });
  this->thread_create_observer_id_ =
      this->emulator_->on_thread_create.add([this](linux_thread &thread) {
        const auto callback = this->callbacks_.thread_create;
        const auto user_data = this->callbacks_.user_data;
        if (callback) {
          const auto value = thread_info(*this->emulator_, thread);
          callback_scope scope{*this->app_};
          callback(user_data, &value);
        }
      });
  this->thread_terminated_observer_id_ =
      this->emulator_->on_thread_terminated.add([this](linux_thread &thread) {
        const auto callback = this->callbacks_.thread_terminated;
        const auto user_data = this->callbacks_.user_data;
        if (callback) {
          const auto value = thread_info(*this->emulator_, thread);
          callback_scope scope{*this->app_};
          callback(user_data, &value);
        }
      });
  this->thread_switch_observer_id_ = this->emulator_->on_thread_switch.add(
      [this](const uint32_t old_tid, const uint32_t new_tid) {
        const auto callback = this->callbacks_.thread_switch;
        const auto user_data = this->callbacks_.user_data;
        if (callback) {
          callback_scope scope{*this->app_};
          callback(user_data, old_tid, new_tid);
        }
      });
}

linux_callback_registry::~linux_callback_registry() {
  if (!this->emulator_) {
    return;
  }
  if (this->memory_violate_observer_id_) {
    this->emulator_->remove_memory_violation_observer(
        this->memory_violate_observer_id_);
  }
  this->emulator_->memory.remove_memory_callback(
      this->memory_allocate_observer_id_);
  this->emulator_->memory.remove_memory_callback(
      this->memory_protect_observer_id_);
  this->emulator_->memory.remove_memory_callback(
      this->memory_release_observer_id_);
  this->emulator_->on_signal.remove(this->signal_observer_id_);
  this->emulator_->on_module_load.remove(this->module_load_observer_id_);
  this->emulator_->on_thread_create.remove(this->thread_create_observer_id_);
  this->emulator_->on_thread_terminated.remove(
      this->thread_terminated_observer_id_);
  this->emulator_->on_thread_switch.remove(this->thread_switch_observer_id_);
  this->emulator_->on_stdout = {};
  this->emulator_->on_stderr = {};
  this->emulator_->on_syscall = {};
}

void linux_callback_registry::set(const sogen_dart_linux_callbacks *callbacks) {
  const auto old_memory_violate = this->callbacks_.memory_violate;
  const auto old_module_load = this->callbacks_.module_load;
  this->callbacks_ = callbacks ? *callbacks : sogen_dart_linux_callbacks{};
  if (old_memory_violate != this->callbacks_.memory_violate) {
    this->refresh_memory_violate_observer();
  }
  if (this->callbacks_.module_load &&
      old_module_load != this->callbacks_.module_load) {
    this->replay_modules();
  }
}

void linux_callback_registry::refresh_memory_violate_observer() {
  if (!this->callbacks_.memory_violate) {
    if (this->memory_violate_observer_id_) {
      this->emulator_->remove_memory_violation_observer(
          this->memory_violate_observer_id_);
      this->memory_violate_observer_id_ = 0;
    }
    return;
  }
  if (this->memory_violate_observer_id_) {
    return;
  }

  this->memory_violate_observer_id_ =
      this->emulator_->add_memory_violation_observer(
          [this](const uint64_t address, const size_t size,
                 const memory_operation operation,
                 const memory_violation_type type) {
            const auto callback = this->callbacks_.memory_violate;
            const auto user_data = this->callbacks_.user_data;
            if (!callback) {
              return memory_violation_continuation::resume;
            }
            callback_scope scope{*this->app_};
            const auto result = callback(user_data, address, size,
                                         static_cast<int32_t>(operation),
                                         static_cast<int32_t>(type));
            if (result <
                    static_cast<int32_t>(memory_violation_continuation::stop) ||
                result > static_cast<int32_t>(
                             memory_violation_continuation::restart)) {
              return memory_violation_continuation::resume;
            }
            return static_cast<memory_violation_continuation>(result);
          });
}

void linux_callback_registry::replay_modules() const {
  const auto callback = this->callbacks_.module_load;
  const auto user_data = this->callbacks_.user_data;
  std::vector<const linux_mapped_module *> modules{};
  modules.reserve(this->emulator_->mod_manager.get_modules().size());
  for (const auto &[_, module] : this->emulator_->mod_manager.get_modules()) {
    modules.push_back(&module);
  }
  std::ranges::sort(modules, {}, &linux_mapped_module::image_base);
  for (const auto *module : modules) {
    invoke_module(*this->app_, callback, user_data, *module);
  }
}
} // namespace sogen::dart

extern "C" {
sogen_dart_status
sogen_dart_linux_set_callbacks(sogen_dart_app *app,
                               const sogen_dart_linux_callbacks *callbacks) {
  return sogen::dart::guarded([&] {
    if (!app || !app->linux || !app->linux_callbacks) {
      throw std::invalid_argument("A valid Linux application is required");
    }
    app->linux_callbacks->set(callbacks);
  });
}
}
