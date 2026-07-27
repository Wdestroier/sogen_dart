# Sogen Dart Bindings Implementation Plan

## 1. Objective

Create a standalone Dart package that exposes the complete Sogen Python-binding feature set through native FFI. The package must build against an unmodified, pinned checkout of upstream Sogen and must not rely on sibling workspace files. The build will fetch Sogen, while applications still supply the emulation root required by Sogen at runtime. The first runnable milestone reproduces the original Python `main.py` on Windows x64:

```dart
import 'package:sogen/ctypes.dart' show uint32;
import 'package:sogen/windows.dart' show apiCall, createApplication;

final app = createApplication(
  r'c:/test-sample.exe',
  emulationRoot: './root',
);

final onSleep = apiCall(
  cc: .stdcall,
  params: [uint32],
  cb: (call, params) {
    print('Sleep(${params[0]})');
  },
);

app.hooks.apis['Sleep'] = onSleep;
app.start();
print('exit status: ${app.process.exitStatus}');
app.dispose();
```

The API deliberately keeps the Python binding's descriptor-list and `(call, params)` callback shape. Dart cannot infer a different static type for every position in a heterogeneous descriptor list without generated or arity-specific APIs; fidelity for library users takes priority. Maintainer-side generation is allowed and encouraged, but generated sources are committed and package users never run a generator. Windows x64 with Unicorn is the bootstrap milestone, not the final scope: completion requires Windows and Linux namespace parity, all common types, callbacks, hooks, state/memory/process/thread/module APIs, Windows API hooks, Linux symbol hooks, and the Linux debugger facade exposed by the pinned Python binding.

## 2. Source Baseline

During initial development, the following local files can be used only as references:

| Item | Path |
| --- | --- |
| Sogen source | `../sogen-main` |
| Python example to match | `../main.py` |
| Emulation root used by the example | `../root` |
| Installed Python type stub | `../.venv/Lib/site-packages/sogen.pyi` |
| Standalone Dart repository | `.` |

The local Python installation is `sogen 0.0.1.dev4771`, pinned to upstream commit `52df4d49a4ee45afff9acd00520badf33f1d4e5c`. The standalone repository fetches that revision into an ignored build directory, including submodules. Neither `../sogen-main`, `../main.py`, `../root`, nor `../.venv` may be a build or runtime dependency because those files will be deleted.

Upstream Sogen is an immutable dependency from this repository's perspective:

- Do not edit, patch, or generate files in the upstream source tree.
- Do not require a pull request to Sogen.
- Keep the complete C ABI adapter in `sogen_dart/native`.
- Build Sogen as a CMake subproject from a pinned clone under `build/deps`.
- Permit an optional `SOGEN_SOURCE_DIR` override for local development, but never depend on it for a clean checkout.
- Run all generated and compiled output outside the upstream source directory.

Primary references:

- Repository: <https://github.com/momo5502/sogen/>
- Python package documentation: <https://pypi.org/project/sogen/0.0.1.dev4771/>
- Emulation root: <https://sogen.dev/root.zip>
- License: <https://github.com/momo5502/sogen/blob/main/LICENSE> (`GPL-2.0-only`)

## 3. Findings That Drive the Design

### 3.1 The Python binary is not a reusable native library

`sogen.cp312-win_amd64.pyd` is a CPython extension built with nanobind. It exports Python module initialization and uses Python objects throughout its callback and ownership code. Dart FFI cannot safely or directly use this file as a Sogen library.

Embedding CPython would add Python as a runtime dependency, retain Python's GIL and callback semantics, and fail the goal of native Dart bindings. It is not part of this plan.

### 3.2 Sogen exposes C++ APIs but no stable C ABI

The Python module links directly to these C++ targets:

- `windows-emulator`
- `linux-emulator`
- `disassembler`
- `backend-selection`

The key C++ construction path is:

```cpp
auto backend = sogen::create_x86_64_emulator(sogen::backend_type::unicorn);
auto app = std::make_unique<sogen::windows_emulator>(
    std::move(backend), application_settings, emulator_settings);
```

C++ classes, exceptions, `std::function`, STL containers, smart pointers, and compiler-specific name mangling must not cross an FFI boundary. A small shared library with exported `extern "C"` functions is required.

### 3.3 The Python API hook logic is binding-specific

`../sogen-main/src/python-bindings/sogen_api_hooks.cpp` implements API-name indexing and dispatch by:

1. Watching module load and unload events.
2. Resolving bare names such as `Sleep` and qualified names such as `kernel32!Sleep`.
3. Indexing each module's `address_names` entries.
4. Installing a memory-execution hook.
5. Decoding arguments at a matching address.
6. Running the language callback.
7. Optionally writing the return value and redirecting `RIP`/`RSP` to intercept the API.

This logic is currently coupled to nanobind. The C ABI implementation must adapt the language-neutral behavior without including Python headers or Python objects.

