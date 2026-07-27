import 'dart:ffi';

import 'package:ffi/ffi.dart';

import 'ffi/sogen_native_bindings.g.dart';
import 'generated/types.g.dart';
import 'native_library.dart';

final class LinuxFactoryBindings {
  const LinuxFactoryBindings._();

  static Pointer<sogen_dart_app> createEmpty(
    NativeLibrary library, {
    required String emulationRoot,
    required Backend backend,
    required bool disableLogging,
    required Map<String, String> pathMappings,
    required Map<String, String> readOnlyPathMappings,
    required Map<int, int> portMappings,
  }) {
    _validatePortMappings(portMappings);
    final root = emulationRoot.toNativeUtf8();
    final writable = _NativePathMappings(pathMappings);
    final readOnly = _NativePathMappings(readOnlyPathMappings);
    final ports = _NativePortMappings(portMappings);
    final output = calloc<Pointer<sogen_dart_app>>();
    try {
      library.checkStatus(
        library.bindings.sogen_dart_linux_create_empty_ex(
          root.cast<Char>(),
          backend.nativeValue,
          disableLogging ? 1 : 0,
          writable.pointer,
          writable.length,
          readOnly.pointer,
          readOnly.length,
          ports.pointer,
          ports.length,
          output,
        ),
      );
      return output.value;
    } finally {
      calloc.free(output);
      ports.dispose();
      readOnly.dispose();
      writable.dispose();
      malloc.free(root);
    }
  }

  static Pointer<sogen_dart_app> createApplication(
    NativeLibrary library,
    String application, {
    required List<String> arguments,
    required Map<String, String>? environment,
    required String emulationRoot,
    required String workingDirectory,
    required Backend backend,
    required bool disableLogging,
    required Map<String, String> pathMappings,
    required Map<String, String> readOnlyPathMappings,
    required Map<int, int> portMappings,
  }) {
    _validatePortMappings(portMappings);
    final applicationUtf8 = application.toNativeUtf8();
    final root = emulationRoot.toNativeUtf8();
    final workingDirectoryUtf8 = workingDirectory.toNativeUtf8();
    final nativeArguments = _NativeStrings(arguments);
    final nativeEnvironment = _NativeEnvironment(environment);
    final writable = _NativePathMappings(pathMappings);
    final readOnly = _NativePathMappings(readOnlyPathMappings);
    final ports = _NativePortMappings(portMappings);
    final output = calloc<Pointer<sogen_dart_app>>();
    try {
      library.checkStatus(
        library.bindings.sogen_dart_linux_create_application_ex(
          applicationUtf8.cast<Char>(),
          nativeArguments.pointer,
          nativeArguments.length,
          nativeEnvironment.pointer,
          nativeEnvironment.length,
          environment == null ? 0 : 1,
          root.cast<Char>(),
          workingDirectoryUtf8.cast<Char>(),
          backend.nativeValue,
          disableLogging ? 1 : 0,
          writable.pointer,
          writable.length,
          readOnly.pointer,
          readOnly.length,
          ports.pointer,
          ports.length,
          output,
        ),
      );
      return output.value;
    } finally {
      calloc.free(output);
      ports.dispose();
      readOnly.dispose();
      writable.dispose();
      nativeEnvironment.dispose();
      nativeArguments.dispose();
      malloc.free(workingDirectoryUtf8);
      malloc.free(root);
      malloc.free(applicationUtf8);
    }
  }
}

final class _NativeStrings {
  _NativeStrings(List<String> values)
    : length = values.length,
      pointer = values.isEmpty
          ? nullptr
          : calloc<Pointer<Char>>(values.length) {
    for (var index = 0; index < values.length; ++index) {
      pointer[index] = values[index].toNativeUtf8().cast<Char>();
    }
  }

  final Pointer<Pointer<Char>> pointer;
  final int length;

  void dispose() {
    for (var index = 0; index < length; ++index) {
      malloc.free(pointer[index]);
    }
    if (pointer != nullptr) calloc.free(pointer);
  }
}

final class _NativeEnvironment {
  _NativeEnvironment(Map<String, String>? values)
    : length = values?.length ?? 0,
      pointer = values == null || values.isEmpty
          ? nullptr
          : calloc<sogen_dart_linux_environment_entry>(values.length) {
    if (values == null) return;
    var index = 0;
    for (final entry in values.entries) {
      final native = pointer[index++];
      native.name_utf8 = entry.key.toNativeUtf8().cast<Char>();
      native.value_utf8 = entry.value.toNativeUtf8().cast<Char>();
    }
  }

  final Pointer<sogen_dart_linux_environment_entry> pointer;
  final int length;

  void dispose() {
    for (var index = 0; index < length; ++index) {
      malloc.free(pointer[index].value_utf8);
      malloc.free(pointer[index].name_utf8);
    }
    if (pointer != nullptr) calloc.free(pointer);
  }
}

final class _NativePathMappings {
  _NativePathMappings(Map<String, String> values)
    : length = values.length,
      pointer = values.isEmpty
          ? nullptr
          : calloc<sogen_dart_linux_path_mapping>(values.length) {
    var index = 0;
    for (final entry in values.entries) {
      final native = pointer[index++];
      native.guest_path_utf8 = entry.key.toNativeUtf8().cast<Char>();
      native.host_path_utf8 = entry.value.toNativeUtf8().cast<Char>();
    }
  }

  final Pointer<sogen_dart_linux_path_mapping> pointer;
  final int length;

  void dispose() {
    for (var index = 0; index < length; ++index) {
      malloc.free(pointer[index].host_path_utf8);
      malloc.free(pointer[index].guest_path_utf8);
    }
    if (pointer != nullptr) calloc.free(pointer);
  }
}

final class _NativePortMappings {
  _NativePortMappings(Map<int, int> values)
    : length = values.length,
      pointer = values.isEmpty
          ? nullptr
          : calloc<sogen_dart_linux_port_mapping>(values.length) {
    var index = 0;
    for (final entry in values.entries) {
      final native = pointer[index++];
      native.emulator_port = entry.key;
      native.host_port = entry.value;
    }
  }

  final Pointer<sogen_dart_linux_port_mapping> pointer;
  final int length;

  void dispose() {
    if (pointer != nullptr) calloc.free(pointer);
  }
}

void _validatePortMappings(Map<int, int> mappings) {
  for (final entry in mappings.entries) {
    _checkPort(entry.key, 'emulatorPort');
    _checkPort(entry.value, 'hostPort');
  }
}

void _checkPort(int port, String name) {
  if (port < 1 || port > 0xffff) {
    throw RangeError.range(port, 1, 0xffff, name);
  }
}
