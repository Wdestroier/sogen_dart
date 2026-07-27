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
      'sogen-dart-linux-models-',
    );
  });

  tearDown(() {
    temporaryDirectory.deleteSync(recursive: true);
  });

  test('collects copied mapped regions on an empty emulator', () {
    final app = createEmpty();
    final first = app.memory.allocateMemory(0x1000, .readWrite);
    final second = app.memory.allocateMemory(0x1000, .readExec);

    final regions = app.memory.getMappedRegions();
    expect(app.memory.mappedRegions, hasLength(regions.length));
    expect(regions.map((region) => region.start), containsAll([first, second]));
    expect(
      regions.map((region) => region.start).toList(),
      orderedEquals(regions.map((region) => region.start).toList()..sort()),
    );
    expect(() => regions.add(regions.first), throwsUnsupportedError);

    final retained = regions.firstWhere((region) => region.start == first);
    expect(app.memory.protectMemory(first, 0x1000, .read), isTrue);
    expect(retained.permissions, MemoryPermission.readWrite);
    expect(app.memory.getRegionInfo(first)!.permissions, MemoryPermission.read);

    expect(app.modules, isEmpty);
    expect(app.findModuleByAddress(first), isNull);
    expect(app.findModuleByName('missing.so'), isNull);
    expect(app.process.threads, isEmpty);
    expect(app.process.activeThread, isNull);
    expect(app.currentThread, isNull);

    app.dispose();
    expect(retained.start, first);
    expect(() => app.memory.mappedRegions, throwsStateError);
    expect(() => app.modules, throwsStateError);
  });

  test('exposes complete immutable ELF module models and exact lookup', () {
    final executable = _writeMetadataElf(temporaryDirectory, 'MixedCase.elf');
    final app = createApplication(executable.path);

    final modules = app.modules;
    expect(modules, hasLength(1));
    expect(() => modules.clear(), throwsUnsupportedError);

    final module = modules.single;
    expect(module.name, 'MixedCase.elf');
    expect(
      File(module.path).resolveSymbolicLinksSync(),
      executable.resolveSymbolicLinksSync(),
    );
    expect(module.imageBase, 0x400000);
    expect(module.sizeOfImage, 0x1000);
    expect(module.entryPoint, 0x400100);
    expect(module.rpath, r'$ORIGIN/legacy');
    expect(module.runpath, r'$ORIGIN/modern');
    expect(module.neededLibraries, ['libfixture.so']);
    expect(
      () => module.neededLibraries.add('other.so'),
      throwsUnsupportedError,
    );

    expect(module.exports, hasLength(1));
    expect(module.exports.single, isA<ExportedSymbol>());
    expect(module.exports.single.name, 'synthetic_export');
    expect(module.exports.single.rva, 0x400100);
    expect(module.exports.single.address, 0x400100);
    expect(() => module.exports.clear(), throwsUnsupportedError);

    final text = module.sections.singleWhere(
      (section) => section.name == '.text',
    );
    expect(text.start, 0x400100);
    expect(text.length, 12);
    expect(text.permissions, MemoryPermission.readExec);
    expect(() => module.sections.clear(), throwsUnsupportedError);

    expect(app.findModuleByAddress(module.imageBase), isNotNull);
    expect(app.findModuleByAddress(module.entryPoint)!.name, module.name);
    expect(
      app.findModuleByAddress(module.imageBase + module.sizeOfImage - 1),
      isNotNull,
    );
    expect(
      app.findModuleByAddress(module.imageBase + module.sizeOfImage),
      isNull,
    );
    expect(
      app.findModuleByName('MixedCase.elf')!.entryPoint,
      module.entryPoint,
    );
    expect(app.findModuleByName('mixedcase.elf'), isNull);
    expect(app.findModuleByName(''), isNull);

    app.dispose();
    expect(module.name, 'MixedCase.elf');
    expect(module.exports.single.name, 'synthetic_export');
    expect(
      module.sections.singleWhere((section) => section.name == '.text'),
      text,
    );
  });

  test('retains live thread wrappers and re-resolves them after restore', () {
    final executable = _writeMetadataElf(temporaryDirectory, 'threads.elf');
    final app = createApplication(executable.path);

    final current = app.currentThread;
    final active = app.process.activeThread;
    final threads = app.process.threads;
    expect(current, isNotNull);
    expect(active, isNotNull);
    expect(threads, hasLength(1));
    expect(current!.tid, app.currentThreadId);
    expect(active!.tid, current.tid);
    expect(threads.single.tid, current.tid);
    expect(threads.single.terminated, isFalse);
    expect(() => threads.clear(), throwsUnsupportedError);
    expect(current.stackBase, isNonZero);
    expect(current.stackSize, isNonZero);
    expect(current.fsBase, isNonNegative);
    expect(current.startAddress, 0x400100);
    expect(current.waitState, ThreadWaitState.running);
    expect(current.setupDone, isTrue);
    expect(current.exitCode, 0);
    expect(current.executedInstructions, 0);
    expect(app.activateThread(current.tid), isTrue);
    app.yieldThread();
    expect(
      () => current.previousIp,
      throwsA(
        isA<UnsupportedError>().having(
          (error) => error.message,
          'message',
          'Linux previousIp is not tracked by the pinned Sogen revision.',
        ),
      ),
    );

    app.writeRegister(.rip, 0x400101);
    expect(current.currentIp, 0x400101);
    expect(active.currentIp, 0x400101);
    expect(threads.single.currentIp, 0x400101);

    final state = app.serializeState();
    app.writeRegister(.rip, 0x400102);
    expect(current.currentIp, 0x400102);
    app.deserializeState(state);
    expect(current.currentIp, 0x400101);
    expect(current.tid, active.tid);

    app.saveSnapshot();
    app.writeRegister(.rip, 0x400103);
    app.restoreSnapshot();
    expect(current.currentIp, 0x400101);

    final originalMmapBase = app.memory.mmapBase;
    final moduleNames = app.modules.map((module) => module.name).toList();
    final moduleCount = app.modules.length;
    final inventoryState = app.serializeState();
    app.memory.mmapBase = originalMmapBase + 0x100000;
    app.deserializeState(inventoryState);
    expect(app.memory.mmapBase, originalMmapBase);
    expect(app.modules, hasLength(moduleCount));
    expect(app.modules.map((module) => module.name), moduleNames);

    app.writeRegister(.rip, 0x400100);
    final preSingleStepCount = app.executedInstructions;
    app.start(1);
    expect(app.readRegister(.rip), 0x400105);
    expect(app.executedInstructions, preSingleStepCount + 1);
    expect(app.process.exitStatus, isNull);

    app.start();
    expect(app.process.exitStatus, 0);
    expect(app.lastStopReason, 'normal_exit');
    expect(app.currentThread, isNull);
    expect(app.currentThreadId, isNull);
    expect(app.process.threads, isEmpty);
    expect(app.process.activeThread, isNotNull);
    expect(app.process.activeThread!.terminated, isTrue);
    expect(current.terminated, isTrue);

    final terminatedState = app.serializeState();
    app.deserializeState(terminatedState);
    expect(current.terminated, isTrue);
    expect(current.tid, isNonZero);
    app.saveSnapshot();
    app.restoreSnapshot();
    expect(current.terminated, isTrue);

    app.dispose();
    expect(() => current.tid, throwsStateError);
    expect(() => active.currentIp, throwsStateError);
    expect(() => threads.single.terminated, throwsStateError);
    expect(() => app.process.threads, throwsStateError);
  });
}