For Python Windows API hooks, the declared ctypes determine the number of machine-word values to read. Dart will preserve that model through `package:sogen/ctypes.dart`: handwritten descriptors such as `uint32`, `int32`, `uint64`, `pointer`, and `bool32` validate and decode each raw word before the callback. Parameter count is derived internally from the descriptor list and will not appear in the public Dart API.

### 3.4 Execution and callbacks are synchronous

`windows_emulator::start()` blocks. With the default one-vCPU Unicorn configuration, hooks normally execute on the same native thread that called `start()` and must return before guest execution continues.

Consequences for Dart:

- Use a synchronous isolate-local native callback, not `NativeCallable.listener`.
- Create, configure, run, and destroy an application on one Dart isolate.
- Retain every native callback object until its hook is removed or the application is disposed.
- Do not send an application pointer to another isolate.
- Catch all Dart callback exceptions and return a deterministic fallback action.
- Do not dispose, mutate hooks, restore snapshots, or recursively start the emulator from a callback.

The first release will not provide asynchronous cancellation. Calling `stop()` from an unrelated thread is not safe for every Sogen backend. A later API can use bounded instruction runs or a native worker design after callback behavior is validated.

### 3.5 How the Python bindings are produced

The Python library itself is not generated. Its module registration and behavior are handwritten C++ under `../sogen-main/src/python-bindings`:

- `sogen_module.cpp` defines `NB_MODULE(sogen, m)`, creates `windows` and `linux` submodules, and invokes the registration functions.
- `sogen_bindings_types.cpp` registers common enums and value objects.
- `sogen_bindings_runtime.cpp` registers the Windows runtime surface and root Windows compatibility aliases.
- `sogen_bindings_linux_runtime.cpp` registers the Linux runtime surface.
- `sogen_wrappers.cpp` and `sogen_linux_wrappers.cpp` implement wrapper behavior and ownership.
- `sogen_callbacks.cpp` and `sogen_linux_callbacks.cpp` implement callback registries.
- `sogen_api_hooks.cpp` implements Windows API hooks.
- `sogen_helpers.cpp` implements factories, conversions, state helpers, and continuation coercion.
- `sogen_internal.hpp` and `sogen_bindings.hpp` declare the binding-only ownership types and registration functions.

`../sogen-main/src/python-bindings/CMakeLists.txt` uses `nanobind_add_module(sogen ...)` to compile every binding `.cpp` file and link `windows-emulator`, `linux-emulator`, `disassembler`, and `backend-selection`.

Only the Python type stub is generated. `nanobind_add_stub` imports the compiled extension and writes `sogen.pyi` plus `py.typed`. The current non-recursive stub is not a complete API specification: it omits most `windows` and `linux` submodule details, represents callback slots as `object`, cannot describe dynamic factory kwargs well, and exposes at least one invalid Windows permission type. Dart parity must therefore be derived from binding registration code, wrapper code, tests, and documentation rather than from `sogen.pyi` alone.

### 3.6 Full parity surface

The compatibility target is the public behavior of the pinned Python binding revision, including platform-dependent availability:

| Area | Required Dart coverage |
| --- | --- |
| Common | `Backend`, memory/register/instruction/continuation enums, `MemoryStats`, `Handle`, region/module/symbol/basic-block objects, and `ApiCall` |
| Root compatibility | Windows aliases corresponding to Python's root aliases, while Linux remains namespace-scoped |
| Windows factories | Empty/application creation, arguments, environment, working directory, root/registry settings, logging/time settings, fake environment, path mappings, port mappings, and backend selection |
| Windows emulator | Start/stop, counted execution, snapshots, serialization, process setup, scheduling, memory/register access, diagnostics, ports, process, memory, callbacks, and hooks |
| Windows process/thread | Process status/counts/current thread and every exposed thread property |
| Windows memory | Allocation/reserve/commit/decommit/protect/release, region lookup, free-base search, stats, and default allocation address |
| Windows callbacks | All twenty callback slots and their continuation semantics |
| Windows hooks | Execution/read/write/instruction/interrupt/violation/basic-block hooks, active/removal behavior, and registry-owned lifetime |
| Windows API hooks | Bare and qualified names, ctypes metadata, observation/interception, mutable return value, module refresh, deletion, replacement, and clear |
| Linux factories | Empty/application creation, arguments, environment/default environment, working directory, writable/read-only mappings, ports, logging, root, and backend selection |
| Linux emulator | Start/stop, counted execution, state, memory/register access, module lookup, scheduling, diagnostics, ports, process, memory, modules, callbacks, hooks, and debug |
| Linux process/thread | IDs, credentials, active/all threads, stacks/TLS/wait state/termination, retained wrapper semantics, and unsupported `previousIp` behavior |
| Linux memory/modules | Allocation-at-address, mappings, regions/stats, ELF metadata, sections, exports, dependencies, rpath/runpath, and module lookup |
| Linux callbacks | Stdout/stderr, syscall, memory violation/lifecycle, signal/exception alias, module replay, and thread lifecycle/switch callbacks plus `set`/`clear` |
| Linux hooks | All common low-level hooks with Linux-specific observer behavior and registry-owned lifetime |
| Linux symbol hooks | `symbolCall`, ctypes decoding, System V argument extraction, bare/qualified names, observation/interception, state restoration, deletion, and clear |
| Linux debugger | Breakpoints, stepping, run control, register/module/thread views, disassembly, call stack, stop reasons, and diagnostic errors |

