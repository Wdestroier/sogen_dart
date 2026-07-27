#include <sogen_dart.h>

#include "app.hpp"
#include "error.hpp"

#include <cstring>
#include <filesystem>
#include <memory>
#include <stdexcept>
#include <string>
#include <string_view>

#include <linux_emulator.hpp>

namespace {
sogen::linux_emulator &linux_app(sogen_dart_app *app) {
  if (!app || !app->linux) {
    throw std::invalid_argument("A valid Linux application is required");
  }
  return *static_cast<sogen::linux_emulator *>(app->linux);
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

void set_buffer(sogen_dart_buffer &output, const std::string_view value) {
  output = {};
  if (value.empty()) {
    return;
  }

  auto bytes = std::make_unique<uint8_t[]>(value.size());
  std::memcpy(bytes.get(), value.data(), value.size());
  output.data = bytes.release();
  output.length = value.size();
}

void free_buffer(sogen_dart_buffer &buffer) {
  delete[] buffer.data;
  buffer = {};
}

void free_buffer_list(sogen_dart_buffer_list &list) {
  for (size_t index = 0; index < list.length; ++index) {
    free_buffer(list.data[index]);
  }
  delete[] list.data;
  list = {};
}

void free_export_list(sogen_dart_linux_exported_symbol_list &list) {
  for (size_t index = 0; index < list.length; ++index) {
    free_buffer(list.data[index].name_utf8);
  }
  delete[] list.data;
  list = {};
}

void free_section_list(sogen_dart_linux_mapped_section_list &list) {
  for (size_t index = 0; index < list.length; ++index) {
    free_buffer(list.data[index].name_utf8);
  }
  delete[] list.data;
  list = {};
}

void free_module(sogen_dart_linux_mapped_module &module) {
  free_buffer(module.name_utf8);
  free_buffer(module.path_utf8);
  free_export_list(module.exports);
  free_buffer_list(module.needed_libraries);
  free_section_list(module.sections);
  free_buffer(module.rpath_utf8);
  free_buffer(module.runpath_utf8);
  module = {};
}

void set_export_list(sogen_dart_linux_exported_symbol_list &output,
                     const std::vector<sogen::linux_exported_symbol> &symbols) {
  output = {};
  if (symbols.empty()) {
    return;
  }

  auto values =
      std::make_unique<sogen_dart_linux_exported_symbol[]>(symbols.size());
  output.data = values.get();
  output.length = symbols.size();
  try {
    for (size_t index = 0; index < symbols.size(); ++index) {
      const auto &source = symbols[index];
      set_buffer(values[index].name_utf8, source.name);
      values[index].rva = source.rva;
      values[index].address = source.address;
    }
  } catch (...) {
    free_export_list(output);
    values.release();
    throw;
  }
  output.data = values.release();
}

void set_buffer_list(sogen_dart_buffer_list &output,
                     const std::vector<std::string> &strings) {
  output = {};
  if (strings.empty()) {
    return;
  }

  auto values = std::make_unique<sogen_dart_buffer[]>(strings.size());
  output.data = values.get();
  output.length = strings.size();
  try {
    for (size_t index = 0; index < strings.size(); ++index) {
      set_buffer(values[index], strings[index]);
    }
  } catch (...) {
    free_buffer_list(output);
    values.release();
    throw;
  }
  output.data = values.release();
}

void set_section_list(
    sogen_dart_linux_mapped_section_list &output,
    const std::vector<sogen::linux_mapped_section> &sections) {
  output = {};
  if (sections.empty()) {
    return;
  }

  auto values =
      std::make_unique<sogen_dart_linux_mapped_section[]>(sections.size());
  output.data = values.get();
  output.length = sections.size();
  try {
    for (size_t index = 0; index < sections.size(); ++index) {
      const auto &source = sections[index];
      set_buffer(values[index].name_utf8, source.name);
      values[index].start = source.start;
      values[index].length = source.length;
      values[index].permissions = static_cast<int32_t>(source.permissions);
    }
  } catch (...) {
    free_section_list(output);
    values.release();
    throw;
  }
  output.data = values.release();
}

void set_module(sogen_dart_linux_mapped_module &output,
                const sogen::linux_mapped_module &module) {
  output = {};
  try {
    set_buffer(output.name_utf8, module.name);
    set_buffer(output.path_utf8, path_to_utf8(module.path));
    output.image_base = module.image_base;
    output.size_of_image = module.size_of_image;
    output.entry_point = module.entry_point;
    set_export_list(output.exports, module.exports);
    set_buffer_list(output.needed_libraries, module.needed_libraries);
    set_section_list(output.sections, module.sections);
    set_buffer(output.rpath_utf8, module.rpath);
    set_buffer(output.runpath_utf8, module.runpath);
  } catch (...) {
    free_module(output);
    throw;
  }
}

sogen_dart_linux_thread_info thread_info(sogen::linux_emulator &emulator,
                                         const sogen::linux_thread &thread) {
  const auto current_ip =
      emulator.process.active_thread &&
              emulator.process.active_thread->tid == thread.tid
          ? emulator.emu().reg<uint64_t>(sogen::x86_register::rip)
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

sogen_dart_memory_region
region_info(const sogen::linux_memory_region_info &region) {
  return {
      region.start,
      region.length,
      static_cast<int32_t>(region.permissions),
      region.allocation_base,
      region.allocation_length,
      region.is_reserved ? 1 : 0,
      region.is_committed ? 1 : 0,
      static_cast<int32_t>(region.initial_permissions),
      static_cast<int32_t>(region.kind),
  };
}
} // namespace

extern "C" {
sogen_dart_status
sogen_dart_linux_get_thread_info(sogen_dart_app *app, const uint32_t tid,
                                 int32_t *has_value,
                                 sogen_dart_linux_thread_info *output) {
  if (!has_value || !output) {
    return sogen::dart::fail(SOGEN_DART_INVALID_ARGUMENT,
                             "Thread info output pointers are required");
  }
  *has_value = 0;
  *output = {};
  return guarded([&] {
    auto &emulator = linux_app(app);
    const auto entry = emulator.process.threads.find(tid);
    if (entry == emulator.process.threads.end()) {
      return;
    }
    *has_value = 1;
    *output = thread_info(emulator, entry->second);
  });
}

sogen_dart_status
sogen_dart_linux_get_active_thread_info(sogen_dart_app *app, int32_t *has_value,
                                        sogen_dart_linux_thread_info *output) {
  if (!has_value || !output) {
    return sogen::dart::fail(SOGEN_DART_INVALID_ARGUMENT,
                             "Thread info output pointers are required");
  }
  *has_value = 0;
  *output = {};
  return guarded([&] {
    auto &emulator = linux_app(app);
    if (!emulator.process.active_thread) {
      return;
    }
    *has_value = 1;
    *output = thread_info(emulator, *emulator.process.active_thread);
  });
}

sogen_dart_status
sogen_dart_linux_get_threads(sogen_dart_app *app,
                             sogen_dart_linux_thread_list *output) {
  if (!output) {
    return sogen::dart::fail(SOGEN_DART_INVALID_ARGUMENT,
                             "Thread list output pointer is required");
  }
  *output = {};
  return guarded([&] {
    auto &emulator = linux_app(app);
    size_t count = 0;
    for (const auto &[_, thread] : emulator.process.threads) {
      count += thread.terminated ? 0 : 1;
    }
    if (!count) {
      return;
    }

    auto values = std::make_unique<sogen_dart_linux_thread_info[]>(count);
    size_t index = 0;
    for (const auto &[_, thread] : emulator.process.threads) {
      if (!thread.terminated) {
        values[index++] = thread_info(emulator, thread);
      }
    }
    output->data = values.release();
    output->length = count;
  });
}

void sogen_dart_linux_thread_list_free(sogen_dart_linux_thread_list *list) {
  if (!list) {
    return;
  }
  delete[] list->data;
  *list = {};
}

sogen_dart_status sogen_dart_linux_memory_get_mapped_regions(
    sogen_dart_app *app, sogen_dart_memory_region_list *output) {
  if (!output) {
    return sogen::dart::fail(SOGEN_DART_INVALID_ARGUMENT,
                             "Region list output pointer is required");
  }
  *output = {};
  return guarded([&] {
    const auto regions = linux_app(app).memory.get_mapped_region_infos();
    if (regions.empty()) {
      return;
    }
    auto values = std::make_unique<sogen_dart_memory_region[]>(regions.size());
    for (size_t index = 0; index < regions.size(); ++index) {
      values[index] = region_info(regions[index]);
    }
    output->data = values.release();
    output->length = regions.size();
  });
}

void sogen_dart_memory_region_list_free(sogen_dart_memory_region_list *list) {
  if (!list) {
    return;
  }
  delete[] list->data;
  *list = {};
}

sogen_dart_status
sogen_dart_linux_get_modules(sogen_dart_app *app,
                             sogen_dart_linux_mapped_module_list *output) {
  if (!output) {
    return sogen::dart::fail(SOGEN_DART_INVALID_ARGUMENT,
                             "Module list output pointer is required");
  }
  *output = {};
  return guarded([&] {
    const auto &modules = linux_app(app).mod_manager.get_modules();
    if (modules.empty()) {
      return;
    }

    auto values =
        std::make_unique<sogen_dart_linux_mapped_module[]>(modules.size());
    output->data = values.get();
    output->length = modules.size();
    try {
      size_t index = 0;
      for (const auto &[_, module] : modules) {
        set_module(values[index++], module);
      }
    } catch (...) {
      sogen_dart_linux_mapped_module_list_free(output);
      values.release();
      throw;
    }
    output->data = values.release();
  });
}

sogen_dart_status sogen_dart_linux_find_module_by_address(
    sogen_dart_app *app, const uint64_t address, int32_t *has_value,
    sogen_dart_linux_mapped_module *output) {
  if (!has_value || !output) {
    return sogen::dart::fail(SOGEN_DART_INVALID_ARGUMENT,
                             "Module output pointers are required");
  }
  *has_value = 0;
  *output = {};
  return guarded([&] {
    const auto *module = linux_app(app).mod_manager.find_by_address(address);
    if (!module) {
      return;
    }
    set_module(*output, *module);
    *has_value = 1;
  });
}

sogen_dart_status
sogen_dart_linux_find_module_by_name(sogen_dart_app *app, const char *name,
                                     int32_t *has_value,
                                     sogen_dart_linux_mapped_module *output) {
  if (!name || !has_value || !output) {
    return sogen::dart::fail(SOGEN_DART_INVALID_ARGUMENT,
                             "Module name and output pointers are required");
  }
  *has_value = 0;
  *output = {};
  return guarded([&] {
    const auto *module = linux_app(app).mod_manager.find_by_name(name);
    if (!module) {
      return;
    }
    set_module(*output, *module);
    *has_value = 1;
  });
}

void sogen_dart_linux_mapped_module_free(
    sogen_dart_linux_mapped_module *module) {
  if (module) {
    free_module(*module);
  }
}

void sogen_dart_linux_mapped_module_list_free(
    sogen_dart_linux_mapped_module_list *list) {
  if (!list) {
    return;
  }
  for (size_t index = 0; index < list->length; ++index) {
    free_module(list->data[index]);
  }
  delete[] list->data;
  *list = {};
}
}
