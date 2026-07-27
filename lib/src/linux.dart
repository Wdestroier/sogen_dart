import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'ffi/sogen_native_bindings.g.dart';
import 'ffi/linux_runtime_bindings.dart';
import 'application.dart' show Hook;
import 'ctypes.dart';
import 'exceptions.dart';
import 'generated/types.g.dart';
import 'hook_continuation.dart';
import 'linux_factory.dart';
import 'native_library.dart' as native;

part 'linux_models.dart';
part 'linux_callbacks.dart';
part 'linux_hooks.dart';

const linux = LinuxNamespace._();

LinuxApplication createEmpty({
  String emulationRoot = '',
  Backend backend = Backend.unicorn,
  Map<String, String> pathMappings = const {},
  Map<String, String> readOnlyPathMappings = const {},
  Map<int, int> portMappings = const {},
  bool disableLogging = true,
}) => linux.createEmpty(
  emulationRoot: emulationRoot,
  backend: backend,
  pathMappings: pathMappings,
  readOnlyPathMappings: readOnlyPathMappings,
  portMappings: portMappings,
  disableLogging: disableLogging,
);

LinuxApplication createApplication(
  String application, {
  List<String> arguments = const [],
  Map<String, String>? environment,
  String emulationRoot = '',
  String workingDirectory = '/',
  Backend backend = Backend.unicorn,
  Map<String, String> pathMappings = const {},
  Map<String, String> readOnlyPathMappings = const {},
  Map<int, int> portMappings = const {},
  bool disableLogging = true,
}) => linux.createApplication(
  application,
  arguments: arguments,
  environment: environment,
  emulationRoot: emulationRoot,
  workingDirectory: workingDirectory,
  backend: backend,
  pathMappings: pathMappings,
  readOnlyPathMappings: readOnlyPathMappings,
  portMappings: portMappings,
  disableLogging: disableLogging,
);

final class LinuxNamespace {
  const LinuxNamespace._();

  LinuxSymbolHook symbolCall({
    List<CType<dynamic>>? params,
    CType<dynamic>? restype,
    required LinuxSymbolHookCallback cb,
  }) => _createLinuxSymbolHook(params: params, restype: restype, cb: cb);

  LinuxApplication createEmpty({
    String emulationRoot = '',
    Backend backend = Backend.unicorn,
    Map<String, String> pathMappings = const {},
    Map<String, String> readOnlyPathMappings = const {},
    Map<int, int> portMappings = const {},
    bool disableLogging = true,
  }) {
    emulationRoot = native.resolveEmulationRoot(emulationRoot);
    final library = native.NativeLibrary.instance;
    final pointer = LinuxFactoryBindings.createEmpty(
      library,
      emulationRoot: emulationRoot,
      backend: backend,
      disableLogging: disableLogging,
      pathMappings: pathMappings,
      readOnlyPathMappings: readOnlyPathMappings,
      portMappings: portMappings,
    );
    return LinuxApplication._(library, pointer);
  }

  LinuxApplication createApplication(
    String application, {
    List<String> arguments = const [],
    Map<String, String>? environment,
    String emulationRoot = '',
    String workingDirectory = '/',
    Backend backend = Backend.unicorn,
    Map<String, String> pathMappings = const {},
    Map<String, String> readOnlyPathMappings = const {},
    Map<int, int> portMappings = const {},
    bool disableLogging = true,
  }) {
    emulationRoot = native.resolveEmulationRoot(emulationRoot);
    final library = native.NativeLibrary.instance;
    final pointer = LinuxFactoryBindings.createApplication(
      library,
      application,
      arguments: arguments,
      environment: environment,
      emulationRoot: emulationRoot,
      workingDirectory: workingDirectory,
      backend: backend,
      disableLogging: disableLogging,
      pathMappings: pathMappings,
      readOnlyPathMappings: readOnlyPathMappings,
      portMappings: portMappings,
    );
    return LinuxApplication._(library, pointer);
  }
}

