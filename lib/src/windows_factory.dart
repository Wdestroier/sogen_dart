import 'dart:ffi';

import 'package:ffi/ffi.dart';

import 'ffi/sogen_native_bindings.g.dart';
import 'generated/types.g.dart';
import 'native_library.dart';

final class WindowsFactoryBindings {
  const WindowsFactoryBindings._();

  static Pointer<sogen_dart_app> createEmpty(
    NativeLibrary library, {
    required String emulationRoot,
    required String registryDirectory,
    required Backend backend,
    required bool disableLogging,
    required bool useRelativeTime,
    required Map<String, String> pathMappings,
    required Map<int, int> portMappings,
    required int numberOfProcessors,
    required int ntProductType,
  }) {
    _validateOptions(
      portMappings: portMappings,
      numberOfProcessors: numberOfProcessors,
      ntProductType: ntProductType,
    );
    return using((arena) {
      final options = arena<sogen_dart_windows_emulator_options>();
      _fillEmulatorOptions(
        options.ref,
        arena,
        emulationRoot: emulationRoot,
        registryDirectory: registryDirectory,
        backend: backend,
        disableLogging: disableLogging,
        useRelativeTime: useRelativeTime,
        pathMappings: pathMappings,
        portMappings: portMappings,
        numberOfProcessors: numberOfProcessors,
        ntProductType: ntProductType,
      );
      final output = arena<Pointer<sogen_dart_app>>();
      library.checkStatus(
        library.bindings.sogen_dart_windows_create_empty_with_options(
          options,
          output,
        ),
      );
      return output.value;
    });
  }

  static Pointer<sogen_dart_app> createApplication(
    NativeLibrary library,
    String application, {
    required List<String> arguments,
    required Map<String, String> environment,
    required String emulationRoot,
    required String workingDirectory,
    required String registryDirectory,
    required Backend backend,
    required bool disableLogging,
    required bool useRelativeTime,
    required Map<String, String> pathMappings,
    required Map<int, int> portMappings,
    required int numberOfProcessors,
    required int ntProductType,
  }) {
    _validateOptions(
      portMappings: portMappings,
      numberOfProcessors: numberOfProcessors,
      ntProductType: ntProductType,
    );
    return using((arena) {
      final applicationOptions =
          arena<sogen_dart_windows_application_options>();
      applicationOptions.ref
        ..application_utf8 = application
            .toNativeUtf8(allocator: arena)
            .cast<Char>()
        ..arguments_utf8 = _strings(arguments, arena)
        ..argument_count = arguments.length
        ..environment = _environment(environment, arena)
        ..environment_count = environment.length
        ..working_directory_utf8 = workingDirectory
            .toNativeUtf8(allocator: arena)
            .cast<Char>();

      final emulatorOptions = arena<sogen_dart_windows_emulator_options>();
      _fillEmulatorOptions(
        emulatorOptions.ref,
        arena,
        emulationRoot: emulationRoot,
        registryDirectory: registryDirectory,
        backend: backend,
        disableLogging: disableLogging,
        useRelativeTime: useRelativeTime,
        pathMappings: pathMappings,
        portMappings: portMappings,
        numberOfProcessors: numberOfProcessors,
        ntProductType: ntProductType,
      );
      final output = arena<Pointer<sogen_dart_app>>();
      library.checkStatus(
        library.bindings.sogen_dart_windows_create_application_with_options(
          applicationOptions,
          emulatorOptions,
          output,
        ),
      );
      return output.value;
    });
  }
}

void _fillEmulatorOptions(
  sogen_dart_windows_emulator_options options,
  Arena arena, {
  required String emulationRoot,
  required String registryDirectory,
  required Backend backend,
  required bool disableLogging,
  required bool useRelativeTime,
  required Map<String, String> pathMappings,
  required Map<int, int> portMappings,
  required int numberOfProcessors,
  required int ntProductType,
}) {
  options
    ..emulation_root_utf8 = emulationRoot
        .toNativeUtf8(allocator: arena)
        .cast<Char>()
    ..registry_directory_utf8 = registryDirectory
        .toNativeUtf8(allocator: arena)
        .cast<Char>()
    ..backend = backend.nativeValue
    ..disable_logging = disableLogging ? 1 : 0
    ..use_relative_time = useRelativeTime ? 1 : 0
    ..path_mappings = _pathMappings(pathMappings, arena)
    ..path_mapping_count = pathMappings.length
    ..port_mappings = _portMappings(portMappings, arena)
    ..port_mapping_count = portMappings.length
    ..number_of_processors = numberOfProcessors
    ..nt_product_type = ntProductType;
}

Pointer<Pointer<Char>> _strings(List<String> values, Arena arena) {
  if (values.isEmpty) return nullptr;
  final result = arena<Pointer<Char>>(values.length);
  for (var index = 0; index < values.length; ++index) {
    result[index] = values[index].toNativeUtf8(allocator: arena).cast<Char>();
  }
  return result;
}

Pointer<sogen_dart_windows_environment_entry> _environment(
  Map<String, String> values,
  Arena arena,
) {
  if (values.isEmpty) return nullptr;
  final result = arena<sogen_dart_windows_environment_entry>(values.length);
  var index = 0;
  for (final entry in values.entries) {
    result[index++]
      ..name_utf8 = entry.key.toNativeUtf8(allocator: arena).cast<Char>()
      ..value_utf8 = entry.value.toNativeUtf8(allocator: arena).cast<Char>();
  }
  return result;
}

Pointer<sogen_dart_windows_path_mapping> _pathMappings(
  Map<String, String> values,
  Arena arena,
) {
  if (values.isEmpty) return nullptr;
  final result = arena<sogen_dart_windows_path_mapping>(values.length);
  var index = 0;
  for (final entry in values.entries) {
    result[index++]
      ..guest_path_utf8 = entry.key.toNativeUtf8(allocator: arena).cast<Char>()
      ..host_path_utf8 = entry.value
          .toNativeUtf8(allocator: arena)
          .cast<Char>();
  }
  return result;
}

Pointer<sogen_dart_windows_port_mapping> _portMappings(
  Map<int, int> values,
  Arena arena,
) {
  if (values.isEmpty) return nullptr;
  final result = arena<sogen_dart_windows_port_mapping>(values.length);
  var index = 0;
  for (final entry in values.entries) {
    result[index++]
      ..emulator_port = entry.key
      ..host_port = entry.value;
  }
  return result;
}

void _validateOptions({
  required Map<int, int> portMappings,
  required int numberOfProcessors,
  required int ntProductType,
}) {
  for (final entry in portMappings.entries) {
    _checkUnsigned(entry.key, 0xffff, 'emulatorPort');
    _checkUnsigned(entry.value, 0xffff, 'hostPort');
  }
  _checkUnsigned(numberOfProcessors, 0xffffffff, 'numberOfProcessors');
  _checkUnsigned(ntProductType, 0xffffffff, 'ntProductType');
}

void _checkUnsigned(int value, int maximum, String name) {
  if (value < 0 || value > maximum) {
    throw RangeError.range(value, 0, maximum, name);
  }
}
