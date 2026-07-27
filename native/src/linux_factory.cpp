#include <sogen_dart.h>

#include "app.hpp"
#include "error.hpp"
#include "linux_callbacks.hpp"
#include "linux_runtime.hpp"

#include <cstring>
#include <filesystem>
#include <memory>
#include <stdexcept>
#include <string>
#include <vector>

#include <backend_selection.hpp>
#include <linux_emulator.hpp>

namespace {
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

std::filesystem::path path_from_utf8(const char *value) {
  const auto *begin = reinterpret_cast<const char8_t *>(value);
  return std::filesystem::path{
      std::u8string{begin, begin + std::strlen(value)}};
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
  if (!values && count != 0) {
    throw std::invalid_argument(std::string{name} +
                                " are required when their count is non-zero");
  }
}

void apply_path_mappings(sogen::linux_emulator &emulator,
                         const sogen_dart_linux_path_mapping *mappings,
                         const size_t count, const bool read_only) {
  require_array(mappings, count, "Linux path mappings");
  for (size_t index = 0; index < count; ++index) {
    const auto &mapping = mappings[index];
    if (!mapping.guest_path_utf8 || !mapping.host_path_utf8) {
      throw std::invalid_argument(
          "Linux path mapping guest and host paths are required");
    }
    emulator.file_sys.add_path_mapping(path_from_utf8(mapping.guest_path_utf8),
                                       path_from_utf8(mapping.host_path_utf8),
                                       read_only);
  }
}

void apply_port_mappings(sogen::linux_emulator &emulator,
                         const sogen_dart_linux_port_mapping *mappings,
                         const size_t count) {
  require_array(mappings, count, "Linux port mappings");
  for (size_t index = 0; index < count; ++index) {
    const auto &mapping = mappings[index];
    if (mapping.emulator_port == 0 || mapping.host_port == 0) {
      throw std::invalid_argument(
          "Linux port mappings require ports in range 1..65535");
    }
    emulator.port_mapper.map_port(mapping.emulator_port, mapping.host_port);
  }
}

std::vector<std::string>
application_arguments(const std::filesystem::path &application,
                      const char *const *arguments, const size_t count) {
  require_array(arguments, count, "Linux application arguments");
  std::vector<std::string> result{application.string()};
  result.reserve(count + 1);
  for (size_t index = 0; index < count; ++index) {
    if (!arguments[index]) {
      throw std::invalid_argument(
          "Linux application arguments must not contain null entries");
    }
    result.emplace_back(arguments[index]);
  }
  return result;
}

std::vector<std::string>
application_environment(const sogen_dart_linux_environment_entry *environment,
                        const size_t count, const bool is_set) {
  if (!is_set) {
    if (count != 0) {
      throw std::invalid_argument("Linux environment count must be zero when "
                                  "the default environment is requested");
    }
    return {"PATH=/usr/bin:/bin", "HOME=/root", "TERM=xterm"};
  }

  require_array(environment, count, "Linux environment entries");
  std::vector<std::string> result{};
  result.reserve(count);
  for (size_t index = 0; index < count; ++index) {
    const auto &entry = environment[index];
    if (!entry.name_utf8 || !entry.value_utf8) {
      throw std::invalid_argument(
          "Linux environment names and values are required");
    }
    result.emplace_back(std::string{entry.name_utf8} + "=" + entry.value_utf8);
  }
  return result;
}

std::unique_ptr<sogen::linux_emulator> create_emulator(const char *root,
                                                       const int32_t backend) {
  return std::make_unique<sogen::linux_emulator>(
      sogen::create_x86_64_emulator(to_backend(backend)), path_from_utf8(root));
}
} // namespace

