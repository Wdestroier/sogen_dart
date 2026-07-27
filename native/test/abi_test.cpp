#include <sogen_dart.h>

#include <array>
#include <barrier>
#include <cassert>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <string>
#include <thread>
#include <type_traits>

namespace {
#define ASSERT_FIELD_ORDER(type, first, second)                                \
  static_assert(offsetof(type, first) < offsetof(type, second))

std::string last_error() {
  const auto length = sogen_dart_last_error(nullptr, 0);
  std::string result(length, '\0');
  if (length != 0) {
    const auto copied = sogen_dart_last_error(result.data(), result.size() + 1);
    assert(copied == length);
  }
  return result;
}

void test_layouts() {
  static_assert(std::is_standard_layout_v<sogen_dart_api_call>);
  static_assert(std::is_standard_layout_v<sogen_dart_buffer>);
  static_assert(std::is_standard_layout_v<sogen_dart_memory_region>);
  static_assert(std::is_standard_layout_v<sogen_dart_windows_callbacks>);
  static_assert(std::is_standard_layout_v<sogen_dart_linux_callbacks>);
  static_assert(offsetof(sogen_dart_buffer, data) == 0);
  static_assert(offsetof(sogen_dart_buffer, length) == sizeof(void *));
  static_assert(sizeof(sogen_dart_buffer) == sizeof(void *) + sizeof(size_t));
  static_assert(sizeof(sogen_dart_linux_thread_list) ==
                sizeof(void *) + sizeof(size_t));
  static_assert(sizeof(sogen_dart_memory_region_list) ==
                sizeof(void *) + sizeof(size_t));
  static_assert(sizeof(sogen_dart_linux_mapped_module_list) ==
                sizeof(void *) + sizeof(size_t));
  static_assert(SOGEN_DART_WINDOWS_CALLBACK_MODULE_LOAD == 0);
  static_assert(SOGEN_DART_WINDOWS_CALLBACK_THREAD_SWITCH == 19);
  static_assert(SOGEN_DART_WINDOWS_CALLBACK_COUNT == 20);
  static_assert(SOGEN_DART_LINUX_CALLBACK_STDOUT == 0);
  static_assert(SOGEN_DART_LINUX_CALLBACK_THREAD_SWITCH == 11);
  static_assert(SOGEN_DART_LINUX_CALLBACK_COUNT == 12);
  ASSERT_FIELD_ORDER(sogen_dart_api_call, module_utf8, name_utf8);
  ASSERT_FIELD_ORDER(sogen_dart_api_call, name_utf8, address);
  ASSERT_FIELD_ORDER(sogen_dart_api_call, address, return_address);
  ASSERT_FIELD_ORDER(sogen_dart_api_call, return_address, return_value);
  ASSERT_FIELD_ORDER(sogen_dart_memory_region, start, length);
  ASSERT_FIELD_ORDER(sogen_dart_memory_region, length, permissions);
  ASSERT_FIELD_ORDER(sogen_dart_memory_region, permissions, allocation_base);
  ASSERT_FIELD_ORDER(sogen_dart_memory_region, allocation_base,
                     allocation_length);
  ASSERT_FIELD_ORDER(sogen_dart_memory_region, allocation_length, is_reserved);
  ASSERT_FIELD_ORDER(sogen_dart_memory_region, is_reserved, is_committed);
  ASSERT_FIELD_ORDER(sogen_dart_memory_region, is_committed,
                     initial_permissions);
  ASSERT_FIELD_ORDER(sogen_dart_memory_region, initial_permissions, kind);
  ASSERT_FIELD_ORDER(sogen_dart_linux_mapped_module, name_utf8, path_utf8);
  ASSERT_FIELD_ORDER(sogen_dart_linux_mapped_module, path_utf8, image_base);
  ASSERT_FIELD_ORDER(sogen_dart_linux_mapped_module, image_base, exports);
  ASSERT_FIELD_ORDER(sogen_dart_linux_mapped_module, exports, needed_libraries);
  ASSERT_FIELD_ORDER(sogen_dart_linux_mapped_module, needed_libraries,
                     sections);
  ASSERT_FIELD_ORDER(sogen_dart_linux_mapped_module, sections, rpath_utf8);
  ASSERT_FIELD_ORDER(sogen_dart_linux_mapped_module, rpath_utf8, runpath_utf8);

  const std::array windows_offsets{
      offsetof(sogen_dart_windows_callbacks, module_load),
      offsetof(sogen_dart_windows_callbacks, module_unload),
      offsetof(sogen_dart_windows_callbacks, stdout_callback),
      offsetof(sogen_dart_windows_callbacks, syscall),
      offsetof(sogen_dart_windows_callbacks, generic_access),
      offsetof(sogen_dart_windows_callbacks, generic_activity),
      offsetof(sogen_dart_windows_callbacks, suspicious_activity),
      offsetof(sogen_dart_windows_callbacks, exception),
      offsetof(sogen_dart_windows_callbacks, instruction),
      offsetof(sogen_dart_windows_callbacks, memory_protect),
      offsetof(sogen_dart_windows_callbacks, memory_allocate),
      offsetof(sogen_dart_windows_callbacks, memory_violate),
      offsetof(sogen_dart_windows_callbacks, rdtsc),
      offsetof(sogen_dart_windows_callbacks, rdtscp),
      offsetof(sogen_dart_windows_callbacks, ioctrl),
      offsetof(sogen_dart_windows_callbacks, debug_string),
      offsetof(sogen_dart_windows_callbacks, thread_create),
      offsetof(sogen_dart_windows_callbacks, thread_terminated),
      offsetof(sogen_dart_windows_callbacks, thread_set_name),
      offsetof(sogen_dart_windows_callbacks, thread_switch),
  };
  for (size_t index = 1; index < windows_offsets.size(); ++index) {
    assert(windows_offsets[index - 1] < windows_offsets[index]);
  }
}

void test_errors_are_thread_local() {
  std::barrier rendezvous(3);
  std::array<std::string, 2> errors{};
  std::thread first([&] {
    assert(sogen_dart_windows_read_register(nullptr, 0, nullptr) ==
           SOGEN_DART_INVALID_ARGUMENT);
    rendezvous.arrive_and_wait();
    rendezvous.arrive_and_wait();
    errors[0] = last_error();
  });
  std::thread second([&] {
    sogen_dart_app *app = nullptr;
    assert(sogen_dart_linux_create_empty(nullptr, SOGEN_DART_BACKEND_UNICORN, 1,
                                         &app) == SOGEN_DART_INVALID_ARGUMENT);
    rendezvous.arrive_and_wait();
    rendezvous.arrive_and_wait();
    errors[1] = last_error();
  });
  rendezvous.arrive_and_wait();
  assert(sogen_dart_windows_destroy(nullptr) == SOGEN_DART_OK);
  rendezvous.arrive_and_wait();
  first.join();
  second.join();
  assert(errors[0] == "Register output pointer is required");
  assert(errors[1] == "Emulation root and output pointer are required");

  assert(last_error().empty());
  assert(sogen_dart_windows_read_register(nullptr, 0, nullptr) ==
         SOGEN_DART_INVALID_ARGUMENT);
  std::array<char, 9> truncated{};
  const auto full_length = sogen_dart_last_error(truncated.data(), 5);
  assert(full_length == std::strlen("Register output pointer is required"));
  assert(std::string(truncated.data()) == "Regi");
}

void test_owned_values_and_lifecycle() {
  assert(sogen_dart_windows_destroy(nullptr) == SOGEN_DART_OK);
  assert(sogen_dart_windows_destroy(nullptr) == SOGEN_DART_OK);
  assert(sogen_dart_linux_destroy(nullptr) == SOGEN_DART_OK);
  assert(sogen_dart_linux_destroy(nullptr) == SOGEN_DART_OK);
  sogen_dart_buffer_free(nullptr);
  sogen_dart_linux_thread_list_free(nullptr);
  sogen_dart_memory_region_list_free(nullptr);
  sogen_dart_linux_mapped_module_free(nullptr);
  sogen_dart_linux_mapped_module_list_free(nullptr);
  sogen_dart_linux_disassembled_instruction_list_free(nullptr);
  sogen_dart_linux_stack_frame_list_free(nullptr);
  assert(sogen_dart_linux_get_backend_name(nullptr, nullptr) ==
         SOGEN_DART_INVALID_ARGUMENT);
  assert(!last_error().empty());

  sogen_dart_app *app = nullptr;
  assert(sogen_dart_linux_create_empty("", SOGEN_DART_BACKEND_UNICORN, 1,
                                       &app) == SOGEN_DART_OK);
  assert(app != nullptr);

  sogen_dart_buffer backend{};
  assert(sogen_dart_linux_get_backend_name(app, &backend) == SOGEN_DART_OK);
  assert(backend.data != nullptr);
  assert(backend.length != 0);
  assert(std::string(reinterpret_cast<char *>(backend.data), backend.length) ==
         "Unicorn Engine");
  sogen_dart_buffer_free(&backend);
  assert(backend.data == nullptr && backend.length == 0);
  sogen_dart_buffer_free(&backend);

  sogen_dart_buffer root{};
  assert(sogen_dart_linux_get_emulation_root(app, &root) == SOGEN_DART_OK);
  assert(root.length == 0 || root.data != nullptr);
  sogen_dart_buffer_free(&root);
  assert(root.data == nullptr && root.length == 0);

  sogen_dart_buffer state{};
  assert(sogen_dart_linux_serialize_state(app, &state) == SOGEN_DART_OK);
  assert(state.data != nullptr && state.length != 0);
  sogen_dart_buffer_free(&state);
  sogen_dart_buffer_free(&state);

  assert(sogen_dart_linux_restore_snapshot(app) == SOGEN_DART_BAD_STATE);
  assert(last_error() == "No Linux snapshot has been saved");

  sogen_dart_buffer wrong_platform{};
  assert(sogen_dart_windows_get_backend_name(app, &wrong_platform) ==
         SOGEN_DART_INVALID_ARGUMENT);
  assert(wrong_platform.data == nullptr && wrong_platform.length == 0);

  constexpr sogen_dart_hook_id missing_hook = 0x123456789ULL;
  assert(sogen_dart_linux_remove_hook(app, missing_hook) == SOGEN_DART_OK);
  assert(sogen_dart_linux_remove_hook(app, missing_hook) == SOGEN_DART_OK);

  uint64_t address = 0;
  assert(sogen_dart_linux_memory_allocate(
             app, 0x1000, SOGEN_DART_MEMORY_PERMISSION_READ_WRITE, 0,
             &address) == SOGEN_DART_OK);
  assert(address != 0);
  sogen_dart_memory_region_list regions{};
  assert(sogen_dart_linux_memory_get_mapped_regions(app, &regions) ==
         SOGEN_DART_OK);
  assert(regions.data != nullptr && regions.length != 0);
  sogen_dart_memory_region_list_free(&regions);
  assert(regions.data == nullptr && regions.length == 0);
  sogen_dart_memory_region_list_free(&regions);

  sogen_dart_linux_thread_list threads{};
  assert(sogen_dart_linux_get_threads(app, &threads) == SOGEN_DART_OK);
  sogen_dart_linux_thread_list_free(&threads);
  assert(threads.data == nullptr && threads.length == 0);
  sogen_dart_linux_thread_list_free(&threads);

  sogen_dart_linux_mapped_module_list modules{};
  assert(sogen_dart_linux_get_modules(app, &modules) == SOGEN_DART_OK);
  sogen_dart_linux_mapped_module_list_free(&modules);
  assert(modules.data == nullptr && modules.length == 0);
  sogen_dart_linux_mapped_module_list_free(&modules);

  sogen_dart_linux_mapped_module module{};
  sogen_dart_linux_mapped_module_free(&module);
  sogen_dart_linux_mapped_module_free(&module);

  assert(sogen_dart_linux_destroy(app) == SOGEN_DART_OK);
}
#undef ASSERT_FIELD_ORDER
} // namespace

int main() {
  assert(sogen_dart_abi_version() == SOGEN_DART_ABI_VERSION);
  test_layouts();
  test_errors_are_thread_local();
  test_owned_values_and_lifecycle();
  return 0;
}