File _writeMetadataElf(Directory directory, String name) {
  const imageBase = 0x400000;
  const codeOffset = 0x100;
  const stringOffset = 0x180;
  const symbolOffset = 0x1d0;
  const dynamicOffset = 0x210;
  const sectionNamesOffset = 0x270;
  const sectionHeadersOffset = 0x300;
  const fileSize = 0x500;
  const sectionCount = 6;
  const code = <int>[
    0xbf,
    0x00,
    0x00,
    0x00,
    0x00,
    0xb8,
    0x3c,
    0x00,
    0x00,
    0x00,
    0x0f,
    0x05,
  ];
  const strings = <int>[
    0,
    ...[
      115,
      121,
      110,
      116,
      104,
      101,
      116,
      105,
      99,
      95,
      101,
      120,
      112,
      111,
      114,
      116,
    ],
    0,
    ...[108, 105, 98, 102, 105, 120, 116, 117, 114, 101, 46, 115, 111],
    0,
    ...[36, 79, 82, 73, 71, 73, 78, 47, 108, 101, 103, 97, 99, 121],
    0,
    ...[36, 79, 82, 73, 71, 73, 78, 47, 109, 111, 100, 101, 114, 110],
    0,
  ];
  const sectionNames = <int>[
    0,
    46,
    116,
    101,
    120,
    116,
    0,
    46,
    100,
    121,
    110,
    115,
    116,
    114,
    0,
    46,
    100,
    121,
    110,
    115,
    121,
    109,
    0,
    46,
    100,
    121,
    110,
    97,
    109,
    105,
    99,
    0,
    46,
    115,
    104,
    115,
    116,
    114,
    116,
    97,
    98,
    0,
  ];
  final bytes = ByteData(fileSize);

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
  bytes.setUint64(32, 64, Endian.little);
  bytes.setUint64(40, sectionHeadersOffset, Endian.little);
  bytes.setUint16(52, 64, Endian.little);
  bytes.setUint16(54, 56, Endian.little);
  bytes.setUint16(56, 2, Endian.little);
  bytes.setUint16(58, 64, Endian.little);
  bytes.setUint16(60, sectionCount, Endian.little);
  bytes.setUint16(62, 5, Endian.little);

  _programHeader(
    bytes,
    64,
    type: 1,
    flags: 7,
    fileOffset: 0,
    virtualAddress: imageBase,
    fileSize: fileSize,
    memorySize: fileSize,
    alignment: 0x1000,
  );
  _programHeader(
    bytes,
    120,
    type: 2,
    flags: 6,
    fileOffset: dynamicOffset,
    virtualAddress: imageBase + dynamicOffset,
    fileSize: 80,
    memorySize: 80,
    alignment: 8,
  );

  bytes.buffer.asUint8List().setRange(
    codeOffset,
    codeOffset + code.length,
    code,
  );
  bytes.buffer.asUint8List().setRange(
    stringOffset,
    stringOffset + strings.length,
    strings,
  );
  bytes.buffer.asUint8List().setRange(
    sectionNamesOffset,
    sectionNamesOffset + sectionNames.length,
    sectionNames,
  );

  bytes.setUint32(symbolOffset + 24, 1, Endian.little);
  bytes.setUint8(symbolOffset + 28, 0x12);
  bytes.setUint16(symbolOffset + 30, 1, Endian.little);
  bytes.setUint64(symbolOffset + 32, imageBase + codeOffset, Endian.little);
  bytes.setUint64(symbolOffset + 40, code.length, Endian.little);

  _dynamicEntry(bytes, dynamicOffset, 5, imageBase + stringOffset);
  _dynamicEntry(bytes, dynamicOffset + 16, 1, 18);
  _dynamicEntry(bytes, dynamicOffset + 32, 15, 32);
  _dynamicEntry(bytes, dynamicOffset + 48, 29, 47);
  _dynamicEntry(bytes, dynamicOffset + 64, 0, 0);

  _sectionHeader(
    bytes,
    sectionHeadersOffset + 64,
    name: 1,
    type: 1,
    flags: 6,
    address: imageBase + codeOffset,
    fileOffset: codeOffset,
    size: code.length,
    alignment: 16,
  );
  _sectionHeader(
    bytes,
    sectionHeadersOffset + 128,
    name: 7,
    type: 3,
    flags: 2,
    address: imageBase + stringOffset,
    fileOffset: stringOffset,
    size: strings.length,
    alignment: 1,
  );
  _sectionHeader(
    bytes,
    sectionHeadersOffset + 192,
    name: 15,
    type: 11,
    flags: 2,
    address: imageBase + symbolOffset,
    fileOffset: symbolOffset,
    size: 48,
    link: 2,
    alignment: 8,
    entrySize: 24,
  );
  _sectionHeader(
    bytes,
    sectionHeadersOffset + 256,
    name: 23,
    type: 6,
    flags: 3,
    address: imageBase + dynamicOffset,
    fileOffset: dynamicOffset,
    size: 80,
    link: 2,
    alignment: 8,
    entrySize: 16,
  );
  _sectionHeader(
    bytes,
    sectionHeadersOffset + 320,
    name: 32,
    type: 3,
    flags: 0,
    address: 0,
    fileOffset: sectionNamesOffset,
    size: sectionNames.length,
    alignment: 1,
  );

  return File('${directory.path}/$name')
    ..writeAsBytesSync(bytes.buffer.asUint8List());
}