extern "C" {
sogen_dart_status sogen_dart_linux_create_empty(const char *root,
                                                const int32_t backend,
                                                const int32_t disable_logging,
                                                sogen_dart_app **output) {
  return sogen_dart_linux_create_empty_ex(root, backend, disable_logging,
                                          nullptr, 0, nullptr, 0, nullptr, 0,
                                          output);
}

sogen_dart_status sogen_dart_linux_create_application(
    const char *application, const char *root, const char *working_directory,
    const int32_t backend, const int32_t disable_logging,
    sogen_dart_app **output) {
  return sogen_dart_linux_create_application_ex(
      application, nullptr, 0, nullptr, 0, 0, root, working_directory, backend,
      disable_logging, nullptr, 0, nullptr, 0, nullptr, 0, output);
}

sogen_dart_status sogen_dart_linux_create_empty_ex(
    const char *root, const int32_t backend, const int32_t disable_logging,
    const sogen_dart_linux_path_mapping *path_mappings,
    const size_t path_mapping_count,
    const sogen_dart_linux_path_mapping *read_only_path_mappings,
    const size_t read_only_path_mapping_count,
    const sogen_dart_linux_port_mapping *port_mappings,
    const size_t port_mapping_count, sogen_dart_app **output) {
  if (!root || !output) {
    return sogen::dart::fail(SOGEN_DART_INVALID_ARGUMENT,
                             "Emulation root and output pointer are required");
  }
  *output = nullptr;
  return guarded([&] {
    auto app = std::make_unique<sogen_dart_app>();
    auto emulator = create_emulator(root, backend);
    apply_path_mappings(*emulator, path_mappings, path_mapping_count, false);
    apply_path_mappings(*emulator, read_only_path_mappings,
                        read_only_path_mapping_count, true);
    apply_port_mappings(*emulator, port_mappings, port_mapping_count);
    emulator->log.disable_output(disable_logging != 0);
    app->linux_callbacks =
        std::make_unique<sogen::dart::linux_callback_registry>(*app, *emulator);
    app->linux_runtime =
        std::make_unique<sogen::dart::linux_runtime_registry>(*app, *emulator);
    app->linux = emulator.release();
    *output = app.release();
  });
}

sogen_dart_status sogen_dart_linux_create_application_ex(
    const char *application, const char *const *arguments,
    const size_t argument_count,
    const sogen_dart_linux_environment_entry *environment,
    const size_t environment_count, const int32_t environment_is_set,
    const char *root, const char *working_directory, const int32_t backend,
    const int32_t disable_logging,
    const sogen_dart_linux_path_mapping *path_mappings,
    const size_t path_mapping_count,
    const sogen_dart_linux_path_mapping *read_only_path_mappings,
    const size_t read_only_path_mapping_count,
    const sogen_dart_linux_port_mapping *port_mappings,
    const size_t port_mapping_count, sogen_dart_app **output) {
  if (!application || !root || !working_directory || !output) {
    return sogen::dart::fail(SOGEN_DART_INVALID_ARGUMENT,
                             "Linux application arguments are required");
  }
  *output = nullptr;
  return guarded([&] {
    const auto application_path = path_from_utf8(application);
    auto argv =
        application_arguments(application_path, arguments, argument_count);
    auto envp = application_environment(environment, environment_count,
                                        environment_is_set != 0);
    auto app = std::make_unique<sogen_dart_app>();
    auto emulator = create_emulator(root, backend);
    emulator->process.current_working_directory =
        sogen::linux_file_system::normalize_guest_path_string(
            working_directory);
    apply_path_mappings(*emulator, path_mappings, path_mapping_count, false);
    apply_path_mappings(*emulator, read_only_path_mappings,
                        read_only_path_mapping_count, true);
    apply_port_mappings(*emulator, port_mappings, port_mapping_count);
    emulator->load_application(application_path, std::move(argv), envp);
    emulator->log.disable_output(disable_logging != 0);
    app->linux_callbacks =
        std::make_unique<sogen::dart::linux_callback_registry>(*app, *emulator);
    app->linux_runtime =
        std::make_unique<sogen::dart::linux_runtime_registry>(*app, *emulator);
    app->linux = emulator.release();
    *output = app.release();
  });
}
}
