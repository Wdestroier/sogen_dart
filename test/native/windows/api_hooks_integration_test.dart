@Tags(<String>['native', 'windowsGuest', 'unicorn', 'requiresCc'])
@Timeout(Duration(minutes: 2))
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:sogen/ctypes.dart' show uint32;
import 'package:sogen/windows.dart';
import 'package:test/test.dart';

import 'windows_hook_fixture.dart';

const _expectedPid = 0xc0ffee01;
const _bareKey = 'GetCurrentProcessId';
const _qualifiedKey = 'kernel32!GetCurrentProcessId';

void main() {
  final configuredRoot = Platform.environment['SOGEN_WINDOWS_ROOT'];
  final exampleRoot = Directory('example/root').absolute;
  final root =
      configuredRoot ?? (exampleRoot.existsSync() ? exampleRoot.path : null);
  final skipReason = !Platform.isWindows
      ? 'The API-hook fixture requires a Windows host.'
      : root == null
      ? 'Set SOGEN_WINDOWS_ROOT or create example/root to run this test.'
      : false;

  group('Windows API hooks', () {
    WindowsHookFixtures? installedFixtures;

    setUpAll(() async {
      installedFixtures = await buildWindowsHookFixtures(
        root!,
        includeWow64: true,
      );
    });

    tearDownAll(() async {
      await installedFixtures?.dispose();
    });

    test('bare name intercepts and returns the mutable result', () {
      final app = createApplication(
        windowsHookFixtureGuest,
        emulationRoot: root!,
      );
      ApiCall? receivedCall;
      List<dynamic>? receivedParameters;
      app.hooks.apis[_bareKey] = apiCall(
        cc: .stdcall,
        cb: (call, parameters) {
          receivedCall = call;
          receivedParameters = parameters;
          call.returnValue = _expectedPid;
          return ApiContinuation.intercept;
        },
      );

      try {
        app.start();
        expect(app.process.exitStatus, 0);
        expect(receivedParameters, isEmpty);
        expect(receivedCall, isNotNull);
        expect(receivedCall!.module.toLowerCase(), 'kernel32.dll');
        expect(receivedCall!.name, _bareKey);
        expect(receivedCall!.address, isNonZero);
        expect(receivedCall!.returnAddress, isNonZero);
        expect(receivedCall!.returnValue, _expectedPid);
      } finally {
        app.dispose();
      }
    });

    test('qualified module name intercepts', () {
      final app = createApplication(
        windowsHookFixtureGuest,
        emulationRoot: root!,
      );
      var hits = 0;
      app.hooks.apis[_qualifiedKey] = _interceptingHook(() => hits++);

      try {
        app.start();
        expect(app.process.exitStatus, 0);
        expect(hits, 1);
      } finally {
        app.dispose();
      }
    });

    test('replacement invokes only the latest hook', () {
      final app = createApplication(
        windowsHookFixtureGuest,
        emulationRoot: root!,
      );
      var replacedHits = 0;
      var replacementHits = 0;
      app.hooks.apis[_bareKey] = _interceptingHook(() => replacedHits++);
      app.hooks.apis[_bareKey] = _interceptingHook(() => replacementHits++);

      try {
        app.start();
        expect(app.process.exitStatus, 0);
        expect(replacedHits, 0);
        expect(replacementHits, 1);
      } finally {
        app.dispose();
      }
    });

    test('null assignment deletes a hook and runs the original', () {
      final app = createApplication(
        windowsHookFixtureGuest,
        emulationRoot: root!,
      );
      var hits = 0;
      app.hooks.apis[_bareKey] = _interceptingHook(() => hits++);
      app.hooks.apis[_bareKey] = null;

      try {
        app.start();
        expect(app.process.exitStatus, 1);
        expect(hits, 0);
        expect(app.hooks.apis[_bareKey], isNull);
      } finally {
        app.dispose();
      }
    });

    test('remove deletes a hook and runs the original', () {
      final app = createApplication(
        windowsHookFixtureGuest,
        emulationRoot: root!,
      );
      var hits = 0;
      app.hooks.apis[_bareKey] = _interceptingHook(() => hits++);
      app.hooks.apis.remove(_bareKey);

      try {
        app.start();
        expect(app.process.exitStatus, 1);
        expect(hits, 0);
        expect(app.hooks.apis[_bareKey], isNull);
      } finally {
        app.dispose();
      }
    });

    test('clear deletes every API hook', () {
      final app = createApplication(
        windowsHookFixtureGuest,
        emulationRoot: root!,
      );
      var hits = 0;
      app.hooks.apis[_bareKey] = _interceptingHook(() => hits++);
      app.hooks.apis['UnusedExport'] = _interceptingHook(() {});
      app.hooks.apis.clear();

      try {
        app.start();
        expect(app.process.exitStatus, 1);
        expect(hits, 0);
        expect(app.hooks.apis[_bareKey], isNull);
        expect(app.hooks.apis['UnusedExport'], isNull);
      } finally {
        app.dispose();
      }
    });

    test('registry retains an otherwise unretained hook', () {
      final app = createApplication(
        windowsHookFixtureGuest,
        emulationRoot: root!,
      );
      var hits = 0;
      app.hooks.apis[_bareKey] = _interceptingHook(() => hits++);

      try {
        app.start();
        expect(app.process.exitStatus, 0);
        expect(hits, 1);
      } finally {
        app.dispose();
      }
    });

    test('callback failure runs the original and is reported', () {
      final app = createApplication(
        windowsHookFixtureGuest,
        emulationRoot: root!,
      );
      app.hooks.apis[_bareKey] = apiCall(
        cc: .stdcall,
        cb: (_, _) => throw StateError('API callback failure'),
      );

      try {
        expect(
          app.start,
          throwsA(
            isA<SogenCallbackException>()
                .having((error) => error.hookKey, 'hookKey', _bareKey)
                .having((error) => error.error, 'error', isA<StateError>()),
          ),
        );
        expect(app.process.exitStatus, 1);
      } finally {
        app.dispose();
      }
    });

    test('module load refreshes hooks registered before process setup', () {
      final app = createApplication(
        windowsHookFixtureGuest,
        emulationRoot: root!,
      );
      var hits = 0;
      app.hooks.apis[_bareKey] = _interceptingHook(() => hits++);

      try {
        expect(hits, 0);
        app.setupProcessIfNecessary();
        expect(hits, 0);
        app.start();
        expect(app.process.exitStatus, 0);
        expect(hits, 1);
      } finally {
        app.dispose();
      }
    });

    test('deserialize refreshes API hooks against restored modules', () {
      final source = createApplication(
        windowsHookFixtureGuest,
        emulationRoot: root!,
      );
      late final Uint8List state;
      try {
        source.setupProcessIfNecessary();
        state = source.serializeState();
      } finally {
        source.dispose();
      }

      final restored = createEmpty(emulationRoot: root);
      var hits = 0;
      restored.hooks.apis[_bareKey] = _interceptingHook(() => hits++);
      try {
        restored.deserializeState(state);
        restored.start();
        expect(restored.process.exitStatus, 0);
        expect(hits, 1);
      } finally {
        restored.dispose();
      }
    });

    test('snapshot restore refreshes API hooks after modules were removed', () {
      final pristine = createApplication(
        windowsHookFixtureGuest,
        emulationRoot: root!,
      );
      late final Uint8List stateWithoutModules;
      try {
        stateWithoutModules = pristine.serializeState();
      } finally {
        pristine.dispose();
      }

      final app = createApplication(
        windowsHookFixtureGuest,
        emulationRoot: root,
      );
      var hits = 0;
      app.hooks.apis[_bareKey] = _interceptingHook(() => hits++);
      try {
        app.setupProcessIfNecessary();
        app.saveSnapshot();
        app.deserializeState(stateWithoutModules);
        app.restoreSnapshot();
        app.start();
        expect(app.process.exitStatus, 0);
        expect(hits, 1);
      } finally {
        app.dispose();
      }
    });

    test('WOW64 selects x86 stdcall and matches full module names', () {
      final app = createApplication(
        windowsHookFixtureWow64Guest,
        emulationRoot: root!,
      );
      final sleepArguments = <int>[];
      var pidHits = 0;
      app.hooks.apis['KERNEL32.DLL!Sleep'] = apiCall(
        cc: .stdcall,
        params: [uint32],
        cb: (_, parameters) {
          sleepArguments.add(parameters.single as int);
          return ApiContinuation.intercept;
        },
      );
      app.hooks.apis['KeRnEl32!GetCurrentProcessId'] = apiCall(
        cc: .stdcall,
        cb: (call, _) {
          pidHits++;
          call.returnValue = _expectedPid;
          return ApiContinuation.intercept;
        },
      );

      try {
        app.setupProcessIfNecessary();
        expect(app.process.isWow64Process, isTrue);
        app.start();
        expect(app.process.exitStatus, 0);
        expect(sleepArguments, [7]);
        expect(pidHits, 1);
      } finally {
        app.dispose();
      }
    });
  }, skip: skipReason);
}

ApiHook _interceptingHook(void Function() onHit) => apiCall(
  cc: .stdcall,
  cb: (call, _) {
    onHit();
    call.returnValue = _expectedPid;
    return ApiContinuation.intercept;
  },
);
