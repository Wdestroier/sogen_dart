@Tags(<String>['native', 'linux', 'unicorn'])
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:sogen/linux.dart';
import 'package:test/test.dart';

void main() {
  late Directory temporaryDirectory;

  setUp(() {
    temporaryDirectory = Directory.systemTemp.createTempSync(
      'sogen-dart-linux-callbacks-',
    );
  });

  tearDown(() {
    temporaryDirectory.deleteSync(recursive: true);
  });

  test('exposes typed slots, aliases, replacement, and null clearing', () {
    final app = createEmpty();
    try {
      void stdout(String _) {}
      void replacement(String _) {}
      void signal(int _, int _, int _) {}

      app.callbacks.onStdout = stdout;
      expect(identical(app.callbacks.onStdout, stdout), isTrue);
      app.callbacks.set('on_stdout', replacement);
      expect(identical(app.callbacks.onStdout, replacement), isTrue);
      app.callbacks.clear('onStdout');
      expect(app.callbacks.onStdout, isNull);

      app.callbacks.set('signal', signal);
      expect(identical(app.callbacks.onSignal, signal), isTrue);
      expect(identical(app.callbacks.onException, signal), isTrue);
      app.callbacks.clear('on_exception');
      expect(app.callbacks.onSignal, isNull);
      app.callbacks.onException = signal;
      expect(identical(app.callbacks.onSignal, signal), isTrue);
      app.callbacks.onSignal = null;
      expect(app.callbacks.onException, isNull);

      final setters = <String, Function>{
        'stderr': (String _) {},
        'onSyscall': (int _, String _) => null,
        'memory_violate':
            (int _, int _, MemoryOperation _, MemoryViolationType _) => null,
        'onMemoryAllocate': (int _, int _, MemoryPermission _, bool _) {},
        'memoryProtect': (int _, int _, MemoryPermission _) {},
        'on_memory_release': (int _, int _) {},
        'moduleLoad': (LinuxMappedModule _) {},
        'onThreadCreate': (LinuxThread _) {},
        'thread_terminated': (LinuxThread _) {},
        'on_thread_switch': (int _, int _) {},
      };
      for (final entry in setters.entries) {
        app.callbacks.set(entry.key, entry.value);
      }
      for (final name in setters.keys) {
        app.callbacks.clear(name);
      }

      expect(
        () => app.callbacks.set('on_unknown', stdout),
        throwsArgumentError,
      );
      expect(() => app.callbacks.clear('unknown'), throwsArgumentError);
      expect(
        app.callbacks.toString(),
        contains('onSignal/onException share the same callback slot'),
      );
    } finally {
      app.dispose();
    }
  });

  test('delivers memory lifecycle payloads after native state changes', () {
    final app = createEmpty();
    const address = 0x300000;
    const length = 0x1000;
    final allocations = <(int, int, MemoryPermission, bool)>[];
    final protections = <(int, int, MemoryPermission)>[];
    final releases = <(int, int)>[];

    app.callbacks.onMemoryAllocate = (base, size, permissions, committed) {
      expect(app.memory.getRegionInfo(base), isNotNull);
      allocations.add((base, size, permissions, committed));
    };
    app.callbacks.onMemoryProtect = (base, size, permissions) {
      expect(app.memory.getRegionInfo(base)!.permissions, permissions);
      protections.add((base, size, permissions));
    };
    app.callbacks.onMemoryRelease = (base, size) {
      expect(app.memory.getRegionInfo(base), isNull);
      releases.add((base, size));
    };

    try {
      expect(app.memory.allocateMemoryAt(address, length, .readWrite), isTrue);
      expect(allocations, [
        (address, length, MemoryPermission.readWrite, true),
      ]);
      expect(app.memory.allocateMemoryAt(address, length, .readWrite), isFalse);
      expect(allocations, hasLength(1));
      expect(app.memory.protectMemory(address, length, .readExec), isTrue);
      expect(protections, [(address, length, MemoryPermission.readExec)]);
      final protected = app.memory.getRegionInfo(address)!;
      expect(protected.permissions, MemoryPermission.readExec);
      expect(protected.initialPermissions, MemoryPermission.readExec);
      expect(app.memory.protectMemory(0x90000000, length, .read), isFalse);
      expect(protections, hasLength(1));
      expect(app.memory.releaseMemory(0x90000000, 0), isFalse);
      expect(releases, isEmpty);
      expect(app.memory.releaseMemory(address, length), isTrue);
      expect(releases, [(address, length)]);
    } finally {
      app.dispose();
    }
  });

  test(
    'replays copied modules and keeps models after application disposal',
    () {
      final executable = _writeElf(
        temporaryDirectory,
        'module-replay.elf',
        _exitCode(0),
      );
      final app = createApplication(executable.path);
      final replay = <LinuxMappedModule>[];

      app.callbacks.onModuleLoad = replay.add;
      expect(replay, hasLength(1));
      expect(replay.single.name, 'module-replay.elf');
      expect(replay.single.imageBase, 0x400000);
      expect(
        replay.map((module) => module.imageBase),
        orderedEquals(
          replay.map((module) => module.imageBase).toList()..sort(),
        ),
      );

      final retained = replay.single;
      app.dispose();
      expect(retained.name, 'module-replay.elf');
      expect(
        File(retained.path).resolveSymbolicLinksSync(),
        executable.resolveSymbolicLinksSync(),
      );
    },
  );

  test(
    'delivers output and syscalls with synchronous callback state access',
    () {
      final executable = _writeElf(
        temporaryDirectory,
        'output.elf',
        _outputProgram('stdout-data', 'stderr-data'),
      );
      final app = createApplication(executable.path);
      final stdout = StringBuffer();
      final stderr = StringBuffer();
      final syscalls = <(int, String)>[];
      var restored = false;

      app.callbacks.onStdout = stdout.write;
      app.callbacks.onStderr = stderr.write;
      app.callbacks.onSyscall = (id, name) {
        syscalls.add((id, name));
        if (!restored) {
          restored = true;
          final state = app.serializeState();
          app.deserializeState(state);
          app.saveSnapshot();
          app.restoreSnapshot();
          return false;
        }
        return null;
      };

      try {
        app.start();
        expect(restored, isTrue);
        expect(stdout.toString(), 'stdout-data');
        expect(stderr.toString(), 'stderr-data');
        expect(syscalls.map((event) => event.$1), containsAll([1, 60]));
        expect(
          syscalls.map((event) => event.$2),
          containsAll(['write', 'exit']),
        );
        expect(app.process.exitStatus, 0);
      } finally {
        app.dispose();
      }
    },
  );

  test('coerces memory violation booleans and delivers exact payloads', () {
    const faultAddress = 0x500000;
    final resumeApp = createEmpty();
    final events = <(int, int, MemoryOperation, MemoryViolationType)>[];
    resumeApp.writeRegister(.rip, faultAddress);
    resumeApp.callbacks.onMemoryViolate = (address, size, operation, type) {
      events.add((address, size, operation, type));
      expect(
        resumeApp.memory.allocateMemoryAt(faultAddress, 0x1000, .readExec),
        isTrue,
      );
      resumeApp.writeMemory(faultAddress, _exitCode(7));
      return true;
    };
    try {
      resumeApp.start();
      expect(events, isNotEmpty);
      expect(events.first.$1, faultAddress);
      expect(events.first.$2, 1);
      expect(events.first.$3, MemoryOperation.exec);
      expect(events.first.$4, MemoryViolationType.unmapped);
      expect(resumeApp.process.exitStatus, 7);
    } finally {
      resumeApp.dispose();
    }

    final stopApp = createEmpty();
    stopApp.writeRegister(.rip, faultAddress);
    stopApp.callbacks.onMemoryViolate = (_, _, _, _) => false;
    try {
      stopApp.start(1);
      expect(stopApp.lastStopReason, 'unhandled_memory_violation');
      expect(stopApp.process.exitStatus, isNull);
    } finally {
      stopApp.dispose();
    }
  });

  test('uses onException as the exact signal callback alias', () {
    final executable = _writeElf(temporaryDirectory, 'signal.elf', const [
      0xcc,
    ]);
    final app = createApplication(executable.path);
    final signals = <(int, int, int)>[];
    app.callbacks.onException = (signum, faultAddress, signalCode) {
      signals.add((signum, faultAddress, signalCode));
    };

    try {
      app.start();
      expect(signals, isNotEmpty);
      expect(signals.first.$1, 5);
      expect(signals.first.$2, greaterThanOrEqualTo(0));
      expect(signals.first.$3, 1);
      expect(app.lastStopReason, 'signal_termination');
      expect(app.process.exitStatus, 133);
    } finally {
      app.dispose();
    }
  });

  test(
    'contains callback failures, uses safe defaults, and reports after start',
    () {
      final executable = _writeElf(
        temporaryDirectory,
        'callback-error.elf',
        _exitCode(0),
      );
      final app = createApplication(executable.path);
      app.callbacks.onSyscall = (_, _) {
        throw StateError('callback failure');
      };

      try {
        expect(
          app.start,
          throwsA(
            isA<SogenCallbackException>()
                .having((error) => error.hookKey, 'hookKey', 'syscall')
                .having((error) => error.error, 'error', isA<StateError>()),
          ),
        );
        expect(app.process.exitStatus, 0);
      } finally {
        app.dispose();
      }
    },
  );

  test('delivers retained thread create, termination, and switch payloads', () {
    final executable = _writeElf(
      temporaryDirectory,
      'threads.elf',
      _threadProgram(),
      memorySize: 0x3000,
    );
    final app = createApplication(executable.path);
    final created = <LinuxThread>[];
    final terminated = <LinuxThread>[];
    final switches = <(int, int)>[];
    app.callbacks.onThreadCreate = created.add;
    app.callbacks.onThreadTerminated = terminated.add;
    app.callbacks.onThreadSwitch = (oldTid, newTid) {
      switches.add((oldTid, newTid));
    };

    try {
      app.start();
      expect(created, isNotEmpty);
      expect(terminated, isNotEmpty);
      expect(
        terminated.map((thread) => thread.tid),
        containsAll(created.map((thread) => thread.tid)),
      );
      expect(
        terminated,
        everyElement(
          isA<LinuxThread>().having(
            (thread) => thread.terminated,
            'terminated',
            isTrue,
          ),
        ),
      );
      expect(switches, isNotEmpty);

      final retained = created.first;
      final retainedTerminated = terminated.first;
      final retainedTid = retained.tid;
      final retainedIp = retained.currentIp;
      final retainedTerminatedTid = retainedTerminated.tid;
      final retainedTerminatedIp = retainedTerminated.currentIp;
      final state = app.serializeState();
      app.deserializeState(state);
      expect(retained.tid, retainedTid);
      expect(retained.currentIp, retainedIp);
      expect(retainedTerminated.tid, retainedTerminatedTid);
      expect(retainedTerminated.currentIp, retainedTerminatedIp);
      expect(retainedTerminated.terminated, isTrue);

      app.saveSnapshot();
      app.restoreSnapshot();
      expect(retained.tid, retainedTid);
      expect(retained.currentIp, retainedIp);
      expect(retainedTerminated.tid, retainedTerminatedTid);
      expect(retainedTerminated.currentIp, retainedTerminatedIp);
      expect(retainedTerminated.terminated, isTrue);
    } finally {
      app.dispose();
    }
  });
}

