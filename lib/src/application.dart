import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'api_hook.dart';
import 'ctypes.dart';
import 'exceptions.dart';
import 'ffi/sogen_native_bindings.g.dart';
import 'generated/types.g.dart';
import 'hook_continuation.dart';
import 'native_library.dart' as native;
import 'windows_factory.dart';

part 'windows_callbacks.dart';

const windows = WindowsNamespace._();

void configureNativeLibrary(String path) => native.configureNativeLibrary(path);

WindowsApplication createApplication(
  String application, {
  List<String> arguments = const [],
  Map<String, String>? environment,
  String emulationRoot = '',
  String workingDirectory = '',
  bool disableLogging = false,
  bool useRelativeTime = false,
  String registryDirectory = './registry',
  Map<String, String> pathMappings = const {},
  Map<int, int> portMappings = const {},
  int numberOfProcessors = 4,
  int ntProductType = 1,
  Backend backend = Backend.unicorn,
}) => windows.createApplication(
  application,
  arguments: arguments,
  environment: environment,
  emulationRoot: emulationRoot,
  workingDirectory: workingDirectory,
  disableLogging: disableLogging,
  useRelativeTime: useRelativeTime,
  registryDirectory: registryDirectory,
  pathMappings: pathMappings,
  portMappings: portMappings,
  numberOfProcessors: numberOfProcessors,
  ntProductType: ntProductType,
  backend: backend,
);

WindowsApplication createEmpty({
  String emulationRoot = '',
  bool disableLogging = false,
  bool useRelativeTime = false,
  String registryDirectory = './registry',
  Map<String, String> pathMappings = const {},
  Map<int, int> portMappings = const {},
  int numberOfProcessors = 4,
  int ntProductType = 1,
  Backend backend = Backend.unicorn,
}) => windows.createEmpty(
  emulationRoot: emulationRoot,
  disableLogging: disableLogging,
  useRelativeTime: useRelativeTime,
  registryDirectory: registryDirectory,
  pathMappings: pathMappings,
  portMappings: portMappings,
  numberOfProcessors: numberOfProcessors,
  ntProductType: ntProductType,
  backend: backend,
);

final class WindowsNamespace {
  const WindowsNamespace._();

  WindowsApplication createApplication(
    String application, {
    List<String> arguments = const [],
    Map<String, String>? environment,
    String emulationRoot = '',
    String workingDirectory = '',
    bool disableLogging = false,
    bool useRelativeTime = false,
    String registryDirectory = './registry',
    Map<String, String> pathMappings = const {},
    Map<int, int> portMappings = const {},
    int numberOfProcessors = 4,
    int ntProductType = 1,
    Backend backend = Backend.unicorn,
  }) {
    emulationRoot = native.resolveEmulationRoot(emulationRoot);
    final library = native.NativeLibrary.instance;
    final pointer = WindowsFactoryBindings.createApplication(
      library,
      application,
      arguments: arguments,
      environment: environment ?? const {},
      emulationRoot: emulationRoot,
      workingDirectory: workingDirectory,
      registryDirectory: registryDirectory,
      backend: backend,
      disableLogging: disableLogging,
      useRelativeTime: useRelativeTime,
      pathMappings: pathMappings,
      portMappings: portMappings,
      numberOfProcessors: numberOfProcessors,
      ntProductType: ntProductType,
    );
    return WindowsApplication._(library, pointer);
  }

  WindowsApplication createEmpty({
    String emulationRoot = '',
    bool disableLogging = false,
    bool useRelativeTime = false,
    String registryDirectory = './registry',
    Map<String, String> pathMappings = const {},
    Map<int, int> portMappings = const {},
    int numberOfProcessors = 4,
    int ntProductType = 1,
    Backend backend = Backend.unicorn,
  }) {
    emulationRoot = native.resolveEmulationRoot(emulationRoot);
    final library = native.NativeLibrary.instance;
    final pointer = WindowsFactoryBindings.createEmpty(
      library,
      emulationRoot: emulationRoot,
      registryDirectory: registryDirectory,
      backend: backend,
      disableLogging: disableLogging,
      useRelativeTime: useRelativeTime,
      pathMappings: pathMappings,
      portMappings: portMappings,
      numberOfProcessors: numberOfProcessors,
      ntProductType: ntProductType,
    );
    return WindowsApplication._(library, pointer);
  }

  ApiHook apiCall({
    required CallingConvention cc,
    List<CType<dynamic>> params = const [],
    CType<dynamic>? restype,
    required ApiHookCallback cb,
  }) => createApiHook(cc: cc, params: params, restype: restype, cb: cb);
}

final class WindowsApplication {
  WindowsApplication._(this._library, this._pointer)
    : hooks = WindowsHooks._(),
      callbacks = WindowsCallbacks._(),
      process = ProcessContext._(),
      memory = WindowsMemoryManager._() {
    hooks._attach(this);
    callbacks._attach(this);
    process._attach(this);
    memory._attach(this);
    _finalizerToken = _WindowsApplicationFinalizerToken(
      _library,
      _pointer,
      hooks.apis._registrations,
      hooks._registrations,
      callbacks._registrations,
      callbacks._deferredCloses,
    );
    _finalizer.attach(this, _finalizerToken, detach: this);
  }

