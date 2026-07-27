import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';

const _sogenRepository = 'https://github.com/momo5502/sogen.git';
const _sogenCommit = '52df4d49a4ee45afff9acd00520badf33f1d4e5c';

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) {
      return;
    }
    final targetOS = input.config.code.targetOS;
    if (targetOS != OS.current ||
        input.config.code.targetArchitecture != Architecture.current) {
      throw UnsupportedError(
        'The Sogen Dart adapter currently requires a native host build; '
        'target is ${targetOS.name}/${input.config.code.targetArchitecture.name}, '
        'host is ${OS.current.name}/${Architecture.current.name}',
      );
    }

    await _addNativeDependencies(input, output);
    output.dependencies.add(input.packageRoot.resolve('sogen.lock'));

    final sogenSource = await _sogenSource(input);
    await _addSourceDependencies(sogenSource, output);
    final buildDirectory = Directory.fromUri(
      input.outputDirectory.resolve('cmake/'),
    );
    await buildDirectory.create(recursive: true);

    final cmake = await _findCmake();
    final configureArguments = [
      '--fresh',
      '-S',
      File.fromUri(
        input.packageRoot.resolve('native/CMakeLists.txt'),
      ).parent.path,
      '-B',
      buildDirectory.path,
      '-DSOGEN_SOURCE_DIR=${sogenSource.path}',
      '-DSOGEN_BUILD_TOOLS=OFF',
      '-DSOGEN_ENABLE_PYTHON_BINDINGS=OFF',
      '-DSOGEN_ENABLE_LTO=OFF',
      if (!Platform.isWindows) '-DCMAKE_BUILD_TYPE=Release',
    ];
    await _run(cmake, configureArguments);
    await _run(cmake, [
      '--build',
      buildDirectory.path,
      '--config',
      'Release',
      '--target',
      'sogen_dart',
      '--parallel',
    ]);

    final libraryName = targetOS.dylibFileName('sogen_dart');
    final library = File.fromUri(
      input.outputDirectory.resolve(
        Platform.isWindows
            ? 'cmake/Release/$libraryName'
            : 'cmake/$libraryName',
      ),
    );
    if (!await library.exists()) {
      throw StateError('CMake did not produce ${library.path}');
    }

    output.assets.code.add(
      CodeAsset(
        package: input.packageName,
        name: 'sogen.dart',
        linkMode: DynamicLoadingBundled(),
        file: library.uri,
      ),
    );
  });
}

Future<void> _addSourceDependencies(
  Directory source,
  BuildOutputBuilder output,
) async {
  output.dependencies.add(File('${source.path}/CMakeLists.txt').uri);
  final sourceDirectory = Directory('${source.path}/src');
  await for (final entity in sourceDirectory.list(recursive: true)) {
    if (entity is File) {
      output.dependencies.add(entity.uri);
    }
  }
}

Future<void> _addNativeDependencies(
  BuildInput input,
  BuildOutputBuilder output,
) async {
  final nativeDirectory = Directory.fromUri(
    input.packageRoot.resolve('native/'),
  );
  await for (final entity in nativeDirectory.list(recursive: true)) {
    if (entity is File) {
      output.dependencies.add(entity.uri);
    }
  }
}

Future<Directory> _sogenSource(BuildInput input) async {
  final local = Directory.fromUri(
    input.packageRoot.resolve('build/deps/sogen/'),
  );
  if (await _hasExpectedCommit(local)) {
    await _updateSubmodules(local);
    await _ensureFlatbuffersTags(local);
    return local;
  }

  final source = Directory.fromUri(
    input.outputDirectoryShared.resolve('sogen/'),
  );
  if (!await _hasExpectedCommit(source)) {
    if (await source.exists()) {
      await source.delete(recursive: true);
    }
    await source.parent.create(recursive: true);
    await _run('git', [
      'clone',
      '--no-checkout',
      _sogenRepository,
      source.path,
    ]);
    await _run('git', [
      '-C',
      source.path,
      'checkout',
      '--detach',
      _sogenCommit,
    ]);
  }
  await _updateSubmodules(source);
  await _ensureFlatbuffersTags(source);
  return source;
}

Future<void> _updateSubmodules(Directory source) => _run('git', [
  '-C',
  source.path,
  'submodule',
  'update',
  '--init',
  '--recursive',
]);

Future<void> _ensureFlatbuffersTags(Directory source) async {
  final flatbuffers = '${source.path}/deps/flatbuffers';
  final describe = await Process.run('git', [
    '-C',
    flatbuffers,
    'describe',
    '--tags',
  ]);
  if (describe.exitCode != 0) {
    final shallow = await Process.run('git', [
      '-C',
      flatbuffers,
      'rev-parse',
      '--is-shallow-repository',
    ]);
    await _run('git', [
      '-C',
      flatbuffers,
      'fetch',
      '--tags',
      if ((shallow.stdout as String).trim() == 'true') '--unshallow',
    ]);
  }
}

Future<bool> _hasExpectedCommit(Directory directory) async {
  if (!await Directory('${directory.path}/.git').exists()) {
    return false;
  }
  final result = await Process.run('git', [
    '-C',
    directory.path,
    'rev-parse',
    'HEAD',
  ]);
  return result.exitCode == 0 &&
      (result.stdout as String).trim() == _sogenCommit;
}

Future<String> _findCmake() async {
  try {
    final result = await Process.run('cmake', ['--version']);
    if (result.exitCode == 0) {
      return 'cmake';
    }
  } on ProcessException {
    // Fall through to Visual Studio's bundled CMake on Windows.
  }
  if (!Platform.isWindows) {
    throw StateError('CMake was not found on PATH');
  }

  final systemDrive = Platform.environment['SYSTEMDRIVE'] ?? 'C:';
  final vswhere = File(
    '$systemDrive\\Program Files (x86)\\Microsoft Visual Studio'
    '\\Installer\\vswhere.exe',
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
    '$installation\\Common7\\IDE\\CommonExtensions\\Microsoft\\CMake'
    '\\CMake\\bin\\cmake.exe',
  );
  if (!await cmake.exists()) {
    throw StateError('Visual Studio CMake was not found at ${cmake.path}');
  }
  return cmake.path;
}

Future<void> _run(String executable, List<String> arguments) async {
  final process = await Process.start(
    executable,
    arguments,
    mode: ProcessStartMode.inheritStdio,
  );
  final exitCode = await process.exitCode;
  if (exitCode != 0) {
    throw ProcessException(executable, arguments, 'Exited with $exitCode');
  }
}