Exact parity means every public Python feature has a Dart counterpart with equivalent behavior and ownership. It does not require reproducing known Python binding defects, ambiguous exported enum globals, Python's GIL, Python object types, snake_case spelling, or untyped `**kwargs`; intentional corrections must be listed in the README compatibility notes and tested.

## 4. Architecture

The package will have three layers:

```text
Dart public API and ctypes descriptors
    lib/sogen.dart
    lib/ctypes.dart
    lib/src/*.dart
          |
          v
Generated private Dart FFI declarations
    lib/src/ffi/sogen_native_bindings.g.dart
          |
          v
Versioned C ABI shared library
    native/include/sogen_dart.h
    native/src/*.cpp
          |
          v
Sogen C++ targets
    windows-emulator + linux-emulator + disassembler + backend-selection
```

### 4.1 Native C ABI

Expose opaque handles and fixed-width C types only. The header must be usable from C and must not include Sogen or C++ headers.

Proposed core types:

```c
typedef struct sogen_dart_app sogen_dart_app;
typedef uint64_t sogen_dart_hook_id;

typedef enum sogen_dart_status {
  SOGEN_DART_OK = 0,
  SOGEN_DART_INVALID_ARGUMENT = 1,
  SOGEN_DART_UNAVAILABLE = 2,
  SOGEN_DART_RUNTIME_ERROR = 3,
  SOGEN_DART_BAD_STATE = 4
} sogen_dart_status;

typedef enum sogen_dart_api_action {
  SOGEN_DART_API_RUN_ORIGINAL = 0,
  SOGEN_DART_API_INTERCEPT = 1
} sogen_dart_api_action;

typedef struct sogen_dart_api_call {
  const char* module_utf8;
  const char* name_utf8;
  uint64_t address;
  uint64_t return_address;
  uint64_t return_value;
} sogen_dart_api_call;

typedef sogen_dart_api_action (*sogen_dart_api_callback)(
    void* user_data,
    sogen_dart_api_call* call,
    const uint64_t* parameters,
    size_t parameter_count);
```

Each `sogen_dart_app` is tagged as Windows or Linux and privately owns:

- Exactly one `windows_emulator` or `linux_emulator`.
- The OS-specific callback and low-level hook registries.
- The Windows API-hook registry or Linux symbol-hook registry.
- All Dart hook callback registrations and user-data pointers.
- Lifecycle state such as `created`, `running`, and `destroying`.
- The most recent callback failure, if any.

The app owns all hooks. Destruction order must remove execution hooks and module observers before deleting the emulator. Hook removal must be idempotent.

Proposed first vertical-slice exports:

```c
uint32_t sogen_dart_abi_version(void);

sogen_dart_status sogen_dart_windows_create_application(
    const char* application_utf8,
    const char* emulation_root_utf8,
    sogen_dart_app** out_app);

sogen_dart_status sogen_dart_windows_add_api_hook(
    sogen_dart_app* app,
    const char* key_utf8,
    int32_t calling_convention,
    size_t parameter_count,
    sogen_dart_api_callback callback,
    void* user_data,
    sogen_dart_hook_id* out_hook);

sogen_dart_status sogen_dart_windows_remove_hook(
    sogen_dart_app* app,
    sogen_dart_hook_id hook);

sogen_dart_status sogen_dart_windows_start(sogen_dart_app* app);
sogen_dart_status sogen_dart_windows_stop(sogen_dart_app* app);

sogen_dart_status sogen_dart_windows_get_exit_status(
    sogen_dart_app* app,
    int32_t* has_value,
    int32_t* value);

sogen_dart_status sogen_dart_windows_get_last_stop_reason(
    sogen_dart_app* app,
    int32_t* value);

sogen_dart_status sogen_dart_windows_destroy(sogen_dart_app* app);

size_t sogen_dart_last_error(char* destination, size_t capacity);
```

These exports are only the first Windows vertical slice. The versioned ABI must grow in organized families for common values, Windows, Linux, callbacks, low-level hooks, API/symbol hooks, debugger operations, state buffers, lists, strings, and owned/borrowed object handles. Full parity must not be forced through one generic JSON or string-command function: use explicit typed C functions so `ffigen`, static analysis, ABI checks, and native debuggers remain useful.

The callback payload should contain borrowed UTF-8 module/name pointers, address, return address, and mutable return value. The pointers are valid only for the callback duration. Parameters are a borrowed `uint64_t` array.

Every exported function must:

- Validate pointers, lengths, enum values, and lifecycle state.
- Catch `std::exception` and unknown exceptions.
- Return a status code instead of throwing across FFI.
- Store an explanatory thread-local error string retrievable through `sogen_dart_last_error`.
- Keep allocation and deallocation inside the same native library.