  static final Finalizer<_WindowsApplicationFinalizerToken> _finalizer =
      Finalizer((token) {
        try {
          token.finalize();
        } on Object {
          // Finalizer callbacks must not throw.
        }
      });

  final native.NativeLibrary _library;
  final Pointer<sogen_dart_app> _pointer;
  final WindowsHooks hooks;
  final WindowsCallbacks callbacks;
  final ProcessContext process;
  final WindowsMemoryManager memory;
  late final _WindowsApplicationFinalizerToken _finalizerToken;
  bool _disposed = false;
  bool _running = false;

  bool get isDisposed => _disposed;

  int get lastStopReasonCode {
    _ensureUsable();
    final value = calloc<Int32>();
    try {
      _library.checkStatus(
        _library.bindings.sogen_dart_windows_get_last_stop_reason(
          _pointer,
          value,
        ),
      );
      return value.value;
    } finally {
      calloc.free(value);
    }
  }

  String get lastStopReason =>
      _stopReasonNames[lastStopReasonCode] ?? 'unknown';

  String get lastStopDetail => _getNativeString(
    _library.bindings.sogen_dart_windows_get_last_stop_detail,
  );

  String get backendName =>
      _getNativeString(_library.bindings.sogen_dart_windows_get_backend_name);

  String get emulationRoot =>
      _getNativeString(_library.bindings.sogen_dart_windows_get_emulation_root);

  int get executedInstructions {
    _ensureUsable();
    final value = calloc<Uint64>();
    try {
      _library.checkStatus(
        _library.bindings.sogen_dart_windows_get_executed_instructions(
          _pointer,
          value,
        ),
      );
      return value.value;
    } finally {
      calloc.free(value);
    }
  }

  WindowsThread? get currentThread {
    _ensureUsable();
    final hasValue = calloc<Int32>();
    final info = calloc<sogen_dart_windows_thread_info>();
    try {
      _library.checkStatus(
        _library.bindings.sogen_dart_windows_get_current_thread_info(
          _pointer,
          hasValue,
          info,
        ),
      );
      if (hasValue.value == 0) {
        return null;
      }
      final value = info.ref;
      return WindowsThread(
        id: value.id,
        name: _getNativeString(
          _library.bindings.sogen_dart_windows_get_current_thread_name,
        ),
        startAddress: value.start_address,
        argument: value.argument,
        executedInstructions: value.executed_instructions,
        currentIp: value.current_ip,
        previousIp: value.previous_ip,
        setupDone: value.setup_done != 0,
        exitStatus: value.has_exit_status == 0 ? null : value.exit_status,
      );
    } finally {
      calloc.free(info);
      calloc.free(hasValue);
    }
  }

  int? get currentThreadId => currentThread?.id;

  void start([int count = 0]) {
    _ensureUsable();
    if (_running) {
      throw StateError('The emulator is already running');
    }
    if (count < 0) {
      throw RangeError.value(count, 'count', 'Must not be negative');
    }

    callbacks._clearCallbackErrors();
    hooks._clearCallbackErrors();
    _running = true;
    Object? nativeError;
    StackTrace? nativeStackTrace;
    try {
      _library.checkStatus(
        _library.bindings.sogen_dart_windows_start(_pointer, count),
      );
    } on Object catch (error, stackTrace) {
      nativeError = error;
      nativeStackTrace = stackTrace;
    } finally {
      _running = false;
      callbacks._finishRun();
      hooks._finishRun();
    }

    final callbackError =
        callbacks._firstCallbackError() ?? hooks._firstCallbackError();
    if (callbackError != null) {
      throw SogenCallbackException(
        callbackError.key,
        callbackError.error,
        callbackError.stackTrace,
      );
    }
    if (nativeError != null) {
      Error.throwWithStackTrace(nativeError, nativeStackTrace!);
    }
  }

  void stop() {
    _ensureUsable();
    _library.checkStatus(_library.bindings.sogen_dart_windows_stop(_pointer));
  }

  void saveSnapshot() {
    _ensureNotRunning();
    _library.checkStatus(
      _library.bindings.sogen_dart_windows_save_snapshot(_pointer),
    );
  }

  void restoreSnapshot() {
    _ensureNotRunning();
    _library.checkStatus(
      _library.bindings.sogen_dart_windows_restore_snapshot(_pointer),
    );
  }

  Uint8List serializeState() {
    _ensureNotRunning();
    final output = calloc<sogen_dart_buffer>();
    try {
      _library.checkStatus(
        _library.bindings.sogen_dart_windows_serialize_state(_pointer, output),
      );
      return _copyNativeBuffer(output.ref);
    } finally {
      _library.bindings.sogen_dart_buffer_free(output);
      calloc.free(output);
    }
  }

  void deserializeState(Uint8List state) {
    _ensureNotRunning();
    final data = calloc<Uint8>(state.length);
    try {
      data.asTypedList(state.length).setAll(0, state);
      _library.checkStatus(
        _library.bindings.sogen_dart_windows_deserialize_state(
          _pointer,
          data,
          state.length,
        ),
      );
    } finally {
      calloc.free(data);
    }
  }