List<int> _exitCode(int code) => <int>[
  0xbf,
  code,
  0,
  0,
  0, // mov edi, code
  0xb8,
  0x3c,
  0,
  0,
  0, // mov eax, 60
  0x0f,
  0x05, // syscall
];

List<int> _outputProgram(String stdout, String stderr) {
  final stdoutBytes = stdout.codeUnits;
  final stderrBytes = stderr.codeUnits;
  final code = <int>[];

  void write(int fd, int dataOffset, int length) {
    code.addAll([0xb8, 1, 0, 0, 0]);
    code.addAll([0xbf, fd, 0, 0, 0]);
    final leaOffset = code.length;
    code.addAll([0x48, 0x8d, 0x35, 0, 0, 0, 0]);
    code.addAll([0xba, length, 0, 0, 0]);
    code.addAll([0x0f, 0x05]);
    _setInt32(code, leaOffset + 3, dataOffset - (leaOffset + 7));
  }

  const instructionLength = 60;
  write(1, instructionLength, stdoutBytes.length);
  write(2, instructionLength + stdoutBytes.length, stderrBytes.length);
  code.addAll(_exitCode(0));
  code.addAll(stdoutBytes);
  code.addAll(stderrBytes);
  return code;
}

List<int> _threadProgram() {
  final code = <int>[
    0xb8, 0x38, 0, 0, 0, // mov eax, 56 (clone)
    0xbf, 0x00, 0x0f, 0x01, 0x00, // mov edi, clone flags
    0x48, 0x8d, 0x35, 0, 0, 0, 0, // lea rsi, [rip + child stack]
    0x31, 0xd2, // xor edx, edx
    0x45, 0x31, 0xd2, // xor r10d, r10d
    0x45, 0x31, 0xc0, // xor r8d, r8d
    0x0f, 0x05, // syscall
    0x48, 0x85, 0xc0, // test rax, rax
    0x74, 0x0e, // jz child
    0xb8, 0x18, 0, 0, 0, // mov eax, 24 (sched_yield)
    0x0f, 0x05, // syscall
    0xb8, 0x3c, 0, 0, 0, // mov eax, 60 (exit)
    0xeb, 0x05, // jmp common
    0xb8, 0x3c, 0, 0, 0, // child: mov eax, 60 (exit)
    0x31, 0xff, // common: xor edi, edi
    0x0f, 0x05, // syscall
  ];
  const leaOffset = 10;
  _setInt32(code, leaOffset + 3, 0x2000 - (leaOffset + 7));
  return code;
}