The ABI must export an integer version from its first implementation. Dart must reject incompatible major ABI versions with a clear error.

### 4.2 Dart FFI layer

Use `package:ffigen` to generate the private low-level Dart declarations from the C-only public header. Dart FFI cannot bind Sogen's C++ classes, templates, STL types, exceptions, or overloaded methods directly, so the C ABI remains mandatory. `ffigen` consumes only `native/include/sogen_dart.h` and generated C declarations included by that header.

Generation is a maintainer workflow, not a consumer workflow:

1. A small declarative schema records stable enums, object kinds, repetitive getters, callback slot IDs, and list/value layouts.
2. `tool/generate_bindings.py` generates repetitive C declarations/implementations plus repetitive Dart enums, value-object accessors, callback-slot tables, and metadata from that schema.
3. Handwritten C++ implements factories, ownership, callbacks, hooks, state, mapping conversion, error translation, and other semantic behavior that cannot be safely generated.
4. `dart run ffigen --config ffigen.yaml` generates `lib/src/ffi/sogen_native_bindings.g.dart` from the resulting C header.
5. Generated sources are formatted, reviewed, committed, and included in the published package.
6. CI reruns generation and fails if `git diff --exit-code` detects stale generated files.

Do not parse arbitrary C++ with regular expressions or attempt to translate nanobind registration code automatically. The Python binding source is the compatibility specification, while the explicit schema is the stable Dart/C ABI specification. Clang-based tools may inspect C++ when useful, but generated output must remain deterministic and understandable.

Package users run neither Python, `ffigen`, `build_runner`, nor another generator. They import the committed library and build/use its native asset normally.

The FFI layer will:

- Load `sogen_dart.dll` on Windows.
- Verify `sogen_dart_abi_version()`.
- Convert Dart strings to temporary UTF-8 allocations for calls.
- Convert every nonzero native status into `SogenException` using `sogen_dart_last_error`.
- Keep callback/native-callable objects alive in a map keyed by hook ID.
- Copy borrowed strings and parameter values during the callback.
- Prevent use after disposal in Dart before reaching native code.

A synchronous callback implementation must use `NativeCallable.isolateLocal` or an equivalent synchronous Dart FFI callback supported by the selected minimum Dart SDK. `NativeCallable.listener` is unsuitable because it is asynchronous, returns `void`, and cannot decide whether an API call should run or be intercepted.

### 4.3 Public Dart API

Preserve the Python binding's API organization and semantic names, translated only to Dart's required or conventional camelCase spelling:

| Python | Dart |
| --- | --- |
| `sogen.windows.create_application(...)` | `createApplication(...)` from `package:sogen/windows.dart` |
| `sogen.windows.api_call(...)` | `apiCall(...)` from `package:sogen/windows.dart` |
| `app.hooks.apis["Sleep"] = hook` | `app.hooks.apis['Sleep'] = hook` |
| `sogen.CallingConvention.stdcall` | `.stdcall` where context infers `CallingConvention` |
| `sogen.ApiContinuation.run_original` | `ApiContinuation.runOriginal` |
| `app.process.exit_status` | `app.process.exitStatus` |
| `app.start()` | `app.start()` |

The directory and repository may remain named `sogen_dart`, but `pubspec.yaml` uses package name `sogen`. Platform libraries are imported directly, for example `package:sogen/windows.dart`, with `show` combinators used to keep call sites concise. Type descriptors live separately under `package:sogen/ctypes.dart`, matching Python's separate `ctypes` vocabulary. `package:sogen/sogen.dart` remains an aggregate compatibility library.

The root library exports common enums/value objects and Python-compatible Windows aliases. The `windows` namespace exports the Windows emulator, process, thread, memory, callback, hook, and API-hook surfaces. The `linux` namespace exports its distinct emulator, process, thread, memory, module, callback, hook, symbol-hook, wait-state, and debugger surfaces. Platform-specific classes remain distinguishable even where Python reuses a short class name inside each submodule.

`ApiHooks` implements `operator []` and `operator []=` so registration remains map-like. Assigning `null` removes a hook, matching Python behavior. The collection and the owning application retain registered hooks even if the caller does not store a separate `Hook` handle.

#### Ctypes-style consumer API

The public API must not expose `parameterCount`, record adapters, `.asParameters`, generated callback classes, or arity-specific `apiCall1`/`apiCall2` methods. Keep the Python model: `params` is a list of descriptors and the callback receives `(call, params)`. Name the callback argument `cb` in both `windows.apiCall` and `linux.symbolCall`.

`package:sogen/ctypes.dart` defines a small handwritten descriptor interface and constants:

```dart
abstract interface class CType<T> {
  T decode(int rawValue);
}

const CType<int> uint8 = Uint8Type();
const CType<int> int8 = Int8Type();
const CType<int> uint16 = Uint16Type();
const CType<int> int16 = Int16Type();
const CType<int> uint32 = Uint32Type();
const CType<int> int32 = Int32Type();
const CType<int> uint64 = Uint64Type();
const CType<int> int64 = Int64Type();
const CType<Uint8List> char = CharType();
const CType<int> pointer = PointerType();
const CType<bool> bool32 = Bool32Type();
```

