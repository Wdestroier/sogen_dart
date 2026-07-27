# Python parity manifest

Baseline: Sogen `0.0.1.dev4771`, upstream commit
`52df4d49a4ee45afff9acd00520badf33f1d4e5c`. The source inventory is
`build/deps/sogen/src/python-bindings/sogen_bindings_*.cpp`; tested Python
behavior is from `test.py` and `test_linux.py` at that revision.

Status:

- `tested`: implemented in Dart and the C adapter with a checked-in test.
- `implemented`: implemented, but the exact row has no independent test.
- `fixture-gated`: tested when the named external fixture/host capability is available.
- `host-gap`: implemented but not exercised on every applicable host/backend.
- `intentional-difference`: documented Dart behavior intentionally differs.
- `unavailable`: no honest equivalent is possible with the pinned native behavior.

Evidence abbreviations are paths relative to this package: `app` is
`lib/src/application.dart`, `linux` is `lib/src/linux.dart`, `lhooks` is
`lib/src/linux_hooks.dart`, and `C ABI` is `native/include/sogen_dart.h` plus
the matching `native/src` implementation. `abi_test` means
`native/test/abi_test.cpp`.

The unit of this manifest is a Python registration: one enum/type/alias,
factory option, callable, property, callback slot, registry operation, or
tested behavior per row. Enum rows cover the named enum registration and list
all of its members; members are not separate callables. Overloads with the
same behavior share one row, while independently readable properties and
independently callable methods do not.

## Common types

