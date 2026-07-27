part of 'linux.dart';

typedef LinuxStdoutCallback = void Function(String data);
typedef LinuxStderrCallback = void Function(String data);
typedef LinuxSyscallCallback = Object? Function(int syscallId, String name);
typedef LinuxMemoryViolateCallback =
    Object? Function(
      int address,
      int length,
      MemoryOperation operation,
      MemoryViolationType type,
    );
typedef LinuxSignalCallback =
    void Function(int signum, int faultAddress, int signalCode);
typedef LinuxMemoryAllocateCallback =
    void Function(
      int address,
      int length,
      MemoryPermission permissions,
      bool committed,
    );
typedef LinuxMemoryProtectCallback =
    void Function(int address, int length, MemoryPermission permissions);
typedef LinuxMemoryReleaseCallback = void Function(int address, int length);
typedef LinuxModuleLoadCallback = void Function(LinuxMappedModule module);
typedef LinuxThreadCallback = void Function(LinuxThread thread);
typedef LinuxThreadSwitchCallback =
    void Function(int oldThreadId, int newThreadId);

typedef _LinuxCallbackSlot = LinuxCallbackSlot;

final class LinuxCallbacks {
  LinuxCallbacks._();

  late LinuxApplication _application;
  final Map<_LinuxCallbackSlot, Function> _callbacks = {};
  final Map<_LinuxCallbackSlot, _LinuxCallbackRegistration> _registrations = {};
  final List<_LinuxCallbackRegistration> _deferredCloses = [];
  _LinuxCallbackError? _callbackError;
  int _callbackDepth = 0;

  LinuxStdoutCallback? get onStdout =>
      _callbacks[_LinuxCallbackSlot.stdout] as LinuxStdoutCallback?;
  set onStdout(LinuxStdoutCallback? callback) =>
      _set(_LinuxCallbackSlot.stdout, callback);

  LinuxStderrCallback? get onStderr =>
      _callbacks[_LinuxCallbackSlot.stderr] as LinuxStderrCallback?;
  set onStderr(LinuxStderrCallback? callback) =>
      _set(_LinuxCallbackSlot.stderr, callback);

  LinuxSyscallCallback? get onSyscall =>
      _callbacks[_LinuxCallbackSlot.syscall] as LinuxSyscallCallback?;
  set onSyscall(LinuxSyscallCallback? callback) =>
      _set(_LinuxCallbackSlot.syscall, callback);

  LinuxMemoryViolateCallback? get onMemoryViolate =>
      _callbacks[_LinuxCallbackSlot.memoryViolate]
          as LinuxMemoryViolateCallback?;
  set onMemoryViolate(LinuxMemoryViolateCallback? callback) =>
      _set(_LinuxCallbackSlot.memoryViolate, callback);

  LinuxSignalCallback? get onSignal =>
      _callbacks[_LinuxCallbackSlot.signal] as LinuxSignalCallback?;
  set onSignal(LinuxSignalCallback? callback) =>
      _set(_LinuxCallbackSlot.signal, callback);

  LinuxSignalCallback? get onException => onSignal;
  set onException(LinuxSignalCallback? callback) => onSignal = callback;

  LinuxMemoryAllocateCallback? get onMemoryAllocate =>
      _callbacks[_LinuxCallbackSlot.memoryAllocate]
          as LinuxMemoryAllocateCallback?;
  set onMemoryAllocate(LinuxMemoryAllocateCallback? callback) =>
      _set(_LinuxCallbackSlot.memoryAllocate, callback);

  LinuxMemoryProtectCallback? get onMemoryProtect =>
      _callbacks[_LinuxCallbackSlot.memoryProtect]
          as LinuxMemoryProtectCallback?;
  set onMemoryProtect(LinuxMemoryProtectCallback? callback) =>
      _set(_LinuxCallbackSlot.memoryProtect, callback);