final class LinuxApplication {
  LinuxApplication._(this._library, this._pointer)
    : memory = LinuxMemoryManager._(),
      process = LinuxProcessContext._(),
      callbacks = LinuxCallbacks._(),
      hooks = LinuxHooks._(),
      debug = LinuxDebug._() {
    memory._application = this;
    process._application = this;
    callbacks._application = this;
    hooks._attach(this);
    debug._application = this;
    _finalizerToken = _LinuxApplicationFinalizerToken(
      _library,
      _pointer,
      callbacks._registrations,
      callbacks._deferredCloses,
      hooks._registrations,
      hooks._deferredCallbackCloses,
      hooks.symbols._registrations,
      hooks.symbols._deferredCallbackCloses,
    );
    _finalizer.attach(this, _finalizerToken, detach: this);
  }

  static final Finalizer<_LinuxApplicationFinalizerToken> _finalizer =
      Finalizer((token) {
        try {
          token.finalize();
        } on Object {
          // Finalizer callbacks must not throw.
        }
      });

  final native.NativeLibrary _library;
  final Pointer<sogen_dart_app> _pointer;
  final LinuxMemoryManager memory;
  final LinuxProcessContext process;
  final LinuxCallbacks callbacks;
  final LinuxHooks hooks;
  final LinuxDebug debug;
  late final _LinuxApplicationFinalizerToken _finalizerToken;
  bool _disposed = false;
  bool _running = false;

  bool get isDisposed => _disposed;

  List<LinuxMappedModule> get modules {
    _check();
    final output = calloc<sogen_dart_linux_mapped_module_list>();
    try {
      _library.checkStatus(
        _library.bindings.sogen_dart_linux_get_modules(_pointer, output),
      );
      return List<LinuxMappedModule>.unmodifiable([
        for (var index = 0; index < output.ref.length; ++index)
          _moduleFromNative(output.ref.data[index]),
      ]);
    } finally {
      _library.bindings.sogen_dart_linux_mapped_module_list_free(output);
      calloc.free(output);
    }
  }

  String get backendName =>
      _string(_library.bindings.sogen_dart_linux_get_backend_name);
  String get emulationRoot =>
      _string(_library.bindings.sogen_dart_linux_get_emulation_root);
  String get lastStopDetail =>
      _string(_library.bindings.sogen_dart_linux_get_last_stop_detail);
  int get executedInstructions =>
      _uint64(_library.bindings.sogen_dart_linux_get_executed_instructions);

  int get lastStopReasonCode {
    _check();
    final output = calloc<Int32>();
    try {
      _library.checkStatus(
        _library.bindings.sogen_dart_linux_get_last_stop_reason(
          _pointer,
          output,
        ),
      );
      return output.value;
    } finally {
      calloc.free(output);
    }
  }

  String get lastStopReason => _stopReasons[lastStopReasonCode] ?? 'unknown';

  LinuxThread? get currentThread {
    final snapshot = _getThreadSnapshot(
      _library.bindings.sogen_dart_linux_get_current_thread_info,
    );
    return snapshot == null ? null : _retainThread(snapshot);
  }

  int? get currentThreadId => currentThread?.tid;

  LinuxMappedModule? findModuleByAddress(int address) {
    _check();
    _address(address);
    final present = calloc<Int32>();
    final output = calloc<sogen_dart_linux_mapped_module>();
    try {
      _library.checkStatus(
        _library.bindings.sogen_dart_linux_find_module_by_address(
          _pointer,
          address,
          present,
          output,
        ),
      );
      return present.value == 0 ? null : _moduleFromNative(output.ref);
    } finally {
      _library.bindings.sogen_dart_linux_mapped_module_free(output);
      calloc.free(output);
      calloc.free(present);
    }
  }

  LinuxMappedModule? findModuleByName(String name) {
    _check();
    final nativeName = name.toNativeUtf8();
    final present = calloc<Int32>();
    final output = calloc<sogen_dart_linux_mapped_module>();
    try {
      _library.checkStatus(
        _library.bindings.sogen_dart_linux_find_module_by_name(
          _pointer,
          nativeName.cast<Char>(),
          present,
          output,
        ),
      );
      return present.value == 0 ? null : _moduleFromNative(output.ref);
    } finally {
      _library.bindings.sogen_dart_linux_mapped_module_free(output);
      calloc.free(output);
      calloc.free(present);
      malloc.free(nativeName);
    }
  }