| ID | Python public feature or tested behavior | Dart/native evidence | Status and test evidence |
| --- | --- | --- | --- |
| C.01 | `Backend.unicorn` | generated `Backend`; C ABI backend enum | tested: all native Dart suites use Unicorn |
| C.02 | `Backend.icicle` | generated `Backend`; both factories route it | host-gap: compiled, not run in checked-in tests |
| C.03 | `Backend.whp` | generated `Backend`; both factories route it | host-gap: Windows-only backend not run in checked-in tests |
| C.04 | `Backend.kvm` | generated `Backend`; both factories route it | host-gap: requires a Linux KVM host |
| C.05 | `MemoryPermission` values, including combined values | generated enum from `api/schema.yaml` | tested: `ctypes_test.dart`, Windows/Linux core and collection tests |
| C.06 | `MemoryOperation is MemoryPermission` | generated typedef alias | tested: continuation and native hook tests |
| C.07 | `MemoryRegionKind` values | generated enum; C ABI region field | tested: Windows/Linux memory tests |
| C.08 | `MemoryViolationType` values | generated enum; callback adapters | tested: Windows/Linux violation tests |
| C.09 | all 51 `Register` values | generated enum; native checked conversion tables | implemented: general-purpose and segment members are exercised; XMM members are not independently exercised |
| C.10 | `HookContinuation.run/skip/finalize_rip` | generated enum; `hook_continuation.dart` | tested: `hook_continuation_test.dart`, low-hook tests |
| C.11 | `MemoryViolationContinuation.stop/resume/restart` | generated enum; `hook_continuation.dart` | tested: `hook_continuation_test.dart`, violation tests |
| C.12 | `Instruction.invalid/syscall/cpuid/rdtsc/rdtscp` | generated enum; C hook ABI | tested: CPUID, syscall and timing paths; `invalid` is validation-only |
| C.13 | `CallingConvention.cdecl/stdcall/fastcall/syscall` | generated enum; API decoder | tested: unit decoding plus x86 stdcall/x64 fixture dispatch; cdecl/syscall have descriptor coverage but no dedicated guest fixture |
| C.14 | `ApiContinuation.run_original/intercept/skip` | generated enum with `skip` alias | tested: `api_hook_test.dart`, Windows and Linux integration tests |
| C.15 | `ThreadWaitState.running/futex_wait/sleeping` | generated enum; Linux thread model | implemented: running is tested; futex/sleeping need workload fixtures |
| C.16 | `MemoryStats.reserved_memory` | generated `MemoryStats.reservedMemory`; C ABI layout | tested: Windows core test |
| C.17 | `MemoryStats.committed_memory` | generated `MemoryStats.committedMemory`; C ABI layout | tested: Windows core test |
| C.18 | `Handle.bits` read/write | `types.dart` | tested: `ctypes_test.dart` |
| C.19 | `Handle.id` | packed accessor in `types.dart` | tested: `ctypes_test.dart` |
| C.20 | `Handle.type` | packed accessor in `types.dart` | tested: `ctypes_test.dart` |
| C.21 | `Handle.is_system` | packed accessor in `types.dart` | tested: `ctypes_test.dart` |
| C.22 | `Handle.is_pseudo` | packed accessor in `types.dart` | tested: `ctypes_test.dart` |
| C.23 | `Handle.high_bits` | packed accessor in `types.dart` | tested: `ctypes_test.dart` |
| C.24 | `MemoryRegionInfo.start` | generated accessor and C layout | tested: Windows core/Linux collections |
| C.25 | `MemoryRegionInfo.length` | generated accessor and C layout | tested: Linux collections |
| C.26 | `MemoryRegionInfo.permissions` | generated accessor and C layout | tested: Windows core/Linux collections |
| C.27 | `MemoryRegionInfo.allocation_base` | generated accessor and C layout | tested: Linux collections |
| C.28 | `MemoryRegionInfo.allocation_length` | generated accessor and C layout | tested: Linux collections |
| C.29 | `MemoryRegionInfo.is_reserved` | generated accessor and C layout | tested: Linux collections |
| C.30 | `MemoryRegionInfo.is_committed` | generated accessor and C layout | tested: Windows core/Linux collections |
| C.31 | `MemoryRegionInfo.initial_permissions` | generated accessor and C layout | tested: Linux collections |
| C.32 | `MemoryRegionInfo.kind` | generated accessor and C layout | tested: Linux collections |
| C.33 | `BasicBlock.address` | generated `BasicBlock`; hook adapters | tested: Windows/Linux low-hook tests |
| C.34 | `BasicBlock.instruction_count` | generated `BasicBlock`; hook adapters | tested: Windows/Linux low-hook tests |
| C.35 | `BasicBlock.size` | generated `BasicBlock`; hook adapters | tested: Windows/Linux low-hook tests |
| C.36 | Windows `ExportedSymbol.name` | generated accessor; module callback ABI | fixture-gated: Windows callback/low-hook fixtures |
| C.37 | Windows `ExportedSymbol.ordinal` | generated accessor; module callback ABI | fixture-gated: Windows callback/low-hook fixtures |
| C.38 | Windows `ExportedSymbol.rva` | generated accessor; module callback ABI | fixture-gated: Windows callback/low-hook fixtures |
| C.39 | Windows `ExportedSymbol.address` | generated accessor; module callback ABI | fixture-gated: Windows callback/low-hook fixtures |
| C.40 | Windows `MappedModule.name` | generated accessor; module callback ABI | fixture-gated: Windows callback/low-hook fixtures |
| C.41 | Windows `MappedModule.path` | generated accessor; module callback ABI | fixture-gated: Windows callback/low-hook fixtures |
| C.42 | Windows `MappedModule.module_path` | generated accessor; module callback ABI | fixture-gated: Windows callback/low-hook fixtures |
| C.43 | Windows `MappedModule.image_base` | generated accessor; module callback ABI | fixture-gated: Windows callback/low-hook fixtures |
| C.44 | Windows `MappedModule.image_base_file` | generated accessor; module callback ABI | fixture-gated: Windows callback/low-hook fixtures |
| C.45 | Windows `MappedModule.size_of_image` | generated accessor; module callback ABI | fixture-gated: Windows callback/low-hook fixtures |
| C.46 | Windows `MappedModule.entry_point` | generated accessor; module callback ABI | fixture-gated: Windows callback/low-hook fixtures |
| C.47 | Windows `MappedModule.exports` | generated accessor and copied export list | fixture-gated: Windows callback/low-hook fixtures |
| C.48 | Windows `MappedModule.is_static` | generated accessor; module callback ABI | fixture-gated: Windows callback/low-hook fixtures |
| C.49 | `ApiCall.module` | `api_hook.dart`; borrowed callback copy | tested: Windows API integration |
| C.50 | `ApiCall.name` | `api_hook.dart`; borrowed callback copy | tested: unit/API integration |
| C.51 | `ApiCall.address` | `api_hook.dart`; C callback bridge | tested: Windows API integration |
| C.52 | `ApiCall.return_address` | `api_hook.dart`; C callback bridge | tested: Windows API integration |
| C.53 | `ApiCall.return_value` read/write | mutable native call bridge | tested: unit/API integration |
| C.54 | ctypes unsigned truncation | `ctypes.dart` | tested: `ctypes_test.dart` |
| C.55 | ctypes signed sign-extension | `ctypes.dart` | tested: `ctypes_test.dart` |
| C.56 | ctypes pointer semantics | `ctypes.dart` | tested: `ctypes_test.dart` |
| C.57 | ctypes `bool32` semantics | `ctypes.dart` | tested: `ctypes_test.dart` |
| C.58 | ctypes char scalar semantics | `ctypes.dart` | tested: `ctypes_test.dart` |

## Namespace and class registrations