  void setupProcessIfNecessary() {
    _ensureNotRunning();
    try {
      _library.checkStatus(
        _library.bindings.sogen_dart_windows_setup_process(_pointer),
      );
    } finally {
      callbacks._finishRun();
    }
  }

  void yieldThread({bool alertable = false}) {
    _ensureUsable();
    try {
      _library.checkStatus(
        _library.bindings.sogen_dart_windows_yield_thread(
          _pointer,
          alertable ? 1 : 0,
        ),
      );
    } finally {
      callbacks._finishRun();
    }
  }

  bool performThreadSwitch() {
    try {
      return _boolOutput(
        _library.bindings.sogen_dart_windows_perform_thread_switch,
      );
    } finally {
      callbacks._finishRun();
    }
  }

  bool activateThread(int id) {
    _ensureUsable();
    if (id < 0 || id > 0xffffffff) {
      throw RangeError.range(id, 0, 0xffffffff, 'id');
    }
    try {
      final output = calloc<Int32>();
      try {
        _library.checkStatus(
          _library.bindings.sogen_dart_windows_activate_thread(
            _pointer,
            id,
            output,
          ),
        );
        return output.value != 0;
      } finally {
        calloc.free(output);
      }
    } finally {
      callbacks._finishRun();
    }
  }

  Uint8List readMemory(int address, int size) {
    _ensureUsable();
    _checkAddress(address);
    if (size < 0) {
      throw RangeError.value(size, 'size', 'Must not be negative');
    }
    final data = calloc<Uint8>(size);
    try {
      _library.checkStatus(
        _library.bindings.sogen_dart_windows_read_memory(
          _pointer,
          address,
          data,
          size,
        ),
      );
      return Uint8List.fromList(data.asTypedList(size));
    } finally {
      calloc.free(data);
    }
  }

  void writeMemory(int address, List<int> data) {
    _ensureUsable();
    _checkAddress(address);
    final source = calloc<Uint8>(data.length);
    try {
      source.asTypedList(data.length).setAll(0, data);
      _library.checkStatus(
        _library.bindings.sogen_dart_windows_write_memory(
          _pointer,
          address,
          source,
          data.length,
        ),
      );
    } finally {
      calloc.free(source);
    }
  }

  int readRegister(Register register) {
    _ensureUsable();
    final output = calloc<Uint64>();
    try {
      _library.checkStatus(
        _library.bindings.sogen_dart_windows_read_register(
          _pointer,
          register.nativeValue,
          output,
        ),
      );
      return output.value;
    } finally {
      calloc.free(output);
    }
  }

  void writeRegister(Register register, int value) {
    _ensureUsable();
    _checkAddress(value, name: 'value');
    _library.checkStatus(
      _library.bindings.sogen_dart_windows_write_register(
        _pointer,
        register.nativeValue,
        value,
      ),
    );
  }

  int getHostPort(int emulatorPort) => _portOutput(
    emulatorPort,
    _library.bindings.sogen_dart_windows_get_host_port,
  );

  int getEmulatorPort(int hostPort) => _portOutput(
    hostPort,
    _library.bindings.sogen_dart_windows_get_emulator_port,
  );

  void mapPort(int emulatorPort, int hostPort) {
    _ensureUsable();
    _checkPort(emulatorPort, 'emulatorPort');
    _checkPort(hostPort, 'hostPort');
    _library.checkStatus(
      _library.bindings.sogen_dart_windows_map_port(
        _pointer,
        emulatorPort,
        hostPort,
      ),
    );
  }

  void dispose() {
    if (_disposed) {
      return;
    }
    if (_running) {
      throw StateError('A running application cannot be disposed');
    }

    _finalizerToken.dispose();
    _finalizer.detach(this);
    _disposed = true;
  }

  void _ensureUsable() {
    if (_disposed) {
      throw StateError('The application has been disposed');
    }
  }

  void _ensureNotRunning() {
    _ensureUsable();
    if (_running) {
      throw StateError('This operation is unavailable while running');
    }
  }

  String _getNativeString(
    int Function(Pointer<sogen_dart_app>, Pointer<sogen_dart_buffer>) getter,
  ) {
    _ensureUsable();
    final output = calloc<sogen_dart_buffer>();
    try {
      _library.checkStatus(getter(_pointer, output));
      return utf8.decode(output.ref.data.asTypedList(output.ref.length));
    } finally {
      _library.bindings.sogen_dart_buffer_free(output);
      calloc.free(output);
    }
  }

  bool _boolOutput(
    int Function(Pointer<sogen_dart_app>, Pointer<Int32>) operation,
  ) {
    _ensureUsable();
    final output = calloc<Int32>();
    try {
      _library.checkStatus(operation(_pointer, output));
      return output.value != 0;
    } finally {
      calloc.free(output);
    }
  }

