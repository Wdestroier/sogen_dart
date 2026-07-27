part of 'application.dart';

typedef ModuleLoadCallback = void Function(MappedModule module);
typedef ModuleUnloadCallback = void Function(MappedModule module);
typedef StdoutCallback = void Function(String data);
typedef SyscallCallback = Object? Function(int syscallId, String syscallName);
typedef GenericAccessCallback = void Function(String type, String name);
typedef GenericActivityCallback = void Function(String description);
typedef SuspiciousActivityCallback = void Function(String description);
typedef ExceptionCallback = void Function();
typedef InstructionCallback = void Function(int address);
typedef MemoryProtectCallback =
    void Function(int address, int length, MemoryPermission permission);
typedef MemoryAllocateCallback =
    void Function(
      int address,
      int length,
      MemoryPermission permission,
      bool commit,
    );
typedef MemoryViolateCallback =
    Object? Function(
      int address,
      int length,
      MemoryOperation operation,
      MemoryViolationType type,
    );
typedef RdtscCallback = void Function();
typedef RdtscpCallback = void Function();
typedef IoctrlCallback = void Function(String deviceName, int code);
typedef DebugStringCallback = void Function(String message);
typedef ThreadCreateCallback =
    void Function(int handle, int threadId, int startAddress, int argument);
typedef ThreadTerminatedCallback = void Function(int handle, int threadId);
typedef ThreadSetNameCallback = void Function(int threadId, String name);
typedef ThreadSwitchCallback =
    void Function(int currentThreadId, int newThreadId);

typedef _WindowsCallbackSlot = WindowsCallbackSlot;

final class WindowsCallbacks {
  WindowsCallbacks._();

  late WindowsApplication _application;
  final Map<_WindowsCallbackSlot, Function> _callbacks = {};
  final Map<_WindowsCallbackSlot, _WindowsCallbackRegistration> _registrations =
      {};
  final List<_WindowsCallbackRegistration> _deferredCloses = [];
  _CallbackError? _callbackError;
  int _callbackDepth = 0;

  void _attach(WindowsApplication application) {
    _application = application;
  }

  ModuleLoadCallback? get onModuleLoad =>
      _callbacks[_WindowsCallbackSlot.moduleLoad] as ModuleLoadCallback?;
  set onModuleLoad(ModuleLoadCallback? callback) =>
      _set(_WindowsCallbackSlot.moduleLoad, callback);

  ModuleUnloadCallback? get onModuleUnload =>
      _callbacks[_WindowsCallbackSlot.moduleUnload] as ModuleUnloadCallback?;
  set onModuleUnload(ModuleUnloadCallback? callback) =>
      _set(_WindowsCallbackSlot.moduleUnload, callback);

  StdoutCallback? get onStdout =>
      _callbacks[_WindowsCallbackSlot.stdout] as StdoutCallback?;
  set onStdout(StdoutCallback? callback) =>
      _set(_WindowsCallbackSlot.stdout, callback);

  SyscallCallback? get onSyscall =>
      _callbacks[_WindowsCallbackSlot.syscall] as SyscallCallback?;
  set onSyscall(SyscallCallback? callback) =>
      _set(_WindowsCallbackSlot.syscall, callback);

  GenericAccessCallback? get onGenericAccess =>
      _callbacks[_WindowsCallbackSlot.genericAccess] as GenericAccessCallback?;
  set onGenericAccess(GenericAccessCallback? callback) =>
      _set(_WindowsCallbackSlot.genericAccess, callback);

  GenericActivityCallback? get onGenericActivity =>
      _callbacks[_WindowsCallbackSlot.genericActivity]
          as GenericActivityCallback?;
  set onGenericActivity(GenericActivityCallback? callback) =>
      _set(_WindowsCallbackSlot.genericActivity, callback);

  SuspiciousActivityCallback? get onSuspiciousActivity =>
      _callbacks[_WindowsCallbackSlot.suspiciousActivity]
          as SuspiciousActivityCallback?;
  set onSuspiciousActivity(SuspiciousActivityCallback? callback) =>
      _set(_WindowsCallbackSlot.suspiciousActivity, callback);

  ExceptionCallback? get onException =>
      _callbacks[_WindowsCallbackSlot.exception] as ExceptionCallback?;
  set onException(ExceptionCallback? callback) =>
      _set(_WindowsCallbackSlot.exception, callback);

  InstructionCallback? get onInstruction =>
      _callbacks[_WindowsCallbackSlot.instruction] as InstructionCallback?;
  set onInstruction(InstructionCallback? callback) =>
      _set(_WindowsCallbackSlot.instruction, callback);

  MemoryProtectCallback? get onMemoryProtect =>
      _callbacks[_WindowsCallbackSlot.memoryProtect] as MemoryProtectCallback?;
  set onMemoryProtect(MemoryProtectCallback? callback) =>
      _set(_WindowsCallbackSlot.memoryProtect, callback);

