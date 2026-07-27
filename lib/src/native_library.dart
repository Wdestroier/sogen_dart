import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import 'exceptions.dart';
import 'ffi/sogen_native_bindings.g.dart';

const _supportedAbiVersion = 0x00010001;
const _nativeAssetId = 'package:sogen/sogen.dart';

String? _libraryPathOverride;
NativeLibrary? _nativeLibrary;

void configureNativeLibrary(String path) {
  if (_nativeLibrary != null) {
    throw StateError('The Sogen native library has already been loaded');
  }
  _libraryPathOverride = path;
}

String resolveEmulationRoot(String root) {
  if (root.isEmpty || Directory(root).existsSync()) {
    return root;
  }
  final rootUri = Uri.file(root, windows: Platform.isWindows);
  if (rootUri.isAbsolute) {
    return root;
  }
  final scriptRelative = Directory.fromUri(Platform.script.resolve(root)).path;
  return Directory(scriptRelative).existsSync() ? scriptRelative : root;
}

final class NativeLibrary {
  NativeLibrary._(this.bindings) {
    final version = bindings.sogen_dart_abi_version();
    if (version != _supportedAbiVersion) {
      throw SogenException(
        'Unsupported sogen_dart ABI 0x${version.toRadixString(16)}; '
        'expected 0x${_supportedAbiVersion.toRadixString(16)}. '
        'Delete stale .dart_tool native assets and rebuild.',
      );
    }
  }

  final SogenNativeBindings bindings;

  static NativeLibrary get instance =>
      _nativeLibrary ??= NativeLibrary._(_openBindings());

  void checkStatus(int status) {
    if (status == SOGEN_DART_OK) {
      return;
    }
    throw SogenException(lastError(), status: status);
  }

  String lastError() {
    final length = bindings.sogen_dart_last_error(nullptr, 0);
    if (length == 0) {
      return 'Native Sogen operation failed without an error message';
    }

    final buffer = calloc<Char>(length + 1);
    try {
      bindings.sogen_dart_last_error(buffer, length + 1);
      final bytes = buffer.cast<Uint8>().asTypedList(length);
      try {
        return utf8.decode(bytes);
      } on FormatException {
        return latin1.decode(bytes);
      }
    } finally {
      calloc.free(buffer);
    }
  }
}

SogenNativeBindings _openBindings() {
  final override =
      _libraryPathOverride ?? Platform.environment['SOGEN_DART_LIBRARY'];
  if (override != null && override.isNotEmpty) {
    return SogenNativeBindings(DynamicLibrary.open(override));
  }
  return SogenNativeBindings.fromLookup(_lookupBundledSymbol);
}

Pointer<T> _lookupBundledSymbol<T extends NativeType>(String symbolName) {
  final name = symbolName.toNativeUtf8();
  try {
    final symbol = _sogenDartLookup(name.cast<Char>());
    if (symbol == nullptr) {
      throw ArgumentError('Unable to find native Sogen symbol $symbolName');
    }
    return symbol.cast<T>();
  } finally {
    malloc.free(name);
  }
}

@Native<Pointer<Void> Function(Pointer<Char>)>(
  symbol: 'sogen_dart_lookup',
  assetId: _nativeAssetId,
)
external Pointer<Void> _sogenDartLookup(Pointer<Char> symbol);
