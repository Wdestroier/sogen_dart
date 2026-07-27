#include <sogen_dart.h>

#include "api_hook_registry.hpp"
#include "app.hpp"
#include "error.hpp"
#include "linux_callbacks.hpp"
#include "linux_runtime.hpp"
#include "windows_callbacks.hpp"

#include <algorithm>
#include <array>
#include <cstring>
#include <filesystem>
#include <memory>
#include <span>
#include <stdexcept>
#include <string>

#include <backend_selection.hpp>
#include <platform/unicode.hpp>
#include <serialization.hpp>
#include <windows_emulator.hpp>

sogen_dart_app::sogen_dart_app() = default;

sogen_dart_app::~sogen_dart_app() {
  if (this->windows) {
    for (const auto &[_, hook] : this->low_hooks) {
      this->windows->emu().delete_hook(
          static_cast<sogen::emulator_hook *>(hook));
    }
  }
  this->low_hooks.clear();
}

namespace {
std::filesystem::path path_from_utf8(const char *value) {
  const auto *begin = reinterpret_cast<const char8_t *>(value);
  return std::filesystem::path{
      std::u8string{begin, begin + std::strlen(value)}};
}

std::string path_to_utf8(const std::filesystem::path &value) {
  const auto utf8 = value.u8string();
  return {reinterpret_cast<const char *>(utf8.data()), utf8.size()};
}

sogen::backend_type to_backend(const int32_t value) {
  switch (value) {
  case SOGEN_DART_BACKEND_UNICORN:
    return sogen::backend_type::unicorn;
  case SOGEN_DART_BACKEND_ICICLE:
    return sogen::backend_type::icicle;
  case SOGEN_DART_BACKEND_WHP:
    return sogen::backend_type::whp;
  case SOGEN_DART_BACKEND_KVM:
    return sogen::backend_type::kvm;
  default:
    throw std::invalid_argument("Invalid backend");
  }
}

template <typename T>
void require_array(const T *values, const size_t count, const char *name) {
  if (count != 0 && !values) {
    throw std::invalid_argument(std::string{name} +
                                " pointer is required when count is non-zero");
  }
}

sogen::emulator_settings make_windows_emulator_settings(
    const sogen_dart_windows_emulator_options &options) {
  if (!options.emulation_root_utf8 || !options.registry_directory_utf8) {
    throw std::invalid_argument(
        "Emulation root and registry directory are required");
  }
  require_array(options.path_mappings, options.path_mapping_count,
                "Windows path mappings");
  require_array(options.port_mappings, options.port_mapping_count,
                "Windows port mappings");

  sogen::emulator_settings settings{};
  settings.emulation_root = path_from_utf8(options.emulation_root_utf8);
  settings.registry_directory = path_from_utf8(options.registry_directory_utf8);
  settings.disable_logging = options.disable_logging != 0;
  settings.use_relative_time = options.use_relative_time != 0;
  settings.fake_env.number_of_processors = options.number_of_processors;
  settings.fake_env.nt_product_type =
      static_cast<uint8_t>(options.nt_product_type);

  for (size_t index = 0; index < options.path_mapping_count; ++index) {
    const auto &mapping = options.path_mappings[index];
    if (!mapping.guest_path_utf8 || !mapping.host_path_utf8) {
      throw std::invalid_argument(
          "Windows path mapping guest and host paths are required");
    }
    settings.path_mappings.emplace(path_from_utf8(mapping.guest_path_utf8),
                                   path_from_utf8(mapping.host_path_utf8));
  }
  for (size_t index = 0; index < options.port_mapping_count; ++index) {
    const auto &mapping = options.port_mappings[index];
    settings.port_mappings.emplace(mapping.emulator_port, mapping.host_port);
  }
  return settings;
}

sogen::application_settings make_windows_application_settings(
    const sogen_dart_windows_application_options &options) {
  if (!options.application_utf8 || !options.working_directory_utf8) {
    throw std::invalid_argument(
        "Application and working directory are required");
  }
  require_array(options.arguments_utf8, options.argument_count,
                "Windows application arguments");
  require_array(options.environment, options.environment_count,
                "Windows environment");

  sogen::application_settings settings{};
  settings.application = path_from_utf8(options.application_utf8);
  settings.working_directory = path_from_utf8(options.working_directory_utf8);
  settings.arguments.reserve(options.argument_count);
  for (size_t index = 0; index < options.argument_count; ++index) {
    if (!options.arguments_utf8[index]) {
      throw std::invalid_argument(
          "Windows application arguments cannot contain null strings");
    }
    settings.arguments.emplace_back(
        sogen::u8_to_u16(options.arguments_utf8[index]));
  }
  for (size_t index = 0; index < options.environment_count; ++index) {
    const auto &entry = options.environment[index];
    if (!entry.name_utf8 || !entry.value_utf8) {
      throw std::invalid_argument(
          "Windows environment names and values are required");
    }
    settings.environment.emplace(sogen::u8_to_u16(entry.name_utf8),
                                 sogen::u8_to_u16(entry.value_utf8));
  }
  return settings;
}

sogen::memory_permission to_memory_permission(const int32_t value) {
  if (value < 0 || (value & ~7) != 0) {
    throw std::invalid_argument("Invalid memory permission");
  }
  return static_cast<sogen::memory_permission>(value);
}

sogen::memory_region_kind to_memory_region_kind(const int32_t value) {
  if (value < 0 ||
      value > static_cast<int32_t>(sogen::memory_region_kind::mmio)) {
    throw std::invalid_argument("Invalid memory region kind");
  }
  return static_cast<sogen::memory_region_kind>(value);
}

sogen::x86_register to_register(const int32_t value) {
  using enum sogen::x86_register;
  static constexpr std::array registers{
      invalid, rax,    rbx,   rcx,   rdx,   rsi,   rdi,  rbp,  rsp,
      rip,     r8,     r9,    r10,   r11,   r12,   r13,  r14,  r15,
      eax,     ebx,    ecx,   edx,   esi,   edi,   ebp,  esp,  eip,
      eflags,  rflags, cs,    ss,    ds,    es,    fs,   gs,   xmm0,
      xmm1,    xmm2,   xmm3,  xmm4,  xmm5,  xmm6,  xmm7, xmm8, xmm9,
      xmm10,   xmm11,  xmm12, xmm13, xmm14, xmm15,
  };
  if (value < 0 || static_cast<size_t>(value) >= registers.size()) {
    throw std::invalid_argument("Invalid register");
  }
  return registers[static_cast<size_t>(value)];
}

void set_buffer(sogen_dart_buffer *output, const void *data,
                const size_t length) {
  if (!output) {
    throw std::invalid_argument("Buffer output pointer is required");
  }
  output->data = nullptr;
  output->length = 0;
  if (length == 0) {
    return;
  }

  auto bytes = std::make_unique<uint8_t[]>(length);
  std::memcpy(bytes.get(), data, length);
  output->data = bytes.release();
  output->length = length;
}

void set_buffer(sogen_dart_buffer *output, const std::string &value) {
  set_buffer(output, value.data(), value.size());
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

void require_app(const sogen_dart_app *app) {
  if (!app || !app->windows || !app->callbacks || !app->api_hooks) {
    throw std::invalid_argument("A valid Windows application is required");
  }
}

void require_mutable(const sogen_dart_app *app) {
  require_app(app);
  if (app->running) {
    throw std::logic_error(
        "Hooks cannot be changed while the emulator is running");
  }
  if (app->api_hooks->in_callback()) {
    throw std::logic_error("Hooks cannot be changed from a callback");
  }
}

void remove_low_hook(sogen_dart_app *app, const sogen_dart_hook_id id) {
  const auto found = app->low_hooks.find(id);
  if (found == app->low_hooks.end()) {
    return;
  }
  app->windows->emu().delete_hook(
      static_cast<sogen::emulator_hook *>(found->second));
  app->low_hooks.erase(found);
}

bool low_hook_active(const sogen_dart_app *app, const sogen_dart_hook_id id) {
  return std::ranges::find(app->deferred_hook_removals, id) ==
         app->deferred_hook_removals.end();
}

void flush_low_hook_removals(sogen_dart_app *app) {
  auto removals = std::move(app->deferred_hook_removals);
  app->deferred_hook_removals.clear();
  for (const auto id : removals) {
    remove_low_hook(app, id);
  }
}

struct low_callback_scope {
  sogen_dart_app *app;

  explicit low_callback_scope(sogen_dart_app *value) : app(value) {
    this->app->in_low_hook_callback = true;
  }

  ~low_callback_scope() { this->app->in_low_hook_callback = false; }
};

sogen_dart_hook_id store_low_hook(sogen_dart_app *app,
                                  sogen::emulator_hook *hook) {
  const auto id = app->next_low_hook_id++;
  app->low_hooks.emplace(id, hook);
  return id;
}

} // namespace

extern "C" {
uint32_t sogen_dart_abi_version(void) { return SOGEN_DART_ABI_VERSION; }

sogen_dart_status
sogen_dart_windows_create_application(const char *application_utf8,
                                      const char *emulation_root_utf8,
                                      sogen_dart_app **out_app) {
  if (!application_utf8 || !emulation_root_utf8 || !out_app) {
    return sogen::dart::fail(
        SOGEN_DART_INVALID_ARGUMENT,
        "Application, emulation root, and output pointer are required");
  }
  *out_app = nullptr;

  return guarded([&] {
    sogen::application_settings application_settings{};
    application_settings.application = path_from_utf8(application_utf8);

    sogen::emulator_settings emulator_settings{};
    emulator_settings.emulation_root = path_from_utf8(emulation_root_utf8);

    auto app = std::make_unique<sogen_dart_app>();
    app->windows = std::make_unique<sogen::windows_emulator>(
        sogen::create_x86_64_emulator(sogen::backend_type::unicorn),
        std::move(application_settings), emulator_settings);
    app->callbacks =
        std::make_unique<sogen::dart::windows_callback_registry>(*app->windows);
    app->api_hooks =
        std::make_unique<sogen::dart::api_hook_registry>(*app->windows);
    *out_app = app.release();
  });
}

sogen_dart_status
sogen_dart_windows_create_empty(const char *emulation_root_utf8,
                                const int32_t backend,
                                sogen_dart_app **out_app) {
  if (!emulation_root_utf8 || !out_app) {
    return sogen::dart::fail(SOGEN_DART_INVALID_ARGUMENT,
                             "Emulation root and output pointer are required");
  }
  *out_app = nullptr;

  return guarded([&] {
    sogen::emulator_settings settings{};
    settings.emulation_root = path_from_utf8(emulation_root_utf8);
    auto app = std::make_unique<sogen_dart_app>();
    app->windows = std::make_unique<sogen::windows_emulator>(
        sogen::create_x86_64_emulator(to_backend(backend)), settings);
    app->callbacks =
        std::make_unique<sogen::dart::windows_callback_registry>(*app->windows);
    app->api_hooks =
        std::make_unique<sogen::dart::api_hook_registry>(*app->windows);
    *out_app = app.release();
  });
}

sogen_dart_status sogen_dart_windows_create_application_ex(
    const char *application_utf8, const char *emulation_root_utf8,
    const int32_t backend, sogen_dart_app **out_app) {
  if (!application_utf8 || !emulation_root_utf8 || !out_app) {
    return sogen::dart::fail(
        SOGEN_DART_INVALID_ARGUMENT,
        "Application, emulation root, and output pointer are required");
  }
  *out_app = nullptr;

  return guarded([&] {
    sogen::application_settings application_settings{};
    application_settings.application = path_from_utf8(application_utf8);
    sogen::emulator_settings emulator_settings{};
    emulator_settings.emulation_root = path_from_utf8(emulation_root_utf8);
    auto app = std::make_unique<sogen_dart_app>();
    app->windows = std::make_unique<sogen::windows_emulator>(
        sogen::create_x86_64_emulator(to_backend(backend)),
        std::move(application_settings), emulator_settings);
    app->callbacks =
        std::make_unique<sogen::dart::windows_callback_registry>(*app->windows);
    app->api_hooks =
        std::make_unique<sogen::dart::api_hook_registry>(*app->windows);
    *out_app = app.release();
  });
}

sogen_dart_status sogen_dart_windows_create_empty_with_options(
    const sogen_dart_windows_emulator_options *options,
    sogen_dart_app **out_app) {
  if (!options || !out_app) {
    return sogen::dart::fail(
        SOGEN_DART_INVALID_ARGUMENT,
        "Windows emulator options and output pointer are required");
  }
  *out_app = nullptr;

  return guarded([&] {
    auto settings = make_windows_emulator_settings(*options);
    auto app = std::make_unique<sogen_dart_app>();
    app->windows = std::make_unique<sogen::windows_emulator>(
        sogen::create_x86_64_emulator(to_backend(options->backend)), settings);
    app->callbacks =
        std::make_unique<sogen::dart::windows_callback_registry>(*app->windows);
    app->api_hooks =
        std::make_unique<sogen::dart::api_hook_registry>(*app->windows);
    *out_app = app.release();
  });
}

sogen_dart_status sogen_dart_windows_create_application_with_options(
    const sogen_dart_windows_application_options *application_options,
    const sogen_dart_windows_emulator_options *emulator_options,
    sogen_dart_app **out_app) {
  if (!application_options || !emulator_options || !out_app) {
    return sogen::dart::fail(SOGEN_DART_INVALID_ARGUMENT,
                             "Windows application options, emulator options, "
                             "and output pointer are required");
  }
  *out_app = nullptr;

  return guarded([&] {
    auto application_settings =
        make_windows_application_settings(*application_options);
    auto emulator_settings = make_windows_emulator_settings(*emulator_options);
    auto app = std::make_unique<sogen_dart_app>();
    app->windows = std::make_unique<sogen::windows_emulator>(
        sogen::create_x86_64_emulator(to_backend(emulator_options->backend)),
        std::move(application_settings), emulator_settings);
    app->callbacks =
        std::make_unique<sogen::dart::windows_callback_registry>(*app->windows);
    app->api_hooks =
        std::make_unique<sogen::dart::api_hook_registry>(*app->windows);
    *out_app = app.release();
  });
}

sogen_dart_status sogen_dart_windows_add_api_hook(
    sogen_dart_app *app, const char *key_utf8, const int32_t calling_convention,
    const size_t parameter_count, const sogen_dart_api_callback callback,
    void *user_data, sogen_dart_hook_id *out_hook) {
  if (!key_utf8 || !callback || !out_hook) {
    return sogen::dart::fail(
        SOGEN_DART_INVALID_ARGUMENT,
        "Hook key, callback, and output pointer are required");
  }
  *out_hook = 0;

  return guarded([&] {
    require_mutable(app);
    *out_hook = app->api_hooks->set(key_utf8, calling_convention,
                                    parameter_count, callback, user_data);
  });
}

sogen_dart_status
sogen_dart_windows_remove_hook(sogen_dart_app *app,
                               const sogen_dart_hook_id hook) {
  return guarded([&] {
    require_app(app);
    if (app->low_hooks.contains(hook)) {
      if (app->in_low_hook_callback) {
        app->deferred_hook_removals.push_back(hook);
        return;
      }
      if (app->running) {
        throw std::logic_error(
            "A low-level hook can only remove itself while running");
      }
      remove_low_hook(app, hook);
      return;
    }
    require_mutable(app);
    app->api_hooks->remove(hook);
  });
}

sogen_dart_status sogen_dart_windows_clear_api_hooks(sogen_dart_app *app) {
  return guarded([&] {
    require_mutable(app);
    app->api_hooks->clear();
  });
}

sogen_dart_status sogen_dart_windows_set_callbacks(
    sogen_dart_app *app, const sogen_dart_windows_callbacks *callbacks) {
  return guarded([&] {
    require_app(app);
    app->callbacks->set(callbacks);
  });
}

sogen_dart_status sogen_dart_windows_hook_memory_execution(
    sogen_dart_app *app, const int32_t has_address, const uint64_t address,
    const sogen_dart_execution_callback callback, void *user_data,
    sogen_dart_hook_id *out_hook) {
  if (!callback || !out_hook) {
    return sogen::dart::fail(SOGEN_DART_INVALID_ARGUMENT,
                             "Callback and hook output pointer are required");
  }
  return guarded([&] {
    require_mutable(app);
    const auto id = app->next_low_hook_id;
    const auto invoke = [app, id, callback,
                         user_data](sogen::cpu_interface &,
                                    const uint64_t hit_address) {
      if (!low_hook_active(app, id)) {
        return;
      }
      const low_callback_scope scope{app};
      callback(user_data, id, hit_address);
    };
    auto *hook =
        has_address ? app->windows->emu().hook_memory_execution(address, invoke)
                    : app->windows->emu().hook_memory_execution(invoke);
    *out_hook = store_low_hook(app, hook);
  });
}

sogen_dart_status sogen_dart_windows_hook_memory_read(
    sogen_dart_app *app, const uint64_t address, const uint64_t size,
    const sogen_dart_memory_callback callback, void *user_data,
    sogen_dart_hook_id *out_hook) {
  if (!callback || !out_hook) {
    return sogen::dart::fail(SOGEN_DART_INVALID_ARGUMENT,
                             "Callback and hook output pointer are required");
  }
  return guarded([&] {
    require_mutable(app);
    const auto id = app->next_low_hook_id;
    auto *hook = app->windows->emu().hook_memory_read(
        address, size,
        [app, id, callback, user_data](sogen::cpu_interface &,
                                       const uint64_t hit_address,
                                       const void *data, const size_t length) {
          if (!low_hook_active(app, id)) {
            return;
          }
          const low_callback_scope scope{app};
          callback(user_data, id, hit_address,
                   static_cast<const uint8_t *>(data), length);
        });
    *out_hook = store_low_hook(app, hook);
  });
}

sogen_dart_status sogen_dart_windows_hook_memory_write(
    sogen_dart_app *app, const uint64_t address, const uint64_t size,
    const sogen_dart_memory_callback callback, void *user_data,
    sogen_dart_hook_id *out_hook) {
  if (!callback || !out_hook) {
    return sogen::dart::fail(SOGEN_DART_INVALID_ARGUMENT,
                             "Callback and hook output pointer are required");
  }
  return guarded([&] {
    require_mutable(app);
    const auto id = app->next_low_hook_id;
    auto *hook = app->windows->emu().hook_memory_write(
        address, size,
        [app, id, callback, user_data](sogen::cpu_interface &,
                                       const uint64_t hit_address,
                                       const void *data, const size_t length) {
          if (!low_hook_active(app, id)) {
            return;
          }
          const low_callback_scope scope{app};
          callback(user_data, id, hit_address,
                   static_cast<const uint8_t *>(data), length);
        });
    *out_hook = store_low_hook(app, hook);
  });
}

sogen_dart_status sogen_dart_windows_hook_instruction(
    sogen_dart_app *app, const int32_t instruction,
    const sogen_dart_instruction_callback callback, void *user_data,
    sogen_dart_hook_id *out_hook) {
  if (!callback || !out_hook || instruction < 0 || instruction > 4) {
    return sogen::dart::fail(
        SOGEN_DART_INVALID_ARGUMENT,
        "Valid instruction, callback, and output are required");
  }
  return guarded([&] {
    require_mutable(app);
    const auto id = app->next_low_hook_id;
    auto *hook = app->windows->emu().hook_instruction(
        static_cast<sogen::x86_hookable_instructions>(instruction),
        [app, id, callback, user_data](sogen::cpu_interface &,
                                       const uint64_t data) {
          if (!low_hook_active(app, id)) {
            return sogen::instruction_hook_continuation::run_instruction;
          }
          const low_callback_scope scope{app};
          const auto result = callback(user_data, id, data);
          if (result < 0 || result > 2) {
            return sogen::instruction_hook_continuation::run_instruction;
          }
          return static_cast<sogen::instruction_hook_continuation>(result);
        });
    *out_hook = store_low_hook(app, hook);
  });
}

sogen_dart_status sogen_dart_windows_hook_interrupt(
    sogen_dart_app *app, const sogen_dart_interrupt_callback callback,
    void *user_data, sogen_dart_hook_id *out_hook) {
  if (!callback || !out_hook) {
    return sogen::dart::fail(SOGEN_DART_INVALID_ARGUMENT,
                             "Callback and hook output pointer are required");
  }
  return guarded([&] {
    require_mutable(app);
    const auto id = app->next_low_hook_id;
    auto *hook = app->windows->emu().hook_interrupt(
        [app, id, callback, user_data](sogen::cpu_interface &,
                                       const int interrupt_number) {
          if (!low_hook_active(app, id)) {
            return;
          }
          const low_callback_scope scope{app};
          callback(user_data, id, interrupt_number);
        });
    *out_hook = store_low_hook(app, hook);
  });
}

sogen_dart_status sogen_dart_windows_hook_memory_violation(
    sogen_dart_app *app, const sogen_dart_memory_violation_callback callback,
    void *user_data, sogen_dart_hook_id *out_hook) {
  if (!callback || !out_hook) {
    return sogen::dart::fail(SOGEN_DART_INVALID_ARGUMENT,
                             "Callback and hook output pointer are required");
  }
  return guarded([&] {
    require_mutable(app);
    const auto id = app->next_low_hook_id;
    auto *hook = app->windows->emu().hook_memory_violation(
        [app, id, callback,
         user_data](sogen::cpu_interface &, const uint64_t address,
                    const size_t size, const sogen::memory_operation operation,
                    const sogen::memory_violation_type type) {
          if (!low_hook_active(app, id)) {
            return sogen::memory_violation_continuation::resume;
          }
          const low_callback_scope scope{app};
          const auto result = callback(user_data, id, address, size,
                                       static_cast<int32_t>(operation),
                                       static_cast<int32_t>(type));
          if (result < 0 || result > 2) {
            return sogen::memory_violation_continuation::stop;
          }
          return static_cast<sogen::memory_violation_continuation>(result);
        });
    *out_hook = store_low_hook(app, hook);
  });
}

sogen_dart_status sogen_dart_windows_hook_basic_block(
    sogen_dart_app *app, const sogen_dart_basic_block_callback callback,
    void *user_data, sogen_dart_hook_id *out_hook) {
  if (!callback || !out_hook) {
    return sogen::dart::fail(SOGEN_DART_INVALID_ARGUMENT,
                             "Callback and hook output pointer are required");
  }
  return guarded([&] {
    require_mutable(app);
    const auto id = app->next_low_hook_id;
    auto *hook = app->windows->emu().hook_basic_block(
        [app, id, callback, user_data](sogen::cpu_interface &,
                                       const sogen::basic_block &block) {
          if (!low_hook_active(app, id)) {
            return;
          }
          const low_callback_scope scope{app};
          callback(user_data, id, block.address, block.instruction_count,
                   block.size);
        });
    *out_hook = store_low_hook(app, hook);
  });
}

sogen_dart_status sogen_dart_windows_start(sogen_dart_app *app,
                                           const size_t instruction_count) {
  return guarded([&] {
    require_app(app);
    if (app->running) {
      throw std::logic_error("The emulator is already running");
    }
    app->running = true;
    try {
      app->windows->start(instruction_count);
    } catch (...) {
      app->running = false;
      flush_low_hook_removals(app);
      throw;
    }
    app->running = false;
    flush_low_hook_removals(app);
  });
}

sogen_dart_status sogen_dart_windows_stop(sogen_dart_app *app) {
  return guarded([&] {
    require_app(app);
    app->windows->stop();
  });
}

sogen_dart_status sogen_dart_windows_save_snapshot(sogen_dart_app *app) {
  return guarded([&] {
    require_mutable(app);
    app->windows->save_snapshot();
  });
}

sogen_dart_status sogen_dart_windows_restore_snapshot(sogen_dart_app *app) {
  return guarded([&] {
    require_mutable(app);
    app->windows->restore_snapshot();
    app->api_hooks->refresh();
  });
}

sogen_dart_status
sogen_dart_windows_serialize_state(sogen_dart_app *app,
                                   sogen_dart_buffer *out_buffer) {
  if (out_buffer) {
    *out_buffer = {};
  }
  return guarded([&] {
    require_mutable(app);
    sogen::utils::buffer_serializer serializer{};
    app->windows->serialize(serializer);
    const auto bytes = serializer.move_buffer();
    set_buffer(out_buffer, bytes.data(), bytes.size());
  });
}

sogen_dart_status sogen_dart_windows_deserialize_state(sogen_dart_app *app,
                                                       const uint8_t *data,
                                                       const size_t length) {
  if (!data && length != 0) {
    return sogen::dart::fail(SOGEN_DART_INVALID_ARGUMENT,
                             "State data is required");
  }
  return guarded([&] {
    require_mutable(app);
    const auto *begin = reinterpret_cast<const std::byte *>(data);
    sogen::utils::buffer_deserializer deserializer{
        std::span(begin, begin + length)};
    app->windows->deserialize(deserializer);
    app->api_hooks->refresh();
  });
}

sogen_dart_status sogen_dart_windows_setup_process(sogen_dart_app *app) {
  return guarded([&] {
    require_mutable(app);
    app->windows->setup_process_if_necessary();
  });
}

sogen_dart_status sogen_dart_windows_yield_thread(sogen_dart_app *app,
                                                  const int32_t alertable) {
  return guarded([&] {
    require_app(app);
    app->windows->yield_thread(app->windows->vcpu(0), alertable != 0);
  });
}

sogen_dart_status sogen_dart_windows_perform_thread_switch(sogen_dart_app *app,
                                                           int32_t *switched) {
  if (!switched) {
    return sogen::dart::fail(SOGEN_DART_INVALID_ARGUMENT,
                             "Switch output pointer is required");
  }
  return guarded([&] {
    require_app(app);
    *switched =
        app->windows->perform_thread_switch(app->windows->vcpu(0)) ? 1 : 0;
  });
}

sogen_dart_status sogen_dart_windows_activate_thread(sogen_dart_app *app,
                                                     const uint32_t id,
                                                     int32_t *activated) {
  if (!activated) {
    return sogen::dart::fail(SOGEN_DART_INVALID_ARGUMENT,
                             "Activation output pointer is required");
  }
  return guarded([&] {
    require_app(app);
    *activated =
        app->windows->activate_thread(app->windows->vcpu(0), id) ? 1 : 0;
  });
}

sogen_dart_status sogen_dart_windows_read_memory(sogen_dart_app *app,
                                                 const uint64_t address,
                                                 uint8_t *destination,
                                                 const size_t length) {
  if (!destination && length != 0) {
    return sogen::dart::fail(SOGEN_DART_INVALID_ARGUMENT,
                             "Memory destination is required");
  }
  return guarded([&] {
    require_app(app);
    app->windows->memory.read_memory(address, destination, length);
  });
}

sogen_dart_status sogen_dart_windows_write_memory(sogen_dart_app *app,
                                                  const uint64_t address,
                                                  const uint8_t *source,
                                                  const size_t length) {
  if (!source && length != 0) {
    return sogen::dart::fail(SOGEN_DART_INVALID_ARGUMENT,
                             "Memory source is required");
  }
  return guarded([&] {
    require_app(app);
    app->windows->memory.write_memory(address, source, length);
  });
}

sogen_dart_status sogen_dart_windows_read_register(sogen_dart_app *app,
                                                   const int32_t reg,
                                                   uint64_t *value) {
  if (!value) {
    return sogen::dart::fail(SOGEN_DART_INVALID_ARGUMENT,
                             "Register output pointer is required");
  }
  return guarded([&] {
    require_app(app);
    *value = app->windows->emu().reg<uint64_t>(to_register(reg));
  });
}

sogen_dart_status sogen_dart_windows_write_register(sogen_dart_app *app,
                                                    const int32_t reg,
                                                    const uint64_t value) {
  return guarded([&] {
    require_app(app);
    app->windows->emu().reg<uint64_t>(to_register(reg), value);
  });
}

sogen_dart_status
sogen_dart_windows_get_executed_instructions(sogen_dart_app *app,
                                             uint64_t *value) {
  if (!value) {
    return sogen::dart::fail(SOGEN_DART_INVALID_ARGUMENT,
                             "Instruction output pointer is required");
  }
  return guarded([&] {
    require_app(app);
    *value = app->windows->get_executed_instructions();
  });
}

sogen_dart_status
sogen_dart_windows_get_backend_name(sogen_dart_app *app,
                                    sogen_dart_buffer *out_buffer) {
  if (out_buffer) {
    *out_buffer = {};
  }
  return guarded([&] {
    require_app(app);
    set_buffer(out_buffer, app->windows->emu().get_name());
  });
}

sogen_dart_status
sogen_dart_windows_get_emulation_root(sogen_dart_app *app,
                                      sogen_dart_buffer *out_buffer) {
  if (out_buffer) {
    *out_buffer = {};
  }
  return guarded([&] {
    require_app(app);
    set_buffer(out_buffer, path_to_utf8(app->windows->emulation_root));
  });
}

sogen_dart_status
sogen_dart_windows_get_last_stop_detail(sogen_dart_app *app,
                                        sogen_dart_buffer *out_buffer) {
  if (out_buffer) {
    *out_buffer = {};
  }
  return guarded([&] {
    require_app(app);
    set_buffer(out_buffer, app->windows->last_stop_detail());
  });
}

sogen_dart_status sogen_dart_windows_get_host_port(sogen_dart_app *app,
                                                   const uint16_t emulator_port,
                                                   uint16_t *host_port) {
  if (!host_port) {
    return sogen::dart::fail(SOGEN_DART_INVALID_ARGUMENT,
                             "Host port output pointer is required");
  }
  return guarded([&] {
    require_app(app);
    *host_port = app->windows->get_host_port(emulator_port);
  });
}

sogen_dart_status sogen_dart_windows_get_emulator_port(
    sogen_dart_app *app, const uint16_t host_port, uint16_t *emulator_port) {
  if (!emulator_port) {
    return sogen::dart::fail(SOGEN_DART_INVALID_ARGUMENT,
                             "Emulator port output pointer is required");
  }
  return guarded([&] {
    require_app(app);
    *emulator_port = app->windows->get_emulator_port(host_port);
  });
}

sogen_dart_status sogen_dart_windows_map_port(sogen_dart_app *app,
                                              const uint16_t emulator_port,
                                              const uint16_t host_port) {
  return guarded([&] {
    require_app(app);
    app->windows->map_port(emulator_port, host_port);
  });
}

sogen_dart_status sogen_dart_windows_memory_allocate(
    sogen_dart_app *app, const size_t size, const int32_t permissions,
    const int32_t reserve_only, const uint64_t start, const int32_t kind,
    uint64_t *address) {
  if (!address) {
    return sogen::dart::fail(SOGEN_DART_INVALID_ARGUMENT,
                             "Allocation output pointer is required");
  }
  return guarded([&] {
    require_app(app);
    *address = app->windows->memory.allocate_memory(
        size, sogen::nt_memory_permission{to_memory_permission(permissions)},
        reserve_only != 0, start, to_memory_region_kind(kind));
  });
}

sogen_dart_status sogen_dart_windows_memory_protect(sogen_dart_app *app,
                                                    const uint64_t address,
                                                    const size_t size,
                                                    const int32_t permissions,
                                                    int32_t *success) {
  if (!success) {
    return sogen::dart::fail(SOGEN_DART_INVALID_ARGUMENT,
                             "Protection output pointer is required");
  }
  return guarded([&] {
    require_app(app);
    *success =
        app->windows->memory.protect_memory(
            address, size,
            sogen::nt_memory_permission{to_memory_permission(permissions)})
            ? 1
            : 0;
  });
}

sogen_dart_status sogen_dart_windows_memory_commit(sogen_dart_app *app,
                                                   const uint64_t address,
                                                   const size_t size,
                                                   const int32_t permissions,
                                                   int32_t *success) {
  if (!success) {
    return sogen::dart::fail(SOGEN_DART_INVALID_ARGUMENT,
                             "Commit output pointer is required");
  }
  return guarded([&] {
    require_app(app);
    *success =
        app->windows->memory.commit_memory(
            address, size,
            sogen::nt_memory_permission{to_memory_permission(permissions)})
            ? 1
            : 0;
  });
}

sogen_dart_status sogen_dart_windows_memory_decommit(sogen_dart_app *app,
                                                     const uint64_t address,
                                                     const size_t size,
                                                     int32_t *success) {
  if (!success) {
    return sogen::dart::fail(SOGEN_DART_INVALID_ARGUMENT,
                             "Decommit output pointer is required");
  }
  return guarded([&] {
    require_app(app);
    *success = app->windows->memory.decommit_memory(address, size) ? 1 : 0;
  });
}

sogen_dart_status sogen_dart_windows_memory_release(sogen_dart_app *app,
                                                    const uint64_t address,
                                                    const size_t size,
                                                    int32_t *success) {
  if (!success) {
    return sogen::dart::fail(SOGEN_DART_INVALID_ARGUMENT,
                             "Release output pointer is required");
  }
  return guarded([&] {
    require_app(app);
    *success = app->windows->memory.release_memory(address, size) ? 1 : 0;
  });
}

sogen_dart_status sogen_dart_windows_memory_find_free_base(sogen_dart_app *app,
                                                           const size_t size,
                                                           const uint64_t start,
                                                           uint64_t *address) {
  if (!address) {
    return sogen::dart::fail(SOGEN_DART_INVALID_ARGUMENT,
                             "Free-base output pointer is required");
  }
  return guarded([&] {
    require_app(app);
    *address = app->windows->memory.find_free_allocation_base(size, start);
  });
}

sogen_dart_status
sogen_dart_windows_memory_get_region(sogen_dart_app *app,
                                     const uint64_t address,
                                     sogen_dart_memory_region *region) {
  if (!region) {
    return sogen::dart::fail(SOGEN_DART_INVALID_ARGUMENT,
                             "Region output pointer is required");
  }
  return guarded([&] {
    require_app(app);
    const auto native = app->windows->memory.get_region_info(address);
    *region = {
        native.start,
        native.length,
        static_cast<int32_t>(native.permissions.common),
        native.allocation_base,
        native.allocation_length,
        native.is_reserved ? 1 : 0,
        native.is_committed ? 1 : 0,
        static_cast<int32_t>(native.initial_permissions.common),
        static_cast<int32_t>(native.kind),
    };
  });
}

sogen_dart_status
sogen_dart_windows_memory_get_stats(sogen_dart_app *app,
                                    sogen_dart_memory_stats *stats) {
  if (!stats) {
    return sogen::dart::fail(SOGEN_DART_INVALID_ARGUMENT,
                             "Memory stats output pointer is required");
  }
  return guarded([&] {
    require_app(app);
    const auto native = app->windows->memory.compute_memory_stats();
    *stats = {native.reserved_memory, native.committed_memory};
  });
}

sogen_dart_status
sogen_dart_windows_memory_get_default_address(sogen_dart_app *app,
                                              uint64_t *address) {
  if (!address) {
    return sogen::dart::fail(SOGEN_DART_INVALID_ARGUMENT,
                             "Default address output pointer is required");
  }
  return guarded([&] {
    require_app(app);
    *address = app->windows->memory.get_default_allocation_address();
  });
}

sogen_dart_status
sogen_dart_windows_memory_set_default_address(sogen_dart_app *app,
                                              const uint64_t address) {
  return guarded([&] {
    require_app(app);
    app->windows->memory.set_default_allocation_address(address);
  });
}

sogen_dart_status
sogen_dart_windows_get_process_info(sogen_dart_app *app,
                                    sogen_dart_windows_process_info *info) {
  if (!info) {
    return sogen::dart::fail(SOGEN_DART_INVALID_ARGUMENT,
                             "Process info output pointer is required");
  }
  return guarded([&] {
    require_app(app);
    const auto *active = app->windows->vcpu(0).active_thread;
    *info = {
        app->windows->process.is_wow64_process ? 1 : 0,
        app->windows->process.exit_status ? 1 : 0,
        app->windows->process.exit_status.value_or(0),
        app->windows->process.get_live_thread_count(),
        app->windows->process.spawned_thread_count,
        active ? 1 : 0,
        active ? active->id : 0,
    };
  });
}

sogen_dart_status sogen_dart_windows_get_current_thread_info(
    sogen_dart_app *app, int32_t *has_value,
    sogen_dart_windows_thread_info *info) {
  if (!has_value || !info) {
    return sogen::dart::fail(SOGEN_DART_INVALID_ARGUMENT,
                             "Thread info output pointers are required");
  }
  return guarded([&] {
    require_app(app);
    const auto *thread = app->windows->vcpu(0).active_thread;
    *has_value = thread ? 1 : 0;
    if (!thread) {
      *info = {};
      return;
    }
    *info = {
        thread->id,
        thread->start_address,
        thread->argument,
        thread->executed_instructions,
        thread->current_ip,
        thread->previous_ip,
        thread->setup_done ? 1 : 0,
        thread->exit_status ? 1 : 0,
        thread->exit_status.value_or(0),
    };
  });
}

sogen_dart_status
sogen_dart_windows_get_current_thread_name(sogen_dart_app *app,
                                           sogen_dart_buffer *out_buffer) {
  if (out_buffer) {
    *out_buffer = {};
  }
  return guarded([&] {
    require_app(app);
    const auto *thread = app->windows->vcpu(0).active_thread;
    set_buffer(out_buffer,
               thread ? sogen::u16_to_u8(thread->name) : std::string{});
  });
}

sogen_dart_status sogen_dart_windows_get_exit_status(sogen_dart_app *app,
                                                     int32_t *has_value,
                                                     int32_t *value) {
  if (!has_value || !value) {
    return sogen::dart::fail(SOGEN_DART_INVALID_ARGUMENT,
                             "Exit status output pointers are required");
  }

  return guarded([&] {
    require_app(app);
    *has_value = app->windows->process.exit_status.has_value() ? 1 : 0;
    *value = app->windows->process.exit_status
                 ? static_cast<int32_t>(*app->windows->process.exit_status)
                 : 0;
  });
}

sogen_dart_status sogen_dart_windows_get_last_stop_reason(sogen_dart_app *app,
                                                          int32_t *value) {
  if (!value) {
    return sogen::dart::fail(SOGEN_DART_INVALID_ARGUMENT,
                             "Stop reason output pointer is required");
  }

  return guarded([&] {
    require_app(app);
    *value = static_cast<int32_t>(app->windows->last_stop_reason());
  });
}

sogen_dart_status sogen_dart_windows_destroy(sogen_dart_app *app) {
  if (!app) {
    return SOGEN_DART_OK;
  }
  if (app->running || (app->api_hooks && app->api_hooks->in_callback())) {
    return sogen::dart::fail(
        SOGEN_DART_BAD_STATE,
        "A running application or callback cannot be disposed");
  }

  return guarded([&] { delete app; });
}

void sogen_dart_buffer_free(sogen_dart_buffer *buffer) {
  if (!buffer) {
    return;
  }
  delete[] buffer->data;
  *buffer = {};
}

size_t sogen_dart_last_error(char *destination, const size_t capacity) {
  const auto &error = sogen::dart::last_error();
  if (destination && capacity) {
    const auto copied = std::min(error.size(), capacity - 1);
    std::memcpy(destination, error.data(), copied);
    destination[copied] = '\0';
  }
  return error.size();
}
}
