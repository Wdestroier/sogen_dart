part of 'linux.dart';

typedef LinuxExecutionHookCallback = void Function(int address);
typedef LinuxMemoryHookCallback = void Function(int address, Uint8List data);
typedef LinuxInterruptHookCallback = void Function(int interruptNumber);
typedef LinuxBasicBlockHookCallback = void Function(BasicBlock block);
typedef LinuxSymbolHookCallback =
    dynamic Function(LinuxSymbolCall call, List<dynamic> parameters);

final class LinuxSymbolCall {
  LinuxSymbolCall({
    required this.module,
    required this.name,
    required this.address,
    required this.returnAddress,
    this.returnValue = 0,
  });

  final LinuxMappedModule module;
  final String name;
  final int address;
  final int returnAddress;
  int returnValue;
}

final class LinuxSymbolHook {
  LinuxSymbolHook._({
    required List<CType<dynamic>> parameters,
    required this.returnType,
    required this.callback,
  }) : parameters = List.unmodifiable(parameters);

  final List<CType<dynamic>> parameters;
  final CType<dynamic>? returnType;
  final LinuxSymbolHookCallback callback;
}

LinuxSymbolHook symbolCall({
  List<CType<dynamic>>? params,
  CType<dynamic>? restype,
  required LinuxSymbolHookCallback cb,
}) => _createLinuxSymbolHook(params: params, restype: restype, cb: cb);

LinuxSymbolHook _createLinuxSymbolHook({
  List<CType<dynamic>>? params,
  CType<dynamic>? restype,
  required LinuxSymbolHookCallback cb,
}) {
  final parameters = params ?? const <CType<dynamic>>[];
  for (final parameter in parameters) {
    _validateLinuxSymbolType(parameter, 'parameter');
  }
  if (restype != null) {
    _validateLinuxSymbolType(restype, 'return');
  }
  return LinuxSymbolHook._(
    parameters: parameters,
    returnType: restype,
    callback: cb,
  );
}

void _validateLinuxSymbolType(CType<dynamic> type, String role) {
  if (type is! Uint8Type &&
      type is! Int8Type &&
      type is! Uint16Type &&
      type is! Int16Type &&
      type is! Uint32Type &&
      type is! Int32Type &&
      type is! Uint64Type &&
      type is! Int64Type &&
      type is! CharType &&
      type is! PointerType &&
      type is! Bool32Type) {
    throw ArgumentError.value(
      type,
      role,
      'Linux symbol hook types must be integer, bool, char, or pointer descriptors',
    );
  }
}

final class LinuxHooks {
  LinuxHooks._() : symbols = LinuxSymbolHooks._();

  final LinuxSymbolHooks symbols;
  final Map<int, _LinuxLowHookRegistration> _registrations = {};
  final List<_LinuxLowHookRegistration> _deferredCallbackCloses = [];
  late LinuxApplication _application;
  late LinuxRuntimeBindings _bindings;
  _LinuxLowHookRegistration? _currentCallback;
  _LinuxHookError? _callbackError;

  void _attach(LinuxApplication application) {
    _application = application;
    _bindings = LinuxRuntimeBindings(application._library.bindings);
    symbols._attach(application, _bindings);
  }

  Hook memoryExecution(LinuxExecutionHookCallback callback) =>
      _execution('memoryExecution', false, 0, callback);

  Hook memoryExecutionAt(int address, LinuxExecutionHookCallback callback) {
    _address(address);
    return _execution('memoryExecutionAt', true, address, callback);
  }