  MemoryAllocateCallback? get onMemoryAllocate =>
      _callbacks[_WindowsCallbackSlot.memoryAllocate]
          as MemoryAllocateCallback?;
  set onMemoryAllocate(MemoryAllocateCallback? callback) =>
      _set(_WindowsCallbackSlot.memoryAllocate, callback);

  MemoryViolateCallback? get onMemoryViolate =>
      _callbacks[_WindowsCallbackSlot.memoryViolate] as MemoryViolateCallback?;
  set onMemoryViolate(MemoryViolateCallback? callback) =>
      _set(_WindowsCallbackSlot.memoryViolate, callback);

  RdtscCallback? get onRdtsc =>
      _callbacks[_WindowsCallbackSlot.rdtsc] as RdtscCallback?;
  set onRdtsc(RdtscCallback? callback) =>
      _set(_WindowsCallbackSlot.rdtsc, callback);

  RdtscpCallback? get onRdtscp =>
      _callbacks[_WindowsCallbackSlot.rdtscp] as RdtscpCallback?;
  set onRdtscp(RdtscpCallback? callback) =>
      _set(_WindowsCallbackSlot.rdtscp, callback);

  IoctrlCallback? get onIoctrl =>
      _callbacks[_WindowsCallbackSlot.ioctrl] as IoctrlCallback?;
  set onIoctrl(IoctrlCallback? callback) =>
      _set(_WindowsCallbackSlot.ioctrl, callback);

  DebugStringCallback? get onDebugString =>
      _callbacks[_WindowsCallbackSlot.debugString] as DebugStringCallback?;
  set onDebugString(DebugStringCallback? callback) =>
      _set(_WindowsCallbackSlot.debugString, callback);

  ThreadCreateCallback? get onThreadCreate =>
      _callbacks[_WindowsCallbackSlot.threadCreate] as ThreadCreateCallback?;
  set onThreadCreate(ThreadCreateCallback? callback) =>
      _set(_WindowsCallbackSlot.threadCreate, callback);

  ThreadTerminatedCallback? get onThreadTerminated =>
      _callbacks[_WindowsCallbackSlot.threadTerminated]
          as ThreadTerminatedCallback?;
  set onThreadTerminated(ThreadTerminatedCallback? callback) =>
      _set(_WindowsCallbackSlot.threadTerminated, callback);

  ThreadSetNameCallback? get onThreadSetName =>
      _callbacks[_WindowsCallbackSlot.threadSetName] as ThreadSetNameCallback?;
  set onThreadSetName(ThreadSetNameCallback? callback) =>
      _set(_WindowsCallbackSlot.threadSetName, callback);

  ThreadSwitchCallback? get onThreadSwitch =>
      _callbacks[_WindowsCallbackSlot.threadSwitch] as ThreadSwitchCallback?;
  set onThreadSwitch(ThreadSwitchCallback? callback) =>
      _set(_WindowsCallbackSlot.threadSwitch, callback);

  void set(String name, Function? callback) => _set(_slotFor(name), callback);

  void clear(String name) => _set(_slotFor(name), null);

