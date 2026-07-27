#include <sogen_dart.h>

#include "app.hpp"
#include "error.hpp"
#include "linux_callbacks.hpp"
#include "linux_runtime.hpp"

#include <array>
#include <cstring>
#include <filesystem>
#include <memory>
#include <span>
#include <stdexcept>
#include <string>

#include <linux_emulator.hpp>
#include <serialization.hpp>

namespace {
sogen::linux_emulator &linux_app(sogen_dart_app *app) {
  if (!app || !app->linux) {
    throw std::invalid_argument("A valid Linux application is required");
  }
  return *static_cast<sogen::linux_emulator *>(app->linux);
}

void require_stopped(const sogen_dart_app *app) {
  if (!app || !app->linux) {
    throw std::invalid_argument("A valid Linux application is required");
  }
  if (app->running && app->linux_callback_depth == 0) {
    throw std::logic_error(
        "This operation is unavailable while the emulator is running");
  }
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

std::string path_to_utf8(const std::filesystem::path &value) {
  const auto utf8 = value.u8string();
  return {reinterpret_cast<const char *>(utf8.data()), utf8.size()};
}

sogen::memory_permission to_permission(const int32_t value) {
  if (value < 0 || (value & ~7) != 0) {
    throw std::invalid_argument("Invalid memory permission");
  }
  return static_cast<sogen::memory_permission>(value);
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
  *output = {};
  if (!length) {
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
} // namespace

extern "C" {
sogen_dart_status sogen_dart_linux_start(sogen_dart_app *app,
                                         const size_t count) {
  return guarded([&] {
    auto &emulator = linux_app(app);
    if (app->running) {
      throw std::logic_error("The emulator is already running");
    }
    app->running = true;
    try {
      emulator.start(count);
    } catch (...) {
      app->running = false;
      throw;
    }
    app->running = false;
  });
}

sogen_dart_status sogen_dart_linux_stop(sogen_dart_app *app) {
  return guarded([&] { linux_app(app).stop(); });
}

sogen_dart_status sogen_dart_linux_serialize_state(sogen_dart_app *app,
                                                   sogen_dart_buffer *output) {
  if (output) {
    *output = {};
  }
  return guarded([&] {
    require_stopped(app);
    sogen::utils::buffer_serializer serializer{};
    linux_app(app).serialize(serializer, false);
    const auto bytes = serializer.move_buffer();
    set_buffer(output, bytes.data(), bytes.size());
  });
}

sogen_dart_status sogen_dart_linux_deserialize_state(sogen_dart_app *app,
                                                     const uint8_t *data,
                                                     const size_t length) {
  if (!data && length) {
    return sogen::dart::fail(SOGEN_DART_INVALID_ARGUMENT,
                             "State data is required");
  }
  return guarded([&] {
    require_stopped(app);
    const auto *begin = reinterpret_cast<const std::byte *>(data);
    sogen::utils::buffer_deserializer deserializer{
        std::span(begin, begin + length)};
    linux_app(app).deserialize(deserializer, false);
    app->linux_runtime->refresh_symbols();
  });
}

sogen_dart_status sogen_dart_linux_save_snapshot(sogen_dart_app *app) {
  return guarded([&] {
    require_stopped(app);
    sogen::utils::buffer_serializer serializer{};
    linux_app(app).serialize(serializer, false);
    app->linux_snapshot = serializer.move_buffer();
  });
}

sogen_dart_status sogen_dart_linux_restore_snapshot(sogen_dart_app *app) {
  return guarded([&] {
    require_stopped(app);
    if (app->linux_snapshot.empty()) {
      throw std::logic_error("No Linux snapshot has been saved");
    }
    sogen::utils::buffer_deserializer deserializer{
        std::span(app->linux_snapshot)};
    linux_app(app).deserialize(deserializer, false);
    app->linux_runtime->refresh_symbols();
  });
}

sogen_dart_status sogen_dart_linux_read_memory(sogen_dart_app *app,
                                               const uint64_t address,
                                               uint8_t *data,
                                               const size_t length) {
  if (!data && length) {
    return sogen::dart::fail(SOGEN_DART_INVALID_ARGUMENT,
                             "Memory destination is required");
  }
  return guarded(
      [&] { linux_app(app).memory.read_memory(address, data, length); });
}

sogen_dart_status sogen_dart_linux_write_memory(sogen_dart_app *app,
                                                const uint64_t address,
                                                const uint8_t *data,
                                                const size_t length) {
  if (!data && length) {
    return sogen::dart::fail(SOGEN_DART_INVALID_ARGUMENT,
                             "Memory source is required");
  }
  return guarded(
      [&] { linux_app(app).memory.write_memory(address, data, length); });
}

sogen_dart_status sogen_dart_linux_read_register(sogen_dart_app *app,
                                                 const int32_t reg,
                                                 uint64_t *value) {
  if (!value) {
    return sogen::dart::fail(SOGEN_DART_INVALID_ARGUMENT,
                             "Register output pointer is required");
  }
  return guarded(
      [&] { *value = linux_app(app).emu().reg<uint64_t>(to_register(reg)); });
}

sogen_dart_status sogen_dart_linux_write_register(sogen_dart_app *app,
                                                  const int32_t reg,
                                                  const uint64_t value) {
  return guarded(
      [&] { linux_app(app).emu().reg<uint64_t>(to_register(reg), value); });
}

sogen_dart_status
sogen_dart_linux_get_executed_instructions(sogen_dart_app *app,
                                           uint64_t *value) {
  if (!value) {
    return sogen::dart::fail(SOGEN_DART_INVALID_ARGUMENT,
                             "Instruction output pointer is required");
  }
  return guarded([&] { *value = linux_app(app).get_executed_instructions(); });
}

sogen_dart_status sogen_dart_linux_get_backend_name(sogen_dart_app *app,
                                                    sogen_dart_buffer *output) {
  return guarded([&] { set_buffer(output, linux_app(app).emu().get_name()); });
}

sogen_dart_status
sogen_dart_linux_get_emulation_root(sogen_dart_app *app,
                                    sogen_dart_buffer *output) {
  return guarded(
      [&] { set_buffer(output, path_to_utf8(linux_app(app).emulation_root)); });
}

sogen_dart_status sogen_dart_linux_get_last_stop_reason(sogen_dart_app *app,
                                                        int32_t *value) {
  if (!value) {
    return sogen::dart::fail(SOGEN_DART_INVALID_ARGUMENT,
                             "Stop reason output pointer is required");
  }
  return guarded([&] {
    *value = static_cast<int32_t>(linux_app(app).last_stop_reason());
  });
}

sogen_dart_status
sogen_dart_linux_get_last_stop_detail(sogen_dart_app *app,
                                      sogen_dart_buffer *output) {
  return guarded(
      [&] { set_buffer(output, linux_app(app).last_stop_detail()); });
}

sogen_dart_status sogen_dart_linux_activate_thread(sogen_dart_app *app,
                                                   const uint32_t tid,
                                                   int32_t *activated) {
  if (!activated) {
    return sogen::dart::fail(SOGEN_DART_INVALID_ARGUMENT,
                             "Activation output pointer is required");
  }
  return guarded(
      [&] { *activated = linux_app(app).activate_thread(tid) ? 1 : 0; });
}

sogen_dart_status sogen_dart_linux_perform_thread_switch(sogen_dart_app *app,
                                                         int32_t *switched) {
  if (!switched) {
    return sogen::dart::fail(SOGEN_DART_INVALID_ARGUMENT,
                             "Switch output pointer is required");
  }
  return guarded(
      [&] { *switched = linux_app(app).perform_thread_switch() ? 1 : 0; });
}

sogen_dart_status sogen_dart_linux_yield_thread(sogen_dart_app *app) {
  return guarded([&] { linux_app(app).yield_thread(); });
}

sogen_dart_status
sogen_dart_linux_get_process_info(sogen_dart_app *app,
                                  sogen_dart_linux_process_info *output) {
  if (!output) {
    return sogen::dart::fail(SOGEN_DART_INVALID_ARGUMENT,
                             "Process info output pointer is required");
  }
  return guarded([&] {
    const auto &process = linux_app(app).process;
    *output = {
        process.exit_status ? 1 : 0,
        process.exit_status.value_or(0),
        process.pid,
        process.ppid,
        process.uid,
        process.gid,
        process.euid,
        process.egid,
        process.threads.size(),
        process.active_thread ? 1 : 0,
        process.active_thread ? process.active_thread->tid : 0,
    };
  });
}

sogen_dart_status
sogen_dart_linux_get_current_thread_info(sogen_dart_app *app,
                                         int32_t *has_value,
                                         sogen_dart_linux_thread_info *output) {
  if (!has_value || !output) {
    return sogen::dart::fail(SOGEN_DART_INVALID_ARGUMENT,
                             "Thread info output pointers are required");
  }
  return guarded([&] {
    auto &emulator = linux_app(app);
    const auto *thread = emulator.current_thread();
    *has_value = thread ? 1 : 0;
    if (!thread) {
      *output = {};
      return;
    }
    *output = {
        thread->tid,
        thread->stack_base,
        thread->stack_size,
        thread->fs_base,
        emulator.emu().reg<uint64_t>(sogen::x86_register::rip),
        thread->saved_regs.rip,
        static_cast<int32_t>(thread->wait_state),
        1,
        thread->terminated ? 1 : 0,
        thread->exit_code,
        thread->executed_instructions,
    };
  });
}

sogen_dart_status sogen_dart_linux_memory_allocate(sogen_dart_app *app,
                                                   const size_t size,
                                                   const int32_t permissions,
                                                   const uint64_t start,
                                                   uint64_t *address) {
  if (!address) {
    return sogen::dart::fail(SOGEN_DART_INVALID_ARGUMENT,
                             "Allocation output pointer is required");
  }
  return guarded([&] {
    *address = linux_app(app).memory.allocate_memory(
        size, to_permission(permissions), start);
  });
}

sogen_dart_status sogen_dart_linux_memory_allocate_at(sogen_dart_app *app,
                                                      const uint64_t address,
                                                      const size_t size,
                                                      const int32_t permissions,
                                                      int32_t *success) {
  if (!success) {
    return sogen::dart::fail(SOGEN_DART_INVALID_ARGUMENT,
                             "Allocation output pointer is required");
  }
  return guarded([&] {
    *success = linux_app(app).memory.allocate_memory(address, size,
                                                     to_permission(permissions))
                   ? 1
                   : 0;
  });
}

sogen_dart_status sogen_dart_linux_memory_protect(sogen_dart_app *app,
                                                  const uint64_t address,
                                                  const size_t size,
                                                  const int32_t permissions,
                                                  int32_t *success) {
  if (!success) {
    return sogen::dart::fail(SOGEN_DART_INVALID_ARGUMENT,
                             "Protection output pointer is required");
  }
  return guarded([&] {
    *success = linux_app(app).memory.protect_memory(address, size,
                                                    to_permission(permissions))
                   ? 1
                   : 0;
  });
}

sogen_dart_status sogen_dart_linux_memory_release(sogen_dart_app *app,
                                                  const uint64_t address,
                                                  const size_t size,
                                                  int32_t *success) {
  if (!success) {
    return sogen::dart::fail(SOGEN_DART_INVALID_ARGUMENT,
                             "Release output pointer is required");
  }
  return guarded([&] {
    *success = linux_app(app).memory.release_memory(address, size) ? 1 : 0;
  });
}

sogen_dart_status sogen_dart_linux_memory_find_free_base(sogen_dart_app *app,
                                                         const size_t size,
                                                         const uint64_t start,
                                                         uint64_t *address) {
  if (!address) {
    return sogen::dart::fail(SOGEN_DART_INVALID_ARGUMENT,
                             "Free-base output pointer is required");
  }
  return guarded([&] {
    *address = linux_app(app).memory.find_free_allocation_base(size, start);
  });
}

sogen_dart_status
sogen_dart_linux_memory_get_region(sogen_dart_app *app, const uint64_t address,
                                   int32_t *has_value,
                                   sogen_dart_memory_region *output) {
  if (!has_value || !output) {
    return sogen::dart::fail(SOGEN_DART_INVALID_ARGUMENT,
                             "Region output pointers are required");
  }
  return guarded([&] {
    const auto region = linux_app(app).memory.get_region_info(address);
    *has_value = region ? 1 : 0;
    if (!region) {
      *output = {};
      return;
    }
    *output = {
        region->start,
        region->length,
        static_cast<int32_t>(region->permissions),
        region->allocation_base,
        region->allocation_length,
        region->is_reserved ? 1 : 0,
        region->is_committed ? 1 : 0,
        static_cast<int32_t>(region->initial_permissions),
        static_cast<int32_t>(region->kind),
    };
  });
}

sogen_dart_status
sogen_dart_linux_memory_get_stats(sogen_dart_app *app,
                                  sogen_dart_linux_memory_stats *output) {
  if (!output) {
    return sogen::dart::fail(SOGEN_DART_INVALID_ARGUMENT,
                             "Memory stats output pointer is required");
  }
  return guarded([&] {
    const auto stats = linux_app(app).memory.compute_memory_stats();
    *output = {stats.region_count, stats.mapped_bytes, stats.executable_bytes};
  });
}

sogen_dart_status sogen_dart_linux_memory_get_mmap_base(sogen_dart_app *app,
                                                        uint64_t *address) {
  if (!address) {
    return sogen::dart::fail(SOGEN_DART_INVALID_ARGUMENT,
                             "mmap base output pointer is required");
  }
  return guarded([&] { *address = linux_app(app).memory.get_mmap_base(); });
}

sogen_dart_status
sogen_dart_linux_memory_set_mmap_base(sogen_dart_app *app,
                                      const uint64_t address) {
  return guarded([&] { linux_app(app).memory.set_mmap_base(address); });
}

sogen_dart_status sogen_dart_linux_get_host_port(sogen_dart_app *app,
                                                 const uint16_t port,
                                                 uint16_t *output) {
  if (!output) {
    return sogen::dart::fail(SOGEN_DART_INVALID_ARGUMENT,
                             "Host port output pointer is required");
  }
  return guarded(
      [&] { *output = linux_app(app).port_mapper.get_host_port(port); });
}

sogen_dart_status sogen_dart_linux_get_emulator_port(sogen_dart_app *app,
                                                     const uint16_t port,
                                                     uint16_t *output) {
  if (!output) {
    return sogen::dart::fail(SOGEN_DART_INVALID_ARGUMENT,
                             "Emulator port output pointer is required");
  }
  return guarded(
      [&] { *output = linux_app(app).port_mapper.get_emulator_port(port); });
}

sogen_dart_status sogen_dart_linux_map_port(sogen_dart_app *app,
                                            const uint16_t emulator_port,
                                            const uint16_t host_port) {
  return guarded(
      [&] { linux_app(app).port_mapper.map_port(emulator_port, host_port); });
}

sogen_dart_status sogen_dart_linux_destroy(sogen_dart_app *app) {
  if (!app) {
    return SOGEN_DART_OK;
  }
  if (app->running) {
    return sogen::dart::fail(SOGEN_DART_BAD_STATE,
                             "A running Linux application cannot be disposed");
  }
  return guarded([&] {
    app->linux_runtime.reset();
    app->linux_callbacks.reset();
    delete &linux_app(app);
    app->linux = nullptr;
    delete app;
  });
}
}