  Hook _execution(
    String name,
    bool hasAddress,
    int address,
    LinuxExecutionHookCallback callback,
  ) {
    late _LinuxLowHookRegistration registration;
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
      name,
      callable,
      callable.close,
      (output) => _bindings.hookMemoryExecution(
        _application._pointer,
        hasAddress ? 1 : 0,
        address,
        callable.nativeFunction,
        nullptr,
        output,
      ),
    );
    return registration.hook;
  }

  Hook memoryRead(int address, int size, LinuxMemoryHookCallback callback) =>
      _memory('memoryRead', address, size, callback, _bindings.hookMemoryRead);

  Hook memoryWrite(int address, int size, LinuxMemoryHookCallback callback) =>
      _memory(
        'memoryWrite',
        address,
        size,
        callback,
        _bindings.hookMemoryWrite,
      );

  Hook _memory(
    String name,
    int address,
    int size,
    LinuxMemoryHookCallback callback,
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
    _range(address, size);
    late _LinuxLowHookRegistration registration;
    final callable =
        NativeCallable<sogen_dart_memory_callbackFunction>.isolateLocal((
          Pointer<Void> _,
          int id,
          int hitAddress,
          Pointer<Uint8> data,
          int length,
        ) {
          _invokeVoid(registration, () {
            callback(
              hitAddress,
              length == 0
                  ? Uint8List(0)
                  : Uint8List.fromList(data.asTypedList(length)),
            );
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

  Hook instruction(Instruction instruction, InstructionHookCallback callback) {
    late _LinuxLowHookRegistration registration;
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
      (output) => _bindings.hookInstruction(
        _application._pointer,
        instruction.nativeValue,
        callable.nativeFunction,
        nullptr,
        output,
      ),
    );
    return registration.hook;
  }

  Hook interrupt(LinuxInterruptHookCallback callback) {
    late _LinuxLowHookRegistration registration;
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
      (output) => _bindings.hookInterrupt(
        _application._pointer,
        callable.nativeFunction,
        nullptr,
        output,
      ),
    );
    return registration.hook;
  }

  Hook memoryViolation(MemoryViolationHookCallback callback) {
    late _LinuxLowHookRegistration registration;
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
                MemoryViolationType.values.firstWhere(
                  (value) => value.nativeValue == type,
                ),
              ),
            ).nativeValue,
          );
        }, exceptionalReturn: 0);
    callable.keepIsolateAlive = false;
    registration = _register(
      'memoryViolation',
      callable,
      callable.close,
      (output) => _bindings.hookMemoryViolation(
        _application._pointer,
        callable.nativeFunction,
        nullptr,
        output,
      ),
    );
    return registration.hook;
  }

  Hook basicBlock(LinuxBasicBlockHookCallback callback) {
    late _LinuxLowHookRegistration registration;
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
      (output) => _bindings.hookBasicBlock(
        _application._pointer,
        callable.nativeFunction,
        nullptr,
        output,
      ),
    );
    return registration.hook;
  }

  _LinuxLowHookRegistration _register(
    String name,
    Object callable,
    void Function() close,
    int Function(Pointer<Uint64>) install,
  ) {
    final output = calloc<Uint64>();
    try {
      _application._checkStopped();
      _application._library.checkStatus(install(output));
      late _LinuxLowHookRegistration registration;
      final hook = Hook.internal(output.value, () => _remove(registration));
      registration = _LinuxLowHookRegistration(name, hook, callable, close);
      _registrations[hook.id] = registration;
      return registration;
    } on Object {
      close();
      rethrow;
    } finally {
      calloc.free(output);
    }
  }

  void _remove(_LinuxLowHookRegistration registration) {
    if (!registration.hook.active) return;
    _application._check();
    if (_application._running && !identical(_currentCallback, registration)) {
      throw StateError(
        'Only the current low-level hook can remove itself while running',
      );
    }
    _application._library.checkStatus(
      _bindings.removeHook(_application._pointer, registration.hook.id),
    );
    registration.hook.deactivate();
    _registrations.remove(registration.hook.id);
    if (registration.callbackDepth == 0) {
      registration.close();
    } else {
      _deferredCallbackCloses.add(registration);
    }
  }

  T _invoke<T>(
    _LinuxLowHookRegistration registration,
    T fallback,
    T Function() callback,
  ) {
    final previous = _currentCallback;
    _currentCallback = registration;
    registration.callbackDepth++;
    try {
      return callback();
    } on Object catch (error, stackTrace) {
      _callbackError ??= _LinuxHookError(registration.name, error, stackTrace);
      return fallback;
    } finally {
      registration.callbackDepth--;
      _currentCallback = previous;
    }
  }

  void _invokeVoid(
    _LinuxLowHookRegistration registration,
    void Function() callback,
  ) {
    _invoke<Object?>(registration, null, () {
      callback();
      return null;
    });
  }

  void _clearCallbackErrors() {
    _callbackError = null;
    symbols._clearCallbackErrors();
  }

  _LinuxHookError? _firstCallbackError() =>
      symbols._firstCallbackError() ?? _callbackError;

  void _finishRun() {
    for (final registration in _deferredCallbackCloses) {
      registration.close();
    }
    _deferredCallbackCloses.clear();
    symbols._finishRun();
  }
}

