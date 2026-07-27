#include "api_hook_registry.hpp"

#include <algorithm>
#include <cctype>
#include <stdexcept>

#include <emulator_utils.hpp>
#include <function_calling_convention.hpp>
#include <windows_emulator.hpp>

namespace sogen::dart {
namespace {
std::string lower_ascii(std::string value) {
  std::ranges::transform(value, value.begin(),
                         [](const unsigned char character) {
                           return static_cast<char>(std::tolower(character));
                         });
  return value;
}

api_hook_target parse_target(const std::string &key) {
  const auto separator = key.find('!');
  if (separator == std::string::npos) {
    return {.name = key};
  }

  return {.module = key.substr(0, separator),
          .name = key.substr(separator + 1)};
}

bool matches_module(const api_hook_entry &entry, const mapped_module &module) {
  if (!entry.module_filter) {
    return true;
  }

  const auto expected = lower_ascii(*entry.module_filter);
  const auto name = lower_ascii(module.name);
  auto stem = name;
  if (const auto dot = stem.rfind('.'); dot != std::string::npos) {
    stem.erase(dot);
  }

  return expected == name || expected == stem;
}

function_calling_convention to_calling_convention(const int32_t value) {
  switch (value) {
  case SOGEN_DART_CALLING_CONVENTION_CDECL:
    return function_calling_convention::x86_cdecl;
  case SOGEN_DART_CALLING_CONVENTION_STDCALL:
    return function_calling_convention::x86_stdcall;
  case SOGEN_DART_CALLING_CONVENTION_FASTCALL:
    return function_calling_convention::x64_fastcall;
  case SOGEN_DART_CALLING_CONVENTION_SYSCALL:
    return function_calling_convention::x64_syscall;
  default:
    throw std::invalid_argument("Invalid calling convention");
  }
}
} // namespace

api_hook_registry::api_hook_registry(windows_emulator &emulator)
    : emulator_(&emulator) {
  this->module_load_id_ = this->emulator_->callbacks.on_module_load.add(
      [this](mapped_module &) { this->refresh(); });
  this->module_unload_id_ = this->emulator_->callbacks.on_module_unload.add(
      [this](mapped_module &) { this->refresh(); });
}

api_hook_registry::~api_hook_registry() {
  this->clear();
  this->emulator_->callbacks.on_module_load.remove(this->module_load_id_);
  this->emulator_->callbacks.on_module_unload.remove(this->module_unload_id_);
}

sogen_dart_hook_id
api_hook_registry::set(const std::string &key, const int32_t calling_convention,
                       const size_t parameter_count,
                       const sogen_dart_api_callback callback,
                       void *user_data) {
  const auto target = parse_target(key);
  if (target.name.empty()) {
    throw std::invalid_argument("API hook key must contain an export name");
  }

  static_cast<void>(to_calling_convention(calling_convention));
  const auto id = this->next_id_++;
  this->entries_[key] = api_hook_entry{
      .id = id,
      .module_filter = target.module,
      .name = target.name,
      .calling_convention = calling_convention,
      .parameter_count = parameter_count,
      .callback = callback,
      .user_data = user_data,
  };
  this->refresh();
  return id;
}

void api_hook_registry::remove(const sogen_dart_hook_id id) {
  const auto entry = std::ranges::find_if(
      this->entries_, [id](const auto &pair) { return pair.second.id == id; });
  if (entry == this->entries_.end()) {
    return;
  }

  this->entries_.erase(entry);
  this->refresh();
}

void api_hook_registry::clear() {
  this->entries_.clear();
  this->address_index_.clear();
  this->remove_execution_hook();
}

bool api_hook_registry::in_callback() const { return this->in_callback_; }

void api_hook_registry::refresh() {
  this->address_index_.clear();
  if (this->entries_.empty()) {
    this->remove_execution_hook();
    return;
  }

  this->ensure_execution_hook();
  for (const auto &[_, module] : this->emulator_->mod_manager.modules()) {
    for (const auto &[key, entry] : this->entries_) {
      this->add_entry_for_module(key, entry, module);
    }
  }
}

void api_hook_registry::ensure_execution_hook() {
  if (this->execution_hook_) {
    return;
  }

  this->execution_hook_ = this->emulator_->emu().hook_memory_execution(
      [this](cpu_interface &, const uint64_t address) {
        try {
          this->dispatch_address(address);
        } catch (...) {
          return;
        }
      });
}

void api_hook_registry::remove_execution_hook() {
  if (!this->execution_hook_) {
    return;
  }

  this->emulator_->emu().delete_hook(this->execution_hook_);
  this->execution_hook_ = nullptr;
}

void api_hook_registry::add_entry_for_module(const std::string &key,
                                             const api_hook_entry &entry,
                                             const mapped_module &module) {
  if (!matches_module(entry, module)) {
    return;
  }

  for (const auto &[address, name] : module.address_names) {
    if (name == entry.name) {
      this->address_index_[address].push_back(
          {key, entry.id, module.name, name, address});
    }
  }
}

void api_hook_registry::dispatch_address(const uint64_t address) {
  const auto found = this->address_index_.find(address);
  if (found == this->address_index_.end()) {
    return;
  }

  auto &cpu = this->emulator_->emu();
  const auto is_32_bit = is_32bit_code_segment(cpu);
  const auto stack_pointer = cpu.reg<uint64_t>(x86_register::rsp);
  uint64_t return_address{};
  if (is_32_bit) {
    uint32_t return_address_32{};
    if (!cpu.try_read_memory(stack_pointer, &return_address_32,
                             sizeof(return_address_32))) {
      return;
    }
    return_address = return_address_32;
  } else if (!cpu.try_read_memory(stack_pointer, &return_address,
                                  sizeof(return_address))) {
    return;
  }

  const auto hits = found->second;
  for (const auto &hit : hits) {
    this->invoke_hook(hit, return_address, stack_pointer, is_32_bit);
  }
}

void api_hook_registry::invoke_hook(const api_hook_hit &hit,
                                    const uint64_t return_address,
                                    const uint64_t stack_pointer,
                                    const bool is_32_bit) {
  const auto found = this->entries_.find(hit.key);
  if (found == this->entries_.end() || found->second.id != hit.id) {
    return;
  }

  const auto &entry = found->second;
  auto &cpu = this->emulator_->emu();
  const auto convention = is_32_bit
                              ? to_calling_convention(entry.calling_convention)
                              : function_calling_convention::x64_fastcall;
  const auto parameters =
      get_function_arguments(cpu, convention, entry.parameter_count);
  sogen_dart_api_call call{
      .module_utf8 = hit.module_name.c_str(),
      .name_utf8 = hit.export_name.c_str(),
      .address = hit.address,
      .return_address = return_address,
      .return_value = 0,
  };

  this->in_callback_ = true;
  const auto action = entry.callback(entry.user_data, &call, parameters.data(),
                                     parameters.size());
  this->in_callback_ = false;
  if (action != SOGEN_DART_API_ACTION_INTERCEPT) {
    return;
  }

  auto stack_adjust = is_32_bit ? sizeof(uint32_t) : sizeof(uint64_t);
  if (is_32_bit && convention == function_calling_convention::x86_stdcall) {
    stack_adjust += sizeof(uint32_t) * entry.parameter_count;
  }
  cpu.reg<uint64_t>(x86_register::rax, call.return_value);
  cpu.reg<uint64_t>(x86_register::rsp, stack_pointer + stack_adjust);
  cpu.reg<uint64_t>(x86_register::rip, call.return_address);
}
} // namespace sogen::dart