`apiCall` derives the native parameter count from `params.length`, decodes each raw machine word with its matching descriptor, and passes an unmodifiable `List<dynamic>` to the callback. This is an intentional type-safety improvement over the current Python implementation, which uses the Windows ctypes list only for argument count. `bool32` decodes zero as `false` and nonzero as `true`. Integer descriptors enforce the requested signedness and width. Guest pointers remain integer guest addresses; they are never host `Pointer<T>` values.

The declaration and registration remain separate, as in the original example:

```dart
final onSleep = apiCall(
  cc: .stdcall,
  params: [uint32],
  cb: (call, params) {
    print('Sleep(${params[0]})');
  },
);

app.hooks.apis['Sleep'] = onSleep;
```

The descriptor list provides runtime validation and conversion but cannot make `params[0]`, `params[1]`, and later heterogeneous positions have different static Dart types. Dart has neither decorators nor variadic generics that can express Python's API exactly. Arity-specific public APIs would diverge from Python, so this limitation is accepted and documented rather than hidden behind unfamiliar syntax. Maintainer-side generation does not alter this consumer-facing callback shape.

A callback that completes without returning a continuation runs the original API, matching Python's `None` behavior. Returning `ApiContinuation.intercept` skips the original API; `ApiContinuation.runOriginal` remains available when an explicit return is clearer.

Support `params: []` for zero-argument APIs. Preserve optional `restype` in both decorator-equivalent functions. Windows descriptors add width/signedness decoding while preserving the same callable feature set; Linux symbol hooks implement Python's System V signed, unsigned, bool, char, and pointer decoding. `ApiCall.returnValue` and `LinuxSymbolCall.returnValue` remain integer machine values because the Python binding stores but does not currently apply `restype` conversion.

The same declaration-then-registration pattern applies to Linux symbols:

```dart
final onTarget = sogen.linux.symbolCall(
  params: [ctypes.int32],
  restype: ctypes.int32,
  cb: (call, params) {
    return sogen.ApiContinuation.runOriginal;
  },
);

app.hooks.symbols['target_function'] = onTarget;
```

`dispose()` is the primary lifetime mechanism. A Dart `Finalizer` may be added only as a leak fallback; correctness must not rely on finalizer timing. Calling any method after disposal must throw `StateError`. Disposing while running or from inside a callback must fail clearly rather than racing native destruction.

## 5. Proposed Package Layout

```text
sogen_dart/
  docs/
    PLAN.md
    PROGRESS.md
    PYTHON_PARITY.md
  README.md
  LICENSE
  pubspec.yaml
  analysis_options.yaml
  ffigen.yaml
  sogen.lock
  api/
    schema.yaml
  lib/
    ctypes.dart
    sogen.dart
    src/
      application.dart
      api_hook.dart
      ctypes.dart
      exceptions.dart
      native_library.dart
      types.dart
      ffi/
        sogen_native_bindings.g.dart
  native/
    CMakeLists.txt
    cmake/
      SogenDependency.cmake
    include/
      sogen_dart.h
      generated/
        sogen_dart_generated.h
    src/
      api_hook_registry.cpp
      api_hook_registry.hpp
      error.cpp
      error.hpp
      generated/
        sogen_dart_generated.cpp
      linux_symbol_hook_registry.cpp
      linux_symbol_hook_registry.hpp
      sogen_dart.cpp
  example/
    main.dart
  test/
    unit/
    native/
      windows/
      linux/
    fixtures/
      windows/
      linux/
  tool/
    bootstrap_native.ps1
    build_native.ps1
    generate_bindings.py
```

Do not copy or modify the Sogen source in this package. `sogen.lock` records the upstream repository URL and exact commit. `bootstrap_native.ps1` clones that revision with `--recurse-submodules` into ignored path `build/deps/sogen`. CMake accepts that path and may accept `SOGEN_SOURCE_DIR` only as an explicit developer override. A clean clone of `sogen_dart` must not search for `../sogen-main`.

The adapter is intentionally outside Sogen's source tree. Its CMake target includes Sogen's public headers and links Sogen targets after adding the dependency as a subdirectory. No patch application step is allowed.

## 6. Build Plan

### Phase 1: Parity specification and generation pipeline

1. Identify the upstream Sogen commit used for development and record it in `sogen.lock`.
2. Inventory the pinned `src/python-bindings` registration/wrapper files in `docs/PYTHON_PARITY.md` with one stable parity ID per public enum, type, method, property, callback slot, hook, factory option, and continuation behavior.
3. Record the corresponding Python test coverage and explicitly mark untested Python exports.
4. Define stable C ABI enum values, object kinds, callback slot IDs, list layouts, and repetitive accessors in `api/schema.yaml`.
5. Implement `tool/generate_bindings.py` with deterministic output and no dependency on the deleted sibling checkout.
6. Configure `ffigen.yaml` to consume only the package's C ABI header and emit committed private Dart declarations.
7. Add a generation-consistency CI check.