final class _LinuxLowHookRegistration {
  _LinuxLowHookRegistration(this.name, this.hook, this.callable, this._close);

  final String name;
  final Hook hook;
  final Object callable;
  final void Function() _close;
  int callbackDepth = 0;
  bool _closed = false;

  void close() {
    if (_closed) return;
    _closed = true;
    try {
      _close();
    } on Object {
      // Continue releasing remaining callbacks.
    }
  }
}

final class LinuxSymbolHooks {
  LinuxSymbolHooks._();

  final Map<String, _LinuxSymbolRegistration> _registrations = {};
  final List<_LinuxSymbolRegistration> _deferredCallbackCloses = [];
  late LinuxApplication _application;
  late LinuxRuntimeBindings _bindings;
  _LinuxHookError? _callbackError;

  void _attach(LinuxApplication application, LinuxRuntimeBindings bindings) {
    _application = application;
    _bindings = bindings;
  }

  LinuxSymbolHook? operator [](String key) => _registrations[key]?.hook;

  void operator []=(String key, LinuxSymbolHook? hook) {
    _application._check();
    if (key.isEmpty || key.endsWith('!')) {
      throw ArgumentError.value(key, 'key', 'Must contain a symbol name');
    }
    _remove(key);
    if (hook == null) return;

    late _LinuxSymbolRegistration registration;
    final callable =
        NativeCallable<sogen_dart_linux_symbol_callbackFunction>.isolateLocal((
          Pointer<Void> _,
          Pointer<sogen_dart_linux_symbol_call> nativeCall,
          Pointer<Uint64> nativeParameters,
          int parameterCount,
        ) {
          registration.callbackDepth++;
          try {
            final name = utf8.decode(
              nativeCall.ref.name_utf8.asTypedList(nativeCall.ref.name_length),
            );
            final module = _application.findModuleByAddress(
              nativeCall.ref.address,
            );
            if (module == null) {
              throw StateError('Symbol hook module is no longer mapped');
            }
            final call = LinuxSymbolCall(
              module: module,
              name: name,
              address: nativeCall.ref.address,
              returnAddress: nativeCall.ref.return_address,
              returnValue: nativeCall.ref.return_value,
            );
            final parameters = List<dynamic>.unmodifiable([
              for (var index = 0; index < parameterCount; ++index)
                hook.parameters[index].decode(nativeParameters[index]),
            ]);
            final result = hook.callback(call, parameters);
            nativeCall.ref.return_value = call.returnValue;
            return switch (result) {
              null || false => ApiContinuation.runOriginal.nativeValue,
              true => ApiContinuation.intercept.nativeValue,
              final ApiContinuation continuation => continuation.nativeValue,
              _ => throw ArgumentError.value(
                result,
                'callback result',
                'Expected ApiContinuation, bool, or null',
              ),
            };
          } on Object catch (error, stackTrace) {
            _callbackError ??= _LinuxHookError(key, error, stackTrace);
            return ApiContinuation.runOriginal.nativeValue;
          } finally {
            registration.callbackDepth--;
          }
        }, exceptionalReturn: 0);
    callable.keepIsolateAlive = false;
    registration = _LinuxSymbolRegistration(hook, callable);

    final nativeKey = key.toNativeUtf8();
    try {
      _application._library.checkStatus(
        _bindings.setSymbolHook(
          _application._pointer,
          nativeKey.cast<Char>(),
          hook.parameters.length,
          callable.nativeFunction,
          nullptr,
        ),
      );
      _registrations[key] = registration;
    } on Object {
      callable.close();
      rethrow;
    } finally {
      malloc.free(nativeKey);
    }
  }

  void remove(String key) {
    _application._check();
    _remove(key);
  }

  void _remove(String key) {
    final registration = _registrations[key];
    if (registration == null) return;
    final nativeKey = key.toNativeUtf8();
    try {
      _application._library.checkStatus(
        _bindings.removeSymbolHook(
          _application._pointer,
          nativeKey.cast<Char>(),
        ),
      );
    } finally {
      malloc.free(nativeKey);
    }
    _registrations.remove(key);
    _close(registration);
  }

  void clear() {
    _application._check();
    _application._library.checkStatus(
      _bindings.clearSymbolHooks(_application._pointer),
    );
    for (final registration in _registrations.values) {
      _close(registration);
    }
    _registrations.clear();
  }