| ID | Python public registration | Dart evidence | Status and test evidence |
| --- | --- | --- | --- |
| N.01 | root `api_call` aliases `windows.api_call` | `sogen.dart`/`windows.dart` export `apiCall` | tested: `api_hook_test.dart` |
| N.02 | root `Hook` aliases `windows.Hook` | shared `Hook` export | tested: hook unit/native tests |
| N.03 | root `ApiHooks` aliases `windows.ApiHooks` | `ApiHooks` export | fixture-gated: API integration |
| N.04 | root `Hooks` aliases `windows.Hooks` | `WindowsHooks` export | fixture-gated: low-hook tests |
| N.05 | root `MemoryManager` aliases `windows.MemoryManager` | `WindowsMemoryManager` export | fixture-gated: core tests |
| N.06 | root `Thread` aliases `windows.Thread` | `WindowsThread` export | fixture-gated: callback tests |
| N.07 | root `Callbacks` aliases `windows.Callbacks` | `WindowsCallbacks` export | fixture-gated: callback tests |
| N.08 | root `ProcessContext` aliases `windows.ProcessContext` | `ProcessContext` export | fixture-gated: callback/core tests |
| N.09 | root `Emulator` aliases `windows.Emulator` | `WindowsApplication` export | fixture-gated: factory/core tests |
| N.10 | `windows.WindowsEmulator` aliases `windows.Emulator` | one `WindowsApplication` type | intentional-difference: Dart uses one canonical class name |
| N.11 | `linux.LinuxEmulator` aliases `linux.Emulator` | one `LinuxApplication` type | intentional-difference: Dart uses one canonical class name; tested by Linux factories |
| N.12 | `linux.Hook` is the Windows/shared hook type | shared `Hook` export | tested: Linux low-hook tests |
| N.13 | Windows emulator `process` facade | `WindowsApplication.process` | fixture-gated: core/callback tests |
| N.14 | Windows emulator `memory` facade | `WindowsApplication.memory` | fixture-gated: core tests |
| N.15 | Windows emulator `callbacks` facade | `WindowsApplication.callbacks` | fixture-gated: callback tests |
| N.16 | Windows emulator `hooks` facade | `WindowsApplication.hooks` | fixture-gated: low/API-hook tests |
| N.17 | Linux emulator `process` facade | `LinuxApplication.process` | tested: Linux core/collections |
| N.18 | Linux emulator `memory` facade | `LinuxApplication.memory` | tested: Linux core/collections |
| N.19 | Linux emulator `callbacks` facade | `LinuxApplication.callbacks` | tested: Linux callback tests |
| N.20 | Linux emulator `hooks` facade | `LinuxApplication.hooks` | tested: Linux low/symbol-hook tests |
| N.21 | Linux emulator `debug` facade | `LinuxApplication.debug` | tested: Linux debugger tests |

## Windows factories and emulator

| ID | Python public feature or tested behavior | Dart/native evidence | Status and test evidence |
| --- | --- | --- | --- |
| W.01 | root `create_empty` alias and `windows.create_empty` | `sogen.dart`, `windows.dart`, `WindowsNamespace` | tested: `windows/factory_test.dart` |
| W.02 | root `create_application` alias and `windows.create_application` | same | fixture-gated: factory and main example tests |
| W.03 | `application_args`/arguments | `windows_factory.dart`; options ABI | fixture-gated: factory test |
| W.04 | default, empty, and explicit environment | options ABI and factory marshalling | fixture-gated: factory test |
| W.05 | `emulation_root` | factory and `emulationRoot` getter | fixture-gated: factory/core tests |
| W.06 | `working_directory` | application options ABI | fixture-gated: factory test |
| W.07 | `registry_directory` | emulator options ABI | fixture-gated: factory test |
| W.08 | `disable_logging` | emulator options ABI | fixture-gated: factory test |
| W.09 | `use_relative_time` | emulator options ABI | fixture-gated: factory test |
| W.10 | writable `path_mappings` | options ABI | fixture-gated: factory test |
| W.11 | initial `port_mappings` | options ABI | fixture-gated: factory test |
| W.12 | `number_of_processors` | options ABI | fixture-gated: factory test |
| W.13 | `nt_product_type` | options ABI | fixture-gated: factory test |
| W.14 | backend selection | options ABI and generated enum | tested for Unicorn; other backends are C.02-C.04 host gaps |
| W.15 | `start(count=0)` and bounded execution | `WindowsApplication.start`; C ABI | fixture-gated: core, callback, hook and example tests |
| W.16 | `stop()` | `WindowsApplication.stop`; C ABI | implemented: callback-driven stop paths are covered; external cross-thread stop is not a supported Dart usage |
| W.17 | `save_snapshot` | app and C ABI | fixture-gated: core/API-refresh tests |
| W.18 | `restore_snapshot` | app and C ABI | fixture-gated: core/API-refresh tests |
| W.19 | `serialize_state` | owned C buffer and app copy | fixture-gated: core/API-refresh tests; ownership in `abi_test` |
| W.20 | `deserialize_state` | borrowed state buffer | fixture-gated: core/API-refresh tests |
| W.21 | `setup_process_if_necessary` | app and C ABI | fixture-gated: API-hook module-refresh test |
| W.22 | `yield_thread(alertable)` | app and C ABI | implemented: no independent alertable-wait fixture |
| W.23 | `perform_thread_switch` | app and C ABI | fixture-gated: callback tests |
| W.24 | `activate_thread` | app and C ABI | fixture-gated: callback tests |
| W.25 | `executed_instructions` | app getter and C ABI | fixture-gated: example/hook tests |
| W.26 | `last_stop_reason` string | Dart code-to-name accessor | fixture-gated: core/hook tests |
| W.27 | `last_stop_reason_code` | app and C ABI | fixture-gated: core/hook tests |
| W.28 | `last_stop_detail` | owned C buffer | fixture-gated: core/hook tests |
| W.29 | `backend_name` | owned C buffer | fixture-gated: core test; ownership in `abi_test` via Linux equivalent |
| W.30 | `emulation_root` getter | owned C buffer | fixture-gated: core test |
| W.31 | direct `read_memory` | app and C ABI | fixture-gated: core/hook tests |
| W.32 | direct `write_memory` | app and C ABI | fixture-gated: core/hook tests |
| W.33 | direct `read_register` | app and C ABI | fixture-gated: core/low-hook tests |
| W.34 | direct `write_register` | app and C ABI | fixture-gated: core/low-hook tests |
| W.35 | `get_host_port` | app and C ABI | fixture-gated: core test |
| W.36 | `get_emulator_port` | app and C ABI | fixture-gated: core test |
| W.37 | `map_port` and replacement | app and C ABI | fixture-gated: core test |
| W.38 | `current_thread` | copied `WindowsThread` snapshot | fixture-gated: callback/example tests |
| W.39 | `current_thread_id` | process/thread ABI | fixture-gated: callback/example tests |