void _setInt32(List<int> bytes, int offset, int value) {
  final encoded = ByteData(4)..setInt32(0, value, Endian.little);
  bytes.setRange(offset, offset + 4, encoded.buffer.asUint8List());
}

File _writeElf(
  Directory directory,
  String name,
  List<int> code, {
  int? memorySize,
}) {
  const headerSize = 64;
  const programHeaderSize = 56;
  const imageBase = 0x400000;
  const codeOffset = headerSize + programHeaderSize;
  final bytes = ByteData(codeOffset + code.length);

  bytes.setUint8(0, 0x7f);
  bytes.setUint8(1, 0x45);
  bytes.setUint8(2, 0x4c);
  bytes.setUint8(3, 0x46);
  bytes.setUint8(4, 2);
  bytes.setUint8(5, 1);
  bytes.setUint8(6, 1);
  bytes.setUint16(16, 2, Endian.little);
  bytes.setUint16(18, 62, Endian.little);
  bytes.setUint32(20, 1, Endian.little);
  bytes.setUint64(24, imageBase + codeOffset, Endian.little);
  bytes.setUint64(32, headerSize, Endian.little);
  bytes.setUint16(52, headerSize, Endian.little);
  bytes.setUint16(54, programHeaderSize, Endian.little);
  bytes.setUint16(56, 1, Endian.little);

  bytes.setUint32(headerSize, 1, Endian.little);
  bytes.setUint32(headerSize + 4, 7, Endian.little);
  bytes.setUint64(headerSize + 16, imageBase, Endian.little);
  bytes.setUint64(headerSize + 24, imageBase, Endian.little);
  bytes.setUint64(headerSize + 32, bytes.lengthInBytes, Endian.little);
  bytes.setUint64(
    headerSize + 40,
    memorySize ?? bytes.lengthInBytes,
    Endian.little,
  );
  bytes.setUint64(headerSize + 48, 0x1000, Endian.little);
  bytes.buffer.asUint8List().setRange(codeOffset, bytes.lengthInBytes, code);

  return File('${directory.path}/$name')
    ..writeAsBytesSync(bytes.buffer.asUint8List());
}
