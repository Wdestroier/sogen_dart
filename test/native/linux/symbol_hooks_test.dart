@Tags(<String>['native', 'linux', 'unicorn'])
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:sogen/ctypes.dart' as ctypes;
import 'package:sogen/linux.dart';
import 'package:test/test.dart';

void main() {
  late Directory temporary;
  late File fixture;

  setUp(() {
    temporary = Directory.systemTemp.createTempSync('sogen-symbol-hooks-');
    fixture = _writeSymbolElf(temporary, 'symbol-fixture.elf');
  });

  tearDown(() => temporary.deleteSync(recursive: true));

  test('matches bare symbols, decodes arguments, and observes original', () {
    final app = createApplication(fixture.path);
    final calls = <LinuxSymbolCall>[];
    final parameters = <List<dynamic>>[];
    final hook = symbolCall(
      params: <ctypes.CType<dynamic>>[ctypes.int32],
      restype: ctypes.int32,
      cb: (call, values) {
        calls.add(call);
        parameters.add(values);
        return ApiContinuation.runOriginal;
      },
    );
    app.hooks.symbols['target_function'] = hook;
    expect(app.hooks.symbols['target_function'], same(hook));
    app.start();
    expect(calls, hasLength(1));
    expect(calls.single.name, 'target_function');
    expect(calls.single.module.name, contains('symbol-fixture'));
    expect(calls.single.address, isNonZero);
    expect(calls.single.returnAddress, isNonZero);
    expect(parameters.single, <dynamic>[41]);
    expect(app.process.exitStatus, 1);
    app.dispose();
  });

  test('decodes exact narrow signed and unsigned symbol arguments', () {
    final app = createApplication(fixture.path);
    final parameters = <List<dynamic>>[];
    app.hooks.symbols['target_function'] = symbolCall(
      params: const <ctypes.CType<dynamic>>[ctypes.int32],
      restype: ctypes.int32,
      cb: (call, _) {
        call.returnValue = 42;
        return ApiContinuation.intercept;
      },
    );
    app.hooks.symbols['target_values'] = symbolCall(
      params: const <ctypes.CType<dynamic>>[
        ctypes.int8,
        ctypes.uint8,
        ctypes.int16,
        ctypes.uint16,
        ctypes.int32,
        ctypes.uint32,
      ],
      restype: ctypes.int32,
      cb: (_, values) {
        parameters.add(values);
        return ApiContinuation.runOriginal;
      },
    );

    try {
      app.start();
      expect(parameters, <List<dynamic>>[
        <dynamic>[-2, 250, -1234, 65000, -123456, 4000000000],
      ]);
      expect(app.process.exitStatus, 0);
    } finally {
      app.dispose();
    }
  });

  test('matches qualified stem and intercepts a mutable return value', () {
    final app = createApplication(fixture.path);
    var hits = 0;
    app.hooks.symbols['symbol-fixture!target_function'] = symbolCall(
      params: <ctypes.CType<dynamic>>[ctypes.int32],
      restype: ctypes.int32,
      cb: (call, values) {
        hits++;
        expect(values, <dynamic>[41]);
        call.returnValue = 42;
        return true;
      },
    );
    final state = app.serializeState();
    app.deserializeState(state);
    app.start();
    expect(hits, 1);
    expect(app.process.exitStatus, 0);
    app.dispose();
  });

  test('refreshes a snapshot-restored intercept exactly once', () {
    final app = createApplication(fixture.path);
    var hits = 0;
    final hook = symbolCall(
      params: <ctypes.CType<dynamic>>[ctypes.int32],
      restype: ctypes.int32,
      cb: (call, values) {
        hits++;
        call.returnValue = 42;
        return ApiContinuation.intercept;
      },
    );
    app.hooks.symbols['target_function'] = hook;

    try {
      app.saveSnapshot();
      app.restoreSnapshot();
      app.hooks.symbols.refresh();
      expect(app.hooks.symbols['target_function'], same(hook));
      app.start();
      expect(hits, 1);
      expect(app.process.exitStatus, 0);
    } finally {
      app.dispose();
    }
  });

  test('nullable assignment removes the hook and runs the original', () {
    final app = createApplication(fixture.path);
    var hits = 0;
    final hook = symbolCall(cb: (_, _) => hits++);
    app.hooks.symbols['target_function'] = hook;

    try {
      expect(app.hooks.symbols['target_function'], same(hook));
      app.hooks.symbols['target_function'] = null;
      expect(app.hooks.symbols['target_function'], isNull);
      app.start();
      expect(hits, 0);
      expect(app.process.exitStatus, 1);
    } finally {
      app.dispose();
    }
  });

  test('replaces, removes, clears, and surfaces callback failures', () {
    final app = createApplication(fixture.path);
    var oldHits = 0;
    var replacementHits = 0;
    app.hooks.symbols['target_function'] = symbolCall(
      cb: (_, _) {
        oldHits++;
      },
    );
    app.hooks.symbols['target_function'] = symbolCall(
      params: <ctypes.CType<dynamic>>[ctypes.int32],
      cb: (_, _) {
        replacementHits++;
        throw StateError('symbol callback failed');
      },
    );
    expect(
      app.start,
      throwsA(
        isA<SogenCallbackException>()
            .having((error) => error.hookKey, 'hookKey', 'target_function')
            .having((error) => error.error, 'error', isA<StateError>()),
      ),
    );
    expect(oldHits, 0);
    expect(replacementHits, 1);
    app.hooks.symbols.remove('target_function');
    expect(app.hooks.symbols['target_function'], isNull);
    app.hooks.symbols['target_function'] = symbolCall(cb: (_, _) {});
    app.hooks.symbols.clear();
    expect(app.hooks.symbols['target_function'], isNull);
    app.dispose();
  });

  test('safely replaces the current symbol callback', () {
    final app = createApplication(fixture.path);
    var firstHits = 0;
    var replacementHits = 0;
    final replacement = symbolCall(
      cb: (_, _) {
        replacementHits++;
      },
    );
    app.hooks.symbols['target_function'] = symbolCall(
      params: <ctypes.CType<dynamic>>[ctypes.int32],
      cb: (_, _) {
        firstHits++;
        app.hooks.symbols['target_function'] = replacement;
      },
    );
    app.start();
    expect(firstHits, 1);
    expect(replacementHits, lessThanOrEqualTo(1));
    expect(app.hooks.symbols['target_function'], same(replacement));
    app.dispose();
  });

  test('rejects unsupported descriptors before native registration', () {
    expect(
      () => symbolCall(
        params: <ctypes.CType<dynamic>>[_UnsupportedType()],
        cb: (_, _) {},
      ),
      throwsArgumentError,
    );
  });
}