## Windows process, thread, and memory

| ID | Python public feature or tested behavior | Dart/native evidence | Status and test evidence |
| --- | --- | --- | --- |
| W.P01 | `ProcessContext.is_wow64_process` | `ProcessContext.isWow64Process`; process-info ABI | fixture-gated: x86 API fixture |
| W.P02 | `ProcessContext.exit_status` | nullable C ABI accessor | fixture-gated: factory/example tests |
| W.P03 | `live_thread_count` | process-info ABI | fixture-gated: callback tests |
| W.P04 | `spawned_thread_count` | process-info ABI | fixture-gated: callback tests |
| W.P05 | `active_thread` | app current thread bridge | fixture-gated: callback tests |
| W.P06 | `process.callbacks` aliases emulator callbacks | same `WindowsCallbacks` object | tested: callback registration tests |
| W.T01 | `Thread.id` | generated `WindowsThread`; thread-info ABI | fixture-gated: callback tests |
| W.T02 | `Thread.name` | generated accessor and owned string ABI | fixture-gated: callback tests |
| W.T03 | `Thread.start_address` | generated accessor; thread-info ABI | fixture-gated: callback tests |
| W.T04 | `Thread.argument` | generated accessor; thread-info ABI | fixture-gated: callback tests |
| W.T05 | `Thread.executed_instructions` | generated accessor; thread-info ABI | fixture-gated: callback/hook tests |
| W.T06 | `Thread.current_ip` | generated accessor; thread-info ABI | fixture-gated: callback/hook tests |
| W.T07 | `Thread.previous_ip` | generated accessor; thread-info ABI | fixture-gated: callback/hook tests |
| W.T08 | `Thread.setup_done` | generated accessor; thread-info ABI | fixture-gated: callback tests |
| W.T09 | `Thread.exit_status` | generated nullable accessor; thread-info ABI | fixture-gated: callback tests |
| W.M01 | memory-manager `read_memory` | delegates to app | fixture-gated: core test |
| W.M02 | memory-manager `write_memory` | delegates to app | fixture-gated: core test |
| W.M03 | `allocate_memory` defaults and explicit start/kind | `WindowsMemoryManager`; C ABI | fixture-gated: core/callback tests |
| W.M04 | reserve-only allocation | C ABI `reserve_only` | fixture-gated: callback tests |
| W.M05 | `protect_memory` | C ABI and bool result | fixture-gated: callbacks/core tests |
| W.M06 | `commit_memory` | C ABI and bool result | fixture-gated: callbacks test |
| W.M07 | `decommit_memory` | C ABI and bool result | fixture-gated: callbacks test |
| W.M08 | `release_memory` | C ABI and bool result | fixture-gated: callbacks test |
| W.M09 | `find_free_allocation_base` | C ABI | fixture-gated: core test |
| W.M10 | `get_region_info` | generated ABI layout and immutable model | fixture-gated: core test |
| W.M11 | `compute_memory_stats` | C ABI and model | fixture-gated: core test |
| W.M12 | `default_allocation_address` getter | C ABI property bridge | implemented: no independent checked-in assertion |
| W.M13 | `default_allocation_address` setter | C ABI property bridge | implemented: no independent checked-in assertion |

## Windows callbacks

Every row uses the generated slot ID/field/callback-type metadata in
`types.g.dart`, the matching C callback table, and `WindowsCallbacks` typed and
dynamic accessors.