### Phase 2: Package and native build skeleton

1. Create package metadata with `name: sogen`, default analysis configuration, `lib/sogen.dart`, and `lib/ctypes.dart`.
2. Add bootstrap logic that creates only ignored build directories and recursively clones the pinned Sogen dependency.
3. Add a CMake project for a shared library named `sogen_dart` without changing Sogen's CMake files.
4. Configure the fetched Sogen source as a subproject with tools and Python bindings disabled.
5. Link the shared library privately to `windows-emulator`, `linux-emulator`, `disassembler`, and `backend-selection`.
6. Export C symbols explicitly using a local cross-platform export macro; do not require adding exports upstream.
7. Build with C++20 and `SOGEN_ENABLE_LTO=OFF` because Sogen's Python package records LTO-related API-hook interception failures.
8. Establish opaque handles, ABI versioning, thread-local errors, owned buffers/lists, callback user data, and deterministic destruction.

Expected development build shape:

```powershell
./tool/bootstrap_native.ps1
cmake -S native -B build/native `
  -DSOGEN_SOURCE_DIR=build/deps/sogen `
  -DSOGEN_BUILD_TOOLS=OFF `
  -DSOGEN_ENABLE_PYTHON_BINDINGS=OFF `
  -DSOGEN_ENABLE_LTO=OFF
cmake --build build/native --config Release
```

Exact generator and output paths must be verified against the local Visual Studio installation and Sogen's artifact-directory helpers before these commands are documented as final user instructions.

### Phase 3: Common and Windows parity

1. Implement all common enums/value objects and root Windows compatibility aliases.
2. Implement Windows empty/application factories with every Python kwarg represented as typed Dart named parameters and matching defaults.
3. Implement the full Windows emulator, process, thread, memory manager, module/symbol, state, scheduler, diagnostics, mapping, and port surface.
4. Implement all twenty Windows callback slots with Python-equivalent payloads and continuation coercion.
5. Implement all low-level hook families, idempotent handles, self-removal, and registry-owned lifetime.
6. Adapt Windows API target parsing, module indexing, argument resolution, observation/interception, replacement/deletion/clear, and callback exception behavior from `sogen_api_hooks.cpp`.
7. Recreate `main.py`, the `Sleep` observation test, the `hook-sample` interception test, state tests, and wrapper-lifetime tests in Dart.

### Phase 4: Linux parity

1. Implement Linux empty/application factories with every Python kwarg and default environment behavior.
2. Implement the full Linux emulator, process, retained thread wrappers, memory manager, ELF module/section/export, state, mappings, ports, diagnostics, and scheduler surface.
3. Implement every Linux callback, including `set`/`clear`, module replay, signal/exception shared slot, memory lifecycle, and thread lifecycle/switch behavior.
4. Implement all Linux low-level hooks with observer-specific behavior and shared `Hook` semantics.
5. Implement `symbolCall`, System V register/stack decoding, ctypes validation/conversion, symbol indexing, observation/interception, and restore-safe registration.
6. Implement the Linux debugger facade: breakpoints, stepping, run control, views, disassembly, call stack, and diagnostic failures.
7. Port every behavior in `test_linux.py` into focused Dart integration tests and add tests for exposed Linux methods not covered there.

### Phase 5: Dart public wrapper and API audit

1. Generate and review the private FFI declarations.
2. Implement dynamic library/native-asset discovery with an explicit override for tests and development.
3. Implement status/exception conversion, owned buffer/list conversion, and deterministic object ownership.
4. Implement the Python-like root, `windows`, `linux`, callbacks, hooks, process, enum, and continuation organization using Dart camelCase.
5. Implement handwritten `ctypes.dart` descriptors and descriptor-list decoding with `cb` naming.
6. Add synchronous callback trampolines and exception containment.
7. Audit every ID in `docs/PYTHON_PARITY.md`; no Python feature may remain unimplemented or untested for release.
8. Document emulation roots, guest paths, backend/platform availability, deliberate differences, and disposal requirements.

### Phase 6: Verification and packaging

1. Run `dart format --output=none --set-exit-if-changed .`.
2. Run `dart analyze` with no diagnostics.
3. Regenerate schema output and `ffigen` output; require a clean diff.
4. Run all Dart unit tests that do not require native assets.
5. Build the native library in Release mode on the supported Windows, Linux, and macOS hosts used by the Python wheels where feasible.
6. Run Windows native tests with `test-sample.exe`, mandatory `hook-sample.exe`, and a supplied Windows emulation root.
7. Run Linux synthetic/native tests with Unicorn and application tests with every available Python-supported backend, including KVM where CI permits it.
8. During development, compare Dart and Python results from the same pinned source, fixtures, roots, and backends; published tests must not depend on Python.
9. Run clang-format and the package's clang-tidy configuration on adapter C++ files without modifying fetched Sogen sources.
10. Document native library placement/assets, runtime dependencies, source/license obligations, and clean-machine setup.

## 7. Completion Criteria

Full Python-binding parity is complete only when all of the following are true:

