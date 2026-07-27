import 'package:sogen/src/hook_continuation.dart'
    show
        coerceInstructionHookContinuation,
        coerceMemoryViolationHookContinuation;
import 'package:sogen/windows.dart';
import 'package:test/test.dart';

void main() {
  group('instruction hook continuation', () {
    test('callback type permits bool, null, and enum results', () {
      final callbacks = <InstructionHookCallback>[
        (_) => null,
        (_) => false,
        (_) => true,
        (_) => HookContinuation.run,
        (_) => HookContinuation.skip,
        (_) => HookContinuation.finalizeRip,
      ];

      expect(
        callbacks
            .map((callback) => coerceInstructionHookContinuation(callback(0)))
            .toList(),
        [
          HookContinuation.run,
          HookContinuation.run,
          HookContinuation.skip,
          HookContinuation.run,
          HookContinuation.skip,
          HookContinuation.finalizeRip,
        ],
      );
    });

    test('rejects every other result type', () {
      for (final result in <Object>[
        0,
        'run',
        MemoryViolationContinuation.resume,
      ]) {
        expect(
          () => coerceInstructionHookContinuation(result),
          throwsA(
            isA<ArgumentError>()
                .having((error) => error.name, 'name', 'callback result')
                .having((error) => error.invalidValue, 'invalidValue', result),
          ),
        );
      }
    });
  });

  group('memory violation hook continuation', () {
    test('callback type permits bool, null, and enum results', () {
      final callbacks = <MemoryViolationHookCallback>[
        (_, _, _, _) => null,
        (_, _, _, _) => true,
        (_, _, _, _) => false,
        (_, _, _, _) => MemoryViolationContinuation.resume,
        (_, _, _, _) => MemoryViolationContinuation.stop,
        (_, _, _, _) => MemoryViolationContinuation.restart,
      ];

      expect(
        callbacks
            .map(
              (callback) => coerceMemoryViolationHookContinuation(
                callback(
                  0,
                  1,
                  MemoryOperation.read,
                  MemoryViolationType.unmapped,
                ),
              ),
            )
            .toList(),
        [
          MemoryViolationContinuation.resume,
          MemoryViolationContinuation.resume,
          MemoryViolationContinuation.stop,
          MemoryViolationContinuation.resume,
          MemoryViolationContinuation.stop,
          MemoryViolationContinuation.restart,
        ],
      );
    });

    test('rejects every other result type', () {
      for (final result in <Object>[0, 'resume', HookContinuation.run]) {
        expect(
          () => coerceMemoryViolationHookContinuation(result),
          throwsA(
            isA<ArgumentError>()
                .having((error) => error.name, 'name', 'callback result')
                .having((error) => error.invalidValue, 'invalidValue', result),
          ),
        );
      }
    });
  });
}
