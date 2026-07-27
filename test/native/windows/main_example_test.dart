@Tags(<String>['native', 'windowsGuest', 'unicorn'])
library;

import 'dart:io';

import 'package:sogen/ctypes.dart' show uint32;
import 'package:sogen/windows.dart' show apiCall, createApplication;
import 'package:test/test.dart';

void main() {
  final root = Platform.environment['SOGEN_WINDOWS_ROOT'];
  final guestBinary = Platform.environment['SOGEN_WINDOWS_TEST_BINARY'];

  final unavailable = [
    if (root == null) 'SOGEN_WINDOWS_ROOT',
    if (guestBinary == null) 'SOGEN_WINDOWS_TEST_BINARY',
  ];

  test(
    'observes Sleep and exits successfully',
    () {
      final sleeps = [];
      final app = createApplication(guestBinary!, emulationRoot: root!);
      final onSleep = apiCall(
        cc: .stdcall,
        params: [uint32],
        cb: (call, params) {
          sleeps.add(params[0]);
        },
      );
      app.hooks.apis['Sleep'] = onSleep;
      try {
        app.start();
        expect(app.process.exitStatus, 0);
        expect(sleeps, [1, 1]);
      } finally {
        app.dispose();
      }
    },
    skip: unavailable.isEmpty
        ? false
        : 'Set ${unavailable.join(', ')} to run the Windows guest test.',
  );
}
