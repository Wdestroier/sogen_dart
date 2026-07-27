import 'dart:io';

const windowsHookFixtureGuest = r'c:/api-hook-fixture.exe';
const windowsHookFixtureWow64Guest = r'c:/api-hook-fixture-x86.exe';

final class WindowsHookFixtures {
  WindowsHookFixtures(this.x64, this.x86);

  final File x64;
  final File? x86;

  Future<void> dispose() async {
    for (final fixture in [x64, x86]) {
      if (fixture != null && await fixture.exists()) {
        await fixture.delete();
      }
    }
  }
}

Future<WindowsHookFixtures> buildWindowsHookFixtures(
  String root, {
  bool includeWow64 = false,
}) async {
  final packageRoot = Directory.current.absolute;
  final source = Directory(
    '${packageRoot.path}/test/native/windows/fixtures/api_hook_fixture',
  );
  final cmake = await _findCmake();
  final x64 = await _buildAndInstall(
    cmake,
    source,
    root,
    architecture: 'x64',
    guestName: 'api-hook-fixture.exe',
  );
  final x86 = includeWow64
      ? await _buildAndInstall(
          cmake,
          source,
          root,
          architecture: 'Win32',
          guestName: 'api-hook-fixture-x86.exe',
        )
      : null;
  return WindowsHookFixtures(x64, x86);
}

Future<File> _buildAndInstall(
  String cmake,
  Directory source,
  String root, {
  required String architecture,
  required String guestName,
}) async {
  final suffix = architecture == 'x64' ? 'x64' : 'x86';
  final build = Directory(
    '${Directory.current.absolute.path}/.dart_tool/windows_api_hook_fixture_$suffix',
  );
  await build.create(recursive: true);
  await _run(cmake, ['-S', source.path, '-B', build.path, '-A', architecture]);
  await _run(cmake, [
    '--build',
    build.path,
    '--config',
    'Release',
    '--parallel',
  ]);

  final built = File('${build.path}/Release/api-hook-fixture.exe');
  if (!await built.exists()) {
    throw StateError('Fixture build did not produce ${built.path}');
  }

  final destination = File('$root/filesys/c/$guestName');
  await destination.parent.create(recursive: true);
  return built.copy(destination.path);
}

Future<String> _findCmake() async {
  try {
    final result = await Process.run('cmake', ['--version']);
    if (result.exitCode == 0) {
      return 'cmake';
    }
  } on ProcessException {
    // Fall through to Visual Studio's bundled CMake.
  }

  final systemDrive = Platform.environment['SYSTEMDRIVE'] ?? 'C:';
  final vswhere = File(
    '$systemDrive/Program Files (x86)/Microsoft Visual Studio/Installer/vswhere.exe',
  );
  if (!await vswhere.exists()) {
    throw StateError('CMake was not found on PATH and vswhere is unavailable');
  }
  final result = await Process.run(vswhere.path, [
    '-latest',
    '-products',
    '*',
    '-requires',
    'Microsoft.VisualStudio.Component.VC.Tools.x86.x64',
    '-property',
    'installationPath',
  ]);
  final installation = (result.stdout as String).trim();
  if (result.exitCode != 0 || installation.isEmpty) {
    throw StateError('Visual Studio with the C++ workload was not found');
  }
  final cmake = File(
    '$installation/Common7/IDE/CommonExtensions/Microsoft/CMake/CMake/bin/cmake.exe',
  );
  if (!await cmake.exists()) {
    throw StateError('Visual Studio CMake was not found at ${cmake.path}');
  }
  return cmake.path;
}

Future<void> _run(String executable, List<String> arguments) async {
  final result = await Process.run(executable, arguments);
  if (result.exitCode != 0) {
    throw ProcessException(
      executable,
      arguments,
      '${result.stdout}\n${result.stderr}',
      result.exitCode,
    );
  }
}