- Every entry in `docs/PYTHON_PARITY.md` is implemented or marked as an intentional, documented Dart-language difference rather than an omitted feature.
- Every public Python factory option, method, property, callback slot, hook type, continuation, debugger operation, and namespace alias has an equivalent Dart API.
- Windows and Linux factories, emulators, memory/process/thread/module models, callbacks, low-level hooks, state APIs, mappings, and ports pass Dart tests.
- Windows API hooks support observation, interception, ctypes metadata, bare/qualified names, mutation/removal/clear, and Python-equivalent ownership.
- Linux symbol hooks support Python-equivalent ctypes validation/decoding, System V arguments, observation/interception, restore behavior, mutation/removal/clear, and ownership.
- The complete Linux debugger facade passes Dart tests.
- `dart analyze` and all applicable test shards succeed.
- A clean checkout bootstraps the pinned recursive Sogen dependency without sibling directories and never patches fetched sources.
- Maintainer generation is deterministic and produces no diff; package users do not run Python, `ffigen`, `build_runner`, or another source generator.
- The C ABI builds on each declared host/architecture, while backend availability matches upstream Sogen's platform rules.
- No C++ or Dart exception crosses the FFI boundary.
- Owned and borrowed handles, callback lifetimes, hook self-removal, state restoration, and repeated disposal are safe under stress tests.
- The Windows example declares `onSleep` separately with `cb`, registers it with `app.hooks.apis['Sleep'] = onSleep;`, and behaves like the Python example.
- The public API contains no `parameterCount`, `.asParameters`, or arity-specific `apiCall1` methods.
- Missing libraries, roots, fixtures, unsupported backends, callback failures, and invalid state produce actionable errors or explicit test skips.
- Compatibility notes list corrections such as Dart camelCase and any Python binding defect not reproduced.
- Security-boundary limitations and GPL-2.0-only source/binary redistribution obligations are documented.

## 8. Testing Strategy

The Python references are `src/python-bindings/test.py` and `test_linux.py`. They are monolithic assertion scripts, so Dart should preserve their behaviors while splitting them into focused tests with tags such as `native`, `windowsGuest`, `linux`, `unicorn`, `kvm`, `requiresCc`, and `requiresNetwork`.

### Dart unit and API tests

- Root, `windows`, and `linux` API surface and compatibility aliases.
- Enum values, aliases, permissions, continuation coercion, stop reasons, and ABI mappings.
- All factory option/default conversions and invalid option validation.
- Signed/unsigned/char/pointer/`bool32` ctypes conversion and unsupported-type rejection.
- Callback slot name mapping, Linux short/`on_` names, and signal/exception aliasing.
- Disposed-object guards, hook state, ABI mismatch, native-library discovery, and error conversion.
- Generated-file freshness and one-to-one schema/parity-manifest coverage.

### Native ABI tests

- ABI version, null/invalid arguments, UTF-8, thread-local errors, owned buffers/lists, object-kind validation, and lifecycle transitions.
- Callback registration/replacement/removal, callback user data, self-removal, and exception containment.
- API/symbol target parsing, module matching rules, continuation mapping, and idempotent hook removal.
- Generated getter/enum/callback-slot coverage against `api/schema.yaml`.

### Windows Dart integration tests

- Empty-emulator surface, memory/register state serialization, snapshots, diagnostics, and process setup.
- Full memory manager, process/thread/scheduler, port, mapping, module, and exported-symbol APIs.
- Every Windows callback slot and every low-level hook family, including boolean/enum continuations.
- `test-sample.exe` with stdout, path/port mappings, normal exit, and observed `Sleep` parameters.
- Mandatory `hook-sample.exe` tests for unretained hook lifetime and `GetCurrentProcessId` interception.
- API hook bare/qualified matching, replacement, deletion, `null`, clear, callback failure, call metadata, and WOW64 behavior where fixtures permit it.
- All Windows factory arguments/defaults and repeated owner/child-wrapper teardown.

### Linux Dart integration tests

- Empty emulator, memory permissions/regions/stats/lifecycle, registers, snapshots, serialization, threads, and stop diagnostics.
- Execution/read/write/instruction/basic-block/interrupt/memory-violation hooks, self-removal, and resume/restart/stop behavior.
- Signals and the exception alias, handled/fatal delivery, syscall continuations, thread lifecycle/switching, and retained wrappers.
- `/bin/true` counted and complete runs across available Unicorn/KVM/Icicle support.
- ELF modules, sections, exports, runtime module replay, lookup, and restored metadata.
- Working directory, writable/read-only mappings, longest-prefix and symlink confinement, mprotect, and host-FD state restoration.
- Mapped TCP proxy behavior, guest endpoint preservation, port lookup/replacement, and explicit unsupported-state serialization failures.
- Symbol observation/interception, signed/unsigned/char/bool/pointer decoding, stack arguments, qualified names, invalid signatures, restore behavior, deletion, and clear.
- Debug breakpoints, stepping, run-to/pause/continue, registers/modules/threads, disassembly, call stack, and every diagnostic failure.