  void refresh() {
    _application._check();
    _application._library.checkStatus(
      _bindings.refreshSymbolHooks(_application._pointer),
    );
  }

  void _close(_LinuxSymbolRegistration registration) {
    if (registration.callbackDepth == 0) {
      registration.close();
    } else {
      _deferredCallbackCloses.add(registration);
    }
  }

  void _clearCallbackErrors() {
    _callbackError = null;
  }

  _LinuxHookError? _firstCallbackError() => _callbackError;

  void _finishRun() {
    for (final registration in _deferredCallbackCloses) {
      registration.close();
    }
    _deferredCallbackCloses.clear();
  }
}

final class _LinuxSymbolRegistration {
  _LinuxSymbolRegistration(this.hook, this.callable);

  final LinuxSymbolHook hook;
  final NativeCallable<sogen_dart_linux_symbol_callbackFunction> callable;
  int callbackDepth = 0;
  bool _closed = false;

  void close() {
    if (_closed) return;
    _closed = true;
    try {
      callable.close();
    } on Object {
      // Continue releasing remaining callbacks.
    }
  }
}

final class LinuxDebug {
  LinuxDebug._();

  late LinuxApplication _application;

  LinuxRuntimeBindings get _bindings => _application.hooks._bindings;

  bool setBreakpoint(int address) =>
      _breakpoint(address, _bindings.debugSetBreakpoint);

  bool clearBreakpoint(int address) =>
      _breakpoint(address, _bindings.debugClearBreakpoint);

  bool _breakpoint(
    int address,
    int Function(Pointer<sogen_dart_app>, int, Pointer<Int32>) operation,
  ) {
    _application._check();
    _address(address);
    final output = calloc<Int32>();
    try {
      _application._library.checkStatus(
        operation(_application._pointer, address, output),
      );
      return output.value != 0;
    } finally {
      calloc.free(output);
    }
  }

  List<int> listBreakpoints() {
    _application._check();
    final output = calloc<sogen_dart_buffer>();
    try {
      _application._library.checkStatus(
        _bindings.debugListBreakpoints(_application._pointer, output),
      );
      final count = output.ref.length ~/ sizeOf<Uint64>();
      return List<int>.unmodifiable([
        for (var index = 0; index < count; ++index)
          output.ref.data.cast<Uint64>()[index],
      ]);
    } finally {
      _application._library.bindings.sogen_dart_buffer_free(output);
      calloc.free(output);
    }
  }

  void stepInto() => _run(_bindings.debugStepInto);
  void stepOver() => _run(_bindings.debugStepOver);
  void stepOut() => _run(_bindings.debugStepOut);
  void runTo(int address) {
    _address(address);
    _run((app) => _bindings.debugRunTo(app, address));
  }

  void continueExecution() => _run(_bindings.debugContinueExecution);

  void pause() {
    _application._check();
    _application._library.checkStatus(
      _bindings.debugPause(_application._pointer),
    );
  }

  Map<String, int> registers() => Map.unmodifiable({
    'rax': _application.readRegister(.rax),
    'rbx': _application.readRegister(.rbx),
    'rcx': _application.readRegister(.rcx),
    'rdx': _application.readRegister(.rdx),
    'rsi': _application.readRegister(.rsi),
    'rdi': _application.readRegister(.rdi),
    'rbp': _application.readRegister(.rbp),
    'rsp': _application.readRegister(.rsp),
    'r8': _application.readRegister(.r8),
    'r9': _application.readRegister(.r9),
    'r10': _application.readRegister(.r10),
    'r11': _application.readRegister(.r11),
    'r12': _application.readRegister(.r12),
    'r13': _application.readRegister(.r13),
    'r14': _application.readRegister(.r14),
    'r15': _application.readRegister(.r15),
    'rip': _application.readRegister(.rip),
    'rflags': _application.readRegister(.eflags),
    'cs': _application.readRegister(.cs),
    'ss': _application.readRegister(.ss),
    'ds': _application.readRegister(.ds),
    'es': _application.readRegister(.es),
    'fs': _application.readRegister(.fs),
    'gs': _application.readRegister(.gs),
  });

  List<LinuxDebugModule> modules() => List.unmodifiable([
    for (final module in _application.modules)
      LinuxDebugModule(
        name: module.name,
        path: module.path,
        imageBase: module.imageBase,
        sizeOfImage: module.sizeOfImage,
        entryPoint: module.entryPoint,
      ),
  ]);

