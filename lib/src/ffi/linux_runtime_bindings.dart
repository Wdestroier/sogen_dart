import 'dart:ffi' as ffi;

import 'sogen_native_bindings.g.dart';

final class LinuxRuntimeBindings {
  LinuxRuntimeBindings(SogenNativeBindings bindings) : _bindings = bindings;

  final SogenNativeBindings _bindings;

  late final hookMemoryExecution = _bindings
      .lookup<
        ffi.NativeFunction<
          ffi.Int32 Function(
            ffi.Pointer<sogen_dart_app>,
            ffi.Int32,
            ffi.Uint64,
            sogen_dart_execution_callback,
            ffi.Pointer<ffi.Void>,
            ffi.Pointer<ffi.Uint64>,
          )
        >
      >('sogen_dart_linux_hook_memory_execution')
      .asFunction<
        int Function(
          ffi.Pointer<sogen_dart_app>,
          int,
          int,
          sogen_dart_execution_callback,
          ffi.Pointer<ffi.Void>,
          ffi.Pointer<ffi.Uint64>,
        )
      >();

  late final hookMemoryRead = _memoryHook('sogen_dart_linux_hook_memory_read');
  late final hookMemoryWrite = _memoryHook(
    'sogen_dart_linux_hook_memory_write',
  );

  int Function(
    ffi.Pointer<sogen_dart_app>,
    int,
    int,
    sogen_dart_memory_callback,
    ffi.Pointer<ffi.Void>,
    ffi.Pointer<ffi.Uint64>,
  )
  _memoryHook(String name) => _bindings
      .lookup<
        ffi.NativeFunction<
          ffi.Int32 Function(
            ffi.Pointer<sogen_dart_app>,
            ffi.Uint64,
            ffi.Uint64,
            sogen_dart_memory_callback,
            ffi.Pointer<ffi.Void>,
            ffi.Pointer<ffi.Uint64>,
          )
        >
      >(name)
      .asFunction();

  late final hookInstruction = _bindings
      .lookup<
        ffi.NativeFunction<
          ffi.Int32 Function(
            ffi.Pointer<sogen_dart_app>,
            ffi.Int32,
            sogen_dart_instruction_callback,
            ffi.Pointer<ffi.Void>,
            ffi.Pointer<ffi.Uint64>,
          )
        >
      >('sogen_dart_linux_hook_instruction')
      .asFunction<
        int Function(
          ffi.Pointer<sogen_dart_app>,
          int,
          sogen_dart_instruction_callback,
          ffi.Pointer<ffi.Void>,
          ffi.Pointer<ffi.Uint64>,
        )
      >();

  late final hookInterrupt = _bindings
      .lookup<
        ffi.NativeFunction<
          ffi.Int32 Function(
            ffi.Pointer<sogen_dart_app>,
            sogen_dart_interrupt_callback,
            ffi.Pointer<ffi.Void>,
            ffi.Pointer<ffi.Uint64>,
          )
        >
      >('sogen_dart_linux_hook_interrupt')
      .asFunction<
        int Function(
          ffi.Pointer<sogen_dart_app>,
          sogen_dart_interrupt_callback,
          ffi.Pointer<ffi.Void>,
          ffi.Pointer<ffi.Uint64>,
        )
      >();

  late final hookMemoryViolation = _bindings
      .lookup<
        ffi.NativeFunction<
          ffi.Int32 Function(
            ffi.Pointer<sogen_dart_app>,
            sogen_dart_memory_violation_callback,
            ffi.Pointer<ffi.Void>,
            ffi.Pointer<ffi.Uint64>,
          )
        >
      >('sogen_dart_linux_hook_memory_violation')
      .asFunction<
        int Function(
          ffi.Pointer<sogen_dart_app>,
          sogen_dart_memory_violation_callback,
          ffi.Pointer<ffi.Void>,
          ffi.Pointer<ffi.Uint64>,
        )
      >();

  late final hookBasicBlock = _bindings
      .lookup<
        ffi.NativeFunction<
          ffi.Int32 Function(
            ffi.Pointer<sogen_dart_app>,
            sogen_dart_basic_block_callback,
            ffi.Pointer<ffi.Void>,
            ffi.Pointer<ffi.Uint64>,
          )
        >
      >('sogen_dart_linux_hook_basic_block')
      .asFunction<
        int Function(
          ffi.Pointer<sogen_dart_app>,
          sogen_dart_basic_block_callback,
          ffi.Pointer<ffi.Void>,
          ffi.Pointer<ffi.Uint64>,
        )
      >();

  late final removeHook = _statusUint64('sogen_dart_linux_remove_hook');

  late final setSymbolHook = _bindings
      .lookup<
        ffi.NativeFunction<
          ffi.Int32 Function(
            ffi.Pointer<sogen_dart_app>,
            ffi.Pointer<ffi.Char>,
            ffi.Size,
            sogen_dart_linux_symbol_callback,
            ffi.Pointer<ffi.Void>,
          )
        >
      >('sogen_dart_linux_set_symbol_hook')
      .asFunction<
        int Function(
          ffi.Pointer<sogen_dart_app>,
          ffi.Pointer<ffi.Char>,
          int,
          sogen_dart_linux_symbol_callback,
          ffi.Pointer<ffi.Void>,
        )
      >();

