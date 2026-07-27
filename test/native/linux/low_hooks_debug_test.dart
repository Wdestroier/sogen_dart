@Tags(<String>['native', 'linux', 'unicorn'])
library;

import 'dart:typed_data';

import 'package:sogen/linux.dart';
import 'package:test/test.dart';

void main() {
  test('delivers every low-level hook payload and supports self-removal', () {
    final app = createEmpty();
    const code = 0x100000;
    const data = 0x200000;
    expect(app.memory.allocateMemoryAt(code, 0x1000, .exec), isTrue);
    expect(app.memory.allocateMemoryAt(data, 0x1000, .readWrite), isTrue);
    app.writeMemory(data, 'ABCDEFGH'.codeUnits);
    app.writeMemory(code, <int>[
      0x48,
      0xbb,
      0x00,
      0x00,
      0x20,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x48,
      0x8b,
      0x03,
      0x48,
      0x89,
      0x43,
      0x08,
      0x0f,
      0xa2,
    ]);
    app.writeRegister(.rip, code);

    final executions = <int>[];
    final exactExecutions = <int>[];
    final reads = <(int, Uint8List)>[];
    final writes = <(int, Uint8List)>[];
    final blocks = <BasicBlock>[];
    final instructions = <int>[];
    late Hook exactHook;
    exactHook = app.hooks.memoryExecutionAt(code, (address) {
      exactExecutions.add(address);
      exactHook.remove();
    });
    final handles = <Hook>[
      app.hooks.memoryExecution(executions.add),
      exactHook,
      app.hooks.memoryRead(data, 8, (address, bytes) {
        reads.add((address, bytes));
      }),
      app.hooks.memoryWrite(data + 8, 8, (address, bytes) {
        writes.add((address, bytes));
      }),
      app.hooks.basicBlock(blocks.add),
      app.hooks.instruction(.cpuid, (value) {
        instructions.add(value);
        app.stop();
        return true;
      }),
    ];

    app.start(50);
    expect(executions, isNotEmpty);
    expect(exactExecutions, <int>[code]);
    expect(exactHook.active, isFalse);
    expect(reads.single.$1, data);
    expect(reads.single.$2, 'ABCDEFGH'.codeUnits);
    expect(writes.single.$1, data + 8);
    expect(writes.single.$2, 'ABCDEFGH'.codeUnits);
    expect(blocks, isNotEmpty);
    expect(blocks.first.address, code);
    expect(blocks.first.size, greaterThan(0));
    expect(instructions, isNotEmpty);
    expect(app.readMemory(data + 8, 8), 'ABCDEFGH'.codeUnits);

    for (final hook in handles) {
      hook.remove();
      hook.remove();
      expect(hook.active, isFalse);
    }
    final retained = app.hooks.interrupt((_) {});
    app.dispose();
    expect(retained.active, isFalse);
    retained.remove();
  });

  test('contains interrupt and memory-violation callback failures', () {
    final interruptApp = createEmpty();
    expect(
      interruptApp.memory.allocateMemoryAt(0x100000, 0x1000, .exec),
      isTrue,
    );
    interruptApp.writeMemory(0x100000, <int>[0xcc]);
    interruptApp.writeRegister(.rip, 0x100000);
    late Hook interrupt;
    interrupt = interruptApp.hooks.interrupt((number) {
      expect(number, 3);
      interrupt.remove();
      interruptApp.stop();
      throw StateError('interrupt failed');
    });
    expect(
      () => interruptApp.start(10),
      throwsA(
        isA<SogenCallbackException>()
            .having((error) => error.hookKey, 'hookKey', 'interrupt')
            .having((error) => error.error, 'error', isA<StateError>()),
      ),
    );
    expect(interrupt.active, isFalse);
    interruptApp.dispose();

    final violationApp = createEmpty();
    const fault = 0xdead0000;
    violationApp.writeRegister(.rip, fault);
    final events = <(int, int, MemoryOperation, MemoryViolationType)>[];
    late Hook violation;
    violation = violationApp.hooks.memoryViolation((
      address,
      size,
      operation,
      type,
    ) {
      events.add((address, size, operation, type));
      violation.remove();
      return false;
    });
    violationApp.start(1);
    expect(events, [
      (fault, 1, MemoryOperation.exec, MemoryViolationType.unmapped),
    ]);
    expect(violation.active, isFalse);
    expect(violationApp.lastStopReason, 'unhandled_memory_violation');
    expect(violationApp.lastStopReasonCode, 7);
    expect(violationApp.lastStopDetail, 'address=0xdead0000 size=1');
    expect(violationApp.process.exitStatus, isNull);
    violationApp.dispose();
  });

  test('reports exact SIGSEGV callback for an invalid fetch', () {
    final app = createEmpty();
    const fault = 0xdead0000;
    final events = <(int, int, int)>[];
    app.writeRegister(.rip, fault);
    app.callbacks.onSignal = (signal, address, code) {
      events.add((signal, address, code));
    };

    try {
      app.start(1);
      expect(events, [(11, fault, 1)]);
    } finally {
      app.dispose();
    }
  });

  for (final testCase in const [
    (opcode: <int>[0x48, 0x8b, 0x05], operation: MemoryOperation.read),
    (opcode: <int>[0x48, 0x89, 0x05], operation: MemoryOperation.write),
  ]) {
    test('reports exact unmapped ${testCase.operation.name} payload', () {
      final app = createEmpty();
      const code = 0x100000;
      const target = 0x200000;
      expect(app.memory.allocateMemoryAt(code, 0x1000, .exec), isTrue);
      app.writeMemory(code, _ripRelative(testCase.opcode, code, target));
      app.writeRegister(.rip, code);
      final events = <(int, int, MemoryOperation, MemoryViolationType)>[];
      late Hook hook;
      hook = app.hooks.memoryViolation((address, size, operation, type) {
        events.add((address, size, operation, type));
        hook.remove();
        return MemoryViolationContinuation.stop;
      });

      try {
        app.start(10);
        expect(events, [
          (target, 8, testCase.operation, MemoryViolationType.unmapped),
        ]);
        expect(hook.active, isFalse);
        expect(app.lastStopReason, 'unhandled_memory_violation');
        expect(app.lastStopDetail, 'address=0x200000 size=8');
        expect(app.process.exitStatus, isNull);
      } finally {
        app.dispose();
      }
    });
  }

  for (final continuation in const [
    MemoryViolationContinuation.resume,
    MemoryViolationContinuation.restart,
  ]) {
    test(
      '${continuation.name} explicitly retries a newly mapped instruction page',
      () {
        final app = createEmpty();
        const target = 0x410000;
        app.writeRegister(.rip, target);
        final events = <(int, int, MemoryOperation, MemoryViolationType)>[];
        var instructionHits = 0;
        app.callbacks.onMemoryViolate = (address, size, operation, type) {
          events.add((address, size, operation, type));
          expect(app.memory.allocateMemoryAt(target, 0x1000, .exec), isTrue);
          app.writeMemory(target, const [0x0f, 0xa2]);
          return continuation;
        };
        final instruction = app.hooks.instruction(.cpuid, (_) {
          instructionHits++;
          app.stop();
          return HookContinuation.skip;
        });

        try {
          app.start(10);
          expect(events, [
            (target, 1, MemoryOperation.exec, MemoryViolationType.unmapped),
          ]);
          expect(instructionHits, 1);
        } finally {
          instruction.remove();
          app.dispose();
        }
      },
    );
  }

  test('reports read, write, and execute protection violations', () {
    const code = 0x100000;
    const target = 0x200000;
    final cases = <(MemoryOperation, MemoryPermission, List<int>)>[
      (
        MemoryOperation.read,
        MemoryPermission.write,
        _ripRelative(const [0x48, 0x8b, 0x05], code, target),
      ),
      (
        MemoryOperation.write,
        MemoryPermission.read,
        _ripRelative(const [0x48, 0x89, 0x05], code, target),
      ),
      (MemoryOperation.exec, MemoryPermission.readWrite, const []),
    ];

    for (final testCase in cases) {
      final app = createEmpty();
      try {
        expect(
          app.memory.allocateMemoryAt(target, 0x1000, testCase.$2),
          isTrue,
        );
        if (testCase.$1 == MemoryOperation.exec) {
          app.writeMemory(target, const [0x90]);
          app.writeRegister(.rip, target);
        } else {
          expect(app.memory.allocateMemoryAt(code, 0x1000, .exec), isTrue);
          app.writeMemory(code, testCase.$3);
          app.writeRegister(.rip, code);
        }
        final events = <(int, MemoryOperation, MemoryViolationType)>[];
        app.callbacks.onMemoryViolate = (address, _, operation, type) {
          events.add((address, operation, type));
          return MemoryViolationContinuation.stop;
        };

        app.start(10);
        expect(events, [(target, testCase.$1, MemoryViolationType.protection)]);
        expect(app.lastStopReason, 'unhandled_memory_violation');
      } finally {
        app.dispose();
      }
    }
  });

  test('implements debugger breakpoint, stepping, views, and diagnostics', () {
    final app = createEmpty();
    const code = 0x100000;
    expect(app.memory.allocateMemoryAt(code, 0x1000, .exec), isTrue);
    app.writeMemory(code, <int>[0x0f, 0xa2, 0x0f, 0xa2, 0x0f, 0xa2]);
    app.writeRegister(.rip, code);

    expect(app.debug.setBreakpoint(code + 2), isTrue);
    expect(app.debug.setBreakpoint(code + 4), isTrue);
    expect(app.debug.listBreakpoints(), <int>[code + 2, code + 4]);
    app.debug.continueExecution();
    expect(app.lastStopReason, 'breakpoint');
    expect(app.debug.registers()['rip'], code + 2);
    app.debug.continueExecution();
    expect(app.debug.registers()['rip'], code + 4);
    app.debug.stepInto();
    expect(app.readRegister(.rip), greaterThan(code + 4));
    expect(app.debug.clearBreakpoint(code + 2), isTrue);
    expect(app.debug.clearBreakpoint(code + 2), isFalse);
    expect(app.debug.clearBreakpoint(code + 4), isTrue);

    app.writeRegister(.rip, code);
    app.debug.runTo(code + 4);
    expect(app.readRegister(.rip), code + 4);
    app.debug.stepOver();
    expect(app.readRegister(.rip), greaterThan(code + 4));
    app.debug.pause();

    app.writeRegister(.rip, code);
    final instructions = app.debug.disassemble(code, 3);
    expect(instructions, hasLength(3));
    expect(instructions.first.mnemonic.toLowerCase(), 'cpuid');
    expect(instructions.first.bytes, <int>[0x0f, 0xa2]);
    expect(app.debug.modules(), isEmpty);
    expect(app.debug.threads(), isEmpty);
    expect(app.debug.callStack().first.instructionPointer, code);

    app.writeRegister(.rbp, 0);
    expect(
      app.debug.stepOut,
      throwsA(
        isA<SogenException>().having(
          (error) => error.message,
          'message',
          'step_out cannot find a caller because RBP is zero; use '
              'run_to(address) when the target return address is known',
        ),
      ),
    );

    app.writeRegister(.rbp, 0x300000);
    expect(
      app.debug.stepOut,
      throwsA(
        isA<SogenException>().having(
          (error) => error.message,
          'message',
          'step_out cannot read the saved return address at 0x300008; use '
              'run_to(address) if frame pointers are unavailable',
        ),
      ),
    );
    expect(app.memory.allocateMemoryAt(0x300000, 0x1000, .readWrite), isTrue);
    app.writeMemory(0x300000, List<int>.filled(16, 0));
    expect(
      app.debug.stepOut,
      throwsA(
        isA<SogenException>().having(
          (error) => error.message,
          'message',
          'step_out found a zero saved return address at 0x300008; use '
              'run_to(address) for an explicit destination',
        ),
      ),
    );
    app.dispose();
  });
}

List<int> _ripRelative(List<int> opcode, int instruction, int target) {
  final displacement = target - (instruction + opcode.length + 4);
  final encoded = ByteData(4)..setInt32(0, displacement, Endian.little);
  return <int>[...opcode, ...encoded.buffer.asUint8List()];
}