  int _portOutput(
    int port,
    int Function(Pointer<sogen_dart_app>, int, Pointer<Uint16>) getter,
  ) {
    _ensureUsable();
    _checkPort(port, 'port');
    final output = calloc<Uint16>();
    try {
      _library.checkStatus(getter(_pointer, port, output));
      return output.value;
    } finally {
      calloc.free(output);
    }
  }
}

final class _WindowsApplicationFinalizerToken {
  _WindowsApplicationFinalizerToken(
    this.library,
    this.pointer,
    this.apiRegistrations,
    this.lowLevelRegistrations,
    this.callbackRegistrations,
    this.deferredCallbackRegistrations,
  );

  final native.NativeLibrary library;
  final Pointer<sogen_dart_app> pointer;
  final Map<String, _RegisteredApiHook> apiRegistrations;
  final Map<int, _RegisteredLowLevelHook> lowLevelRegistrations;
  final Map<_WindowsCallbackSlot, _WindowsCallbackRegistration>
  callbackRegistrations;
  final List<_WindowsCallbackRegistration> deferredCallbackRegistrations;
  bool _disposed = false;

  void dispose() {
    if (_disposed) {
      return;
    }
    library.checkStatus(library.bindings.sogen_dart_windows_destroy(pointer));
    _disposed = true;
    _closeCallbacks();
  }

  void finalize() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    try {
      library.bindings.sogen_dart_windows_destroy(pointer);
    } on Object {
      // Finalizer callbacks must not throw.
    }
    _closeCallbacks();
  }

  void _closeCallbacks() {
    for (final registration in apiRegistrations.values) {
      try {
        registration.callable.close();
      } on Object {
        // Continue releasing the remaining callbacks.
      }
    }
    apiRegistrations.clear();
    for (final registration in lowLevelRegistrations.values) {
      registration.hook._active = false;
      registration.close();
    }
    lowLevelRegistrations.clear();
    for (final registration in callbackRegistrations.values) {
      registration.close();
    }
    callbackRegistrations.clear();
    for (final registration in deferredCallbackRegistrations) {
      registration.close();
    }
    deferredCallbackRegistrations.clear();
  }
}

final class ProcessContext {
  ProcessContext._();

  late WindowsApplication _application;

  void _attach(WindowsApplication application) {
    _application = application;
  }

  int? get exitStatus {
    _application._ensureUsable();
    final hasValue = calloc<Int32>();
    final value = calloc<Int32>();
    try {
      _application._library.checkStatus(
        _application._library.bindings.sogen_dart_windows_get_exit_status(
          _application._pointer,
          hasValue,
          value,
        ),
      );
      return hasValue.value == 0 ? null : value.value;
    } finally {
      calloc.free(value);
      calloc.free(hasValue);
    }
  }

  bool get isWow64Process => _info().isWow64Process;
  int get liveThreadCount => _info().liveThreadCount;
  int get spawnedThreadCount => _info().spawnedThreadCount;
  WindowsThread? get activeThread => _application.currentThread;
  WindowsCallbacks get callbacks => _application.callbacks;

  _ProcessInfo _info() {
    _application._ensureUsable();
    final output = calloc<sogen_dart_windows_process_info>();
    try {
      _application._library.checkStatus(
        _application._library.bindings.sogen_dart_windows_get_process_info(
          _application._pointer,
          output,
        ),
      );
      final value = output.ref;
      return _ProcessInfo(
        isWow64Process: value.is_wow64_process != 0,
        liveThreadCount: value.live_thread_count,
        spawnedThreadCount: value.spawned_thread_count,
      );
    } finally {
      calloc.free(output);
    }
  }
}

final class WindowsMemoryManager {
  WindowsMemoryManager._();

  late WindowsApplication _application;

  void _attach(WindowsApplication application) {
    _application = application;
  }

  int get defaultAllocationAddress {
    _application._ensureUsable();
    final output = calloc<Uint64>();
    try {
      _application._library.checkStatus(
        _application._library.bindings
            .sogen_dart_windows_memory_get_default_address(
              _application._pointer,
              output,
            ),
      );
      return output.value;
    } finally {
      calloc.free(output);
    }
  }

  set defaultAllocationAddress(int address) {
    _application._ensureUsable();
    _checkAddress(address);
    _application._library.checkStatus(
      _application._library.bindings
          .sogen_dart_windows_memory_set_default_address(
            _application._pointer,
            address,
          ),
    );
  }

  Uint8List readMemory(int address, int size) =>
      _application.readMemory(address, size);

  void writeMemory(int address, List<int> data) =>
      _application.writeMemory(address, data);

  int allocateMemory(
    int size,
    MemoryPermission permissions, {
    bool reserveOnly = false,
    int start = 0,
    MemoryRegionKind kind = MemoryRegionKind.privateAllocation,
  }) {
    _application._ensureUsable();
    if (size < 0) {
      throw RangeError.value(size, 'size', 'Must not be negative');
    }
    _checkAddress(start, name: 'start');
    final output = calloc<Uint64>();
    try {
      _application._library.checkStatus(
        _application._library.bindings.sogen_dart_windows_memory_allocate(
          _application._pointer,
          size,
          permissions.nativeValue,
          reserveOnly ? 1 : 0,
          start,
          kind.nativeValue,
          output,
        ),
      );
      return output.value;
    } finally {
      calloc.free(output);
    }
  }