void _programHeader(
  ByteData bytes,
  int offset, {
  required int type,
  required int flags,
  required int fileOffset,
  required int virtualAddress,
  required int fileSize,
  required int memorySize,
  required int alignment,
}) {
  bytes.setUint32(offset, type, Endian.little);
  bytes.setUint32(offset + 4, flags, Endian.little);
  bytes.setUint64(offset + 8, fileOffset, Endian.little);
  bytes.setUint64(offset + 16, virtualAddress, Endian.little);
  bytes.setUint64(offset + 24, virtualAddress, Endian.little);
  bytes.setUint64(offset + 32, fileSize, Endian.little);
  bytes.setUint64(offset + 40, memorySize, Endian.little);
  bytes.setUint64(offset + 48, alignment, Endian.little);
}

void _dynamicEntry(ByteData bytes, int offset, int tag, int value) {
  bytes.setInt64(offset, tag, Endian.little);
  bytes.setUint64(offset + 8, value, Endian.little);
}

void _sectionHeader(
  ByteData bytes,
  int offset, {
  required int name,
  required int type,
  required int flags,
  required int address,
  required int fileOffset,
  required int size,
  required int alignment,
  int link = 0,
  int entrySize = 0,
}) {
  bytes.setUint32(offset, name, Endian.little);
  bytes.setUint32(offset + 4, type, Endian.little);
  bytes.setUint64(offset + 8, flags, Endian.little);
  bytes.setUint64(offset + 16, address, Endian.little);
  bytes.setUint64(offset + 24, fileOffset, Endian.little);
  bytes.setUint64(offset + 32, size, Endian.little);
  bytes.setUint32(offset + 40, link, Endian.little);
  bytes.setUint64(offset + 48, alignment, Endian.little);
  bytes.setUint64(offset + 56, entrySize, Endian.little);
}