  late final removeSymbolHook = _statusString(
    'sogen_dart_linux_remove_symbol_hook',
  );
  late final clearSymbolHooks = _status('sogen_dart_linux_clear_symbol_hooks');
  late final refreshSymbolHooks = _status(
    'sogen_dart_linux_refresh_symbol_hooks',
  );

  late final debugSetBreakpoint = _breakpoint(
    'sogen_dart_linux_debug_set_breakpoint',
  );
  late final debugClearBreakpoint = _breakpoint(
    'sogen_dart_linux_debug_clear_breakpoint',
  );
  late final debugListBreakpoints = _bindings
      .lookup<
        ffi.NativeFunction<
          ffi.Int32 Function(
            ffi.Pointer<sogen_dart_app>,
            ffi.Pointer<sogen_dart_buffer>,
          )
        >
      >('sogen_dart_linux_debug_list_breakpoints')
      .asFunction<
        int Function(
          ffi.Pointer<sogen_dart_app>,
          ffi.Pointer<sogen_dart_buffer>,
        )
      >();

  late final debugStepInto = _status('sogen_dart_linux_debug_step_into');
  late final debugStepOver = _status('sogen_dart_linux_debug_step_over');
  late final debugStepOut = _status('sogen_dart_linux_debug_step_out');
  late final debugRunTo = _statusUint64('sogen_dart_linux_debug_run_to');
  late final debugContinueExecution = _status(
    'sogen_dart_linux_debug_continue_execution',
  );
  late final debugPause = _status('sogen_dart_linux_debug_pause');

  late final debugDisassemble = _bindings
      .lookup<
        ffi.NativeFunction<
          ffi.Int32 Function(
            ffi.Pointer<sogen_dart_app>,
            ffi.Uint64,
            ffi.Size,
            ffi.Pointer<sogen_dart_linux_disassembled_instruction_list>,
          )
        >
      >('sogen_dart_linux_debug_disassemble')
      .asFunction<
        int Function(
          ffi.Pointer<sogen_dart_app>,
          int,
          int,
          ffi.Pointer<sogen_dart_linux_disassembled_instruction_list>,
        )
      >();

  late final freeDisassembly = _bindings
      .lookup<
        ffi.NativeFunction<
          ffi.Void Function(
            ffi.Pointer<sogen_dart_linux_disassembled_instruction_list>,
          )
        >
      >('sogen_dart_linux_disassembled_instruction_list_free')
      .asFunction<
        void Function(
          ffi.Pointer<sogen_dart_linux_disassembled_instruction_list>,
        )
      >();

  late final debugCallStack = _bindings
      .lookup<
        ffi.NativeFunction<
          ffi.Int32 Function(
            ffi.Pointer<sogen_dart_app>,
            ffi.Pointer<sogen_dart_linux_stack_frame_list>,
          )
        >
      >('sogen_dart_linux_debug_call_stack')
      .asFunction<
        int Function(
          ffi.Pointer<sogen_dart_app>,
          ffi.Pointer<sogen_dart_linux_stack_frame_list>,
        )
      >();

  late final freeCallStack = _bindings
      .lookup<
        ffi.NativeFunction<
          ffi.Void Function(ffi.Pointer<sogen_dart_linux_stack_frame_list>)
        >
      >('sogen_dart_linux_stack_frame_list_free')
      .asFunction<
        void Function(ffi.Pointer<sogen_dart_linux_stack_frame_list>)
      >();

  int Function(ffi.Pointer<sogen_dart_app>) _status(String name) => _bindings
      .lookup<
        ffi.NativeFunction<ffi.Int32 Function(ffi.Pointer<sogen_dart_app>)>
      >(name)
      .asFunction();

  int Function(ffi.Pointer<sogen_dart_app>, int) _statusUint64(String name) =>
      _bindings
          .lookup<
            ffi.NativeFunction<
              ffi.Int32 Function(ffi.Pointer<sogen_dart_app>, ffi.Uint64)
            >
          >(name)
          .asFunction();

  int Function(ffi.Pointer<sogen_dart_app>, ffi.Pointer<ffi.Char>)
  _statusString(String name) => _bindings
      .lookup<
        ffi.NativeFunction<
          ffi.Int32 Function(ffi.Pointer<sogen_dart_app>, ffi.Pointer<ffi.Char>)
        >
      >(name)
      .asFunction();

  int Function(ffi.Pointer<sogen_dart_app>, int, ffi.Pointer<ffi.Int32>)
  _breakpoint(String name) => _bindings
      .lookup<
        ffi.NativeFunction<
          ffi.Int32 Function(
            ffi.Pointer<sogen_dart_app>,
            ffi.Uint64,
            ffi.Pointer<ffi.Int32>,
          )
        >
      >(name)
      .asFunction();
}
