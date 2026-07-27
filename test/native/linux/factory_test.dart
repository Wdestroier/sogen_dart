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
      'sogen-dart-linux-factory-',
    );
  });

  tearDown(() {
    temporaryDirectory.deleteSync(recursive: true);
  });

  test('passes application arguments after argv zero', () {
    final executable = _writeElf(temporaryDirectory, 'argc.elf', <int>[
      0x48, 0x8b, 0x3c, 0x24, // mov rdi, [rsp]
      0xb8, 0x3c, 0x00, 0x00, 0x00, // mov eax, 60
      0x0f, 0x05, // syscall
    ]);

    final app = createApplication(
      executable.path,
      arguments: const ['alpha', '', 'space value'],
    );
    try {
      app.start();
      expect(app.process.exitStatus, 4);
    } finally {
      app.dispose();
    }
  });

  test('start(1) advances exactly one instruction before normal exit', () {
    final executable = _writeElf(temporaryDirectory, 'single-step.elf', <int>[
      0xbf, 0x00, 0x00, 0x00, 0x00, // mov edi, 0
      0xb8, 0x3c, 0x00, 0x00, 0x00, // mov eax, 60
      0x0f, 0x05, // syscall
    ]);
    final app = createApplication(executable.path);
    try {
      final initialRip = app.readRegister(.rip);
      final initialCount = app.executedInstructions;
      app.start(1);
      expect(app.readRegister(.rip), initialRip + 5);
      expect(app.executedInstructions, initialCount + 1);
      expect(app.process.exitStatus, isNull);
      expect(app.lastStopReason, 'instruction_limit');

      app.start();
      expect(app.process.exitStatus, 0);
      expect(app.lastStopReason, 'normal_exit');
    } finally {
      app.dispose();
    }
  });

  test('distinguishes default, empty, and explicit environments', () {
    final executable = _writeElf(temporaryDirectory, 'envc.elf', <int>[
      0x48, 0x8b, 0x0c, 0x24, // mov rcx, [rsp]
      0x48, 0x8d, 0x74, 0xcc, 0x10, // lea rsi, [rsp + rcx * 8 + 16]
      0x31, 0xff, // xor edi, edi
      0x48, 0x83, 0x3c, 0xfe, 0x00, // cmp qword [rsi + rdi * 8], 0
      0x74, 0x05, // je done
      0x48, 0xff, 0xc7, // inc rdi
      0xeb, 0xf4, // jmp loop
      0xb8, 0x3c, 0x00, 0x00, 0x00, // mov eax, 60
      0x0f, 0x05, // syscall
    ]);

    expect(_runAndReadExitStatus(executable.path), 3);
    expect(_runAndReadExitStatus(executable.path, environment: const {}), 0);
    expect(
      _runAndReadExitStatus(
        executable.path,
        environment: const {'FIRST': 'one', 'SECOND': 'two=2'},
      ),
      2,
    );
  });

  test('normalizes paths and applies writable mappings', () {
    final mapped = Directory('${temporaryDirectory.path}/writable')
      ..createSync();
    final executable = _writeOpenElf(mapped, 'app.elf');

    final app = createApplication(
      executable.path,
      workingDirectory: r'\work\.\nested\..',
      pathMappings: <String, String>{'/work/.': mapped.path},
      portMappings: const <int, int>{1234: 4321},
    );
    try {
      expect(app.getHostPort(1234), 4321);
      app.start();
      expect(app.process.exitStatus, isNot(13));
      expect(File('${mapped.path}/output.txt').existsSync(), isTrue);
    } finally {
      app.dispose();
    }
  });

  test('applies read-only mappings after writable mappings', () {
    final wrong = Directory('${temporaryDirectory.path}/wrong')..createSync();
    final mapped = Directory('${temporaryDirectory.path}/read-only')
      ..createSync();
    _writeOpenElf(mapped, 'app.elf');

    final app = createApplication(
      '/work/app.elf',
      workingDirectory: r'\work\.\nested\..',
      pathMappings: <String, String>{'/work': wrong.path},
      readOnlyPathMappings: <String, String>{r'\work\.': mapped.path},
    );
    try {
      app.start();
      expect(app.process.exitStatus, 13);
      expect(File('${mapped.path}/output.txt').existsSync(), isFalse);
    } finally {
      app.dispose();
    }
  });

  test('installs mappings and ports on empty factories', () {
    final app = createEmpty(
      pathMappings: <String, String>{'/writable': temporaryDirectory.path},
      readOnlyPathMappings: <String, String>{
        '/read-only': temporaryDirectory.path,
      },
      portMappings: const <int, int>{8080: 18080, 8443: 18443},
    );
    try {
      expect(app.getHostPort(8080), 18080);
      expect(app.getHostPort(8443), 18443);
      expect(app.getEmulatorPort(18443), 8443);
    } finally {
      app.dispose();
    }
  });

  test('rejects invalid initial ports before entering native code', () {
    expect(
      () => createEmpty(portMappings: const <int, int>{0: 80}),
      throwsRangeError,
    );
    expect(
      () => createEmpty(portMappings: const <int, int>{80: 65536}),
      throwsRangeError,
    );
  });
}

int? _runAndReadExitStatus(
  String executable, {
  Map<String, String>? environment,
}) {
  final app = createApplication(executable, environment: environment);
  try {
    app.start();
    return app.process.exitStatus;
  } finally {
    app.dispose();
  }
}

File _writeOpenElf(Directory directory, String name) =>
    _writeElf(directory, name, <int>[
      0xb8, 0x01, 0x01, 0x00, 0x00, // mov eax, 257 (openat)
      0xbf, 0x9c, 0xff, 0xff, 0xff, // mov edi, -100 (AT_FDCWD)
      0x48, 0x8d, 0x35, 0x1c, 0x00, 0x00, 0x00, // lea rsi, [rip + 28]
      0xba, 0x41, 0x02, 0x00, 0x00, // mov edx, O_WRONLY|O_CREAT|O_TRUNC
      0x41, 0xba, 0xb6, 0x01, 0x00, 0x00, // mov r10d, 0666
      0x0f, 0x05, // syscall
      0x85, 0xc0, // test eax, eax
      0x79, 0x02, // jns success
      0xf7, 0xd8, // neg eax
      0x89, 0xc7, // mov edi, eax
      0xb8, 0x3c, 0x00, 0x00, 0x00, // mov eax, 60
      0x0f, 0x05, // syscall
      ...'output.txt'.codeUnits,
      0,
    ]);

File _writeElf(Directory directory, String name, List<int> code) {
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
  bytes.setUint32(headerSize + 4, 5, Endian.little);
  bytes.setUint64(headerSize + 16, imageBase, Endian.little);
  bytes.setUint64(headerSize + 24, imageBase, Endian.little);
  bytes.setUint64(headerSize + 32, bytes.lengthInBytes, Endian.little);
  bytes.setUint64(headerSize + 40, bytes.lengthInBytes, Endian.little);
  bytes.setUint64(headerSize + 48, 0x1000, Endian.little);
  bytes.buffer.asUint8List().setRange(codeOffset, bytes.lengthInBytes, code);

  return File('${directory.path}/$name')
    ..writeAsBytesSync(bytes.buffer.asUint8List());
}