  List<LinuxDebugThread> threads() {
    final activeId = _application.process.activeThreadId;
    return List.unmodifiable([
      for (final thread in _application.process.threads)
        LinuxDebugThread(
          tid: thread.tid,
          currentIp: thread.currentIp,
          active: thread.tid == activeId,
          terminated: thread.terminated,
        ),
    ]);
  }

  List<LinuxDisassembledInstruction> disassemble(int address, int countOrSize) {
    _application._check();
    _range(address, countOrSize);
    final output = calloc<sogen_dart_linux_disassembled_instruction_list>();
    try {
      _application._library.checkStatus(
        _bindings.debugDisassemble(
          _application._pointer,
          address,
          countOrSize,
          output,
        ),
      );
      return List.unmodifiable([
        for (var index = 0; index < output.ref.length; ++index)
          LinuxDisassembledInstruction(
            address: output.ref.data[index].address,
            size: output.ref.data[index].size,
            bytes: _application._copyNativeBuffer(output.ref.data[index].bytes),
            mnemonic: _nativeString(output.ref.data[index].mnemonic_utf8),
            operands: _nativeString(output.ref.data[index].operands_utf8),
          ),
      ]);
    } finally {
      _bindings.freeDisassembly(output);
      calloc.free(output);
    }
  }

  List<LinuxStackFrame> callStack() {
    _application._check();
    final output = calloc<sogen_dart_linux_stack_frame_list>();
    try {
      _application._library.checkStatus(
        _bindings.debugCallStack(_application._pointer, output),
      );
      return List.unmodifiable([
        for (var index = 0; index < output.ref.length; ++index)
          LinuxStackFrame(
            instructionPointer: output.ref.data[index].instruction_pointer,
            stackPointer: output.ref.data[index].stack_pointer,
            module: _nativeString(output.ref.data[index].module_utf8),
          ),
      ]);
    } finally {
      _bindings.freeCallStack(output);
      calloc.free(output);
    }
  }

  void _run(int Function(Pointer<sogen_dart_app>) operation) {
    _application._check();
    if (_application._running) {
      throw StateError('The emulator is already running');
    }
    _application.callbacks._clearCallbackErrors();
    _application.hooks._clearCallbackErrors();
    _application._running = true;
    Object? nativeError;
    StackTrace? nativeStackTrace;
    try {
      _application._library.checkStatus(operation(_application._pointer));
    } on Object catch (error, stackTrace) {
      nativeError = error;
      nativeStackTrace = stackTrace;
    } finally {
      _application._running = false;
      _application.callbacks._finishRun();
      _application.hooks._finishRun();
    }
    final callbackError = _application.callbacks._firstCallbackError();
    if (callbackError != null) {
      throw SogenCallbackException(
        callbackError.key,
        callbackError.error,
        callbackError.stackTrace,
      );
    }
    final hookError = _application.hooks._firstCallbackError();
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
}

final class LinuxDebugModule {
  const LinuxDebugModule({
    required this.name,
    required this.path,
    required this.imageBase,
    required this.sizeOfImage,
    required this.entryPoint,
  });

  final String name;
  final String path;
  final int imageBase;
  final int sizeOfImage;
  final int entryPoint;
}

final class LinuxDebugThread {
  const LinuxDebugThread({
    required this.tid,
    required this.currentIp,
    required this.active,
    required this.terminated,
  });

  final int tid;
  final int currentIp;
  final bool active;
  final bool terminated;
}

final class LinuxDisassembledInstruction {
  LinuxDisassembledInstruction({
    required this.address,
    required this.size,
    required Uint8List bytes,
    required this.mnemonic,
    required this.operands,
  }) : bytes = Uint8List.fromList(bytes);

  final int address;
  final int size;
  final Uint8List bytes;
  final String mnemonic;
  final String operands;
}

final class LinuxStackFrame {
  const LinuxStackFrame({
    required this.instructionPointer,
    required this.stackPointer,
    required this.module,
  });

  final int instructionPointer;
  final int stackPointer;
  final String module;
}

final class _LinuxHookError {
  const _LinuxHookError(this.key, this.error, this.stackTrace);

  final String key;
  final Object error;
  final StackTrace stackTrace;
}