  bool protectMemory(int address, int size, MemoryPermission permissions) =>
      _permissionOperation(
        address,
        size,
        permissions,
        _application._library.bindings.sogen_dart_windows_memory_protect,
      );

  bool commitMemory(int address, int size, MemoryPermission permissions) =>
      _permissionOperation(
        address,
        size,
        permissions,
        _application._library.bindings.sogen_dart_windows_memory_commit,
      );

  bool decommitMemory(int address, int size) => _rangeOperation(
    address,
    size,
    _application._library.bindings.sogen_dart_windows_memory_decommit,
  );

  bool releaseMemory(int address, int size) => _rangeOperation(
    address,
    size,
    _application._library.bindings.sogen_dart_windows_memory_release,
  );

  int findFreeAllocationBase(int size, [int start = 0]) {
    _application._ensureUsable();
    _checkSizeAndAddress(size, start);
    final output = calloc<Uint64>();
    try {
      _application._library.checkStatus(
        _application._library.bindings.sogen_dart_windows_memory_find_free_base(
          _application._pointer,
          size,
          start,
          output,
        ),
      );
      return output.value;
    } finally {
      calloc.free(output);
    }
  }

  MemoryRegionInfo getRegionInfo(int address) {
    _application._ensureUsable();
    _checkAddress(address);
    final output = calloc<sogen_dart_memory_region>();
    try {
      _application._library.checkStatus(
        _application._library.bindings.sogen_dart_windows_memory_get_region(
          _application._pointer,
          address,
          output,
        ),
      );
      final value = output.ref;
      return MemoryRegionInfo(
        start: value.start,
        length: value.length,
        permissions: _memoryPermission(value.permissions),
        allocationBase: value.allocation_base,
        allocationLength: value.allocation_length,
        isReserved: value.is_reserved != 0,
        isCommitted: value.is_committed != 0,
        initialPermissions: _memoryPermission(value.initial_permissions),
        kind: MemoryRegionKind.values.firstWhere(
          (kind) => kind.nativeValue == value.kind,
        ),
      );
    } finally {
      calloc.free(output);
    }
  }

  MemoryStats computeMemoryStats() {
    _application._ensureUsable();
    final output = calloc<sogen_dart_memory_stats>();
    try {
      _application._library.checkStatus(
        _application._library.bindings.sogen_dart_windows_memory_get_stats(
          _application._pointer,
          output,
        ),
      );
      return MemoryStats(
        reservedMemory: output.ref.reserved_memory,
        committedMemory: output.ref.committed_memory,
      );
    } finally {
      calloc.free(output);
    }
  }

  bool _permissionOperation(
    int address,
    int size,
    MemoryPermission permissions,
    int Function(Pointer<sogen_dart_app>, int, int, int, Pointer<Int32>)
    operation,
  ) {
    _application._ensureUsable();
    _checkSizeAndAddress(size, address);
    final output = calloc<Int32>();
    try {
      _application._library.checkStatus(
        operation(
          _application._pointer,
          address,
          size,
          permissions.nativeValue,
          output,
        ),
      );
      return output.value != 0;
    } finally {
      calloc.free(output);
    }
  }

  bool _rangeOperation(
    int address,
    int size,
    int Function(Pointer<sogen_dart_app>, int, int, Pointer<Int32>) operation,
  ) {
    _application._ensureUsable();
    _checkSizeAndAddress(size, address);
    final output = calloc<Int32>();
    try {
      _application._library.checkStatus(
        operation(_application._pointer, address, size, output),
      );
      return output.value != 0;
    } finally {
      calloc.free(output);
    }
  }
}

typedef ExecutionHookCallback = void Function(int address);
typedef MemoryHookCallback = void Function(int address, Uint8List data);
typedef InterruptHookCallback = void Function(int interruptNumber);
typedef BasicBlockHookCallback = void Function(BasicBlock block);

final class Hook {
  Hook.internal(this.id, this._remove);

  final int id;
  final void Function() _remove;
  bool _active = true;

  bool get active => _active;

  void deactivate() => _active = false;

  void remove() {
    if (_active) {
      _remove();
    }
  }
}

final class WindowsHooks {
  WindowsHooks._() : apis = ApiHooks._();

  final ApiHooks apis;
  final Map<int, _RegisteredLowLevelHook> _registrations =
      <int, _RegisteredLowLevelHook>{};
  final List<_RegisteredLowLevelHook> _deferredCallbackCloses =
      <_RegisteredLowLevelHook>[];
  late WindowsApplication _application;
  _RegisteredLowLevelHook? _currentCallback;
  _CallbackError? _callbackError;

  void _attach(WindowsApplication application) {
    _application = application;
    apis._attach(application);
  }