| ID | Python callback property | Status and evidence |
| --- | --- | --- |
| W.C01 | `on_module_load` | fixture-gated: callback, low-hook, and API-refresh tests |
| W.C02 | `on_module_unload` | fixture-gated: callback tests |
| W.C03 | `on_stdout` | fixture-gated: callback and example tests |
| W.C04 | `on_syscall` | fixture-gated: callback continuation/payload tests |
| W.C05 | `on_generic_access` | fixture-gated: callback test |
| W.C06 | `on_generic_activity` | fixture-gated: callback test |
| W.C07 | `on_suspicious_activity` | fixture-gated: callback test |
| W.C08 | `on_exception` | fixture-gated: callback test |
| W.C09 | `on_instruction` | fixture-gated: callback test |
| W.C10 | `on_memory_protect` | fixture-gated: callback test |
| W.C11 | `on_memory_allocate` | fixture-gated: callback test |
| W.C12 | `on_memory_violate` | fixture-gated: callback continuation/payload test |
| W.C13 | `on_rdtsc` | fixture-gated: callback test |
| W.C14 | `on_rdtscp` | fixture-gated: callback test |
| W.C15 | `on_ioctrl` | fixture-gated: callback test |
| W.C16 | `on_debug_string` | fixture-gated: callback test |
| W.C17 | `on_thread_create` | fixture-gated: callback test |
| W.C18 | `on_thread_terminated` | fixture-gated: callback test |
| W.C19 | `on_thread_set_name` | fixture-gated: callback test |
| W.C20 | `on_thread_switch` | fixture-gated: callback test |
| W.C21 | callback replacement and nullable clearing | `WindowsCallbacks.set/clear` and property setters; fixture-gated callback test |
| W.C22 | callback return coercion and safe exceptional fallback | callback bridge and continuation coercers; fixture-gated callback/low-hook tests |
| W.C23 | callback lifetime retained independently of local variable | registration maps and deferred close | fixture-gated callback tests |

## Windows hooks and API hooks

| ID | Python public feature or tested behavior | Dart/native evidence | Status and test evidence |
| --- | --- | --- | --- |
| W.H01 | `Hook.active` | `Hook`; native hook IDs | fixture-gated: low-hook tests |
| W.H02 | `Hook.remove()` and idempotence | `Hook`; native hook IDs | fixture-gated: low-hook tests; missing-ID idempotence in `abi_test` |
| W.H03 | global `memory_execution` | `WindowsHooks.memoryExecution` | fixture-gated: low-hook test |
| W.H04 | address `memory_execution_at` | `memoryExecutionAt` | fixture-gated: low-hook test |
| W.H05 | `memory_read` exact payload | `memoryRead` | fixture-gated: low-hook test |
| W.H06 | `memory_write` exact payload | `memoryWrite` | fixture-gated: low-hook test |
| W.H07 | `instruction` and three continuations | `instruction` | fixture-gated: CPUID continuation tests |
| W.H08 | `interrupt` vector and self-removal | `interrupt` | fixture-gated: low-hook test |
| W.H09 | `memory_violation` stop/resume/restart | `memoryViolation` | fixture-gated: low-hook tests |
| W.H10 | `basic_block` payload | `basicBlock` | fixture-gated: low-hook test |
| W.H11 | current low hook may remove itself; other mutation rejected while running | Dart/native callback-depth guards | fixture-gated: low-hook tests |
| W.A01 | `api_call(cc, params, restype)` descriptor | `apiCall`; `ApiHook` | tested: `api_hook_test.dart` |
| W.A02 | heterogeneous argument decoding and arity checks | `ApiHook.invoke` | tested: `api_hook_test.dart` |
| W.A03 | mutable return value and intercept | API callback ABI | fixture-gated: API integration test |
| W.A04 | bare export matching | native `api_hook_registry` | fixture-gated: API integration test |
| W.A05 | qualified module matching | native `api_hook_registry` | fixture-gated: API integration test |
| W.A06 | registry replacement | `ApiHooks.operator []=` | fixture-gated: API integration test |
| W.A07 | registry delete | `ApiHooks.remove` | fixture-gated: API integration test |
| W.A08 | nullable assignment removes | `ApiHooks.operator []=` | fixture-gated: API integration test |
| W.A09 | registry clear | `ApiHooks.clear` | fixture-gated: API integration test |
| W.A10 | registry retains callback lifetime | registration map | fixture-gated: API integration test |
| W.A11 | hooks refresh on module load | native registry refresh | fixture-gated: API integration tests |
| W.A12 | hooks refresh on deserialize | native registry refresh | fixture-gated: API integration tests |
| W.A13 | hooks refresh on snapshot restore | native registry refresh | fixture-gated: API integration tests |
| W.A14 | callback exception runs original and is reported after `start` | Dart callback error capture | intentional-difference, fixture-gated |
| W.A15 | x86/WOW64 stdcall return and stack cleanup | native API decoder | fixture-gated: x86 integration; fixes pinned Python defects |

## Linux factories and emulator

