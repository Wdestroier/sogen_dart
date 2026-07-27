export 'generated/types.g.dart'
    show
        BasicBlock,
        ExportedSymbol,
        LinuxMemoryStats,
        MappedModule,
        MemoryRegionInfo,
        MemoryStats,
        WindowsThread;

final class Handle {
  Handle([int bits = 0]) : _bits = _validateHandleBits(bits);

  int _bits;

  int get bits => _bits;
  set bits(int value) => _bits = _validateHandleBits(value);

  int get id => _bits & 0x7fffff;
  int get type => (_bits >> 23) & 0x7f;
  bool get isSystem => ((_bits >> 30) & 1) != 0;
  bool get isPseudo => ((_bits >> 31) & 1) != 0;
  int get highBits => (_bits >> 32) & 0xffffffff;
}

int _validateHandleBits(int bits) {
  if (bits < 0) {
    throw RangeError.value(bits, 'bits', 'Must not be negative');
  }
  return bits;
}