  Hook memoryExecution(ExecutionHookCallback callback) {
    late _RegisteredLowLevelHook registration;
    final callable =
        NativeCallable<sogen_dart_execution_callbackFunction>.isolateLocal((
          Pointer<Void> _,
          int id,
          int address,
        ) {
          _invokeVoid(registration, () => callback(address));
        });
    callable.keepIsolateAlive = false;
    registration = _register(
      'memoryExecution',
      callable,
      callable.close,
      (output) => _application._library.bindings
          .sogen_dart_windows_hook_memory_execution(
            _application._pointer,
            0,
            0,
            callable.nativeFunction,
            nullptr,
            output,
          ),
    );
    return registration.hook;
  }

  Hook memoryExecutionAt(int address, ExecutionHookCallback callback) {
    _checkAddress(address);
    late _RegisteredLowLevelHook registration;
    final callable =
        NativeCallable<sogen_dart_execution_callbackFunction>.isolateLocal((
          Pointer<Void> _,
          int id,
          int hitAddress,
        ) {
          _invokeVoid(registration, () => callback(hitAddress));
        });
    callable.keepIsolateAlive = false;
    registration = _register(
      'memoryExecutionAt',
      callable,
      callable.close,
      (output) => _application._library.bindings
          .sogen_dart_windows_hook_memory_execution(
            _application._pointer,
            1,
            address,
            callable.nativeFunction,
            nullptr,
            output,
          ),
    );
    return registration.hook;
  }

  Hook memoryRead(int address, int size, MemoryHookCallback callback) =>
      _memoryRangeHook(
        'memoryRead',
        address,
        size,
        callback,
        _application._library.bindings.sogen_dart_windows_hook_memory_read,
      );

  Hook memoryWrite(int address, int size, MemoryHookCallback callback) =>
      _memoryRangeHook(
        'memoryWrite',
        address,
        size,
        callback,
        _application._library.bindings.sogen_dart_windows_hook_memory_write,
      );

  Hook instruction(Instruction instruction, InstructionHookCallback callback) {
    late _RegisteredLowLevelHook registration;
    final callable =
        NativeCallable<sogen_dart_instruction_callbackFunction>.isolateLocal((
          Pointer<Void> _,
          int id,
          int data,
        ) {
          return _invoke(
            registration,
            HookContinuation.run.nativeValue,
            () => coerceInstructionHookContinuation(callback(data)).nativeValue,
          );
        }, exceptionalReturn: 0);
    callable.keepIsolateAlive = false;
    registration = _register(
      'instruction',
      callable,
      callable.close,
      (output) =>
          _application._library.bindings.sogen_dart_windows_hook_instruction(
            _application._pointer,
            instruction.nativeValue,
            callable.nativeFunction,
            nullptr,
            output,
          ),
    );
    return registration.hook;
  }

  Hook interrupt(InterruptHookCallback callback) {
    late _RegisteredLowLevelHook registration;
    final callable =
        NativeCallable<sogen_dart_interrupt_callbackFunction>.isolateLocal((
          Pointer<Void> _,
          int id,
          int interruptNumber,
        ) {
          _invokeVoid(registration, () => callback(interruptNumber));
        });
    callable.keepIsolateAlive = false;
    registration = _register(
      'interrupt',
      callable,
      callable.close,
      (output) =>
          _application._library.bindings.sogen_dart_windows_hook_interrupt(
            _application._pointer,
            callable.nativeFunction,
            nullptr,
            output,
          ),
    );
    return registration.hook;
  }

  Hook memoryViolation(MemoryViolationHookCallback callback) {
    late _RegisteredLowLevelHook registration;
    final callable =
        NativeCallable<
          sogen_dart_memory_violation_callbackFunction
        >.isolateLocal((
          Pointer<Void> _,
          int id,
          int address,
          int size,
          int operation,
          int type,
        ) {
          return _invoke(
            registration,
            MemoryViolationContinuation.stop.nativeValue,
            () => coerceMemoryViolationHookContinuation(
              callback(
                address,
                size,
                _memoryPermission(operation),
                _memoryViolationType(type),
              ),
            ).nativeValue,
          );
        }, exceptionalReturn: 0);
    callable.keepIsolateAlive = false;
    registration = _register(
      'memoryViolation',
      callable,
      callable.close,
      (output) => _application._library.bindings
          .sogen_dart_windows_hook_memory_violation(
            _application._pointer,
            callable.nativeFunction,
            nullptr,
            output,
          ),
    );
    return registration.hook;
  }

  Hook basicBlock(BasicBlockHookCallback callback) {
    late _RegisteredLowLevelHook registration;
    final callable =
        NativeCallable<sogen_dart_basic_block_callbackFunction>.isolateLocal((
          Pointer<Void> _,
          int id,
          int address,
          int instructionCount,
          int size,
        ) {
          _invokeVoid(
            registration,
            () => callback(
              BasicBlock(
                address: address,
                instructionCount: instructionCount,
                size: size,
              ),
            ),
          );
        });
    callable.keepIsolateAlive = false;
    registration = _register(
      'basicBlock',
      callable,
      callable.close,
      (output) =>
          _application._library.bindings.sogen_dart_windows_hook_basic_block(
            _application._pointer,
            callable.nativeFunction,
            nullptr,
            output,
          ),
    );
    return registration.hook;
  }

