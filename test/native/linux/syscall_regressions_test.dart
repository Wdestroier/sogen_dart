@Tags(<String>['native', 'linux', 'unicorn'])
@Timeout(Duration(minutes: 2))
library;

import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:sogen/linux.dart';
import 'package:test/test.dart';

const _entryPoint = 0x400078;

void main() {
  late Directory temporary;

  setUp(() {
    temporary = Directory.systemTemp.createTempSync('sogen-linux-syscalls-');
  });

  tearDown(() {
    temporary.deleteSync(recursive: true);
  });

  test('returns the guest cwd and reads through a guest path mapping', () {
    final cwd = _cwdProgram();
    final cwdExecutable = _writeElf(temporary, 'cwd.elf', cwd.bytes);
    final cwdOutput = StringBuffer();
    final cwdApp = createApplication(
      cwdExecutable.path,
      workingDirectory: '/tmp',
    );
    cwdApp.callbacks.onStdout = cwdOutput.write;
    try {
      cwdApp.start();
      expect(cwdOutput.toString(), '/tmp');
      expect(cwdApp.process.exitStatus, 0);
    } finally {
      cwdApp.dispose();
    }

    final hostWork = Directory('${temporary.path}/host-work')..createSync();
    File('${hostWork.path}/mapped.txt').writeAsStringSync('mapped\n');
    final read = _readProgram('/work/mapped.txt');
    final readExecutable = _writeElf(temporary, 'read.elf', read.bytes);
    final readOutput = StringBuffer();
    final readApp = createApplication(
      readExecutable.path,
      pathMappings: <String, String>{'/work': hostWork.path},
    );
    readApp.callbacks.onStdout = readOutput.write;
    try {
      readApp.start();
      expect(readOutput.toString(), 'mapped\n');
      expect(readApp.process.exitStatus, 0);
    } finally {
      readApp.dispose();
    }
  });

  test('keeps absolute symlink targets inside the emulation root', () {
    final sandbox = Directory('${temporary.path}/sandbox');
    Directory('${sandbox.path}/tmp').createSync(recursive: true);
    final contained = File('${sandbox.path}/outside/escape.txt');
    contained.parent.createSync(recursive: true);
    contained.writeAsStringSync('contained\n');
    final external = File('${temporary.path}/external.txt')
      ..writeAsStringSync('escaped\n');
    final program = _symlinkProgram();
    _writeElf(temporary, 'symlink.elf', program.bytes);
    final output = StringBuffer();
    final app = createApplication(
      '/guest-bin/symlink.elf',
      emulationRoot: sandbox.path,
      pathMappings: <String, String>{'/guest-bin': temporary.path},
      workingDirectory: '/tmp',
    );
    app.callbacks.onStdout = output.write;
    try {
      app.start();
      expect(output.toString(), 'contained\n');
      expect(app.process.exitStatus, 0);
      expect(external.readAsStringSync(), 'escaped\n');
    } finally {
      app.dispose();
    }
  });

  test('read-only existing files are readable and never truncated', () {
    final readOnly = Directory('${temporary.path}/readonly')..createSync();
    final locked = File('${readOnly.path}/locked.txt')
      ..writeAsStringSync('locked');
    final program = _readOnlyProgram();
    final executable = _writeElf(temporary, 'readonly.elf', program.bytes);
    final app = createApplication(
      executable.path,
      readOnlyPathMappings: <String, String>{'/ro': readOnly.path},
    );
    try {
      app.start();
      expect(app.process.exitStatus, 0);
      expect(
        app.readMemory(program.addresses['buffer']!, 6),
        'locked'.codeUnits,
      );
      expect(locked.readAsStringSync(), 'locked');
    } finally {
      app.dispose();
    }
  });

  test('mprotect on unmapped memory returns ENOMEM', () {
    final program = _mprotectProgram();
    final executable = _writeElf(temporary, 'mprotect.elf', program.bytes);
    final app = createApplication(executable.path);
    try {
      app.start();
      expect(app.process.exitStatus, 0);
      expect(app.lastStopReason, 'normal_exit');
    } finally {
      app.dispose();
    }
  });

  test('deserialize in a callback preserves a write-only descriptor mode', () {
    final stateDirectory = Directory('${temporary.path}/state')..createSync();
    final stateFile = File('${stateDirectory.path}/writeonly.txt')
      ..writeAsStringSync('initial');
    final program = _writeOnlyProgram();
    final executable = _writeElf(temporary, 'writeonly.elf', program.bytes);
    final app = createApplication(
      executable.path,
      pathMappings: <String, String>{'/state': stateDirectory.path},
    );
    var restored = false;
    app.callbacks.onSyscall = (_, name) {
      if (name == 'getpid' && !restored) {
        restored = true;
        final state = app.serializeState();
        app.deserializeState(state);
      }
      return HookContinuation.run;
    };
    try {
      app.start();
      expect(restored, isTrue);
      expect(app.process.exitStatus, 0);
      expect(stateFile.readAsStringSync(), 'updated');
    } finally {
      app.dispose();
    }
  });

  test('records an ELF module mapped at runtime and invokes module load', () {
    final mapped = _writeElf(temporary, 'runtime.so', const <int>[0xc3]);
    final program = _mmapProgram('/fixtures/runtime.so');
    _writeElf(temporary, 'mmap-main.elf', program.bytes);
    final app = createApplication(
      '/fixtures/mmap-main.elf',
      pathMappings: <String, String>{'/fixtures': temporary.path},
    );
    final initialNames = app.modules.map((module) => module.name).toSet();
    final loaded = <String>[];
    app.callbacks.onModuleLoad = (module) => loaded.add(module.name);
    try {
      expect(initialNames, contains('mmap-main.elf'));
      app.start();
      final runtimeNames = app.modules
          .map((module) => module.name)
          .where((name) => !initialNames.contains(name));
      expect(runtimeNames, contains(mapped.uri.pathSegments.last));
      expect(loaded, contains('runtime.so'));
      expect(app.process.exitStatus, 0);
    } finally {
      app.dispose();
    }
  });

  for (final alias in const ['signal', 'exception']) {
    test('fatal SIGTERM is delivered through on$alias', () {
      final program = _fatalSignalProgram();
      final executable = _writeElf(
        temporary,
        'sigterm-$alias.elf',
        program.bytes,
      );
      final app = createApplication(executable.path);
      final events = <(int, int, int)>[];
      if (alias == 'signal') {
        app.callbacks.onSignal = (signal, address, code) {
          events.add((signal, address, code));
        };
      } else {
        app.callbacks.onException = (signal, address, code) {
          events.add((signal, address, code));
        };
      }
      try {
        app.start();
        expect(events, isNotEmpty);
        expect(events.first.$1, 15);
        expect(app.lastStopReason, 'signal_termination');
        expect(app.process.exitStatus, 143);
      } finally {
        app.dispose();
      }
    });
  }

  test('handled SIGUSR1 survives kill and tgkill', () {
    final program = _handledSignalProgram(signal: 10, twice: true);
    final executable = _writeElf(temporary, 'sigusr1.elf', program.bytes);
    final app = createApplication(executable.path);
    final events = <(int, int, int)>[];
    app.callbacks.onSignal = (signal, address, code) {
      events.add((signal, address, code));
    };
    try {
      app.start();
      expect(events.where((event) => event.$1 == 10), hasLength(2));
      expect(app.lastStopReason, 'normal_exit');
      expect(app.process.exitStatus, 0);
    } finally {
      app.dispose();
    }
  });

  test('handled INT3 reports SIGTRAP and continues', () {
    final program = _handledSignalProgram(signal: 5, interrupt: true);
    final executable = _writeElf(temporary, 'int3.elf', program.bytes);
    final app = createApplication(executable.path);
    final events = <(int, int, int)>[];
    app.callbacks.onSignal = (signal, address, code) {
      events.add((signal, address, code));
    };
    try {
      app.start();
      expect(events, isNotEmpty);
      expect(events.first.$1, 5);
      expect(events.first.$3, 1);
      expect(app.lastStopReason, 'normal_exit');
      expect(app.process.exitStatus, 0);
    } finally {
      app.dispose();
    }
  });

  test('reports exact SIGSEGV address and code', () {
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

  test(
    'proxies a live socket and rejects snapshots while it is open',
    () async {
      final receive = ReceivePort();
      final isolate = await Isolate.spawn(_socketServer, receive.sendPort);
      final messages = StreamIterator<dynamic>(receive);
      await messages.moveNext();
      final hostPort = messages.current as int;
      final program = _socketProgram();
      final executable = _writeElf(temporary, 'socket.elf', program.bytes);
      final app = createApplication(
        executable.path,
        portMappings: <int, int>{40000: hostPort},
      );
      final syscalls = <String>[];
      String? snapshotError;
      var received = false;
      app.callbacks.onSyscall = (_, name) {
        syscalls.add(name);
        if (name == 'recvmsg') received = true;
        if (name == 'close' && received && snapshotError == null) {
          try {
            app.serializeState();
          } on SogenException catch (error) {
            snapshotError = error.message;
          }
        }
        return HookContinuation.run;
      };
      try {
        expect(app.getHostPort(40000), hostPort);
        expect(app.getEmulatorPort(hostPort), 40000);
        app.start();
        await messages.moveNext();
        expect(messages.current, <int>[
          ...'dup payload'.codeUnits,
          ...'sendmsg payload'.codeUnits,
        ]);
        expect(app.process.exitStatus, 0);
        expect(
          syscalls,
          containsAll(['connect', 'getpeername', 'dup', 'sendmsg', 'recvmsg']),
        );
        expect(snapshotError, isNotNull);
        expect(snapshotError!.toLowerCase(), contains('socket'));
        final peer = app.readMemory(program.addresses['peer']!, 16);
        expect(peer.sublist(0, 2), [2, 0]);
        expect(peer.sublist(2, 4), [0x9c, 0x40]);
        expect(peer.sublist(4, 8), [127, 0, 0, 1]);
        expect(
          app.readMemory(program.addresses['receiveBuffer']!, 16),
          'recvmsg response'.codeUnits,
        );
      } finally {
        app.dispose();
        await messages.cancel();
        receive.close();
        isolate.kill(priority: Isolate.immediate);
      }
    },
  );
}

Future<void> _socketServer(SendPort output) async {
  final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  output.send(server.port);
  final socket = await server.first;
  final payload = <int>[];
  await for (final chunk in socket) {
    payload.addAll(chunk);
    if (payload.length >= 26) break;
  }
  socket.add('recvmsg response'.codeUnits);
  await socket.flush();
  output.send(payload);
  await socket.close();
  await server.close();
}

_Program _cwdProgram() {
  final builder = _Builder()
    ..emit([0xb8, 79, 0, 0, 0])
    ..absolute([0x48, 0xbf], 'buffer')
    ..emit([0xbe, 0x00, 0x10, 0, 0, 0x0f, 0x05, 0x89, 0xc2, 0xff, 0xca])
    ..emit([0xb8, 1, 0, 0, 0, 0xbf, 1, 0, 0, 0])
    ..absolute([0x48, 0xbe], 'buffer')
    ..emit([0x0f, 0x05]);
  _exit(builder, 0);
  builder.data('buffer', List<int>.filled(4096, 0));
  return builder.build();
}

_Program _readProgram(String path) {
  final builder = _Builder()
    ..emit([0xb8, 1, 1, 0, 0, 0xbf, 0x9c, 0xff, 0xff, 0xff])
    ..absolute([0x48, 0xbe], 'path')
    ..emit([0x31, 0xd2, 0x45, 0x31, 0xd2, 0x0f, 0x05, 0x89, 0xc7])
    ..emit([0x31, 0xc0])
    ..absolute([0x48, 0xbe], 'buffer')
    ..emit([0xba, 32, 0, 0, 0, 0x0f, 0x05, 0x89, 0xc2])
    ..emit([0xb8, 1, 0, 0, 0, 0xbf, 1, 0, 0, 0])
    ..absolute([0x48, 0xbe], 'buffer')
    ..emit([0x0f, 0x05]);
  _exit(builder, 0);
  builder.data('path', [...path.codeUnits, 0]);
  builder.data('buffer', List<int>.filled(32, 0));
  return builder.build();
}

_Program _symlinkProgram() {
  final builder = _Builder()
    ..emit([0xb8, 88, 0, 0, 0])
    ..absolute([0x48, 0xbf], 'target')
    ..absolute([0x48, 0xbe], 'link')
    ..emit([0x0f, 0x05])
    ..emit([0xb8, 1, 1, 0, 0, 0xbf, 0x9c, 0xff, 0xff, 0xff])
    ..absolute([0x48, 0xbe], 'link')
    ..emit([0x31, 0xd2, 0x45, 0x31, 0xd2, 0x0f, 0x05, 0x89, 0xc7])
    ..emit([0x31, 0xc0])
    ..absolute([0x48, 0xbe], 'buffer')
    ..emit([0xba, 32, 0, 0, 0, 0x0f, 0x05, 0x89, 0xc2])
    ..emit([0xb8, 1, 0, 0, 0, 0xbf, 1, 0, 0, 0])
    ..absolute([0x48, 0xbe], 'buffer')
    ..emit([0x0f, 0x05]);
  _exit(builder, 0);
  builder.data('target', [...'/outside/escape.txt'.codeUnits, 0]);
  builder.data('link', [...'/tmp/link'.codeUnits, 0]);
  builder.data('buffer', List<int>.filled(32, 0));
  return builder.build();
}

_Program _readOnlyProgram() {
  final builder = _Builder()
    ..emit([0xb8, 1, 1, 0, 0, 0xbf, 0x9c, 0xff, 0xff, 0xff])
    ..absolute([0x48, 0xbe], 'path')
    ..emit([0x31, 0xd2, 0x45, 0x31, 0xd2, 0x0f, 0x05, 0x89, 0xc7])
    ..emit([0x31, 0xc0])
    ..absolute([0x48, 0xbe], 'buffer')
    ..emit([0xba, 6, 0, 0, 0, 0x0f, 0x05])
    ..emit([0xb8, 1, 1, 0, 0, 0xbf, 0x9c, 0xff, 0xff, 0xff])
    ..absolute([0x48, 0xbe], 'path')
    ..emit([0xba, 1, 2, 0, 0, 0x45, 0x31, 0xd2, 0x0f, 0x05])
    ..emit([0x48, 0x85, 0xc0])
    ..relative([0x0f, 0x88], 'success');
  _exit(builder, 3);
  builder.label('success');
  _exit(builder, 0);
  builder.data('path', [...'/ro/locked.txt'.codeUnits, 0]);
  builder.data('buffer', List<int>.filled(16, 0));
  return builder.build();
}

_Program _mprotectProgram() {
  final builder = _Builder()
    ..emit([0xb8, 10, 0, 0, 0])
    ..emit([0x48, 0xbf, 0x00, 0x00, 0x00, 0x00, 0x00, 0x70, 0x00, 0x00])
    ..emit([0xbe, 0x00, 0x10, 0, 0, 0xba, 1, 0, 0, 0, 0x0f, 0x05])
    ..emit([0x48, 0x83, 0xf8, 0xf4])
    ..relative([0x0f, 0x84], 'success');
  _exit(builder, 2);
  builder.label('success');
  _exit(builder, 0);
  return builder.build();
}

_Program _writeOnlyProgram() {
  final builder = _Builder()
    ..emit([0xb8, 1, 1, 0, 0, 0xbf, 0x9c, 0xff, 0xff, 0xff])
    ..absolute([0x48, 0xbe], 'path')
    ..emit([0xba, 1, 0, 0, 0, 0x45, 0x31, 0xd2, 0x0f, 0x05])
    ..emit([0x41, 0x89, 0xc4])
    ..emit([0xb8, 1, 0, 0, 0, 0x44, 0x89, 0xe7])
    ..absolute([0x48, 0xbe], 'updated')
    ..emit([0xba, 7, 0, 0, 0, 0x0f, 0x05])
    ..emit([0xb8, 39, 0, 0, 0, 0x0f, 0x05])
    ..emit([0x31, 0xc0, 0x44, 0x89, 0xe7])
    ..absolute([0x48, 0xbe], 'buffer')
    ..emit([0xba, 1, 0, 0, 0, 0x0f, 0x05, 0x48, 0x85, 0xc0])
    ..relative([0x0f, 0x88], 'success');
  _exit(builder, 3);
  builder.label('success');
  _exit(builder, 0);
  builder.data('path', [...'/state/writeonly.txt'.codeUnits, 0]);
  builder.data('updated', 'updated'.codeUnits);
  builder.data('buffer', [0]);
  return builder.build();
}

_Program _mmapProgram(String path) {
  final builder = _Builder()
    ..emit([0xb8, 1, 1, 0, 0, 0xbf, 0x9c, 0xff, 0xff, 0xff])
    ..absolute([0x48, 0xbe], 'path')
    ..emit([0x31, 0xd2, 0x45, 0x31, 0xd2, 0x0f, 0x05, 0x49, 0x89, 0xc0])
    ..emit([0xb8, 9, 0, 0, 0, 0x31, 0xff])
    ..emit([0xbe, 0x00, 0x10, 0, 0, 0xba, 5, 0, 0, 0])
    ..emit([0x41, 0xba, 2, 0, 0, 0, 0x45, 0x31, 0xc9, 0x0f, 0x05]);
  _exit(builder, 0);
  builder.data('path', [...path.codeUnits, 0]);
  return builder.build();
}

_Program _fatalSignalProgram() {
  final builder = _Builder()
    ..emit([0xb8, 39, 0, 0, 0, 0x0f, 0x05, 0x89, 0xc7])
    ..emit([0xbe, 15, 0, 0, 0, 0xb8, 62, 0, 0, 0, 0x0f, 0x05]);
  _exit(builder, 1);
  return builder.build();
}

_Program _handledSignalProgram({
  required int signal,
  bool twice = false,
  bool interrupt = false,
}) {
  final builder = _Builder()
    ..emit([0xb8, 13, 0, 0, 0, 0xbf, signal, 0, 0, 0])
    ..absolute([0x48, 0xbe], 'action')
    ..emit([0x31, 0xd2, 0x41, 0xba, 8, 0, 0, 0, 0x0f, 0x05]);
  if (interrupt) {
    builder.emit([0xcc]);
  } else {
    builder
      ..emit([0xb8, 39, 0, 0, 0, 0x0f, 0x05, 0x41, 0x89, 0xc4])
      ..emit([0x44, 0x89, 0xe7, 0xbe, signal, 0, 0, 0])
      ..emit([0xb8, 62, 0, 0, 0, 0x0f, 0x05]);
    if (twice) {
      builder
        ..emit([0xb8, 186, 0, 0, 0, 0x0f, 0x05, 0x89, 0xc6])
        ..emit([0x44, 0x89, 0xe7, 0xba, signal, 0, 0, 0])
        ..emit([0xb8, 234, 0, 0, 0, 0x0f, 0x05]);
    }
  }
  builder
    ..absolute([0x48, 0xbb], 'counter')
    ..emit([0x48, 0x83, 0x3b, twice ? 2 : 1])
    ..relative([0x0f, 0x84], 'success');
  _exit(builder, 6);
  builder.label('success');
  _exit(builder, 0);
  builder.label('handler');
  builder
    ..absolute([0x48, 0xbb], 'counter')
    ..emit([0x48, 0xff, 0x03, 0xc3]);
  builder.label('restorer');
  builder.emit([0xb8, 15, 0, 0, 0, 0x0f, 0x05]);
  builder.align(8);
  builder.label('action');
  builder.pointer('handler');
  builder.emit([0x00, 0x00, 0x00, 0x04, 0, 0, 0, 0]);
  builder.pointer('restorer');
  builder.emit(List<int>.filled(8, 0));
  builder.label('counter');
  builder.emit(List<int>.filled(8, 0));
  return builder.build();
}

_Program _socketProgram() {
  final builder = _Builder()
    ..emit([0xb8, 41, 0, 0, 0, 0xbf, 2, 0, 0, 0, 0xbe, 1, 0, 0, 0])
    ..emit([0x31, 0xd2, 0x0f, 0x05, 0x41, 0x89, 0xc4])
    ..emit([0xb8, 42, 0, 0, 0, 0x44, 0x89, 0xe7])
    ..absolute([0x48, 0xbe], 'sockaddr')
    ..emit([0xba, 16, 0, 0, 0, 0x0f, 0x05])
    ..emit([0xb8, 52, 0, 0, 0, 0x44, 0x89, 0xe7])
    ..absolute([0x48, 0xbe], 'peer')
    ..absolute([0x48, 0xba], 'peerLength')
    ..emit([0x0f, 0x05])
    ..emit([0xb8, 32, 0, 0, 0, 0x44, 0x89, 0xe7, 0x0f, 0x05, 0x41, 0x89, 0xc5])
    ..emit([0xb8, 44, 0, 0, 0, 0x44, 0x89, 0xef])
    ..absolute([0x48, 0xbe], 'dupPayload')
    ..emit([
      0xba,
      11,
      0,
      0,
      0,
      0x45,
      0x31,
      0xd2,
      0x45,
      0x31,
      0xc0,
      0x45,
      0x31,
      0xc9,
      0x0f,
      0x05,
    ])
    ..emit([0xb8, 46, 0, 0, 0, 0x44, 0x89, 0xe7])
    ..absolute([0x48, 0xbe], 'sendMessage')
    ..emit([0x31, 0xd2, 0x0f, 0x05])
    ..emit([0xb8, 47, 0, 0, 0, 0x44, 0x89, 0xe7])
    ..absolute([0x48, 0xbe], 'receiveMessage')
    ..emit([0x31, 0xd2, 0x0f, 0x05])
    ..emit([0xb8, 3, 0, 0, 0, 0x44, 0x89, 0xef, 0x0f, 0x05])
    ..emit([0xb8, 3, 0, 0, 0, 0x44, 0x89, 0xe7, 0x0f, 0x05]);
  _exit(builder, 0);
  builder.align(8);
  builder.data('sockaddr', [
    2,
    0,
    0x9c,
    0x40,
    127,
    0,
    0,
    1,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
  ]);
  builder.data('peer', List<int>.filled(16, 0));
  builder.data('peerLength', [16, 0, 0, 0]);
  builder.data('dupPayload', 'dup payload'.codeUnits);
  builder.data('sendPayload', 'sendmsg payload'.codeUnits);
  builder.data('receiveBuffer', List<int>.filled(64, 0));
  builder.align(8);
  builder.label('sendIov');
  builder.pointer('sendPayload');
  builder.uint64(15);
  builder.label('receiveIov');
  builder.pointer('receiveBuffer');
  builder.uint64(64);
  builder.label('sendMessage');
  builder.emit(List<int>.filled(16, 0));
  builder.pointer('sendIov');
  builder.uint64(1);
  builder.emit(List<int>.filled(24, 0));
  builder.label('receiveMessage');
  builder.emit(List<int>.filled(16, 0));
  builder.pointer('receiveIov');
  builder.uint64(1);
  builder.emit(List<int>.filled(24, 0));
  return builder.build();
}

void _exit(_Builder builder, int status) {
  builder.emit([0xbf, status, 0, 0, 0, 0xb8, 60, 0, 0, 0, 0x0f, 0x05]);
}

File _writeElf(Directory directory, String name, List<int> image) {
  const headerSize = 64;
  const programHeaderSize = 56;
  const imageBase = 0x400000;
  const codeOffset = headerSize + programHeaderSize;
  final bytes = ByteData(codeOffset + image.length);
  final raw = bytes.buffer.asUint8List();
  raw.setAll(0, const [0x7f, 0x45, 0x4c, 0x46, 2, 1, 1]);
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
  bytes.setUint64(headerSize + 40, bytes.lengthInBytes + 0x2000, Endian.little);
  bytes.setUint64(headerSize + 48, 0x1000, Endian.little);
  raw.setRange(codeOffset, raw.length, image);
  return File('${directory.path}/$name')..writeAsBytesSync(raw);
}

final class _Program {
  const _Program(this.bytes, this.addresses);

  final List<int> bytes;
  final Map<String, int> addresses;
}

final class _Patch {
  const _Patch(this.offset, this.label, this.relative);

  final int offset;
  final String label;
  final bool relative;
}

final class _Builder {
  final List<int> _bytes = [];
  final Map<String, int> _labels = {};
  final List<_Patch> _patches = [];

  void emit(List<int> bytes) => _bytes.addAll(bytes);

  void label(String name) => _labels[name] = _bytes.length;

  void data(String name, List<int> bytes) {
    label(name);
    emit(bytes);
  }

  void align(int alignment) {
    while (_bytes.length % alignment != 0) {
      _bytes.add(0);
    }
  }

  void absolute(List<int> opcode, String target) {
    emit(opcode);
    pointer(target);
  }

  void pointer(String target) {
    _patches.add(_Patch(_bytes.length, target, false));
    emit(List<int>.filled(8, 0));
  }

  void relative(List<int> opcode, String target) {
    emit(opcode);
    _patches.add(_Patch(_bytes.length, target, true));
    emit(List<int>.filled(4, 0));
  }

  void uint64(int value) {
    final data = ByteData(8)..setUint64(0, value, Endian.little);
    emit(data.buffer.asUint8List());
  }

  _Program build() {
    final result = Uint8List.fromList(_bytes);
    final data = ByteData.sublistView(result);
    for (final patch in _patches) {
      final target = _labels[patch.label];
      if (target == null) throw StateError('Unknown label ${patch.label}');
      if (patch.relative) {
        data.setInt32(patch.offset, target - (patch.offset + 4), Endian.little);
      } else {
        data.setUint64(patch.offset, _entryPoint + target, Endian.little);
      }
    }
    return _Program(result, <String, int>{
      for (final entry in _labels.entries) entry.key: _entryPoint + entry.value,
    });
  }
}
