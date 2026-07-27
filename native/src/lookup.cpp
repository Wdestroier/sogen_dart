#include <sogen_dart.h>

#include <cstdint>

#if defined(_WIN32)
#include <windows.h>
#else
#include <dlfcn.h>
#endif

extern "C" void *sogen_dart_lookup(const char *symbol) {
  if (!symbol) {
    return nullptr;
  }

#if defined(_WIN32)
  HMODULE module = nullptr;
  const auto address = reinterpret_cast<LPCSTR>(&sogen_dart_lookup);
  if (!GetModuleHandleExA(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS |
                              GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                          address, &module)) {
    return nullptr;
  }
  return reinterpret_cast<void *>(GetProcAddress(module, symbol));
#else
  Dl_info info{};
  const auto address = reinterpret_cast<void *>(
      reinterpret_cast<std::uintptr_t>(&sogen_dart_lookup));
  if (dladdr(address, &info) == 0) {
    return nullptr;
  }
  void *module = dlopen(info.dli_fname, RTLD_LAZY | RTLD_NOLOAD);
  if (!module) {
    return nullptr;
  }
  void *result = dlsym(module, symbol);
  dlclose(module);
  return result;
#endif
}