| ID | Python public feature or tested behavior | Dart/native evidence | Status and test evidence |
| --- | --- | --- | --- |
| L.01 | separate `linux.create_empty` | `LinuxNamespace.createEmpty`; factory C ABI | tested: Linux core/factory tests |
| L.02 | separate `linux.create_application` | `LinuxNamespace.createApplication`; factory C ABI | tested: all synthetic ELF tests |
| L.03 | application arguments after `argv[0]` | `linux_factory.dart`; C ABI | tested: `linux/factory_test.dart` |
| L.04 | default, empty, and explicit environment | nullable Dart option and C ABI flag | tested: factory test |
| L.05 | working-directory normalization | factory C ABI | tested: factory test |
| L.06 | writable path mappings | factory C ABI | tested: factory test |
| L.07 | read-only path mappings and precedence | factory C ABI | tested: factory test |
| L.08 | initial port mappings and validation | factory C ABI | tested: factory test |
| L.09 | disable logging | factory C ABI | implemented: used by every factory; output suppression is not independently asserted |
| L.10 | backend selection | generated enum and native factory | tested for Unicorn; KVM is a host gap |
| L.11 | `start(count=0)` and bounded execution | `LinuxApplication.start`; C ABI | tested: callback, hook and synthetic ELF tests |
| L.12 | `stop()` | `LinuxApplication.stop`; C ABI | tested: callback/hook tests |
| L.13 | `save_snapshot` | app and native snapshot storage | tested: core/collection tests |
| L.14 | `restore_snapshot` | app and native snapshot storage | tested: core/collection tests |
| L.15 | `serialize_state` | app and owned buffer ABI | tested: core/collection tests; ownership in `abi_test` |
| L.16 | `deserialize_state` | app and borrowed input ABI | tested: core/collection tests |
| L.17 | direct `read_memory` | app and C ABI | tested: core/hook tests |
| L.18 | direct `write_memory` | app and C ABI | tested: core/hook tests |
| L.19 | direct `read_register` | app and C ABI | tested: core/hook tests |
| L.20 | direct `write_register` | app and C ABI | tested: core/hook tests |
| L.21 | `activate_thread` | app and C ABI | tested: empty false and thread behavior |
| L.22 | `perform_thread_switch` | app and C ABI | tested: empty false and callback behavior |
| L.23 | `yield_thread` | app and C ABI | tested: thread callback behavior |
| L.24 | `executed_instructions` | app and C ABI | tested: low-hook/debug tests |
| L.25 | `backend_name` | owned buffer ABI | tested: core; ownership/free in `abi_test` |
| L.26 | `emulation_root` | owned buffer ABI | tested: factory/core; ownership/free in `abi_test` |
| L.27 | `last_stop_reason` | app string mapping | tested: callback, violation/debugger tests |
| L.28 | `last_stop_reason_code` | C ABI | tested: callback, violation/debugger tests |
| L.29 | `last_stop_detail` | owned buffer ABI | tested: violation/debugger tests |
| L.30 | `current_thread` | retained Linux thread model | tested: collection tests |
| L.31 | `current_thread_id` | process/thread ABI | tested: collection tests |
| L.32 | `get_host_port` | app and C ABI | tested: factory/core behavior |
| L.33 | `get_emulator_port` | app and C ABI | tested: factory/core behavior |
| L.34 | `map_port` | app and C ABI | tested: factory/core behavior |

## Linux process, thread, memory, and modules

| ID | Python public feature or tested behavior | Dart/native evidence | Status and test evidence |
| --- | --- | --- | --- |
| L.P01 | process `exit_status` | `LinuxProcessContext`; process-info ABI | tested: core/application tests |
| L.P02 | process `pid` | process-info ABI | tested: core/application tests |
| L.P03 | process `ppid` | process-info ABI | tested: core/application tests |
| L.P04 | process `uid` | process-info ABI | tested: factory tests |
| L.P05 | process `gid` | process-info ABI | tested: factory tests |
| L.P06 | process `euid` | process-info ABI | tested: factory tests |
| L.P07 | process `egid` | process-info ABI | tested: factory tests |
| L.P08 | process `thread_count` | process-info ABI | tested: core/collection tests |
| L.P09 | process `active_thread` | retained wrapper | tested: collection/callback tests |
| L.P10 | process `threads` | owned thread-list ABI and retained wrappers | tested: collections; free in `abi_test` |
| L.T01 | thread `tid` | thread-info ABI | tested: collection/callback tests |
| L.T02 | thread `stack_base` | thread-info ABI | tested: collection/callback tests |
| L.T03 | thread `stack_size` | thread-info ABI | tested: collection/callback tests |
| L.T04 | thread `fs_base` | thread-info ABI | tested: collection/callback tests |
| L.T05 | thread `current_ip` | retained resolver | tested: collection tests |
| L.T06 | thread `start_address` | retained resolver | tested: collection tests |
| L.T07 | thread `wait_state` | retained resolver and generated enum | tested: collection tests |
| L.T08 | thread `setup_done` | retained resolver | tested: collection tests |
| L.T09 | thread `terminated` | retained resolver | tested: collection/callback tests |
| L.T10 | thread `exit_code` | retained resolver | tested: collection/callback tests |
| L.T11 | thread `executed_instructions` | retained resolver | tested: collection/callback tests |
| L.T12 | thread `previous_ip` | Dart throws a precise `UnsupportedError` | unavailable: pinned native Linux thread snapshots do not retain a distinct previous IP safely |
| L.M01 | memory-manager `read_memory` | delegates to app | tested: core test |
| L.M02 | memory-manager `write_memory` | delegates to app | tested: core test |
| L.M03 | allocate with optional start | C ABI | tested: core test |
| L.M04 | `allocate_memory_at` success/failure | C ABI | tested: callbacks/low-hook tests |
| L.M05 | `protect_memory` success and missing-region false | C ABI | tested: callbacks tests |
| L.M06 | `release_memory` success and missing-region false | C ABI | tested: callbacks tests |
| L.M07 | `find_free_allocation_base` | C ABI | tested: core test |
| L.M08 | nullable `get_region_info` | C ABI/generated model | tested: collections/callbacks |
| L.M09 | `get_mapped_regions` | owned list ABI | tested: collections; free/idempotence in `abi_test` |
| L.M10 | `mapped_regions` property | immutable owned-list copy | tested: collections |
| L.M11 | memory stats `region_count` | generated `LinuxMemoryStats`; C ABI | tested: callbacks/core |
| L.M12 | memory stats `mapped_bytes` | generated `LinuxMemoryStats`; C ABI | tested: callbacks/core |
| L.M13 | memory stats `executable_bytes` | generated `LinuxMemoryStats`; C ABI | tested: callbacks/core |
| L.M14 | `mmap_base` getter | C ABI property bridge | tested: core test |
| L.M15 | `mmap_base` setter | C ABI property bridge | tested: core test |
| L.O01 | `ExportedSymbol.name` | `linux_models.dart`; owned nested ABI | tested: collection test |
| L.O02 | `ExportedSymbol.rva` | model and nested ABI | tested: collection test |
| L.O03 | `ExportedSymbol.address` | model and nested ABI | tested: collection test |
| L.O04 | `MappedSection.name` | model and nested ABI | tested: collection test |
| L.O05 | `MappedSection.start` | model and nested ABI | tested: collection test |
| L.O06 | `MappedSection.length` | model and nested ABI | tested: collection test |
| L.O07 | `MappedSection.permissions` | model and nested ABI | tested: collection test |
| L.O08 | `LinuxMappedModule.name` | model and owned ABI | tested: collection test |
| L.O09 | `LinuxMappedModule.path` | model and owned ABI | tested: collection test |
| L.O10 | `LinuxMappedModule.image_base` | model and owned ABI | tested: collection test |
| L.O11 | `LinuxMappedModule.size_of_image` | model and owned ABI | tested: collection test |
| L.O12 | `LinuxMappedModule.entry_point` | model and owned ABI | tested: collection test |
| L.O13 | module `exports` | immutable nested copy | tested: collection test |
| L.O14 | module `needed_libraries` | immutable nested copy | tested: collection test |
| L.O15 | module `sections` | immutable nested copy | tested: collection test |
| L.O16 | module `rpath` | immutable nested copy | tested: collection test |
| L.O17 | module `runpath` | immutable nested copy | tested: collection test |
| L.O18 | `modules` immutable list | module-list ABI | tested: collection test |
| L.O19 | exact `find_module_by_address` boundary behavior | lookup C ABI | tested: collection test |
| L.O20 | exact case-sensitive `find_module_by_name` | lookup C ABI | tested: collection test |
| L.O21 | copied modules/regions survive app disposal | Dart-owned models | tested: collection test |