  LinuxMemoryReleaseCallback? get onMemoryRelease =>
      _callbacks[_LinuxCallbackSlot.memoryRelease]
          as LinuxMemoryReleaseCallback?;
  set onMemoryRelease(LinuxMemoryReleaseCallback? callback) =>
      _set(_LinuxCallbackSlot.memoryRelease, callback);

  LinuxModuleLoadCallback? get onModuleLoad =>
      _callbacks[_LinuxCallbackSlot.moduleLoad] as LinuxModuleLoadCallback?;
  set onModuleLoad(LinuxModuleLoadCallback? callback) =>
      _set(_LinuxCallbackSlot.moduleLoad, callback);

  LinuxThreadCallback? get onThreadCreate =>
      _callbacks[_LinuxCallbackSlot.threadCreate] as LinuxThreadCallback?;
  set onThreadCreate(LinuxThreadCallback? callback) =>
      _set(_LinuxCallbackSlot.threadCreate, callback);

  LinuxThreadCallback? get onThreadTerminated =>
      _callbacks[_LinuxCallbackSlot.threadTerminated] as LinuxThreadCallback?;
  set onThreadTerminated(LinuxThreadCallback? callback) =>
      _set(_LinuxCallbackSlot.threadTerminated, callback);

  LinuxThreadSwitchCallback? get onThreadSwitch =>
      _callbacks[_LinuxCallbackSlot.threadSwitch] as LinuxThreadSwitchCallback?;
  set onThreadSwitch(LinuxThreadSwitchCallback? callback) =>
      _set(_LinuxCallbackSlot.threadSwitch, callback);

  void set(String name, Function? callback) =>
      _set(_linuxSlotFor(name), callback);

  void clear(String name) => _set(_linuxSlotFor(name), null);

  void _set(_LinuxCallbackSlot slot, Function? callback) {
    _application._check();
    final oldCallback = _callbacks[slot];
    final oldRegistration = _registrations[slot];
    final registration = callback == null
        ? null
        : _createRegistration(slot, callback);

    if (callback == null) {
      _callbacks.remove(slot);
      _registrations.remove(slot);
    } else {
      _callbacks[slot] = callback;
      _registrations[slot] = registration!;
    }
    try {
      _sync();
    } on Object {
      registration?.close();
      if (oldCallback == null) {
        _callbacks.remove(slot);
        _registrations.remove(slot);
      } else {
        _callbacks[slot] = oldCallback;
        _registrations[slot] = oldRegistration!;
      }
      rethrow;
    }

    if (oldRegistration != null) {
      if (_application._running || _callbackDepth != 0) {
        _deferredCloses.add(oldRegistration);
      } else {
        oldRegistration.close();
      }
    }
  }

  void _sync() {
    final table = calloc<sogen_dart_linux_callbacks>();
    try {
      table.ref
        ..user_data = nullptr
        ..stdout_callback = _pointer<sogen_dart_text_callbackFunction>(
          _LinuxCallbackSlot.stdout,
        )
        ..stderr_callback = _pointer<sogen_dart_text_callbackFunction>(
          _LinuxCallbackSlot.stderr,
        )
        ..syscall = _pointer<sogen_dart_linux_syscall_callbackFunction>(
          _LinuxCallbackSlot.syscall,
        )
        ..memory_violate =
            _pointer<sogen_dart_memory_violate_event_callbackFunction>(
              _LinuxCallbackSlot.memoryViolate,
            )
        ..signal = _pointer<sogen_dart_linux_signal_callbackFunction>(
          _LinuxCallbackSlot.signal,
        )
        ..memory_allocate =
            _pointer<sogen_dart_memory_allocate_event_callbackFunction>(
              _LinuxCallbackSlot.memoryAllocate,
            )
        ..memory_protect =
            _pointer<sogen_dart_memory_protect_event_callbackFunction>(
              _LinuxCallbackSlot.memoryProtect,
            )
        ..memory_release =
            _pointer<sogen_dart_linux_memory_release_callbackFunction>(
              _LinuxCallbackSlot.memoryRelease,
            )
        ..module_load = _pointer<sogen_dart_linux_module_callbackFunction>(
          _LinuxCallbackSlot.moduleLoad,
        )
        ..thread_create = _pointer<sogen_dart_linux_thread_callbackFunction>(
          _LinuxCallbackSlot.threadCreate,
        )
        ..thread_terminated =
            _pointer<sogen_dart_linux_thread_callbackFunction>(
              _LinuxCallbackSlot.threadTerminated,
            )
        ..thread_switch =
            _pointer<sogen_dart_linux_thread_switch_callbackFunction>(
              _LinuxCallbackSlot.threadSwitch,
            );
      _application._library.checkStatus(
        _application._library.bindings.sogen_dart_linux_set_callbacks(
          _application._pointer,
          table,
        ),
      );
    } finally {
      calloc.free(table);
    }
  }