### Coverage policy

- Port every assertion in both Python scripts to Dart or record why it is inapplicable.
- Add Dart tests for binding exports that Python exposes but its scripts do not test.
- Any test calling `createEmpty` is native integration, even if it executes only synthetic instructions.
- Keep root/guest binaries, host compiler, KVM, and network requirements in separately tagged shards.
- Never silently skip `hook-sample`, the only controlled Windows API-interception fixture.
- During development, differential tests may run Python and Dart against the same pinned source and fixture; released tests must not require Python.

## 9. Out Of Scope

Only features not exposed by the pinned Python bindings are outside parity scope:

- Python embedding or invoking the `.pyd` file.
- Automatically downloading or redistributing an emulation root.
- Flutter plugin UI integration and mobile/web packaging beyond platforms supported by the native dependency work.
- New asynchronous or cross-isolate execution APIs not present in Python.
- New native Sogen functionality such as minidump APIs that the pinned Python binding does not expose.
- An optional generated strongly typed convenience API over `(call, params)`; it may be considered later but cannot replace the compatible API.

Dart must never bind directly to Sogen C++ symbols. Future non-parity features extend the versioned C ABI first.

## 10. Risks and Mitigations

| Risk | Mitigation |
| --- | --- |
| Sogen has no stable C ABI | Keep a small versioned façade and pin the tested Sogen revision. |
| Python package and checkout versions differ | Record one compatibility baseline before tests or implementation. |
| The original sibling checkout will be deleted | Bootstrap the pinned recursive clone under ignored `build/deps`; never search parent directories. |
| Upstream changes would require a pull request | Keep all adapter code and build integration in this repository; treat fetched Sogen as read-only. |
| A heterogeneous descriptor list cannot statically type each list index | Accept the documented `List<dynamic>` callback shape to preserve Python fidelity and avoid code generation or arity-specific APIs. |
| Full parity creates a large repetitive ABI | Generate enums, getters, callback IDs, and low-level Dart declarations from a reviewed schema; handwrite semantic behavior. |
| Generated code drifts from its schema/header | Commit generated output and require regeneration to produce a clean CI diff. |
| The generated Python stub is incomplete | Use registration code, wrappers, tests, and docs as the parity source; track every item in `docs/PYTHON_PARITY.md`. |
| Callback lifetime causes use-after-free | App owns hook registrations; Dart retains native callables until removal/disposal. |
| C++ exception crosses FFI | Catch all exceptions in every exported function and return status/error text. |
| Dart exception escapes callback | Catch in trampoline, record it, and return a defined fallback action. |
| Blocking `start()` freezes an isolate | Document synchronous behavior and recommend a dedicated isolate for an entire run, without sharing handles. |
| Cross-thread stop is backend-dependent | Match Python's synchronous execution API and do not add unsupported asynchronous guarantees. |
| Hook mutation during callback can invalidate registries | Design deferred removal/self-removal explicitly and test every supported mutation path. |
| LTO breaks hook interception | Build native bindings with `SOGEN_ENABLE_LTO=OFF`. |
| 32-bit interception semantics differ | Match the pinned Python implementation and add WOW64 fixtures before claiming that platform path. |
| Native dependency packaging is large/complex | First deliver a source build; inventory and automate runtime DLL packaging afterward. |
| Upstream internals change frequently | Keep upstream adaptation in the native façade and regression-test the pinned revision. |
| Full integration tests are expensive and environment-specific | Split tagged CI shards and make requirements/skips explicit without reducing parity accounting. |
| Sogen is not a malware sandbox boundary | Document host-access and trust limitations prominently. |
| GPL-2.0-only affects distribution | Preserve license notices and review distribution obligations before publishing binaries. |

## 11. Decisions Required Before Broader Releases

Before publishing the parity release, decide:

1. Which exact upstream commit is the first compatibility baseline; the implementation will pin it rather than depend on a sibling checkout.
2. Whether native binaries are distributed through pub.dev native assets, GitHub releases, a Flutter plugin, or source-only instructions.
3. Minimum Dart SDK is 3.12.0 for synchronous `NativeCallable.isolateLocal`
   callbacks and current dot-shorthand syntax.
4. Whether a future optional typed convenience layer is worthwhile in addition to, not instead of, the ctypes-compatible API.
5. Which host/architecture matrix receives prebuilt native assets versus source-build support.

## 12. Implementation Order Summary

1. Pin Sogen and create the complete Python-parity manifest.
2. Establish the schema, Python generator, C ABI, `ffigen`, and stale-generation CI check.
3. Implement common types, ownership, errors, buffers, and callback infrastructure.
4. Implement and test full Windows parity, using the original example as the first vertical slice.
5. Implement and test full Linux parity, symbol hooks, and debugger support.
6. Audit every Python export and port both Python assertion scripts into focused Dart tests.
7. Validate supported platforms/backends, generated output, disposal/lifetimes, and differential behavior.
8. Document API mapping, build/runtime setup, roots, platform limits, intentional differences, licensing, and security boundaries.