## Linux callbacks

| ID | Python callback property or registry behavior | Status and evidence |
| --- | --- | --- |
| L.C01 | `on_stdout` | tested: `linux/callbacks_test.dart` |
| L.C02 | `on_stderr` | tested: callbacks test |
| L.C03 | `on_syscall` | tested: callbacks test |
| L.C04 | `on_memory_violate` | tested: continuation and exact-payload callback tests |
| L.C05 | `on_signal` | tested: signal callback tests |
| L.C06 | `on_exception` exact alias of signal slot | generated alias metadata and Dart property alias; tested |
| L.C07 | `on_memory_allocate` | tested: lifecycle callback test |
| L.C08 | `on_memory_protect` | tested: lifecycle callback test |
| L.C09 | `on_memory_release` | tested: lifecycle callback test |
| L.C10 | `on_module_load`, including existing-module replay | tested: module callback tests |
| L.C11 | `on_thread_create` retained payload | tested: callback test |
| L.C12 | `on_thread_terminated` retained payload | tested: callback test |
| L.C13 | `on_thread_switch` exact old/new IDs | tested: callback test |
| L.C14 | dynamic `Callbacks.set` | `LinuxCallbacks.set`; tested: callbacks test |
| L.C15 | dynamic `Callbacks.clear` | `LinuxCallbacks.clear`; tested: callbacks test |
| L.C16 | callback replacement and nullable clearing | registration map; tested: callbacks tests |
| L.C17 | callback lifetime after local references are dropped | registration map/deferred close; tested: callbacks tests |
| L.C18 | callback exceptional fallback | error capture and safe continuation; tested: callbacks tests |

## Linux low-level and symbol hooks