  Pointer<NativeFunction<T>> _pointer<T extends Function>(
    _LinuxCallbackSlot slot,
  ) => _registrations[slot]?.pointer.cast<NativeFunction<T>>() ?? nullptr;

  _LinuxCallbackRegistration _createRegistration(
    _LinuxCallbackSlot slot,
    Function callback,
  ) => switch (slot) {
    .stdout || .stderr => _registration(
      NativeCallable<sogen_dart_text_callbackFunction>.isolateLocal((
        Pointer<Void> _,
        Pointer<Uint8> text,
        int length,
      ) {
        _invokeVoid(
          slot,
          () => Function.apply(callback, [_linuxString(text, length)]),
        );
      }),
    ),
    .syscall => _registration(
      NativeCallable<sogen_dart_linux_syscall_callbackFunction>.isolateLocal((
        Pointer<Void> _,
        int id,
        Pointer<Uint8> name,
        int length,
      ) {
        return _invoke(
          slot,
          HookContinuation.run.nativeValue,
          () => coerceInstructionHookContinuation(
            Function.apply(callback, [id, _linuxString(name, length)]),
          ).nativeValue,
        );
      }, exceptionalReturn: 0),
    ),
    .memoryViolate => _registration(
      NativeCallable<
        sogen_dart_memory_violate_event_callbackFunction
      >.isolateLocal((
        Pointer<Void> _,
        int address,
        int length,
        int operation,
        int type,
      ) {
        return _invoke(
          slot,
          MemoryViolationContinuation.resume.nativeValue,
          () => coerceMemoryViolationHookContinuation(
            Function.apply(callback, [
              address,
              length,
              _memoryPermission(operation),
              _linuxMemoryViolationType(type),
            ]),
          ).nativeValue,
        );
      }, exceptionalReturn: 1),
    ),
    .signal => _registration(
      NativeCallable<sogen_dart_linux_signal_callbackFunction>.isolateLocal((
        Pointer<Void> _,
        int signum,
        int faultAddress,
        int signalCode,
      ) {
        _invokeVoid(
          slot,
          () => Function.apply(callback, [signum, faultAddress, signalCode]),
        );
      }),
    ),
    .memoryAllocate => _registration(
      NativeCallable<
        sogen_dart_memory_allocate_event_callbackFunction
      >.isolateLocal((
        Pointer<Void> _,
        int address,
        int length,
        int permission,
        int committed,
      ) {
        _invokeVoid(
          slot,
          () => Function.apply(callback, [
            address,
            length,
            _memoryPermission(permission),
            committed != 0,
          ]),
        );
      }),
    ),
    .memoryProtect => _registration(
      NativeCallable<
        sogen_dart_memory_protect_event_callbackFunction
      >.isolateLocal((
        Pointer<Void> _,
        int address,
        int length,
        int permission,
      ) {
        _invokeVoid(
          slot,
          () => Function.apply(callback, [
            address,
            length,
            _memoryPermission(permission),
          ]),
        );
      }),
    ),
    .memoryRelease => _registration(
      NativeCallable<
        sogen_dart_linux_memory_release_callbackFunction
      >.isolateLocal((Pointer<Void> _, int address, int length) {
        _invokeVoid(slot, () => Function.apply(callback, [address, length]));
      }),
    ),
    .moduleLoad => _registration(
      NativeCallable<sogen_dart_linux_module_callbackFunction>.isolateLocal((
        Pointer<Void> _,
        Pointer<sogen_dart_linux_mapped_module> module,
      ) {
        _invokeVoid(
          slot,
          () => Function.apply(callback, [_moduleFromNative(module.ref)]),
        );
      }),
    ),
    .threadCreate || .threadTerminated => _registration(
      NativeCallable<sogen_dart_linux_thread_callbackFunction>.isolateLocal((
        Pointer<Void> _,
        Pointer<sogen_dart_linux_thread_info> thread,
      ) {
        _invokeVoid(
          slot,
          () => Function.apply(callback, [
            _application._retainThread(_threadSnapshot(thread.ref)),
          ]),
        );
      }),
    ),
    .threadSwitch => _registration(
      NativeCallable<
        sogen_dart_linux_thread_switch_callbackFunction
      >.isolateLocal((Pointer<Void> _, int oldThreadId, int newThreadId) {
        _invokeVoid(
          slot,
          () => Function.apply(callback, [oldThreadId, newThreadId]),
        );
      }),
    ),
  };