  void start([int count = 0]) {
    _check();
    if (_running) throw StateError('The emulator is already running');
    if (count < 0) throw RangeError.value(count, 'count');
    callbacks._clearCallbackErrors();
    hooks._clearCallbackErrors();
    _running = true;
    Object? nativeError;
    StackTrace? nativeStackTrace;
    try {
      _library.checkStatus(
        _library.bindings.sogen_dart_linux_start(_pointer, count),
      );
    } on Object catch (error, stackTrace) {
      nativeError = error;
      nativeStackTrace = stackTrace;
    } finally {
      _running = false;
      callbacks._finishRun();
      hooks._finishRun();
    }

    final callbackError = callbacks._firstCallbackError();
    if (callbackError != null) {
      throw SogenCallbackException(
        callbackError.key,
        callbackError.error,
        callbackError.stackTrace,
      );
    }
    final hookError = hooks._firstCallbackError();
    if (hookError != null) {
      throw SogenCallbackException(
        hookError.key,
        hookError.error,
        hookError.stackTrace,
      );
    }
    if (nativeError != null) {
      Error.throwWithStackTrace(nativeError, nativeStackTrace!);
    }
  }

  void stop() => _call(_library.bindings.sogen_dart_linux_stop);
  void saveSnapshot() =>
      _stopped(_library.bindings.sogen_dart_linux_save_snapshot);
  void restoreSnapshot() =>
      _stopped(_library.bindings.sogen_dart_linux_restore_snapshot);

  Uint8List serializeState() {
    _checkStopped();
    final output = calloc<sogen_dart_buffer>();
    try {
      _library.checkStatus(
        _library.bindings.sogen_dart_linux_serialize_state(_pointer, output),
      );
      return _copyNativeBuffer(output.ref);
    } finally {
      _library.bindings.sogen_dart_buffer_free(output);
      calloc.free(output);
    }
  }

  void deserializeState(Uint8List state) {
    _checkStopped();
    final data = calloc<Uint8>(state.length);
    try {
      data.asTypedList(state.length).setAll(0, state);
      _library.checkStatus(
        _library.bindings.sogen_dart_linux_deserialize_state(
          _pointer,
          data,
          state.length,
        ),
      );
    } finally {
      calloc.free(data);
    }
  }

  bool activateThread(int tid) {
    _check();
    if (tid < 0 || tid > 0xffffffff) {
      throw RangeError.range(tid, 0, 0xffffffff, 'tid');
    }
    final output = calloc<Int32>();
    try {
      _library.checkStatus(
        _library.bindings.sogen_dart_linux_activate_thread(
          _pointer,
          tid,
          output,
        ),
      );
      return output.value != 0;
    } finally {
      calloc.free(output);
    }
  }

  bool performThreadSwitch() {
    _check();
    final output = calloc<Int32>();
    try {
      _library.checkStatus(
        _library.bindings.sogen_dart_linux_perform_thread_switch(
          _pointer,
          output,
        ),
      );
      return output.value != 0;
    } finally {
      calloc.free(output);
    }
  }

  void yieldThread() => _call(_library.bindings.sogen_dart_linux_yield_thread);

  Uint8List readMemory(int address, int size) {
    _check();
    _range(address, size);
    final output = calloc<Uint8>(size);
    try {
      _library.checkStatus(
        _library.bindings.sogen_dart_linux_read_memory(
          _pointer,
          address,
          output,
          size,
        ),
      );
      return Uint8List.fromList(output.asTypedList(size));
    } finally {
      calloc.free(output);
    }
  }

  void writeMemory(int address, List<int> bytes) {
    _check();
    _address(address);
    final data = calloc<Uint8>(bytes.length);
    try {
      data.asTypedList(bytes.length).setAll(0, bytes);
      _library.checkStatus(
        _library.bindings.sogen_dart_linux_write_memory(
          _pointer,
          address,
          data,
          bytes.length,
        ),
      );
    } finally {
      calloc.free(data);
    }
  }