final class _UnsupportedType implements ctypes.CType<double> {
  const _UnsupportedType();

  @override
  double decode(int rawValue) => rawValue.toDouble();
}

File _writeSymbolElf(Directory directory, String name) {
  const imageBase = 0x400000;
  const codeOffset = 0x100;
  const targetOffset = 0x180;
  const targetValuesOffset = 0x190;
  const stringsOffset = 0x1b0;
  const symbolsOffset = 0x200;
  const dynamicOffset = 0x250;
  const sectionNamesOffset = 0x2a0;
  const sectionHeadersOffset = 0x300;
  const fileSize = 0x500;
  const sectionCount = 6;
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
  final code = <int>[
    0xbf,
    0x29,
    0x00,
    0x00,
    0x00,
    0xe8,
    0x76,
    0x00,
    0x00,
    0x00,
    0x83,
    0xf8,
    0x2a,
    0x75,
    0x2f,
    0xbf,
    0xfe,
    0xff,
    0xff,
    0xff,
    0xbe,
    0xfa,
    0x00,
    0x00,
    0x00,
    0xba,
    0x2e,
    0xfb,
    0xff,
    0xff,
    0xb9,
    0xe8,
    0xfd,
    0x00,
    0x00,
    0x41,
    0xb8,
    0xc0,
    0x1d,
    0xfe,
    0xff,
    0x41,
    0xb9,
    0x00,
    0x28,
    0x6b,
    0xee,
    0xe8,
    0x5c,
    0x00,
    0x00,
    0x00,
    0x85,
    0xc0,
    0x0f,
    0x94,
    0xc0,
    0x0f,
    0xb6,
    0xf8,
    0xeb,
    0x05,
    0xbf,
    0x01,
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
    ...List<int>.filled(targetOffset - codeOffset - 74, 0x90),
    0x8d,
    0x47,
    0x02,
    0xc3,
    ...List<int>.filled(targetValuesOffset - targetOffset - 4, 0x90),
    0xb8,
    0x01,
    0x00,
    0x00,
    0x00,
    0xc3,
  ];
  const strings = <int>[
    0,
    116,
    97,
    114,
    103,
    101,
    116,
    95,
    102,
    117,
    110,
    99,
    116,
    105,
    111,
    110,
    0,
    116,
    97,
    114,
    103,
    101,
    116,
    95,
    118,
    97,
    108,
    117,
    101,
    115,
    0,
  ];
  final bytes = ByteData(fileSize);
  final raw = bytes.buffer.asUint8List();
  raw.setAll(0, <int>[0x7f, 0x45, 0x4c, 0x46, 2, 1, 1]);
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
    address: imageBase,
    size: fileSize,
    alignment: 0x1000,
  );
  _programHeader(
    bytes,
    120,
    type: 2,
    flags: 6,
    fileOffset: dynamicOffset,
    address: imageBase + dynamicOffset,
    size: 64,
    alignment: 8,
  );
  raw.setRange(codeOffset, codeOffset + code.length, code);
  raw.setRange(stringsOffset, stringsOffset + strings.length, strings);
  raw.setRange(
    sectionNamesOffset,
    sectionNamesOffset + sectionNames.length,
    sectionNames,
  );
  bytes.setUint32(symbolsOffset + 24, 1, Endian.little);
  bytes.setUint8(symbolsOffset + 28, 0x12);
  bytes.setUint16(symbolsOffset + 30, 1, Endian.little);
  bytes.setUint64(symbolsOffset + 32, imageBase + targetOffset, Endian.little);
  bytes.setUint64(symbolsOffset + 40, 4, Endian.little);
  bytes.setUint32(symbolsOffset + 48, 17, Endian.little);
  bytes.setUint8(symbolsOffset + 52, 0x12);
  bytes.setUint16(symbolsOffset + 54, 1, Endian.little);
  bytes.setUint64(
    symbolsOffset + 56,
    imageBase + targetValuesOffset,
    Endian.little,
  );
  bytes.setUint64(symbolsOffset + 64, 6, Endian.little);
  _dynamic(bytes, dynamicOffset, 5, imageBase + stringsOffset);
  _dynamic(bytes, dynamicOffset + 16, 6, imageBase + symbolsOffset);
  _dynamic(bytes, dynamicOffset + 32, 11, 24);
  _dynamic(bytes, dynamicOffset + 48, 0, 0);
  _section(
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
  _section(
    bytes,
    sectionHeadersOffset + 128,
    name: 7,
    type: 3,
    flags: 2,
    address: imageBase + stringsOffset,
    fileOffset: stringsOffset,
    size: strings.length,
    alignment: 1,
  );
  _section(
    bytes,
    sectionHeadersOffset + 192,
    name: 15,
    type: 11,
    flags: 2,
    address: imageBase + symbolsOffset,
    fileOffset: symbolsOffset,
    size: 72,
    link: 2,
    alignment: 8,
    entrySize: 24,
  );
  _section(
    bytes,
    sectionHeadersOffset + 256,
    name: 23,
    type: 6,
    flags: 3,
    address: imageBase + dynamicOffset,
    fileOffset: dynamicOffset,
    size: 64,
    link: 2,
    alignment: 8,
    entrySize: 16,
  );
  _section(
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
  return File('${directory.path}/$name')..writeAsBytesSync(raw);
}

void _programHeader(
  ByteData data,
  int offset, {
  required int type,
  required int flags,
  required int fileOffset,
  required int address,
  required int size,
  required int alignment,
}) {
  data.setUint32(offset, type, Endian.little);
  data.setUint32(offset + 4, flags, Endian.little);
  data.setUint64(offset + 8, fileOffset, Endian.little);
  data.setUint64(offset + 16, address, Endian.little);
  data.setUint64(offset + 24, address, Endian.little);
  data.setUint64(offset + 32, size, Endian.little);
  data.setUint64(offset + 40, size, Endian.little);
  data.setUint64(offset + 48, alignment, Endian.little);
}

void _dynamic(ByteData data, int offset, int tag, int value) {
  data.setUint64(offset, tag, Endian.little);
  data.setUint64(offset + 8, value, Endian.little);
}

void _section(
  ByteData data,
  int offset, {
  required int name,
  required int type,
  required int flags,
  required int address,
  required int fileOffset,
  required int size,
  int link = 0,
  required int alignment,
  int entrySize = 0,
}) {
  data.setUint32(offset, name, Endian.little);
  data.setUint32(offset + 4, type, Endian.little);
  data.setUint64(offset + 8, flags, Endian.little);
  data.setUint64(offset + 16, address, Endian.little);
  data.setUint64(offset + 24, fileOffset, Endian.little);
  data.setUint64(offset + 32, size, Endian.little);
  data.setUint32(offset + 40, link, Endian.little);
  data.setUint64(offset + 48, alignment, Endian.little);
  data.setUint64(offset + 56, entrySize, Endian.little);
}