  _LinuxCallbackRegistration _registration<T extends Function>(
    NativeCallable<T> callable,
  ) {
    callable.keepIsolateAlive = false;
    return _LinuxCallbackRegistration(
      callable.nativeFunction.cast<Void>(),
      callable.close,
    );
  }

  T _invoke<T>(_LinuxCallbackSlot slot, T fallback, T Function() callback) {
    _callbackDepth++;
    try {
      return callback();
    } on Object catch (error, stackTrace) {
      _callbackError ??= _LinuxCallbackError(slot.name, error, stackTrace);
      return fallback;
    } finally {
      _callbackDepth--;
    }
  }

  void _invokeVoid(_LinuxCallbackSlot slot, void Function() callback) {
    _invoke<Object?>(slot, null, () {
      callback();
      return null;
    });
  }

  void _clearCallbackErrors() {
    _callbackError = null;
  }

  _LinuxCallbackError? _firstCallbackError() => _callbackError;

  void _finishRun() {
    if (_callbackDepth != 0) {
      return;
    }
    for (final registration in _deferredCloses) {
      registration.close();
    }
    _deferredCloses.clear();
  }

  @override
  String toString() =>
      'LinuxCallbacks(onSignal/onException share the same callback slot)';
}

final class _LinuxCallbackRegistration {
  _LinuxCallbackRegistration(this.pointer, this._close);

  final Pointer<Void> pointer;
  final void Function() _close;
  bool _closed = false;

  void close() {
    if (_closed) {
      return;
    }
    _closed = true;
    try {
      _close();
    } on Object {
      // Continue releasing callbacks during application disposal.
    }
  }
}

final class _LinuxCallbackError {
  const _LinuxCallbackError(this.key, this.error, this.stackTrace);

  final String key;
  final Object error;
  final StackTrace stackTrace;
}

_LinuxCallbackSlot _linuxSlotFor(String name) {
  final normalized = name.startsWith('on_')
      ? name.substring(3)
      : name.startsWith('on') && name.length > 2
      ? '${name[2].toLowerCase()}${name.substring(3)}'
      : name;
  final camel = normalized.replaceAllMapped(
    RegExp(r'_([a-z])'),
    (match) => match[1]!.toUpperCase(),
  );
  for (final slot in _LinuxCallbackSlot.values) {
    if (slot.accepts(camel)) {
      return slot;
    }
  }
  throw ArgumentError.value(name, 'name', 'Unknown Linux callback name');
}

String _linuxString(Pointer<Uint8> value, int length) =>
    length == 0 ? '' : utf8.decode(value.asTypedList(length));

MemoryViolationType _linuxMemoryViolationType(int value) =>
    MemoryViolationType.values.firstWhere((type) => type.nativeValue == value);
