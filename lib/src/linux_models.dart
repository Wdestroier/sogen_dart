part of 'linux.dart';

// ignore_for_file: prefer_initializing_formals

final class ExportedSymbol {
  const ExportedSymbol({
    required this.name,
    required this.rva,
    required this.address,
  });

  final String name;
  final int rva;
  final int address;
}

typedef LinuxExportedSymbol = ExportedSymbol;

final class MappedSection {
  const MappedSection({
    required this.name,
    required this.start,
    required this.length,
    required this.permissions,
  });

  final String name;
  final int start;
  final int length;
  final MemoryPermission permissions;
}

final class LinuxMappedModule {
  LinuxMappedModule({
    required this.name,
    required this.path,
    required this.imageBase,
    required this.sizeOfImage,
    required this.entryPoint,
    required List<ExportedSymbol> exports,
    required List<String> neededLibraries,
    required List<MappedSection> sections,
    required this.rpath,
    required this.runpath,
  }) : exports = List.unmodifiable(exports),
       neededLibraries = List.unmodifiable(neededLibraries),
       sections = List.unmodifiable(sections);

  final String name;
  final String path;
  final int imageBase;
  final int sizeOfImage;
  final int entryPoint;
  final List<ExportedSymbol> exports;
  final List<String> neededLibraries;
  final List<MappedSection> sections;
  final String rpath;
  final String runpath;
}

final class LinuxThread {
  const LinuxThread({
    required int tid,
    required int stackBase,
    required int stackSize,
    required int fsBase,
    required int currentIp,
    required int startAddress,
    required ThreadWaitState waitState,
    required bool terminated,
    required int exitCode,
    required int executedInstructions,
  }) : _tid = tid,
       _stackBase = stackBase,
       _stackSize = stackSize,
       _fsBase = fsBase,
       _currentIp = currentIp,
       _startAddress = startAddress,
       _waitState = waitState,
       _terminated = terminated,
       _exitCode = exitCode,
       _executedInstructions = executedInstructions,
       _resolve = null;

  LinuxThread._retained(_LinuxThreadSnapshot snapshot, this._resolve)
    : _tid = snapshot.tid,
      _stackBase = snapshot.stackBase,
      _stackSize = snapshot.stackSize,
      _fsBase = snapshot.fsBase,
      _currentIp = snapshot.currentIp,
      _startAddress = snapshot.startAddress,
      _waitState = snapshot.waitState,
      _terminated = snapshot.terminated,
      _exitCode = snapshot.exitCode,
      _executedInstructions = snapshot.executedInstructions;

  final _LinuxThreadSnapshot Function()? _resolve;

  _LinuxThreadSnapshot get _view => _resolve!.call();

  final int _tid;
  final int _stackBase;
  final int _stackSize;
  final int _fsBase;
  final int _currentIp;
  final int _startAddress;
  final ThreadWaitState _waitState;
  final bool _terminated;
  final int _exitCode;
  final int _executedInstructions;

  int get tid => _resolve == null ? _tid : _view.tid;
  int get stackBase => _resolve == null ? _stackBase : _view.stackBase;
  int get stackSize => _resolve == null ? _stackSize : _view.stackSize;
  int get fsBase => _resolve == null ? _fsBase : _view.fsBase;
  int get currentIp => _resolve == null ? _currentIp : _view.currentIp;
  int get startAddress => _resolve == null ? _startAddress : _view.startAddress;
  ThreadWaitState get waitState =>
      _resolve == null ? _waitState : _view.waitState;
  bool get terminated => _resolve == null ? _terminated : _view.terminated;
  int get exitCode => _resolve == null ? _exitCode : _view.exitCode;
  int get executedInstructions =>
      _resolve == null ? _executedInstructions : _view.executedInstructions;
  bool get setupDone {
    _resolve?.call();
    return true;
  }

  int get previousIp => throw UnsupportedError(
    'Linux previousIp is not tracked by the pinned Sogen revision.',
  );
}

final class _LinuxThreadSnapshot {
  const _LinuxThreadSnapshot({
    required this.tid,
    required this.stackBase,
    required this.stackSize,
    required this.fsBase,
    required this.currentIp,
    required this.startAddress,
    required this.waitState,
    required this.terminated,
    required this.exitCode,
    required this.executedInstructions,
  });

  final int tid;
  final int stackBase;
  final int stackSize;
  final int fsBase;
  final int currentIp;
  final int startAddress;
  final ThreadWaitState waitState;
  final bool terminated;
  final int exitCode;
  final int executedInstructions;
}
