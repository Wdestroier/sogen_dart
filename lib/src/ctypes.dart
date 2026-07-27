import 'dart:typed_data';

abstract interface class CType<T> {
  const CType();

  T decode(int rawValue);
}

final class Uint8Type implements CType<int> {
  const Uint8Type();

  @override
  int decode(int rawValue) => rawValue & 0xff;
}

final class Int8Type implements CType<int> {
  const Int8Type();

  @override
  int decode(int rawValue) => _signed(rawValue, 8);
}

final class Uint16Type implements CType<int> {
  const Uint16Type();

  @override
  int decode(int rawValue) => rawValue & 0xffff;
}

final class Int16Type implements CType<int> {
  const Int16Type();

  @override
  int decode(int rawValue) => _signed(rawValue, 16);
}

final class Uint32Type implements CType<int> {
  const Uint32Type();

  @override
  int decode(int rawValue) => rawValue & 0xffffffff;
}

final class Int32Type implements CType<int> {
  const Int32Type();

  @override
  int decode(int rawValue) => _signed(rawValue, 32);
}

final class Uint64Type implements CType<int> {
  const Uint64Type();

  @override
  int decode(int rawValue) => rawValue;
}

final class Int64Type implements CType<int> {
  const Int64Type();

  @override
  int decode(int rawValue) => _signed(rawValue, 64);
}

final class CharType implements CType<Uint8List> {
  const CharType();

  @override
  Uint8List decode(int rawValue) => Uint8List.fromList([rawValue & 0xff]);
}

final class PointerType implements CType<int> {
  const PointerType();

  @override
  int decode(int rawValue) => rawValue;
}

final class Bool32Type implements CType<bool> {
  const Bool32Type();

  @override
  bool decode(int rawValue) => (rawValue & 0xffffffff) != 0;
}

int _signed(int rawValue, int width) {
  final mask = (1 << width) - 1;
  final value = rawValue & mask;
  final signBit = 1 << (width - 1);
  return value & signBit == 0 ? value : value - (1 << width);
}

const CType<int> uint8 = Uint8Type();
const CType<int> int8 = Int8Type();
const CType<int> uint16 = Uint16Type();
const CType<int> int16 = Int16Type();
const CType<int> uint32 = Uint32Type();
const CType<int> int32 = Int32Type();
const CType<int> uint64 = Uint64Type();
const CType<int> int64 = Int64Type();
const CType<Uint8List> char = CharType();
const CType<int> pointer = PointerType();
const CType<bool> bool32 = Bool32Type();
