@Tags(<String>['native', 'windowsGuest', 'unicorn', 'requiresCc'])
@Timeout(Duration(minutes: 4))
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:sogen/windows.dart';
import 'package:test/test.dart';

import 'windows_hook_fixture.dart';

const _payloadBytes = <int>[8, 7, 6, 5, 4, 3, 2, 1];
const _faultAddress = 0x22220000;
const _faultValueBytes = <int>[0x57, 0x13, 0x68, 0x24];
const _skippedCpuidValue = 0x13572468;

void main() {
  final configuredRoot = Platform.environment['SOGEN_WINDOWS_ROOT'];
  final exampleRoot = Directory('example/root').absolute;
  final root =
      configuredRoot ?? (exampleRoot.existsSync() ? exampleRoot.path : null);
  final skipReason = !Platform.isWindows
      ? 'The low-hook fixture requires a Windows host.'
      : root == null
      ? 'Set SOGEN_WINDOWS_ROOT or create example/root to run this test.'
      : false;

  group('Windows low-level hooks', () {
    WindowsHookFixtures? installedFixtures;

    setUpAll(() async {
      installedFixtures = await buildWindowsHookFixtures(root!);
    });

    tearDownAll(() async {
      await installedFixtures?.dispose();
    });

    test('registers and removes every low-level hook family', () {
      final app = createEmpty(emulationRoot: root!);
      try {
        final hooks = <Hook>[
          app.hooks.memoryExecution((_) {}),
          app.hooks.memoryExecutionAt(0, (_) {}),
          app.hooks.memoryRead(0, 1, (_, _) {}),
          app.hooks.memoryWrite(0, 1, (_, _) {}),
          for (final instruction in Instruction.values)
            app.hooks.instruction(instruction, (_) => HookContinuation.run),
          app.hooks.interrupt((_) {}),
          app.hooks.memoryViolation(
            (_, _, _, _) => MemoryViolationContinuation.stop,
          ),
          app.hooks.basicBlock((_) {}),
        ];

        expect(hooks.map((hook) => hook.id).toSet(), hasLength(hooks.length));
        expect(
          hooks,
          everyElement(isA<Hook>().having((h) => h.active, 'active', isTrue)),
        );
        for (final hook in hooks) {
          hook.remove();
          hook.remove();
          expect(hook.active, isFalse);
        }

        final retained = app.hooks.interrupt((_) {});
        app.dispose();
        expect(retained.active, isFalse);
        retained.remove();
      } finally {
        app.dispose();
      }
    });

    test(
      'delivers every execution, memory, instruction, and block payload',
      () {
        final app = _fixtureApplication(root!, 'hooks');
        MappedModule? fixtureModule;
        app.callbacks.onModuleLoad = (module) {
          if (module.name.toLowerCase() == 'api-hook-fixture.exe') {
            fixtureModule = module;
          }
        };
        app.setupProcessIfNecessary();
        final module = fixtureModule!;
        final exports = <String, ExportedSymbol>{
          for (final symbol in module.exports) symbol.name: symbol,
        };
        final readAddress = exports['hook_read_payload']!.address;
        final writeAddress = exports['hook_write_payload']!.address;
        final executionAddress = exports['hook_execution_probe']!.address;

        Hook? executionHook;
        Hook? exactExecutionHook;
        Hook? readHook;
        Hook? writeHook;
        Hook? blockHook;
        final instructionHooks = <Instruction, Hook>{};
        int? executionHit;
        int? exactExecutionHit;
        int? readHit;
        int? writeHit;
        Uint8List? readBytes;
        Uint8List? writeBytes;
        BasicBlock? block;
        final instructionData = <Instruction, int>{};

        executionHook = app.hooks.memoryExecution((address) {
          executionHit = address;
          executionHook!.remove();
        });
        exactExecutionHook = app.hooks.memoryExecutionAt(executionAddress, (
          address,
        ) {
          exactExecutionHit = address;
          exactExecutionHook!.remove();
        });
        readHook = app.hooks.memoryRead(readAddress, 8, (address, data) {
          readHit = address;
          readBytes = data;
          readHook!.remove();
        });
        writeHook = app.hooks.memoryWrite(writeAddress, 8, (address, data) {
          writeHit = address;
          writeBytes = data;
          writeHook!.remove();
        });
        blockHook = app.hooks.basicBlock((value) {
          block = value;
          blockHook!.remove();
        });
        for (final instruction in const [
          Instruction.syscall,
          Instruction.cpuid,
          Instruction.rdtsc,
          Instruction.rdtscp,
        ]) {
          late Hook hook;
          hook = app.hooks.instruction(instruction, (data) {
            instructionData[instruction] = data;
            hook.remove();
            return HookContinuation.run;
          });
          instructionHooks[instruction] = hook;
        }

        try {
          app.start();
          expect(app.process.exitStatus, 0);
          expect(executionHit, isNonZero);
          expect(exactExecutionHit, executionAddress);
          expect(readHit, readAddress);
          expect(writeHit, writeAddress);
          expect(readBytes, _payloadBytes);
          expect(writeBytes, _payloadBytes);
          expect(app.readMemory(writeAddress, 8), _payloadBytes);
          app.writeMemory(readAddress, List<int>.filled(8, 0));
          expect(readBytes, _payloadBytes);
          expect(writeBytes, _payloadBytes);
          expect(instructionData.keys, containsAll(instructionHooks.keys));
          expect(instructionData.values, everyElement(0));
          expect(block, isNotNull);
          expect(block!.address, isNonZero);
          expect(block!.instructionCount, greaterThanOrEqualTo(0));
          expect(block!.size, greaterThan(0));
          expect(
            [
              executionHook,
              exactExecutionHook,
              readHook,
              writeHook,
              blockHook,
              ...instructionHooks.values,
            ],
            everyElement(
              isA<Hook>().having((h) => h.active, 'active', isFalse),
            ),
          );
        } finally {
          app.dispose();
        }
      },
    );

    test(
      'skip continuation bypasses CPUID and preserves callback registers',
      () {
        final app = _fixtureApplication(root!, 'instruction-skip');
        MappedModule? fixtureModule;
        app.callbacks.onModuleLoad = (module) {
          if (module.name.toLowerCase() == 'api-hook-fixture.exe') {
            fixtureModule = module;
          }
        };
        app.setupProcessIfNecessary();
        final probeAddress = fixtureModule!.exports
            .singleWhere((symbol) => symbol.name == 'hook_instruction_probe')
            .address;
        Hook? hook;
        int? data;
        hook = app.hooks.instruction(.cpuid, (value) {
          final rip = app.readRegister(.rip);
          if (rip < probeAddress || rip >= probeAddress + 0x100) {
            return HookContinuation.run;
          }
          data = value;
          app.writeRegister(.eax, _skippedCpuidValue);
          hook!.remove();
          return HookContinuation.skip;
        });

        try {
          app.start();
          expect(app.process.exitStatus, 0);
          expect(data, 0);
          expect(hook.active, isFalse);
        } finally {
          app.dispose();
        }
      },
    );

    test(
      'finalize RIP continuation preserves the callback-selected syscall RIP',
      () {
        final app = _fixtureApplication(root!);
        app.hooks.apis['GetCurrentProcessId'] = apiCall(
          cc: .stdcall,
          cb: (call, _) {
            call.returnValue = 0xc0ffee01;
            return ApiContinuation.intercept;
          },
        );
        Hook? hook;
        int? selectedRip;
        hook = app.hooks.instruction(.syscall, (data) {
          expect(data, 0);
          selectedRip = app.readRegister(.rip);
          app.writeRegister(.rip, selectedRip!);
          hook!.remove();
          return HookContinuation.finalizeRip;
        });

        try {
          app.start();
          expect(app.process.exitStatus, 0);
          expect(selectedRip, isNonZero);
          expect(hook.active, isFalse);
        } finally {
          app.dispose();
        }
      },
    );

    test('interrupt delivers its vector and permits self-removal', () {
      final app = _fixtureApplication(root!, 'interrupt');
      Hook? hook;
      int? vector;
      hook = app.hooks.interrupt((value) {
        vector = value;
        hook!.remove();
        app.stop();
      });

      try {
        app.start();
        expect(vector, 3);
        expect(hook.active, isFalse);
      } finally {
        app.dispose();
      }
    });

    test(
      'keeps a low-level hook active without retaining the returned Hook',
      () {
        final app = _fixtureApplication(root!, 'hooks');
        MappedModule? fixtureModule;
        app.callbacks.onModuleLoad = (module) {
          if (module.name.toLowerCase() == 'api-hook-fixture.exe') {
            fixtureModule = module;
          }
        };
        app.setupProcessIfNecessary();
        final probeAddress = fixtureModule!.exports
            .singleWhere((symbol) => symbol.name == 'hook_execution_probe')
            .address;
        final hits = <int>[];
        app.hooks.memoryExecutionAt(probeAddress, hits.add);

        try {
          app.start();
          expect(hits, [probeAddress]);
          expect(app.process.exitStatus, 0);
        } finally {
          app.dispose();
        }
      },
    );

    for (final testCase in const [
      (
        argument: 'violation-unmapped-read',
        operation: MemoryPermission.read,
        continuation: MemoryViolationContinuation.restart,
        exitStatus: 0,
      ),
      (
        argument: 'violation-unmapped-write',
        operation: MemoryPermission.write,
        continuation: MemoryViolationContinuation.resume,
        exitStatus: 0,
      ),
      (
        argument: 'violation-unmapped-execute',
        operation: MemoryPermission.exec,
        continuation: MemoryViolationContinuation.restart,
        exitStatus: -1073741819,
      ),
    ]) {
      test('${testCase.continuation.name} repairs unmapped '
          '${testCase.operation.name} violations', () {
        final app = _fixtureApplication(root!, testCase.argument);
        Hook? hook;
        (int, int, MemoryOperation, MemoryViolationType)? violation;
        hook = app.hooks.memoryViolation((address, size, operation, type) {
          violation = (address, size, operation, type);
          final base = address & ~0xfff;
          expect(app.memory.allocateMemory(0x1000, .all, start: base), base);
          if (operation == MemoryPermission.exec) {
            app.writeMemory(address, const [0xb8, 42, 0, 0, 0, 0xc3]);
          } else {
            app.writeMemory(address, _faultValueBytes);
          }
          hook!.remove();
          return testCase.continuation;
        });

        try {
          app.start();
          expect(app.process.exitStatus, testCase.exitStatus);
          expect(violation, isNotNull);
          expect(violation!.$1, _faultAddress);
          expect(violation!.$2, greaterThan(0));
          expect(violation!.$3, testCase.operation);
          expect(violation!.$4, MemoryViolationType.unmapped);
          expect(hook.active, isFalse);
        } finally {
          app.dispose();
        }
      });
    }

    for (final testCase in const [
      (argument: 'violation-protection-read', operation: MemoryPermission.read),
      (
        argument: 'violation-protection-write',
        operation: MemoryPermission.write,
      ),
      (
        argument: 'violation-protection-execute',
        operation: MemoryPermission.exec,
      ),
    ]) {
      test('stop handles protection ${testCase.operation.name} violations', () {
        final app = _fixtureApplication(root!, testCase.argument);
        Hook? hook;
        (int, int, MemoryOperation, MemoryViolationType)? violation;
        hook = app.hooks.memoryViolation((address, size, operation, type) {
          violation = (address, size, operation, type);
          hook!.remove();
          return MemoryViolationContinuation.stop;
        });

        try {
          app.start();
          expect(
            app.process.exitStatus,
            testCase.operation == MemoryPermission.exec ? isNot(0) : 0,
          );
          expect(violation, isNotNull);
          expect(violation!.$1, isNonZero);
          expect(violation!.$2, greaterThan(0));
          expect(violation!.$3, testCase.operation);
          expect(violation!.$4, MemoryViolationType.protection);
          expect(hook.active, isFalse);
        } finally {
          app.dispose();
        }
      });
    }

    test(
      'instruction callback errors run the instruction and are reported',
      () {
        final app = _fixtureApplication(root!, 'instruction-run');
        app.hooks.instruction(.cpuid, (_) {
          throw StateError('instruction callback failure');
        });

        try {
          expect(
            app.start,
            throwsA(
              isA<SogenCallbackException>()
                  .having((error) => error.hookKey, 'hookKey', 'instruction')
                  .having((error) => error.error, 'error', isA<StateError>()),
            ),
          );
          expect(app.process.exitStatus, 0);
        } finally {
          app.dispose();
        }
      },
    );

    test('memory callback errors stop the violation and are reported', () {
      final app = _fixtureApplication(root!, 'violation-unmapped-read');
      app.hooks.memoryViolation((_, _, _, _) {
        throw StateError('memory violation callback failure');
      });

      try {
        expect(
          app.start,
          throwsA(
            isA<SogenCallbackException>()
                .having((error) => error.hookKey, 'hookKey', 'memoryViolation')
                .having((error) => error.error, 'error', isA<StateError>()),
          ),
        );
        expect(app.process.exitStatus, 0);
      } finally {
        app.dispose();
      }
    });

    test('void callback errors use safe fallback and reject hook mutation', () {
      final app = _fixtureApplication(root!, 'hooks');
      Hook? current;
      final other = app.hooks.interrupt((_) {});
      Object? removalError;
      Object? additionError;
      current = app.hooks.memoryExecution((_) {
        try {
          other.remove();
        } on Object catch (error) {
          removalError = error;
        }
        try {
          app.hooks.interrupt((_) {});
        } on Object catch (error) {
          additionError = error;
        }
        current!.remove();
        throw StateError('execution callback failure');
      });

      try {
        expect(
          app.start,
          throwsA(
            isA<SogenCallbackException>()
                .having((error) => error.hookKey, 'hookKey', 'memoryExecution')
                .having((error) => error.error, 'error', isA<StateError>()),
          ),
        );
        expect(app.process.exitStatus, 0);
        expect(removalError, isA<StateError>());
        expect(additionError, isA<StateError>());
        expect(current.active, isFalse);
        expect(other.active, isTrue);
      } finally {
        app.dispose();
      }
    });
  }, skip: skipReason);
}

WindowsApplication _fixtureApplication(String root, [String? argument]) =>
    createApplication(
      windowsHookFixtureGuest,
      arguments: [?argument],
      emulationRoot: root,
    );
