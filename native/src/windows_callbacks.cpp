#include "windows_callbacks.hpp"

#include <filesystem>
#include <string>
#include <vector>

#include <platform/unicode.hpp>
#include <windows_emulator.hpp>

namespace sogen::dart {
namespace {
const uint8_t *bytes(const std::string &value) {
  return reinterpret_cast<const uint8_t *>(value.data());
}

std::string path_to_utf8(const std::filesystem::path &value) {
  const auto utf8 = value.u8string();
  return {reinterpret_cast<const char *>(utf8.data()), utf8.size()};
}

void invoke_module(const sogen_dart_module_callback callback, void *user_data,
                   const mapped_module &module) {
  if (!callback) {
    return;
  }

  const auto path = path_to_utf8(module.path);
  const auto module_path = module.module_path.string();
  std::vector<sogen_dart_exported_symbol> exports{};
  exports.reserve(module.exports.size());
  for (const auto &symbol : module.exports) {
    exports.push_back({bytes(symbol.name), symbol.name.size(), symbol.ordinal,
                       symbol.rva, symbol.address});
  }

  const sogen_dart_mapped_module value{
      bytes(module.name),
      module.name.size(),
      bytes(path),
      path.size(),
      bytes(module_path),
      module_path.size(),
      module.image_base,
      module.image_base_file,
      module.size_of_image,
      module.entry_point,
      exports.data(),
      exports.size(),
      module.is_static ? 1 : 0,
  };
  callback(user_data, &value);
}

void invoke_text(const sogen_dart_text_callback callback, void *user_data,
                 const std::string_view text) {
  if (callback) {
    callback(user_data, reinterpret_cast<const uint8_t *>(text.data()),
             text.size());
  }
}
} // namespace

windows_callback_registry::windows_callback_registry(windows_emulator &emulator)
    : emulator_(&emulator) {
  this->emulator_->callbacks.on_module_load.add([this](mapped_module &module) {
    invoke_module(this->callbacks_.module_load, this->callbacks_.user_data,
                  module);
  });
  this->emulator_->callbacks.on_module_unload.add(
      [this](mapped_module &module) {
        invoke_module(this->callbacks_.module_unload,
                      this->callbacks_.user_data, module);
      });
  this->emulator_->callbacks.on_stdout = [this](const std::string_view text) {
    invoke_text(this->callbacks_.stdout_callback, this->callbacks_.user_data,
                text);
  };
  this->emulator_->callbacks.on_syscall = [this](const uint32_t id,
                                                 const std::string_view name) {
    const auto callback = this->callbacks_.syscall;
    if (!callback) {
      return instruction_hook_continuation::run_instruction;
    }
    const auto result =
        callback(this->callbacks_.user_data, id,
                 reinterpret_cast<const uint8_t *>(name.data()), name.size());
    if (result < static_cast<int32_t>(
                     instruction_hook_continuation::run_instruction) ||
        result >
            static_cast<int32_t>(
                instruction_hook_continuation::finalized_instruction_pointer)) {
      return instruction_hook_continuation::run_instruction;
    }
    return static_cast<instruction_hook_continuation>(result);
  };
  this->emulator_->callbacks.on_generic_access =
      [this](const std::string_view type, const std::u16string_view name) {
        const auto callback = this->callbacks_.generic_access;
        if (!callback) {
          return;
        }
        const auto name_utf8 = u16_to_u8(name);
        callback(this->callbacks_.user_data,
                 reinterpret_cast<const uint8_t *>(type.data()), type.size(),
                 bytes(name_utf8), name_utf8.size());
      };
  this->emulator_->callbacks.on_generic_activity =
      [this](const std::string_view description) {
        invoke_text(this->callbacks_.generic_activity,
                    this->callbacks_.user_data, description);
      };
  this->emulator_->callbacks.on_suspicious_activity =
      [this](const std::string_view description) {
        invoke_text(this->callbacks_.suspicious_activity,
                    this->callbacks_.user_data, description);
      };
  this->emulator_->callbacks.on_exception = [this] {
    if (this->callbacks_.exception) {
      this->callbacks_.exception(this->callbacks_.user_data);
    }
  };
  this->emulator_->callbacks.on_instruction = [this](const uint64_t address) {
    if (this->callbacks_.instruction) {
      this->callbacks_.instruction(this->callbacks_.user_data, address);
    }
  };
  this->emulator_->callbacks.on_memory_protect =
      [this](const uint64_t address, const uint64_t length,
             const memory_permission permission) {
        if (this->callbacks_.memory_protect) {
          this->callbacks_.memory_protect(this->callbacks_.user_data, address,
                                          length,
                                          static_cast<int32_t>(permission));
        }
      };
  this->emulator_->callbacks.on_memory_allocate =
      [this](const uint64_t address, const uint64_t length,
             const memory_permission permission, const bool commit) {
        if (this->callbacks_.memory_allocate) {
          this->callbacks_.memory_allocate(
              this->callbacks_.user_data, address, length,
              static_cast<int32_t>(permission), commit ? 1 : 0);
        }
      };
  this->emulator_->callbacks
      .on_memory_violate = [this](const uint64_t address, const uint64_t length,
                                  const memory_operation operation,
                                  const memory_violation_type type) {
    const auto callback = this->callbacks_.memory_violate;
    if (!callback) {
      return memory_violation_continuation::resume;
    }
    const auto result =
        callback(this->callbacks_.user_data, address, length,
                 static_cast<int32_t>(operation), static_cast<int32_t>(type));
    if (result < static_cast<int32_t>(memory_violation_continuation::stop) ||
        result > static_cast<int32_t>(memory_violation_continuation::restart)) {
      return memory_violation_continuation::resume;
    }
    return static_cast<memory_violation_continuation>(result);
  };
  this->emulator_->callbacks.on_rdtsc = [this] {
    if (this->callbacks_.rdtsc) {
      this->callbacks_.rdtsc(this->callbacks_.user_data);
    }
  };
  this->emulator_->callbacks.on_rdtscp = [this] {
    if (this->callbacks_.rdtscp) {
      this->callbacks_.rdtscp(this->callbacks_.user_data);
    }
  };
  this->emulator_->callbacks.on_ioctrl =
      [this](io_device &, const std::u16string_view device_name,
             const ULONG code) {
        const auto callback = this->callbacks_.ioctrl;
        if (!callback) {
          return;
        }
        const auto name_utf8 = u16_to_u8(device_name);
        callback(this->callbacks_.user_data, bytes(name_utf8), name_utf8.size(),
                 code);
      };
  this->emulator_->callbacks.on_debug_string.add(
      [this](const std::string_view message) {
        invoke_text(this->callbacks_.debug_string, this->callbacks_.user_data,
                    message);
      });

  if (this->emulator_->process.callbacks_) {
    this->emulator_->process.callbacks_->on_thread_create =
        [this](const handle value, emulator_thread &thread) {
          if (this->callbacks_.thread_create) {
            this->callbacks_.thread_create(
                this->callbacks_.user_data, value.bits, thread.id,
                thread.start_address, thread.argument);
          }
        };
    this->emulator_->process.callbacks_->on_thread_terminated =
        [this](const handle value, emulator_thread &thread) {
          if (this->callbacks_.thread_terminated) {
            this->callbacks_.thread_terminated(this->callbacks_.user_data,
                                               value.bits, thread.id);
          }
        };
    this->emulator_->process.callbacks_->on_thread_set_name =
        [this](emulator_thread &thread) {
          const auto callback = this->callbacks_.thread_set_name;
          if (!callback) {
            return;
          }
          const auto name_utf8 = u16_to_u8(thread.name);
          callback(this->callbacks_.user_data, thread.id, bytes(name_utf8),
                   name_utf8.size());
        };
    this->emulator_->process.callbacks_->on_thread_switch =
        [this](emulator_thread &current_thread, emulator_thread &new_thread) {
          if (this->callbacks_.thread_switch) {
            this->callbacks_.thread_switch(this->callbacks_.user_data,
                                           current_thread.id, new_thread.id);
          }
        };
  }
}

void windows_callback_registry::set(
    const sogen_dart_windows_callbacks *callbacks) {
  this->callbacks_ = callbacks ? *callbacks : sogen_dart_windows_callbacks{};
}
} // namespace sogen::dart
