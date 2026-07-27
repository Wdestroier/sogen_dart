@Tags(<String>['native', 'windowsGuest', 'unicorn'])
library;

import 'dart:io';

import 'package:sogen/windows.dart';
import 'package:test/test.dart';

void main() {
  final root = Directory('example/root').absolute;
  final registry = Directory('${root.path}/registry');
  final sample = File('${root.path}/filesys/c/test-sample.exe');
  final unavailable = <String>[
    if (!registry.existsSync()) registry.path,
    if (!sample.existsSync()) sample.path,
  ];
  final emptyUnavailable = <String>[if (!registry.existsSync()) registry.path];

  test(
    'exposes one callback view with all twenty settable slots',
    () {
      final app = createEmpty(
        emulationRoot: root.path,
        registryDirectory: registry.path,
      );
      try {
        expect(identical(app.callbacks, app.process.callbacks), isTrue);
        expect(app.currentThread, isNull);
        expect(app.currentThreadId, isNull);
        expect(app.process.activeThread, isNull);

        app.callbacks.onModuleLoad = (_) {};
        app.callbacks.onModuleUnload = (_) {};
        app.callbacks.onStdout = (_) {};
        app.callbacks.onSyscall = (_, _) => null;
        app.callbacks.onGenericAccess = (_, _) {};
        app.callbacks.onGenericActivity = (_) {};
        app.callbacks.onSuspiciousActivity = (_) {};
        app.callbacks.onException = () {};
        app.callbacks.onInstruction = (_) {};
        app.callbacks.onMemoryProtect = (_, _, _) {};
        app.callbacks.onMemoryAllocate = (_, _, _, _) {};
        app.callbacks.onMemoryViolate = (_, _, _, _) => null;
        app.callbacks.onRdtsc = () {};
        app.callbacks.onRdtscp = () {};
        app.callbacks.onIoctrl = (_, _) {};
        app.callbacks.onDebugString = (_) {};
        app.callbacks.onThreadCreate = (_, _, _, _) {};
        app.callbacks.onThreadTerminated = (_, _) {};
        app.callbacks.onThreadSetName = (_, _) {};
        app.callbacks.onThreadSwitch = (_, _) {};

        expect(<Function?>[
          app.callbacks.onModuleLoad,
          app.callbacks.onModuleUnload,
          app.callbacks.onStdout,
          app.callbacks.onSyscall,
          app.callbacks.onGenericAccess,
          app.callbacks.onGenericActivity,
          app.callbacks.onSuspiciousActivity,
          app.callbacks.onException,
          app.callbacks.onInstruction,
          app.callbacks.onMemoryProtect,
          app.callbacks.onMemoryAllocate,
          app.callbacks.onMemoryViolate,
          app.callbacks.onRdtsc,
          app.callbacks.onRdtscp,
          app.callbacks.onIoctrl,
          app.callbacks.onDebugString,
          app.callbacks.onThreadCreate,
          app.callbacks.onThreadTerminated,
          app.callbacks.onThreadSetName,
          app.callbacks.onThreadSwitch,
        ], everyElement(isNotNull));

        const slots = <String>[
          'moduleLoad',
          'moduleUnload',
          'stdout',
          'syscall',
          'genericAccess',
          'genericActivity',
          'suspiciousActivity',
          'exception',
          'instruction',
          'memoryProtect',
          'memoryAllocate',
          'memoryViolate',
          'rdtsc',
          'rdtscp',
          'ioctrl',
          'debugString',
          'threadCreate',
          'threadTerminated',
          'threadSetName',
          'threadSwitch',
        ];
        for (final slot in slots) {
          app.callbacks.clear('on$slot');
        }
        expect(<Function?>[
          app.callbacks.onModuleLoad,
          app.callbacks.onModuleUnload,
          app.callbacks.onStdout,
          app.callbacks.onSyscall,
          app.callbacks.onGenericAccess,
          app.callbacks.onGenericActivity,
          app.callbacks.onSuspiciousActivity,
          app.callbacks.onException,
          app.callbacks.onInstruction,
          app.callbacks.onMemoryProtect,
          app.callbacks.onMemoryAllocate,
          app.callbacks.onMemoryViolate,
          app.callbacks.onRdtsc,
          app.callbacks.onRdtscp,
          app.callbacks.onIoctrl,
          app.callbacks.onDebugString,
          app.callbacks.onThreadCreate,
          app.callbacks.onThreadTerminated,
          app.callbacks.onThreadSetName,
          app.callbacks.onThreadSwitch,
        ], everyElement(isNull));

        void stdout(String _) {}
        app.callbacks.set('on_stdout', stdout);
        expect(identical(app.callbacks.onStdout, stdout), isTrue);
        app.callbacks.clear('stdout');
        expect(app.callbacks.onStdout, isNull);
        app.callbacks.onStdout = stdout;
        app.callbacks.onStdout = null;
        expect(app.callbacks.onStdout, isNull);
        expect(
          () => app.callbacks.clear('unknown'),
          throwsA(isA<ArgumentError>()),
        );
        expect(
          () => app.callbacks.set('on_unknown', stdout),
          throwsA(isA<ArgumentError>()),
        );
      } finally {
        app.dispose();
      }
    },
    skip: emptyUnavailable.isEmpty
        ? false
        : 'Missing ${emptyUnavailable.join(', ')}.',
  );

  test(
    'delivers copied callback payloads and current thread names',
    () {
      final modules = <MappedModule>[];
      final unloadedModules = <MappedModule>[];
      final output = StringBuffer();
      final syscalls = <(int, String)>[];
      final accesses = <(String, String)>[];
      final activities = <String>[];
      final suspiciousActivities = <String>[];
      final allocations = <(int, int, MemoryPermission, bool)>[];
      final protections = <(int, int, MemoryPermission)>[];
      final violations = <(int, int, MemoryOperation, MemoryViolationType)>[];
      final ioctrls = <(String, int)>[];
      final debugStrings = <String>[];
      final threadCreates = <(int, int, int, int)>[];
      final threadTerminations = <(int, int)>[];
      final threadNames = <(int, String)>[];
      final threadSwitches = <(int, int)>[];
      var instructionHits = 0;
      var exceptionHits = 0;
      var rdtscHits = 0;
      var rdtscpHits = 0;

      final app = createApplication(
        r'C:\test-sample.exe',
        emulationRoot: root.path,
        registryDirectory: registry.path,
      );
      app.callbacks.onModuleLoad = modules.add;
      app.callbacks.onModuleUnload = unloadedModules.add;
      app.callbacks.onStdout = output.write;
      app.callbacks.onSyscall = (id, name) {
        syscalls.add((id, name));
        return false;
      };
      app.callbacks.onGenericAccess = (type, name) {
        accesses.add((type, name));
      };
      app.callbacks.onGenericActivity = activities.add;
      app.callbacks.onSuspiciousActivity = suspiciousActivities.add;
      app.callbacks.onException = () {
        exceptionHits++;
      };
      app.callbacks.onInstruction = (_) {
        instructionHits++;
        app.callbacks.onInstruction = null;
      };
      app.callbacks.onMemoryAllocate = (address, length, permission, commit) {
        allocations.add((address, length, permission, commit));
      };
      app.callbacks.onMemoryProtect = (address, length, permission) {
        protections.add((address, length, permission));
      };
      app.callbacks.onMemoryViolate = (address, length, operation, type) {
        violations.add((address, length, operation, type));
        return null;
      };
      app.callbacks.onRdtsc = () {
        rdtscHits++;
      };
      app.callbacks.onRdtscp = () {
        rdtscpHits++;
      };
      app.callbacks.onIoctrl = (deviceName, code) {
        ioctrls.add((deviceName, code));
      };
      app.callbacks.onDebugString = debugStrings.add;
      app.callbacks.onThreadCreate = (handle, id, start, argument) {
        threadCreates.add((handle, id, start, argument));
      };
      app.callbacks.onThreadTerminated = (handle, id) {
        threadTerminations.add((handle, id));
      };
      app.callbacks.onThreadSetName = (id, name) {
        threadNames.add((id, name));
      };
      app.callbacks.onThreadSwitch = (current, next) {
        threadSwitches.add((current, next));
      };

      try {
        app.start();
        expect(app.process.exitStatus, 0);
        expect(instructionHits, 1);
        expect(output.toString(), isNotEmpty);
        expect(syscalls, isNotEmpty);
        for (final (id, name) in syscalls) {
          expect(id, greaterThanOrEqualTo(0));
          expect(name, isNotEmpty);
        }
        expect(modules, isNotEmpty);
        expect(
          modules,
          everyElement(
            isA<MappedModule>()
                .having((module) => module.name, 'name', isNotEmpty)
                .having((module) => module.modulePath, 'modulePath', isNotEmpty)
                .having(
                  (module) => module.sizeOfImage,
                  'sizeOfImage',
                  greaterThan(0),
                )
                .having(
                  (module) => module.exports,
                  'exports',
                  everyElement(
                    isA<ExportedSymbol>()
                        .having((symbol) => symbol.name, 'name', isNotEmpty)
                        .having(
                          (symbol) => symbol.address,
                          'address',
                          greaterThan(0),
                        ),
                  ),
                ),
          ),
        );
        final mainModule = modules.firstWhere(
          (module) => module.name.toLowerCase() == 'test-sample.exe',
        );
        expect(mainModule.path.toLowerCase(), endsWith('test-sample.exe'));
        expect(mainModule.modulePath.toLowerCase(), r'c:\test-sample.exe');
        final moduleWithExports = modules.firstWhere(
          (module) => module.exports.isNotEmpty,
        );
        final exportedSymbol = moduleWithExports.exports.first;
        expect(
          exportedSymbol.address,
          moduleWithExports.imageBase + exportedSymbol.rva,
        );
        expect(exportedSymbol.ordinal, greaterThanOrEqualTo(0));
        expect(
          () => moduleWithExports.exports.add(exportedSymbol),
          throwsUnsupportedError,
        );
        expect(unloadedModules, isNotEmpty);
        expect(unloadedModules, everyElement(isA<MappedModule>()));
        expect(accesses, isNotEmpty);
        for (final (type, name) in accesses) {
          expect(type, isNotEmpty);
          expect(name, isNotEmpty);
        }
        expect(activities, isNotEmpty);
        expect(activities, everyElement(isNotEmpty));
        expect(suspiciousActivities, isNotEmpty);
        expect(suspiciousActivities, everyElement(isNotEmpty));
        expect(exceptionHits, greaterThan(0));
        expect(allocations, isNotEmpty);
        for (final (address, length, permission, commit) in allocations) {
          expect(address, greaterThan(0));
          expect(length, greaterThan(0));
          expect(permission, isA<MemoryPermission>());
          expect(commit, isA<bool>());
        }
        expect(protections, isNotEmpty);
        for (final (address, length, permission) in protections) {
          expect(address, greaterThan(0));
          expect(length, greaterThan(0));
          expect(permission, isA<MemoryPermission>());
        }
        expect(violations, isNotEmpty);
        for (final (address, length, operation, type) in violations) {
          expect(address, greaterThanOrEqualTo(0));
          expect(length, greaterThan(0));
          expect(operation, isA<MemoryOperation>());
          expect(type, isA<MemoryViolationType>());
        }
        expect(rdtscpHits, greaterThan(0));
        expect(ioctrls, isNotEmpty);
        for (final (deviceName, code) in ioctrls) {
          expect(deviceName, isNotEmpty);
          expect(code, inInclusiveRange(0, 0xffffffff));
        }
        expect(threadCreates, isNotEmpty);
        for (final (handle, id, start, argument) in threadCreates) {
          expect(handle, greaterThanOrEqualTo(0));
          expect(id, greaterThan(0));
          expect(start, greaterThanOrEqualTo(0));
          expect(argument, greaterThanOrEqualTo(0));
        }
        expect(threadTerminations, isNotEmpty);
        for (final (handle, id) in threadTerminations) {
          expect(handle, greaterThanOrEqualTo(0));
          expect(id, greaterThan(0));
        }
        for (final (id, name) in threadNames) {
          expect(id, greaterThan(0));
          expect(name, isA<String>());
        }
        expect(threadSwitches, isNotEmpty);
        for (final (current, next) in threadSwitches) {
          expect(current, greaterThan(0));
          expect(next, greaterThan(0));
        }
        expect(rdtscHits, 0);
        expect(debugStrings, isEmpty);
        expect(threadNames, isEmpty);
        final thread = app.currentThread;
        if (thread != null) {
          expect(thread.name, isA<String>());
          expect(app.process.activeThread?.name, thread.name);
        }
      } finally {
        app.dispose();
      }
    },
    skip: unavailable.isEmpty ? false : 'Missing ${unavailable.join(', ')}.',
  );

  test(
    'contains callback exceptions and reports them after start',
    () {
      final app = createApplication(
        r'C:\test-sample.exe',
        emulationRoot: root.path,
        registryDirectory: registry.path,
      );
      app.callbacks.onInstruction = (_) {
        app.callbacks.onInstruction = null;
        throw StateError('callback failure');
      };
      try {
        expect(
          app.start,
          throwsA(
            isA<SogenCallbackException>()
                .having((error) => error.hookKey, 'hookKey', 'instruction')
                .having((error) => error.error, 'error', isA<StateError>()),
          ),
        );
        expect(app.process.exitStatus, 0);
      } finally {
        app.dispose();
      }
    },
    skip: unavailable.isEmpty ? false : 'Missing ${unavailable.join(', ')}.',
  );
}
