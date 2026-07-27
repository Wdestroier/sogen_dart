import 'generated/types.g.dart';

typedef InstructionHookCallback = Object? Function(int data);
typedef MemoryViolationHookCallback =
    Object? Function(
      int address,
      int size,
      MemoryOperation operation,
      MemoryViolationType type,
    );

HookContinuation coerceInstructionHookContinuation(Object? result) =>
    switch (result) {
      null || false => HookContinuation.run,
      true => HookContinuation.skip,
      final HookContinuation continuation => continuation,
      _ => throw ArgumentError.value(
        result,
        'callback result',
        'Expected HookContinuation, bool, or null',
      ),
    };

MemoryViolationContinuation coerceMemoryViolationHookContinuation(
  Object? result,
) => switch (result) {
  null || true => MemoryViolationContinuation.resume,
  false => MemoryViolationContinuation.stop,
  final MemoryViolationContinuation continuation => continuation,
  _ => throw ArgumentError.value(
    result,
    'callback result',
    'Expected MemoryViolationContinuation, bool, or null',
  ),
};