  Hook _memoryRangeHook(
    String name,
    int address,
    int size,
    MemoryHookCallback callback,
    int Function(
      Pointer<sogen_dart_app>,
      int,
      int,
      sogen_dart_memory_callback,
      Pointer<Void>,
      Pointer<Uint64>,
    )
    install,
  ) {
    _checkSizeAndAddress(size, address);
    late _RegisteredLowLevelHook registration;
    final callable =
        NativeCallable<sogen_dart_memory_callbackFunction>.isolateLocal((
          Pointer<Void> _,
          int id,
          int hitAddress,
          Pointer<Uint8> data,
          int length,
        ) {
          _invokeVoid(registration, () {
            final bytes = length == 0
                ? Uint8List(0)
                : Uint8List.fromList(data.asTypedList(length));
            callback(hitAddress, bytes);
          });
        });
    callable.keepIsolateAlive = false;
    registration = _register(
      name,
      callable,
      callable.close,
      (output) => install(
        _application._pointer,
        address,
        size,
        callable.nativeFunction,
        nullptr,
        output,
      ),
    );
    return registration.hook;
  }

  _RegisteredLowLevelHook _register(
    String name,
    Object callable,
    void Function() close,
    int Function(Pointer<Uint64>) install,
  ) {
    final output = calloc<Uint64>();
    try {
      _application._ensureNotRunning();
      _application._library.checkStatus(install(output));
      late _RegisteredLowLevelHook registration;
      final hook = Hook.internal(output.value, () => _remove(registration));
      registration = _RegisteredLowLevelHook(name, hook, callable, close);
      _registrations[hook.id] = registration;
      return registration;
    } on Object {
      close();
      rethrow;
    } finally {
      calloc.free(output);
    }
  }

  void _remove(_RegisteredLowLevelHook registration) {
    if (!registration.hook._active) {
      return;
    }
    _application._ensureUsable();
    if (_application._running && !identical(_currentCallback, registration)) {
      throw StateError(
        'Only the current low-level hook can remove itself while running',
      );
    }
    if (_application._running) {
      registration.hook._active = false;
      _registrations.remove(registration.hook.id);
      _deferredCallbackCloses.add(registration);
      return;
    }

    _application._library.checkStatus(
      _application._library.bindings.sogen_dart_windows_remove_hook(
        _application._pointer,
        registration.hook.id,
      ),
    );
    registration.hook._active = false;
    _registrations.remove(registration.hook.id);
    if (registration.callbackDepth == 0) {
      registration.close();
    } else {
      _deferredCallbackCloses.add(registration);
    }
  }

  T _invoke<T>(
    _RegisteredLowLevelHook registration,
    T fallback,
    T Function() callback,
  ) {
    if (!registration.hook._active) {
      return fallback;
    }
    final previousCallback = _currentCallback;
    _currentCallback = registration;
    registration.callbackDepth++;
    try {
      return callback();
    } on Object catch (error, stackTrace) {
      _callbackError ??= _CallbackError(registration.name, error, stackTrace);
      return fallback;
    } finally {
      registration.callbackDepth--;
      _currentCallback = previousCallback;
    }
  }

  void _invokeVoid(
    _RegisteredLowLevelHook registration,
    void Function() callback,
  ) {
    _invoke<Object?>(registration, null, () {
      callback();
      return null;
    });
  }

  void _clearCallbackErrors() {
    apis._clearCallbackErrors();
    _callbackError = null;
  }

  _CallbackError? _firstCallbackError() =>
      apis._firstCallbackError() ?? _callbackError;

  void _finishRun() {
    for (final registration in _deferredCallbackCloses) {
      _application._library.checkStatus(
        _application._library.bindings.sogen_dart_windows_remove_hook(
          _application._pointer,
          registration.hook.id,
        ),
      );
      registration.close();
    }
    _deferredCallbackCloses.clear();
  }
}

final class _RegisteredLowLevelHook {
  _RegisteredLowLevelHook(this.name, this.hook, this.callable, this._close);

  final String name;
  final Hook hook;
  final Object callable;
  final void Function() _close;
  int callbackDepth = 0;
  bool _closed = false;

  void close() {
    if (_closed) {
      return;
    }
    _closed = true;
    try {
      _close();
    } on Object {
      // Continue releasing the remaining callbacks during application disposal.
    }
  }
}

final class ApiHooks {
  ApiHooks._();

  late WindowsApplication _application;
  final Map<String, _RegisteredApiHook> _registrations =
      <String, _RegisteredApiHook>{};

  void _attach(WindowsApplication application) {
    _application = application;
  }

  ApiHook? operator [](String key) => _registrations[key]?.hook;