  void _set(_WindowsCallbackSlot slot, Function? callback) {
    _application._ensureUsable();
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
    final table = calloc<sogen_dart_windows_callbacks>();
    try {
      table.ref
        ..user_data = nullptr
        ..module_load = _pointer<sogen_dart_module_callbackFunction>(
          _WindowsCallbackSlot.moduleLoad,
        )
        ..module_unload = _pointer<sogen_dart_module_callbackFunction>(
          _WindowsCallbackSlot.moduleUnload,
        )
        ..stdout_callback = _pointer<sogen_dart_text_callbackFunction>(
          _WindowsCallbackSlot.stdout,
        )
        ..syscall = _pointer<sogen_dart_syscall_callbackFunction>(
          _WindowsCallbackSlot.syscall,
        )
        ..generic_access = _pointer<sogen_dart_generic_access_callbackFunction>(
          _WindowsCallbackSlot.genericAccess,
        )
        ..generic_activity = _pointer<sogen_dart_text_callbackFunction>(
          _WindowsCallbackSlot.genericActivity,
        )
        ..suspicious_activity = _pointer<sogen_dart_text_callbackFunction>(
          _WindowsCallbackSlot.suspiciousActivity,
        )
        ..exception = _pointer<sogen_dart_void_callbackFunction>(
          _WindowsCallbackSlot.exception,
        )
        ..instruction = _pointer<sogen_dart_address_callbackFunction>(
          _WindowsCallbackSlot.instruction,
        )
        ..memory_protect =
            _pointer<sogen_dart_memory_protect_event_callbackFunction>(
              _WindowsCallbackSlot.memoryProtect,
            )
        ..memory_allocate =
            _pointer<sogen_dart_memory_allocate_event_callbackFunction>(
              _WindowsCallbackSlot.memoryAllocate,
            )
        ..memory_violate =
            _pointer<sogen_dart_memory_violate_event_callbackFunction>(
              _WindowsCallbackSlot.memoryViolate,
            )
        ..rdtsc = _pointer<sogen_dart_void_callbackFunction>(
          _WindowsCallbackSlot.rdtsc,
        )
        ..rdtscp = _pointer<sogen_dart_void_callbackFunction>(
          _WindowsCallbackSlot.rdtscp,
        )
        ..ioctrl = _pointer<sogen_dart_ioctrl_callbackFunction>(
          _WindowsCallbackSlot.ioctrl,
        )
        ..debug_string = _pointer<sogen_dart_text_callbackFunction>(
          _WindowsCallbackSlot.debugString,
        )
        ..thread_create = _pointer<sogen_dart_thread_create_callbackFunction>(
          _WindowsCallbackSlot.threadCreate,
        )
        ..thread_terminated =
            _pointer<sogen_dart_thread_terminated_callbackFunction>(
              _WindowsCallbackSlot.threadTerminated,
            )
        ..thread_set_name =
            _pointer<sogen_dart_thread_set_name_callbackFunction>(
              _WindowsCallbackSlot.threadSetName,
            )
        ..thread_switch = _pointer<sogen_dart_thread_switch_callbackFunction>(
          _WindowsCallbackSlot.threadSwitch,
        );
      _application._library.checkStatus(
        _application._library.bindings.sogen_dart_windows_set_callbacks(
          _application._pointer,
          table,
        ),
      );
    } finally {
      calloc.free(table);
    }
  }

  Pointer<NativeFunction<T>> _pointer<T extends Function>(
    _WindowsCallbackSlot slot,
  ) => _registrations[slot]?.pointer.cast<NativeFunction<T>>() ?? nullptr;