| ID | Python public feature or tested behavior | Dart/native evidence | Status and test evidence |
| --- | --- | --- | --- |
| L.H01 | `Hook.active` | shared `Hook`; native runtime registry | tested: low-hook test |
| L.H02 | `Hook.remove` and idempotence | shared `Hook`; native runtime registry | tested: low-hook and `abi_test` |
| L.H03 | global execution hook | `LinuxHooks.memoryExecution` | tested: low-hook test |
| L.H04 | address execution hook | `LinuxHooks.memoryExecutionAt` | tested: low-hook test |
| L.H05 | read hook with copied bytes | `LinuxHooks.memoryRead` | tested: low-hook test |
| L.H06 | write hook with copied bytes | `LinuxHooks.memoryWrite` | tested: low-hook test |
| L.H07 | instruction hook continuations | `LinuxHooks.instruction` | tested: low-hook test |
| L.H08 | interrupt payload and self-removal | `LinuxHooks.interrupt` | tested: low-hook test |
| L.H09 | memory violation payload/continuations | `LinuxHooks.memoryViolation` | tested: low-hook/callback tests |
| L.H10 | basic-block payload | `LinuxHooks.basicBlock` | tested: low-hook test |
| L.H11 | callback failures use safe fallback and report after execution | Dart error capture | tested: low-hook test |
| L.S01 | `symbol_call(params, restype)` descriptor | `symbolCall`; type validation | tested: symbol-hook and descriptor rejection tests |
| L.S02 | `LinuxSymbolCall.module` | `lhooks`; resolved copied module | tested: symbol-hook tests |
| L.S03 | `LinuxSymbolCall.name` | `lhooks`; symbol callback ABI | tested: symbol-hook tests |
| L.S04 | `LinuxSymbolCall.address` | `lhooks`; symbol callback ABI | tested: symbol-hook tests |
| L.S05 | `LinuxSymbolCall.returnAddress` | `lhooks`; symbol callback ABI | tested: symbol-hook tests |
| L.S06 | `LinuxSymbolCall.returnValue` read/write | mutable callback ABI | tested: symbol-hook tests |
| L.S07 | bare symbol matching and original observation | native Linux runtime registry | tested: symbol-hook test |
| L.S08 | qualified module-stem matching | native runtime registry | tested: symbol-hook test |
| L.S09 | argument decoding and mutable return interception | Dart descriptor bridge | tested: symbol-hook tests |
| L.S10 | registry replacement | `LinuxSymbolHooks.operator []=` | tested: symbol-hook tests |
| L.S11 | registry delete | `LinuxSymbolHooks.remove` | tested: symbol-hook tests |
| L.S12 | nullable assignment removes | `LinuxSymbolHooks.operator []=` | tested: symbol-hook tests |
| L.S13 | registry clear | `LinuxSymbolHooks.clear` | tested: symbol-hook tests |
| L.S14 | registry refresh after state restore | native refresh | tested: symbol-hook tests |
| L.S15 | safe replacement from the current callback | deferred callable close | tested: symbol-hook test |
| L.S16 | unsupported descriptors rejected before registration | Dart validation | tested: symbol-hook test |
| L.S17 | callback exception runs original and reports after execution | Dart error capture | intentional-difference, tested |

## Linux debugger

| ID | Python `Debug` feature | Dart/native evidence | Status and test evidence |
| --- | --- | --- | --- |
| L.D01 | set/clear/list breakpoints | `LinuxDebug`; C ABI | tested: `low_hooks_debug_test.dart` |
| L.D02 | step into/over/out | `LinuxDebug`; native runtime registry | tested: debugger test |
| L.D03 | run to/continue/pause | `LinuxDebug`; native runtime registry | tested: debugger test |
| L.D04 | register view | Dart immutable map over register ABI | tested: debugger test |
| L.D05 | module view | Dart immutable debug models | tested: debugger test |
| L.D06 | thread view | Dart immutable debug models | tested: debugger test |
| L.D07 | disassembly bytes/mnemonic/operands | owned nested list ABI | tested: debugger test |
| L.D08 | call stack | owned nested list ABI | tested: debugger test |

## Dart lifecycle, ABI, and host gaps

| ID | Difference or gap | Status and evidence |
| --- | --- | --- |
| D.01 | Public names use Dart camelCase. | intentional-difference |
| D.02 | Descriptors validate width, signedness, arity, and supported Linux symbol types before native entry. | intentional-difference; unit/symbol tests |
| D.03 | `dispose()` is deterministic and idempotent; all public use after disposal throws `StateError`. | intentional-difference; Linux/Windows core tests |
| D.04 | A `Finalizer` is fallback-only and swallows cleanup exceptions. | intentional-difference; implementation evidence only because finalizer timing is nondeterministic |
| D.05 | Callback exceptions use a safe continuation and surface as `SogenCallbackException` after execution. | intentional-difference; Windows/Linux callback/hook tests |
| D.06 | ABI major/version, schema layout order, owned buffer/list free and repeated free, null destroy, safe null-handle errors, and thread-local last error. | tested directly by `abi_test` |
| D.07 | Reusing a pointer after native destroy is not tested because dereferencing a freed C handle is undefined; Dart prevents this before native entry. | intentional-difference/safety boundary |
| H.01 | Windows guest integration requires `SOGEN_WINDOWS_ROOT`; the main example additionally requires `SOGEN_WINDOWS_TEST_BINARY`. | fixture-gated, never reported as an unconditional pass |
| H.02 | Linux guest behavior is testable on the current Windows host through synthetic ELF fixtures, but a native Linux host build/KVM run remains unverified here. | host-gap |
| H.03 | macOS native-asset compilation and runtime behavior remain unverified here. | host-gap |
| H.04 | ffigen regeneration requires `clang`/`libclang`; `generate_bindings.py --check` still audits every public function name and generated/manual struct field without it. | host-gap with deterministic fallback audit |
