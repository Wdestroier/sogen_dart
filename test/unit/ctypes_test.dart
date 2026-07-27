import 'dart:typed_data';

import 'package:sogen/ctypes.dart' as ctypes;
import 'package:sogen/sogen.dart' show Handle;
import 'package:test/test.dart';

void main() {
  test('Handle exposes the packed Sogen bit fields', () {
    final handle = Handle(
      0x12345678 << 32 | 1 << 31 | 1 << 30 | 0x25 << 23 | 0x12345,
    );

    expect(handle.id, 0x12345);
    expect(handle.type, 0x25);
    expect(handle.isSystem, isTrue);
    expect(handle.isPseudo, isTrue);
    expect(handle.highBits, 0x12345678);
    expect(() => handle.bits = -1, throwsRangeError);
  });

  test('unsigned descriptors truncate to their width', () {
    expect(ctypes.uint8.decode(0x1ff), 0xff);
    expect(ctypes.uint16.decode(0x1ffff), 0xffff);
    expect(ctypes.uint32.decode(0x1ffffffff), 0xffffffff);
    expect(ctypes.uint64.decode(-1), -1);
  });

  test('signed descriptors sign extend their width', () {
    expect(ctypes.int8.decode(0xff), -1);
    expect(ctypes.int16.decode(0x8000), -0x8000);
    expect(ctypes.int32.decode(0xffffffff), -1);
    expect(ctypes.int64.decode(0xffffffffffffffff), -1);
  });

  test('pointer, bool32, and char use guest scalar semantics', () {
    expect(ctypes.pointer.decode(-1), -1);
    expect(ctypes.bool32.decode(0), isFalse);
    expect(ctypes.bool32.decode(0x100000000), isFalse);
    expect(ctypes.bool32.decode(2), isTrue);
    expect(ctypes.char.decode(0x141), Uint8List.fromList([0x41]));
  });
}
