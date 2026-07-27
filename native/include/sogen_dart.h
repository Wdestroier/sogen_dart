#pragma once

#include <stddef.h>
#include <stdint.h>

#include "generated/sogen_dart_generated.h"

#if defined(_WIN32)
#define SOGEN_DART_EXPORT __declspec(dllexport)
#elif defined(__GNUC__)
#define SOGEN_DART_EXPORT __attribute__((visibility("default")))
#else
#define SOGEN_DART_EXPORT
#endif

#ifdef __cplusplus
extern "C" {
#endif

typedef struct sogen_dart_app sogen_dart_app;

SOGEN_DART_EXPORT void *sogen_dart_lookup(const char *symbol);

SOGEN_DART_EXPORT uint32_t sogen_dart_abi_version(void);

SOGEN_DART_EXPORT sogen_dart_status sogen_dart_windows_create_application(
    const char *application_utf8, const char *emulation_root_utf8,
    sogen_dart_app **out_app);

SOGEN_DART_EXPORT sogen_dart_status sogen_dart_windows_create_empty(
    const char *emulation_root_utf8, int32_t backend, sogen_dart_app **out_app);

SOGEN_DART_EXPORT sogen_dart_status sogen_dart_windows_create_application_ex(
    const char *application_utf8, const char *emulation_root_utf8,
    int32_t backend, sogen_dart_app **out_app);

SOGEN_DART_EXPORT sogen_dart_status
sogen_dart_windows_create_empty_with_options(
    const sogen_dart_windows_emulator_options *options,
    sogen_dart_app **out_app);

SOGEN_DART_EXPORT sogen_dart_status
sogen_dart_windows_create_application_with_options(
    const sogen_dart_windows_application_options *application_options,
    const sogen_dart_windows_emulator_options *emulator_options,
    sogen_dart_app **out_app);

SOGEN_DART_EXPORT sogen_dart_status sogen_dart_windows_add_api_hook(
    sogen_dart_app *app, const char *key_utf8, int32_t calling_convention,
    size_t parameter_count, sogen_dart_api_callback callback, void *user_data,
    sogen_dart_hook_id *out_hook);

SOGEN_DART_EXPORT sogen_dart_status
sogen_dart_windows_remove_hook(sogen_dart_app *app, sogen_dart_hook_id hook);

SOGEN_DART_EXPORT sogen_dart_status
sogen_dart_windows_clear_api_hooks(sogen_dart_app *app);

SOGEN_DART_EXPORT sogen_dart_status sogen_dart_windows_set_callbacks(
    sogen_dart_app *app, const sogen_dart_windows_callbacks *callbacks);

SOGEN_DART_EXPORT sogen_dart_status sogen_dart_windows_hook_memory_execution(
    sogen_dart_app *app, int32_t has_address, uint64_t address,
    sogen_dart_execution_callback callback, void *user_data,
    sogen_dart_hook_id *out_hook);

SOGEN_DART_EXPORT sogen_dart_status sogen_dart_windows_hook_memory_read(
    sogen_dart_app *app, uint64_t address, uint64_t size,
    sogen_dart_memory_callback callback, void *user_data,
    sogen_dart_hook_id *out_hook);

SOGEN_DART_EXPORT sogen_dart_status sogen_dart_windows_hook_memory_write(
    sogen_dart_app *app, uint64_t address, uint64_t size,
    sogen_dart_memory_callback callback, void *user_data,
    sogen_dart_hook_id *out_hook);

SOGEN_DART_EXPORT sogen_dart_status sogen_dart_windows_hook_instruction(
    sogen_dart_app *app, int32_t instruction,
    sogen_dart_instruction_callback callback, void *user_data,
    sogen_dart_hook_id *out_hook);

SOGEN_DART_EXPORT sogen_dart_status sogen_dart_windows_hook_interrupt(
    sogen_dart_app *app, sogen_dart_interrupt_callback callback,
    void *user_data, sogen_dart_hook_id *out_hook);

SOGEN_DART_EXPORT sogen_dart_status sogen_dart_windows_hook_memory_violation(
    sogen_dart_app *app, sogen_dart_memory_violation_callback callback,
    void *user_data, sogen_dart_hook_id *out_hook);

SOGEN_DART_EXPORT sogen_dart_status sogen_dart_windows_hook_basic_block(
    sogen_dart_app *app, sogen_dart_basic_block_callback callback,
    void *user_data, sogen_dart_hook_id *out_hook);

SOGEN_DART_EXPORT sogen_dart_status
sogen_dart_windows_start(sogen_dart_app *app, size_t instruction_count);

SOGEN_DART_EXPORT sogen_dart_status
sogen_dart_windows_stop(sogen_dart_app *app);

SOGEN_DART_EXPORT sogen_dart_status
sogen_dart_windows_save_snapshot(sogen_dart_app *app);

SOGEN_DART_EXPORT sogen_dart_status
sogen_dart_windows_restore_snapshot(sogen_dart_app *app);

SOGEN_DART_EXPORT sogen_dart_status sogen_dart_windows_serialize_state(
    sogen_dart_app *app, sogen_dart_buffer *out_buffer);

SOGEN_DART_EXPORT sogen_dart_status sogen_dart_windows_deserialize_state(
    sogen_dart_app *app, const uint8_t *data, size_t length);

SOGEN_DART_EXPORT sogen_dart_status
sogen_dart_windows_setup_process(sogen_dart_app *app);

SOGEN_DART_EXPORT sogen_dart_status
sogen_dart_windows_yield_thread(sogen_dart_app *app, int32_t alertable);

SOGEN_DART_EXPORT sogen_dart_status sogen_dart_windows_perform_thread_switch(
    sogen_dart_app *app, int32_t *switched);

SOGEN_DART_EXPORT sogen_dart_status sogen_dart_windows_activate_thread(
    sogen_dart_app *app, uint32_t id, int32_t *activated);

SOGEN_DART_EXPORT sogen_dart_status sogen_dart_windows_read_memory(
    sogen_dart_app *app, uint64_t address, uint8_t *destination, size_t length);

SOGEN_DART_EXPORT sogen_dart_status
sogen_dart_windows_write_memory(sogen_dart_app *app, uint64_t address,
                                const uint8_t *source, size_t length);

SOGEN_DART_EXPORT sogen_dart_status sogen_dart_windows_read_register(
    sogen_dart_app *app, int32_t reg, uint64_t *value);

SOGEN_DART_EXPORT sogen_dart_status sogen_dart_windows_write_register(
    sogen_dart_app *app, int32_t reg, uint64_t value);

SOGEN_DART_EXPORT sogen_dart_status
sogen_dart_windows_get_executed_instructions(sogen_dart_app *app,
                                             uint64_t *value);

SOGEN_DART_EXPORT sogen_dart_status sogen_dart_windows_get_backend_name(
    sogen_dart_app *app, sogen_dart_buffer *out_buffer);

SOGEN_DART_EXPORT sogen_dart_status sogen_dart_windows_get_emulation_root(
    sogen_dart_app *app, sogen_dart_buffer *out_buffer);

SOGEN_DART_EXPORT sogen_dart_status sogen_dart_windows_get_last_stop_detail(
    sogen_dart_app *app, sogen_dart_buffer *out_buffer);

SOGEN_DART_EXPORT sogen_dart_status sogen_dart_windows_get_host_port(
    sogen_dart_app *app, uint16_t emulator_port, uint16_t *host_port);

SOGEN_DART_EXPORT sogen_dart_status sogen_dart_windows_get_emulator_port(
    sogen_dart_app *app, uint16_t host_port, uint16_t *emulator_port);

SOGEN_DART_EXPORT sogen_dart_status sogen_dart_windows_map_port(
    sogen_dart_app *app, uint16_t emulator_port, uint16_t host_port);

SOGEN_DART_EXPORT sogen_dart_status sogen_dart_windows_memory_allocate(
    sogen_dart_app *app, size_t size, int32_t permissions, int32_t reserve_only,
    uint64_t start, int32_t kind, uint64_t *address);

SOGEN_DART_EXPORT sogen_dart_status sogen_dart_windows_memory_protect(
    sogen_dart_app *app, uint64_t address, size_t size, int32_t permissions,
    int32_t *success);

SOGEN_DART_EXPORT sogen_dart_status sogen_dart_windows_memory_commit(
    sogen_dart_app *app, uint64_t address, size_t size, int32_t permissions,
    int32_t *success);

SOGEN_DART_EXPORT sogen_dart_status sogen_dart_windows_memory_decommit(
    sogen_dart_app *app, uint64_t address, size_t size, int32_t *success);

SOGEN_DART_EXPORT sogen_dart_status sogen_dart_windows_memory_release(
    sogen_dart_app *app, uint64_t address, size_t size, int32_t *success);

SOGEN_DART_EXPORT sogen_dart_status sogen_dart_windows_memory_find_free_base(
    sogen_dart_app *app, size_t size, uint64_t start, uint64_t *address);

SOGEN_DART_EXPORT sogen_dart_status sogen_dart_windows_memory_get_region(
    sogen_dart_app *app, uint64_t address, sogen_dart_memory_region *region);

SOGEN_DART_EXPORT sogen_dart_status sogen_dart_windows_memory_get_stats(
    sogen_dart_app *app, sogen_dart_memory_stats *stats);

SOGEN_DART_EXPORT sogen_dart_status
sogen_dart_windows_memory_get_default_address(sogen_dart_app *app,
                                              uint64_t *address);

SOGEN_DART_EXPORT sogen_dart_status
sogen_dart_windows_memory_set_default_address(sogen_dart_app *app,
                                              uint64_t address);

SOGEN_DART_EXPORT sogen_dart_status sogen_dart_windows_get_process_info(
    sogen_dart_app *app, sogen_dart_windows_process_info *info);

SOGEN_DART_EXPORT sogen_dart_status sogen_dart_windows_get_current_thread_info(
    sogen_dart_app *app, int32_t *has_value,
    sogen_dart_windows_thread_info *info);

SOGEN_DART_EXPORT sogen_dart_status sogen_dart_windows_get_current_thread_name(
    sogen_dart_app *app, sogen_dart_buffer *out_buffer);

SOGEN_DART_EXPORT sogen_dart_status sogen_dart_windows_get_exit_status(
    sogen_dart_app *app, int32_t *has_value, int32_t *value);

SOGEN_DART_EXPORT sogen_dart_status
sogen_dart_windows_get_last_stop_reason(sogen_dart_app *app, int32_t *value);

SOGEN_DART_EXPORT sogen_dart_status
sogen_dart_windows_destroy(sogen_dart_app *app);

SOGEN_DART_EXPORT sogen_dart_status sogen_dart_linux_create_empty(
    const char *emulation_root_utf8, int32_t backend, int32_t disable_logging,
    sogen_dart_app **out_app);

SOGEN_DART_EXPORT sogen_dart_status sogen_dart_linux_create_application(
    const char *application_utf8, const char *emulation_root_utf8,
    const char *working_directory_utf8, int32_t backend,
    int32_t disable_logging, sogen_dart_app **out_app);

SOGEN_DART_EXPORT sogen_dart_status sogen_dart_linux_create_empty_ex(
    const char *emulation_root_utf8, int32_t backend, int32_t disable_logging,
    const sogen_dart_linux_path_mapping *path_mappings,
    size_t path_mapping_count,
    const sogen_dart_linux_path_mapping *read_only_path_mappings,
    size_t read_only_path_mapping_count,
    const sogen_dart_linux_port_mapping *port_mappings,
    size_t port_mapping_count, sogen_dart_app **out_app);

SOGEN_DART_EXPORT sogen_dart_status sogen_dart_linux_create_application_ex(
    const char *application_utf8, const char *const *arguments_utf8,
    size_t argument_count,
    const sogen_dart_linux_environment_entry *environment,
    size_t environment_count, int32_t environment_is_set,
    const char *emulation_root_utf8, const char *working_directory_utf8,
    int32_t backend, int32_t disable_logging,
    const sogen_dart_linux_path_mapping *path_mappings,
    size_t path_mapping_count,
    const sogen_dart_linux_path_mapping *read_only_path_mappings,
    size_t read_only_path_mapping_count,
    const sogen_dart_linux_port_mapping *port_mappings,
    size_t port_mapping_count, sogen_dart_app **out_app);

SOGEN_DART_EXPORT sogen_dart_status
sogen_dart_linux_start(sogen_dart_app *app, size_t instruction_count);

SOGEN_DART_EXPORT sogen_dart_status sogen_dart_linux_set_callbacks(
    sogen_dart_app *app, const sogen_dart_linux_callbacks *callbacks);

SOGEN_DART_EXPORT sogen_dart_status sogen_dart_linux_hook_memory_execution(
    sogen_dart_app *app, int32_t has_address, uint64_t address,
    sogen_dart_execution_callback callback, void *user_data,
    sogen_dart_hook_id *out_hook);
SOGEN_DART_EXPORT sogen_dart_status sogen_dart_linux_hook_memory_read(
    sogen_dart_app *app, uint64_t address, uint64_t size,
    sogen_dart_memory_callback callback, void *user_data,
    sogen_dart_hook_id *out_hook);
SOGEN_DART_EXPORT sogen_dart_status sogen_dart_linux_hook_memory_write(
    sogen_dart_app *app, uint64_t address, uint64_t size,
    sogen_dart_memory_callback callback, void *user_data,
    sogen_dart_hook_id *out_hook);
SOGEN_DART_EXPORT sogen_dart_status sogen_dart_linux_hook_instruction(
    sogen_dart_app *app, int32_t instruction,
    sogen_dart_instruction_callback callback, void *user_data,
    sogen_dart_hook_id *out_hook);
SOGEN_DART_EXPORT sogen_dart_status sogen_dart_linux_hook_interrupt(
    sogen_dart_app *app, sogen_dart_interrupt_callback callback,
    void *user_data, sogen_dart_hook_id *out_hook);
SOGEN_DART_EXPORT sogen_dart_status sogen_dart_linux_hook_memory_violation(
    sogen_dart_app *app, sogen_dart_memory_violation_callback callback,
    void *user_data, sogen_dart_hook_id *out_hook);
SOGEN_DART_EXPORT sogen_dart_status sogen_dart_linux_hook_basic_block(
    sogen_dart_app *app, sogen_dart_basic_block_callback callback,
    void *user_data, sogen_dart_hook_id *out_hook);
SOGEN_DART_EXPORT sogen_dart_status
sogen_dart_linux_remove_hook(sogen_dart_app *app, sogen_dart_hook_id hook);

SOGEN_DART_EXPORT sogen_dart_status sogen_dart_linux_set_symbol_hook(
    sogen_dart_app *app, const char *key_utf8, size_t parameter_count,
    sogen_dart_linux_symbol_callback callback, void *user_data);
SOGEN_DART_EXPORT sogen_dart_status
sogen_dart_linux_remove_symbol_hook(sogen_dart_app *app, const char *key_utf8);
SOGEN_DART_EXPORT sogen_dart_status
sogen_dart_linux_clear_symbol_hooks(sogen_dart_app *app);
SOGEN_DART_EXPORT sogen_dart_status
sogen_dart_linux_refresh_symbol_hooks(sogen_dart_app *app);

SOGEN_DART_EXPORT sogen_dart_status sogen_dart_linux_debug_set_breakpoint(
    sogen_dart_app *app, uint64_t address, int32_t *success);
SOGEN_DART_EXPORT sogen_dart_status sogen_dart_linux_debug_clear_breakpoint(
    sogen_dart_app *app, uint64_t address, int32_t *success);
SOGEN_DART_EXPORT sogen_dart_status sogen_dart_linux_debug_list_breakpoints(
    sogen_dart_app *app, sogen_dart_buffer *addresses);
SOGEN_DART_EXPORT sogen_dart_status
sogen_dart_linux_debug_step_into(sogen_dart_app *app);
SOGEN_DART_EXPORT sogen_dart_status
sogen_dart_linux_debug_step_over(sogen_dart_app *app);
SOGEN_DART_EXPORT sogen_dart_status
sogen_dart_linux_debug_step_out(sogen_dart_app *app);
SOGEN_DART_EXPORT sogen_dart_status
sogen_dart_linux_debug_run_to(sogen_dart_app *app, uint64_t address);
SOGEN_DART_EXPORT sogen_dart_status
sogen_dart_linux_debug_continue_execution(sogen_dart_app *app);
SOGEN_DART_EXPORT sogen_dart_status
sogen_dart_linux_debug_pause(sogen_dart_app *app);
SOGEN_DART_EXPORT sogen_dart_status sogen_dart_linux_debug_disassemble(
    sogen_dart_app *app, uint64_t address, size_t count_or_size,
    sogen_dart_linux_disassembled_instruction_list *instructions);
SOGEN_DART_EXPORT void sogen_dart_linux_disassembled_instruction_list_free(
    sogen_dart_linux_disassembled_instruction_list *instructions);
SOGEN_DART_EXPORT sogen_dart_status sogen_dart_linux_debug_call_stack(
    sogen_dart_app *app, sogen_dart_linux_stack_frame_list *frames);
SOGEN_DART_EXPORT void sogen_dart_linux_stack_frame_list_free(
    sogen_dart_linux_stack_frame_list *frames);

SOGEN_DART_EXPORT sogen_dart_status sogen_dart_linux_stop(sogen_dart_app *app);

SOGEN_DART_EXPORT sogen_dart_status
sogen_dart_linux_save_snapshot(sogen_dart_app *app);

SOGEN_DART_EXPORT sogen_dart_status
sogen_dart_linux_restore_snapshot(sogen_dart_app *app);

SOGEN_DART_EXPORT sogen_dart_status sogen_dart_linux_serialize_state(
    sogen_dart_app *app, sogen_dart_buffer *out_buffer);

SOGEN_DART_EXPORT sogen_dart_status sogen_dart_linux_deserialize_state(
    sogen_dart_app *app, const uint8_t *data, size_t length);

SOGEN_DART_EXPORT sogen_dart_status sogen_dart_linux_read_memory(
    sogen_dart_app *app, uint64_t address, uint8_t *destination, size_t length);

SOGEN_DART_EXPORT sogen_dart_status
sogen_dart_linux_write_memory(sogen_dart_app *app, uint64_t address,
                              const uint8_t *source, size_t length);

SOGEN_DART_EXPORT sogen_dart_status sogen_dart_linux_read_register(
    sogen_dart_app *app, int32_t reg, uint64_t *value);

SOGEN_DART_EXPORT sogen_dart_status sogen_dart_linux_write_register(
    sogen_dart_app *app, int32_t reg, uint64_t value);

SOGEN_DART_EXPORT sogen_dart_status sogen_dart_linux_get_executed_instructions(
    sogen_dart_app *app, uint64_t *value);

SOGEN_DART_EXPORT sogen_dart_status sogen_dart_linux_get_backend_name(
    sogen_dart_app *app, sogen_dart_buffer *out_buffer);

SOGEN_DART_EXPORT sogen_dart_status sogen_dart_linux_get_emulation_root(
    sogen_dart_app *app, sogen_dart_buffer *out_buffer);

SOGEN_DART_EXPORT sogen_dart_status
sogen_dart_linux_get_last_stop_reason(sogen_dart_app *app, int32_t *value);

SOGEN_DART_EXPORT sogen_dart_status sogen_dart_linux_get_last_stop_detail(
    sogen_dart_app *app, sogen_dart_buffer *out_buffer);

SOGEN_DART_EXPORT sogen_dart_status sogen_dart_linux_activate_thread(
    sogen_dart_app *app, uint32_t tid, int32_t *activated);

SOGEN_DART_EXPORT sogen_dart_status
sogen_dart_linux_perform_thread_switch(sogen_dart_app *app, int32_t *switched);

SOGEN_DART_EXPORT sogen_dart_status
sogen_dart_linux_yield_thread(sogen_dart_app *app);

SOGEN_DART_EXPORT sogen_dart_status sogen_dart_linux_get_process_info(
    sogen_dart_app *app, sogen_dart_linux_process_info *info);

SOGEN_DART_EXPORT sogen_dart_status sogen_dart_linux_get_current_thread_info(
    sogen_dart_app *app, int32_t *has_value,
    sogen_dart_linux_thread_info *info);

SOGEN_DART_EXPORT sogen_dart_status sogen_dart_linux_get_thread_info(
    sogen_dart_app *app, uint32_t tid, int32_t *has_value,
    sogen_dart_linux_thread_info *info);

SOGEN_DART_EXPORT sogen_dart_status
sogen_dart_linux_get_active_thread_info(sogen_dart_app *app, int32_t *has_value,
                                        sogen_dart_linux_thread_info *info);

SOGEN_DART_EXPORT sogen_dart_status sogen_dart_linux_get_threads(
    sogen_dart_app *app, sogen_dart_linux_thread_list *threads);

SOGEN_DART_EXPORT void
sogen_dart_linux_thread_list_free(sogen_dart_linux_thread_list *threads);

SOGEN_DART_EXPORT sogen_dart_status sogen_dart_linux_memory_allocate(
    sogen_dart_app *app, size_t size, int32_t permissions, uint64_t start,
    uint64_t *address);

SOGEN_DART_EXPORT sogen_dart_status sogen_dart_linux_memory_allocate_at(
    sogen_dart_app *app, uint64_t address, size_t size, int32_t permissions,
    int32_t *success);

SOGEN_DART_EXPORT sogen_dart_status sogen_dart_linux_memory_protect(
    sogen_dart_app *app, uint64_t address, size_t size, int32_t permissions,
    int32_t *success);

SOGEN_DART_EXPORT sogen_dart_status sogen_dart_linux_memory_release(
    sogen_dart_app *app, uint64_t address, size_t size, int32_t *success);

SOGEN_DART_EXPORT sogen_dart_status sogen_dart_linux_memory_find_free_base(
    sogen_dart_app *app, size_t size, uint64_t start, uint64_t *address);

SOGEN_DART_EXPORT sogen_dart_status sogen_dart_linux_memory_get_region(
    sogen_dart_app *app, uint64_t address, int32_t *has_value,
    sogen_dart_memory_region *region);

SOGEN_DART_EXPORT sogen_dart_status sogen_dart_linux_memory_get_stats(
    sogen_dart_app *app, sogen_dart_linux_memory_stats *stats);

SOGEN_DART_EXPORT sogen_dart_status sogen_dart_linux_memory_get_mapped_regions(
    sogen_dart_app *app, sogen_dart_memory_region_list *regions);

SOGEN_DART_EXPORT void
sogen_dart_memory_region_list_free(sogen_dart_memory_region_list *regions);

SOGEN_DART_EXPORT sogen_dart_status
sogen_dart_linux_memory_get_mmap_base(sogen_dart_app *app, uint64_t *address);

SOGEN_DART_EXPORT sogen_dart_status
sogen_dart_linux_memory_set_mmap_base(sogen_dart_app *app, uint64_t address);

SOGEN_DART_EXPORT sogen_dart_status sogen_dart_linux_get_host_port(
    sogen_dart_app *app, uint16_t emulator_port, uint16_t *host_port);

SOGEN_DART_EXPORT sogen_dart_status sogen_dart_linux_get_emulator_port(
    sogen_dart_app *app, uint16_t host_port, uint16_t *emulator_port);

SOGEN_DART_EXPORT sogen_dart_status sogen_dart_linux_map_port(
    sogen_dart_app *app, uint16_t emulator_port, uint16_t host_port);

SOGEN_DART_EXPORT sogen_dart_status sogen_dart_linux_get_modules(
    sogen_dart_app *app, sogen_dart_linux_mapped_module_list *modules);

SOGEN_DART_EXPORT sogen_dart_status sogen_dart_linux_find_module_by_address(
    sogen_dart_app *app, uint64_t address, int32_t *has_value,
    sogen_dart_linux_mapped_module *module);

SOGEN_DART_EXPORT sogen_dart_status sogen_dart_linux_find_module_by_name(
    sogen_dart_app *app, const char *name_utf8, int32_t *has_value,
    sogen_dart_linux_mapped_module *module);

SOGEN_DART_EXPORT void
sogen_dart_linux_mapped_module_free(sogen_dart_linux_mapped_module *module);

SOGEN_DART_EXPORT void sogen_dart_linux_mapped_module_list_free(
    sogen_dart_linux_mapped_module_list *modules);

SOGEN_DART_EXPORT sogen_dart_status
sogen_dart_linux_destroy(sogen_dart_app *app);

SOGEN_DART_EXPORT void sogen_dart_buffer_free(sogen_dart_buffer *buffer);

SOGEN_DART_EXPORT size_t sogen_dart_last_error(char *destination,
                                               size_t capacity);

#ifdef __cplusplus
}
#endif
