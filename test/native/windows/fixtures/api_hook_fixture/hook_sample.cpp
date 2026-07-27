// Source:
// https://github.com/momo5502/sogen/tree/52df4d49a4ee45afff9acd00520badf33f1d4e5c/src/samples/hook-sample

#include <intrin.h>
#include <windows.h>

#include <cstdint>
#include <cstring>

constexpr DWORD kExpectedPid = 0xC0FFEE01;
constexpr uint64_t kPayload = 0x0102030405060708;
constexpr uint32_t kFaultValue = 0x24681357;
constexpr uintptr_t kUnmappedAddress = 0x22220000;
constexpr int kSkippedCpuidValue = 0x13572468;

extern "C" {
__declspec(dllexport) volatile uint64_t hook_read_payload = kPayload;
__declspec(dllexport) volatile uint64_t hook_write_payload = 0;
__declspec(dllexport) volatile uint64_t hook_tsc_payload = 0;

__declspec(dllexport) __declspec(noinline) void hook_execution_probe() {
  hook_write_payload = hook_read_payload;
}
}

int run_hook_payloads() {
  hook_execution_probe();

  int cpu_info[4]{};
  __cpuid(cpu_info, 0);
  hook_tsc_payload = __rdtsc();
  unsigned int auxiliary{};
  hook_tsc_payload = __rdtscp(&auxiliary);

  return hook_write_payload == kPayload ? 0 : 2;
}

extern "C" __declspec(dllexport) __declspec(noinline) int
hook_instruction_probe(const bool expect_skipped) {
  int cpu_info[4]{};
  __cpuid(cpu_info, 0);
  if (!expect_skipped) {
    return cpu_info[0] > 0 ? 0 : 3;
  }

  return cpu_info[0] == kSkippedCpuidValue ? 0 : 4;
}

int run_unmapped_read() {
  __try {
    const auto *value =
        reinterpret_cast<volatile const uint32_t *>(kUnmappedAddress);
    return *value == kFaultValue ? 0 : 5;
  } __except (EXCEPTION_EXECUTE_HANDLER) {
    return 0;
  }
}

int run_unmapped_write() {
  __try {
    auto *value = reinterpret_cast<volatile uint32_t *>(kUnmappedAddress);
    *value = kFaultValue;
    return *value == kFaultValue ? 0 : 5;
  } __except (EXCEPTION_EXECUTE_HANDLER) {
    return 0;
  }
}

int run_unmapped_execute() {
  __try {
    const auto function = reinterpret_cast<int (*)()>(kUnmappedAddress);
    return function() == 42 ? 0 : 5;
  } __except (EXCEPTION_EXECUTE_HANDLER) {
    return 0;
  }
}

int run_protection_read() {
  auto *value = static_cast<volatile uint32_t *>(
      VirtualAlloc(nullptr, 0x1000, MEM_RESERVE | MEM_COMMIT, PAGE_READWRITE));
  if (!value) {
    return 6;
  }
  *value = kFaultValue;
  DWORD old_protection{};
  if (!VirtualProtect(const_cast<uint32_t *>(value), 0x1000, PAGE_NOACCESS,
                      &old_protection)) {
    return 7;
  }
  __try {
    return *value == kFaultValue ? 0 : 8;
  } __except (EXCEPTION_EXECUTE_HANDLER) {
    return 0;
  }
}

int run_protection_write() {
  auto *value = static_cast<volatile uint32_t *>(
      VirtualAlloc(nullptr, 0x1000, MEM_RESERVE | MEM_COMMIT, PAGE_READONLY));
  if (!value) {
    return 9;
  }
  __try {
    *value = kFaultValue;
    return *value == kFaultValue ? 0 : 10;
  } __except (EXCEPTION_EXECUTE_HANDLER) {
    return 0;
  }
}

int run_protection_execute() {
  auto *code = static_cast<uint8_t *>(
      VirtualAlloc(nullptr, 0x1000, MEM_RESERVE | MEM_COMMIT, PAGE_READWRITE));
  if (!code) {
    return 11;
  }
  constexpr uint8_t return_42[] = {0xB8, 0x2A, 0x00, 0x00, 0x00, 0xC3};
  std::memcpy(code, return_42, sizeof(return_42));
  __try {
    const auto function = reinterpret_cast<int (*)()>(code);
    return function() == 42 ? 0 : 12;
  } __except (EXCEPTION_EXECUTE_HANDLER) {
    return 0;
  }
}

int main(const int argc, char **argv) {
  if (argc > 1) {
    if (std::strcmp(argv[1], "hooks") == 0) {
      return run_hook_payloads();
    }
    if (std::strcmp(argv[1], "instruction-run") == 0) {
      return hook_instruction_probe(false);
    }
    if (std::strcmp(argv[1], "instruction-skip") == 0) {
      return hook_instruction_probe(true);
    }
    if (std::strcmp(argv[1], "interrupt") == 0) {
      __debugbreak();
      return 0;
    }
    if (std::strcmp(argv[1], "violation-unmapped-read") == 0) {
      return run_unmapped_read();
    }
    if (std::strcmp(argv[1], "violation-unmapped-write") == 0) {
      return run_unmapped_write();
    }
    if (std::strcmp(argv[1], "violation-unmapped-execute") == 0) {
      return run_unmapped_execute();
    }
    if (std::strcmp(argv[1], "violation-protection-read") == 0) {
      return run_protection_read();
    }
    if (std::strcmp(argv[1], "violation-protection-write") == 0) {
      return run_protection_write();
    }
    if (std::strcmp(argv[1], "violation-protection-execute") == 0) {
      return run_protection_execute();
    }
    return 13;
  }

  Sleep(7);
  return GetCurrentProcessId() == kExpectedPid ? 0 : 1;
}