  int readRegister(Register register) {
    _check();
    final output = calloc<Uint64>();
    try {
      _library.checkStatus(
        _library.bindings.sogen_dart_linux_read_register(
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
    _check();
    _address(value, 'value');
    _library.checkStatus(
      _library.bindings.sogen_dart_linux_write_register(
        _pointer,
        register.nativeValue,
        value,
      ),
    );
  }

  void mapPort(int emulatorPort, int hostPort) {
    _check();
    _port(emulatorPort);
    _port(hostPort);
    _library.checkStatus(
      _library.bindings.sogen_dart_linux_map_port(
        _pointer,
        emulatorPort,
        hostPort,
      ),
    );
  }

  int getHostPort(int port) =>
      _portResult(port, _library.bindings.sogen_dart_linux_get_host_port);
  int getEmulatorPort(int port) =>
      _portResult(port, _library.bindings.sogen_dart_linux_get_emulator_port);

  void dispose() {
    if (_disposed) return;
    if (_running) throw StateError('A running application cannot be disposed');
    _finalizerToken.dispose();
    _finalizer.detach(this);
    _disposed = true;
  }

  void _check() {
    if (_disposed) throw StateError('The application has been disposed');
  }

  void _call(int Function(Pointer<sogen_dart_app>) operation) {
    _check();
    _library.checkStatus(operation(_pointer));
  }

  void _stopped(int Function(Pointer<sogen_dart_app>) operation) {
    _checkStopped();
    _library.checkStatus(operation(_pointer));
  }

  void _checkStopped() {
    _check();
    if (_running && callbacks._callbackDepth == 0) {
      throw StateError('This operation is unavailable while running');
    }
  }

  String _string(
    int Function(Pointer<sogen_dart_app>, Pointer<sogen_dart_buffer>) getter,
  ) {
    _check();
    final output = calloc<sogen_dart_buffer>();
    try {
      _library.checkStatus(getter(_pointer, output));
      final bytes = output.ref.length == 0
          ? Uint8List(0)
          : output.ref.data.asTypedList(output.ref.length);
      return utf8.decode(bytes);
    } finally {
      _library.bindings.sogen_dart_buffer_free(output);
      calloc.free(output);
    }
  }

  int _uint64(int Function(Pointer<sogen_dart_app>, Pointer<Uint64>) getter) {
    _check();
    final output = calloc<Uint64>();
    try {
      _library.checkStatus(getter(_pointer, output));
      return output.value;
    } finally {
      calloc.free(output);
    }
  }

  int _portResult(
    int port,
    int Function(Pointer<sogen_dart_app>, int, Pointer<Uint16>) getter,
  ) {
    _check();
    _port(port);
    final output = calloc<Uint16>();
    try {
      _library.checkStatus(getter(_pointer, port, output));
      return output.value;
    } finally {
      calloc.free(output);
    }
  }

  Uint8List _copyNativeBuffer(sogen_dart_buffer buffer) => buffer.length == 0
      ? Uint8List(0)
      : Uint8List.fromList(buffer.data.asTypedList(buffer.length));

  LinuxThread _retainThread(_LinuxThreadSnapshot snapshot) =>
      LinuxThread._retained(
        snapshot,
        () => _getThreadSnapshotById(snapshot.tid) ?? snapshot,
      );

  _LinuxThreadSnapshot? _getThreadSnapshot(
    int Function(
      Pointer<sogen_dart_app>,
      Pointer<Int32>,
      Pointer<sogen_dart_linux_thread_info>,
    )
    getter,
  ) {
    _check();
    final present = calloc<Int32>();
    final output = calloc<sogen_dart_linux_thread_info>();
    try {
      _library.checkStatus(getter(_pointer, present, output));
      return present.value == 0 ? null : _threadSnapshot(output.ref);
    } finally {
      calloc.free(output);
      calloc.free(present);
    }
  }

  _LinuxThreadSnapshot? _getThreadSnapshotById(int tid) {
    _check();
    final present = calloc<Int32>();
    final output = calloc<sogen_dart_linux_thread_info>();
    try {
      _library.checkStatus(
        _library.bindings.sogen_dart_linux_get_thread_info(
          _pointer,
          tid,
          present,
          output,
        ),
      );
      return present.value == 0 ? null : _threadSnapshot(output.ref);
    } finally {
      calloc.free(output);
      calloc.free(present);
    }
  }
}

final class LinuxProcessContext {
  LinuxProcessContext._();

  late LinuxApplication _application;

  int? get exitStatus => _info.exitStatus;
  int get pid => _info.pid;
  int get ppid => _info.ppid;
  int get uid => _info.uid;
  int get gid => _info.gid;
  int get effectiveUid => _info.effectiveUid;
  int get effectiveGid => _info.effectiveGid;
  int get threadCount => _info.threadCount;
  int? get activeThreadId => _info.activeThreadId;
  LinuxThread? get activeThread {
    final snapshot = _application._getThreadSnapshot(
      _application._library.bindings.sogen_dart_linux_get_active_thread_info,
    );
    return snapshot == null ? null : _application._retainThread(snapshot);
  }

  List<LinuxThread> get threads {
    _application._check();
    final output = calloc<sogen_dart_linux_thread_list>();
    try {
      _application._library.checkStatus(
        _application._library.bindings.sogen_dart_linux_get_threads(
          _application._pointer,
          output,
        ),
      );
      return List<LinuxThread>.unmodifiable([
        for (var index = 0; index < output.ref.length; ++index)
          _application._retainThread(_threadSnapshot(output.ref.data[index])),
      ]);
    } finally {
      _application._library.bindings.sogen_dart_linux_thread_list_free(output);
      calloc.free(output);
    }
  }

  _LinuxProcessInfo get _info {
    _application._check();
    final output = calloc<sogen_dart_linux_process_info>();
    try {
      _application._library.checkStatus(
        _application._library.bindings.sogen_dart_linux_get_process_info(
          _application._pointer,
          output,
        ),
      );
      final value = output.ref;
      return _LinuxProcessInfo(
        exitStatus: value.has_exit_status == 0 ? null : value.exit_status,
        pid: value.pid,
        ppid: value.ppid,
        uid: value.uid,
        gid: value.gid,
        effectiveUid: value.euid,
        effectiveGid: value.egid,
        threadCount: value.thread_count,
        activeThreadId: value.has_active_thread == 0
            ? null
            : value.active_thread_id,
      );
    } finally {
      calloc.free(output);
    }
  }
}

final class _LinuxProcessInfo {
  const _LinuxProcessInfo({
    required this.exitStatus,
    required this.pid,
    required this.ppid,
    required this.uid,
    required this.gid,
    required this.effectiveUid,
    required this.effectiveGid,
    required this.threadCount,
    required this.activeThreadId,
  });

  final int? exitStatus;
  final int pid;
  final int ppid;
  final int uid;
  final int gid;
  final int effectiveUid;
  final int effectiveGid;
  final int threadCount;
  final int? activeThreadId;
}

final class _LinuxApplicationFinalizerToken {
  _LinuxApplicationFinalizerToken(
    this.library,
    this.pointer,
    this.callbackRegistrations,
    this.deferredCallbackRegistrations,
    this.lowLevelRegistrations,
    this.deferredLowLevelRegistrations,
    this.symbolRegistrations,
    this.deferredSymbolRegistrations,
  );

  final native.NativeLibrary library;
  final Pointer<sogen_dart_app> pointer;
  final Map<_LinuxCallbackSlot, _LinuxCallbackRegistration>
  callbackRegistrations;
  final List<_LinuxCallbackRegistration> deferredCallbackRegistrations;
  final Map<int, _LinuxLowHookRegistration> lowLevelRegistrations;
  final List<_LinuxLowHookRegistration> deferredLowLevelRegistrations;
  final Map<String, _LinuxSymbolRegistration> symbolRegistrations;
  final List<_LinuxSymbolRegistration> deferredSymbolRegistrations;
  bool _disposed = false;

  void dispose() {
    if (_disposed) {
      return;
    }
    library.checkStatus(library.bindings.sogen_dart_linux_destroy(pointer));
    _disposed = true;
    _closeCallbacks();
  }

  void finalize() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    try {
      library.bindings.sogen_dart_linux_destroy(pointer);
    } on Object {
      // Finalizer callbacks must not throw.
    }
    _closeCallbacks();
  }

  void _closeCallbacks() {
    for (final registration in callbackRegistrations.values) {
      registration.close();
    }
    callbackRegistrations.clear();
    for (final registration in deferredCallbackRegistrations) {
      registration.close();
    }
    deferredCallbackRegistrations.clear();
    for (final registration in lowLevelRegistrations.values) {
      registration.hook.deactivate();
      registration.close();
    }
    lowLevelRegistrations.clear();
    for (final registration in deferredLowLevelRegistrations) {
      registration.close();
    }
    deferredLowLevelRegistrations.clear();
    for (final registration in symbolRegistrations.values) {
      registration.close();
    }
    symbolRegistrations.clear();
    for (final registration in deferredSymbolRegistrations) {
      registration.close();
    }
    deferredSymbolRegistrations.clear();
  }
}

final class LinuxMemoryManager {
  LinuxMemoryManager._();
  late LinuxApplication _application;

  int allocateMemory(int size, MemoryPermission permissions, {int start = 0}) {
    _application._check();
    _range(start, size);
    final output = calloc<Uint64>();
    try {
      _application._library.checkStatus(
        _application._library.bindings.sogen_dart_linux_memory_allocate(
          _application._pointer,
          size,
          permissions.nativeValue,
          start,
          output,
        ),
      );
      return output.value;
    } finally {
      calloc.free(output);
    }
  }

  bool allocateMemoryAt(int address, int size, MemoryPermission permissions) =>
      _permission(
        address,
        size,
        permissions,
        _application._library.bindings.sogen_dart_linux_memory_allocate_at,
      );

  bool protectMemory(int address, int size, MemoryPermission permissions) =>
      _permission(
        address,
        size,
        permissions,
        _application._library.bindings.sogen_dart_linux_memory_protect,
      );

  bool releaseMemory(int address, int size) {
    _application._check();
    _range(address, size);
    final output = calloc<Int32>();
    try {
      _application._library.checkStatus(
        _application._library.bindings.sogen_dart_linux_memory_release(
          _application._pointer,
          address,
          size,
          output,
        ),
      );
      return output.value != 0;
    } finally {
      calloc.free(output);
    }
  }

  LinuxMemoryStats computeMemoryStats() {
    _application._check();
    final output = calloc<sogen_dart_linux_memory_stats>();
    try {
      _application._library.checkStatus(
        _application._library.bindings.sogen_dart_linux_memory_get_stats(
          _application._pointer,
          output,
        ),
      );
      return LinuxMemoryStats(
        regionCount: output.ref.region_count,
        mappedBytes: output.ref.mapped_bytes,
        executableBytes: output.ref.executable_bytes,
      );
    } finally {
      calloc.free(output);
    }
  }

  int findFreeAllocationBase(int size, {int start = 0}) {
    _application._check();
    _range(start, size);
    final output = calloc<Uint64>();
    try {
      _application._library.checkStatus(
        _application._library.bindings.sogen_dart_linux_memory_find_free_base(
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

  MemoryRegionInfo? getRegionInfo(int address) {
    _application._check();
    _address(address);
    final present = calloc<Int32>();
    final output = calloc<sogen_dart_memory_region>();
    try {
      _application._library.checkStatus(
        _application._library.bindings.sogen_dart_linux_memory_get_region(
          _application._pointer,
          address,
          present,
          output,
        ),
      );
      if (present.value == 0) {
        return null;
      }
      return _memoryRegion(output.ref);
    } finally {
      calloc.free(output);
      calloc.free(present);
    }
  }

  List<MemoryRegionInfo> getMappedRegions() {
    _application._check();
    final output = calloc<sogen_dart_memory_region_list>();
    try {
      _application._library.checkStatus(
        _application._library.bindings
            .sogen_dart_linux_memory_get_mapped_regions(
              _application._pointer,
              output,
            ),
      );
      return List<MemoryRegionInfo>.unmodifiable([
        for (var index = 0; index < output.ref.length; ++index)
          _memoryRegion(output.ref.data[index]),
      ]);
    } finally {
      _application._library.bindings.sogen_dart_memory_region_list_free(output);
      calloc.free(output);
    }
  }

  List<MemoryRegionInfo> get mappedRegions => getMappedRegions();

  int get mmapBase {
    _application._check();
    final output = calloc<Uint64>();
    try {
      _application._library.checkStatus(
        _application._library.bindings.sogen_dart_linux_memory_get_mmap_base(
          _application._pointer,
          output,
        ),
      );
      return output.value;
    } finally {
      calloc.free(output);
    }
  }

  set mmapBase(int address) {
    _application._check();
    _address(address);
    _application._library.checkStatus(
      _application._library.bindings.sogen_dart_linux_memory_set_mmap_base(
        _application._pointer,
        address,
      ),
    );
  }

  bool _permission(
    int address,
    int size,
    MemoryPermission permission,
    int Function(Pointer<sogen_dart_app>, int, int, int, Pointer<Int32>)
    operation,
  ) {
    _application._check();
    _range(address, size);
    final output = calloc<Int32>();
    try {
      _application._library.checkStatus(
        operation(
          _application._pointer,
          address,
          size,
          permission.nativeValue,
          output,
        ),
      );
      return output.value != 0;
    } finally {
      calloc.free(output);
    }
  }
}

MemoryPermission _memoryPermission(int value) => MemoryPermission.values
    .firstWhere((permission) => permission.nativeValue == value);

_LinuxThreadSnapshot _threadSnapshot(sogen_dart_linux_thread_info value) =>
    _LinuxThreadSnapshot(
      tid: value.tid,
      stackBase: value.stack_base,
      stackSize: value.stack_size,
      fsBase: value.fs_base,
      currentIp: value.current_ip,
      startAddress: value.start_address,
      waitState: ThreadWaitState.values[value.wait_state],
      terminated: value.terminated != 0,
      exitCode: value.exit_code,
      executedInstructions: value.executed_instructions,
    );

MemoryRegionInfo _memoryRegion(sogen_dart_memory_region value) =>
    MemoryRegionInfo(
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

LinuxMappedModule _moduleFromNative(sogen_dart_linux_mapped_module value) =>
    LinuxMappedModule(
      name: _nativeString(value.name_utf8),
      path: _nativeString(value.path_utf8),
      imageBase: value.image_base,
      sizeOfImage: value.size_of_image,
      entryPoint: value.entry_point,
      exports: [
        for (var index = 0; index < value.exports.length; ++index)
          ExportedSymbol(
            name: _nativeString(value.exports.data[index].name_utf8),
            rva: value.exports.data[index].rva,
            address: value.exports.data[index].address,
          ),
      ],
      neededLibraries: [
        for (var index = 0; index < value.needed_libraries.length; ++index)
          _nativeString(value.needed_libraries.data[index]),
      ],
      sections: [
        for (var index = 0; index < value.sections.length; ++index)
          MappedSection(
            name: _nativeString(value.sections.data[index].name_utf8),
            start: value.sections.data[index].start,
            length: value.sections.data[index].length,
            permissions: _memoryPermission(
              value.sections.data[index].permissions,
            ),
          ),
      ],
      rpath: _nativeString(value.rpath_utf8),
      runpath: _nativeString(value.runpath_utf8),
    );

String _nativeString(sogen_dart_buffer value) =>
    value.length == 0 ? '' : utf8.decode(value.data.asTypedList(value.length));

void _address(int value, [String name = 'address']) {
  if (value < 0 || value > 0x7fffffffffffffff) {
    throw RangeError.value(
      value,
      name,
      'Must be a non-negative 64-bit integer',
    );
  }
}

void _range(int address, int size) {
  _address(address);
  if (size < 0) throw RangeError.value(size, 'size');
}

void _port(int value) {
  if (value <= 0 || value > 0xffff) throw RangeError.range(value, 1, 0xffff);
}

const _stopReasons = <int, String>{
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