  _WindowsCallbackRegistration _createRegistration(
    _WindowsCallbackSlot slot,
    Function callback,
  ) => switch (slot) {
    .moduleLoad || .moduleUnload => _registration(
      NativeCallable<sogen_dart_module_callbackFunction>.isolateLocal((
        Pointer<Void> _,
        Pointer<sogen_dart_mapped_module> module,
      ) {
        _invokeVoid(slot, () => Function.apply(callback, [_module(module)]));
      }),
    ),
    .stdout ||
    .genericActivity ||
    .suspiciousActivity ||
    .debugString => _registration(
      NativeCallable<sogen_dart_text_callbackFunction>.isolateLocal((
        Pointer<Void> _,
        Pointer<Uint8> text,
        int length,
      ) {
        _invokeVoid(
          slot,
          () => Function.apply(callback, [_string(text, length)]),
        );
      }),
    ),
    .syscall => _registration(
      NativeCallable<sogen_dart_syscall_callbackFunction>.isolateLocal((
        Pointer<Void> _,
        int id,
        Pointer<Uint8> name,
        int length,
      ) {
        return _invoke(
          slot,
          HookContinuation.run.nativeValue,
          () => coerceInstructionHookContinuation(
            Function.apply(callback, [id, _string(name, length)]),
          ).nativeValue,
        );
      }, exceptionalReturn: 0),
    ),
    .genericAccess => _registration(
      NativeCallable<sogen_dart_generic_access_callbackFunction>.isolateLocal((
        Pointer<Void> _,
        Pointer<Uint8> type,
        int typeLength,
        Pointer<Uint8> name,
        int nameLength,
      ) {
        _invokeVoid(
          slot,
          () => Function.apply(callback, [
            _string(type, typeLength),
            _string(name, nameLength),
          ]),
        );
      }),
    ),
    .exception || .rdtsc || .rdtscp => _registration(
      NativeCallable<sogen_dart_void_callbackFunction>.isolateLocal((
        Pointer<Void> _,
      ) {
        _invokeVoid(slot, () => Function.apply(callback, const []));
      }),
    ),
    .instruction => _registration(
      NativeCallable<sogen_dart_address_callbackFunction>.isolateLocal((
        Pointer<Void> _,
        int address,
      ) {
        _invokeVoid(slot, () => Function.apply(callback, [address]));
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
    .memoryAllocate => _registration(
      NativeCallable<
        sogen_dart_memory_allocate_event_callbackFunction
      >.isolateLocal((
        Pointer<Void> _,
        int address,
        int length,
        int permission,
        int commit,
      ) {
        _invokeVoid(
          slot,
          () => Function.apply(callback, [
            address,
            length,
            _memoryPermission(permission),
            commit != 0,
          ]),
        );
      }),
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
              _memoryViolationType(type),
            ]),
          ).nativeValue,
        );
      }, exceptionalReturn: 1),
    ),
    .ioctrl => _registration(
      NativeCallable<sogen_dart_ioctrl_callbackFunction>.isolateLocal((
        Pointer<Void> _,
        Pointer<Uint8> name,
        int length,
        int code,
      ) {
        _invokeVoid(
          slot,
          () => Function.apply(callback, [_string(name, length), code]),
        );
      }),
    ),
    .threadCreate => _registration(
      NativeCallable<sogen_dart_thread_create_callbackFunction>.isolateLocal((
        Pointer<Void> _,
        int handle,
        int threadId,
        int startAddress,
        int argument,
      ) {
        _invokeVoid(
          slot,
          () => Function.apply(callback, [
            handle,
            threadId,
            startAddress,
            argument,
          ]),
        );
      }),
    ),
    .threadTerminated => _registration(
      NativeCallable<
        sogen_dart_thread_terminated_callbackFunction
      >.isolateLocal((Pointer<Void> _, int handle, int threadId) {
        _invokeVoid(slot, () => Function.apply(callback, [handle, threadId]));
      }),
    ),
    .threadSetName => _registration(
      NativeCallable<sogen_dart_thread_set_name_callbackFunction>.isolateLocal((
        Pointer<Void> _,
        int threadId,
        Pointer<Uint8> name,
        int length,
      ) {
        _invokeVoid(
          slot,
          () => Function.apply(callback, [threadId, _string(name, length)]),
        );
      }),
    ),
    .threadSwitch => _registration(
      NativeCallable<sogen_dart_thread_switch_callbackFunction>.isolateLocal((
        Pointer<Void> _,
        int currentThreadId,
        int newThreadId,
      ) {
        _invokeVoid(
          slot,
          () => Function.apply(callback, [currentThreadId, newThreadId]),
        );
      }),
    ),
  };

  _WindowsCallbackRegistration _registration<T extends Function>(
    NativeCallable<T> callable,
  ) {
    callable.keepIsolateAlive = false;
    return _WindowsCallbackRegistration(
      callable.nativeFunction.cast<Void>(),
      callable.close,
    );
  }

  T _invoke<T>(_WindowsCallbackSlot slot, T fallback, T Function() callback) {
    _callbackDepth++;
    try {
      return callback();
    } on Object catch (error, stackTrace) {
      _callbackError ??= _CallbackError(slot.name, error, stackTrace);
      return fallback;
    } finally {
      _callbackDepth--;
    }
  }

  void _invokeVoid(_WindowsCallbackSlot slot, void Function() callback) {
    _invoke<Object?>(slot, null, () {
      callback();
      return null;
    });
  }

  void _clearCallbackErrors() {
    _callbackError = null;
  }

  _CallbackError? _firstCallbackError() => _callbackError;

  void _finishRun() {
    if (_callbackDepth != 0) {
      return;
    }
    for (final registration in _deferredCloses) {
      registration.close();
    }
    _deferredCloses.clear();
  }
}

final class _WindowsCallbackRegistration {
  _WindowsCallbackRegistration(this.pointer, this._close);

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

_WindowsCallbackSlot _slotFor(String name) {
  final normalized = name.startsWith('on_')
      ? name.substring(3)
      : name.startsWith('on') && name.length > 2
      ? '${name[2].toLowerCase()}${name.substring(3)}'
      : name;
  final camel = normalized.replaceAllMapped(
    RegExp(r'_([a-z])'),
    (match) => match[1]!.toUpperCase(),
  );
  for (final slot in _WindowsCallbackSlot.values) {
    if (slot.accepts(camel)) {
      return slot;
    }
  }
  throw ArgumentError.value(name, 'name', 'Unknown Windows callback name');
}

String _string(Pointer<Uint8> value, int length) =>
    length == 0 ? '' : utf8.decode(value.asTypedList(length));

MappedModule _module(Pointer<sogen_dart_mapped_module> pointer) {
  final module = pointer.ref;
  return MappedModule(
    name: _string(module.name_utf8, module.name_length),
    path: _string(module.path_utf8, module.path_length),
    modulePath: _string(module.module_path_utf8, module.module_path_length),
    imageBase: module.image_base,
    imageBaseFile: module.image_base_file,
    sizeOfImage: module.size_of_image,
    entryPoint: module.entry_point,
    exports: List<ExportedSymbol>.unmodifiable([
      for (var index = 0; index < module.export_count; index++)
        ExportedSymbol(
          name: _string(
            module.exports[index].name_utf8,
            module.exports[index].name_length,
          ),
          ordinal: module.exports[index].ordinal,
          rva: module.exports[index].rva,
          address: module.exports[index].address,
        ),
    ]),
    isStatic: module.is_static != 0,
  );
}