  void operator []=(String key, ApiHook? hook) {
    _application._ensureUsable();
    if (_application._running) {
      throw StateError('API hooks cannot be changed while running');
    }
    if (key.isEmpty || key.endsWith('!')) {
      throw ArgumentError.value(key, 'key', 'Must contain an export name');
    }

    _remove(key);
    if (hook == null) {
      return;
    }

    late _RegisteredApiHook registration;
    final callable =
        NativeCallable<sogen_dart_api_callbackFunction>.isolateLocal((
          Pointer<Void> _,
          Pointer<sogen_dart_api_call> nativeCall,
          Pointer<Uint64> nativeParameters,
          int parameterCount,
        ) {
          try {
            final call = ApiCall(
              module: nativeCall.ref.module_utf8.cast<Utf8>().toDartString(),
              name: nativeCall.ref.name_utf8.cast<Utf8>().toDartString(),
              address: nativeCall.ref.address,
              returnAddress: nativeCall.ref.return_address,
              returnValue: nativeCall.ref.return_value,
            );
            final continuation = hook.invoke(call, [
              for (var index = 0; index < parameterCount; index++)
                nativeParameters[index],
            ]);
            nativeCall.ref.return_value = call.returnValue;
            return continuation.nativeValue;
          } on Object catch (error, stackTrace) {
            registration.callbackError ??= _CallbackError(
              key,
              error,
              stackTrace,
            );
            return ApiContinuation.runOriginal.nativeValue;
          }
        }, exceptionalReturn: 0);
    callable.keepIsolateAlive = false;
    registration = _RegisteredApiHook(hook, callable);

    final keyUtf8 = key.toNativeUtf8();
    final output = calloc<Uint64>();
    try {
      _application._library.checkStatus(
        _application._library.bindings.sogen_dart_windows_add_api_hook(
          _application._pointer,
          keyUtf8.cast<Char>(),
          hook.callingConvention.nativeValue,
          hook.parameters.length,
          callable.nativeFunction,
          nullptr,
          output,
        ),
      );
      registration.id = output.value;
      _registrations[key] = registration;
    } on Object {
      callable.close();
      rethrow;
    } finally {
      calloc.free(output);
      malloc.free(keyUtf8);
    }
  }

  void remove(String key) {
    _application._ensureUsable();
    if (_application._running) {
      throw StateError('API hooks cannot be changed while running');
    }
    _remove(key);
  }

  void clear() {
    _application._ensureUsable();
    if (_application._running) {
      throw StateError('API hooks cannot be changed while running');
    }
    _application._library.checkStatus(
      _application._library.bindings.sogen_dart_windows_clear_api_hooks(
        _application._pointer,
      ),
    );
    for (final registration in _registrations.values) {
      registration.callable.close();
    }
    _registrations.clear();
  }

  void _remove(String key) {
    final registration = _registrations[key];
    if (registration == null) {
      return;
    }
    _application._library.checkStatus(
      _application._library.bindings.sogen_dart_windows_remove_hook(
        _application._pointer,
        registration.id,
      ),
    );
    _registrations.remove(key);
    registration.callable.close();
  }

  void _clearCallbackErrors() {
    for (final registration in _registrations.values) {
      registration.callbackError = null;
    }
  }

  _CallbackError? _firstCallbackError() {
    for (final registration in _registrations.values) {
      final error = registration.callbackError;
      if (error != null) {
        return error;
      }
    }
    return null;
  }
}

final class _RegisteredApiHook {
  _RegisteredApiHook(this.hook, this.callable);

  final ApiHook hook;
  final NativeCallable<sogen_dart_api_callbackFunction> callable;
  int id = 0;
  _CallbackError? callbackError;
}

final class _CallbackError {
  const _CallbackError(this.key, this.error, this.stackTrace);

  final String key;
  final Object error;
  final StackTrace stackTrace;
}

final class _ProcessInfo {
  const _ProcessInfo({
    required this.isWow64Process,
    required this.liveThreadCount,
    required this.spawnedThreadCount,
  });

  final bool isWow64Process;
  final int liveThreadCount;
  final int spawnedThreadCount;
}

const _stopReasonNames = <int, String>{
  0: 'none',
  1: 'unknown_syscall',
  2: 'unimplemented_syscall',
  3: 'syscall_exception',
  4: 'instruction_limit',
  5: 'normal_exit',
  6: 'signal_termination',
  7: 'unhandled_memory_violation',
  8: 'explicit_stop',
  9: 'backend_error',
  10: 'breakpoint',
  11: 'watchpoint',
};

Uint8List _copyNativeBuffer(sogen_dart_buffer buffer) => buffer.length == 0
    ? Uint8List(0)
    : Uint8List.fromList(buffer.data.asTypedList(buffer.length));

void _checkAddress(int value, {String name = 'address'}) {
  if (value < 0 || value > _maxUint64) {
    throw RangeError.value(value, name, 'Must be an unsigned 64-bit integer');
  }
}

void _checkSizeAndAddress(int size, int address) {
  if (size < 0) {
    throw RangeError.value(size, 'size', 'Must not be negative');
  }
  _checkAddress(address);
}

void _checkPort(int value, String name) {
  if (value < 0 || value > 0xffff) {
    throw RangeError.range(value, 0, 0xffff, name);
  }
}

MemoryPermission _memoryPermission(int value) => MemoryPermission.values
    .firstWhere((permission) => permission.nativeValue == value);

MemoryViolationType _memoryViolationType(int value) =>
    MemoryViolationType.values.firstWhere((type) => type.nativeValue == value);

const int _maxUint64 = 0x7fffffffffffffff;
