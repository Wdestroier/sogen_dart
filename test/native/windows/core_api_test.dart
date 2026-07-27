@Tags(<String>['native', 'windowsGuest', 'unicorn'])
library;

import 'dart:io';

import 'package:sogen/windows.dart' show MemoryPermission, createEmpty;
import 'package:test/test.dart';

void main() {
  final root = Platform.environment['SOGEN_WINDOWS_ROOT'];
  final unavailable = <String>[if (root == null) 'SOGEN_WINDOWS_ROOT'];

  test(
    'supports memory, registers, snapshots, state, and ports',
    () {
      final app = createEmpty(emulationRoot: root!);
      try {
        expect(app.backendName, 'Unicorn Engine');
        expect(app.emulationRoot, isNotEmpty);
        expect(app.lastStopReason, 'none');

        final address = app.memory.allocateMemory(0x1000, .readWrite);
        app.writeMemory(address, [1, 2, 3, 4]);
        expect(app.readMemory(address, 4), [1, 2, 3, 4]);

        app.writeRegister(.rax, 0x12345678);
        expect(app.readRegister(.rax), 0x12345678);

        final region = app.memory.getRegionInfo(address);
        expect(region.start, address);
        expect(region.permissions, MemoryPermission.readWrite);
        expect(region.isCommitted, isTrue);
        expect(app.memory.computeMemoryStats().committedMemory, greaterThan(0));

        app.saveSnapshot();
        app.writeMemory(address, [9, 9, 9, 9]);
        app.restoreSnapshot();
        expect(app.readMemory(address, 4), [1, 2, 3, 4]);

        final state = app.serializeState();
        app.writeRegister(.rax, 0);
        app.deserializeState(state);
        expect(app.readRegister(.rax), 0x12345678);

        app.mapPort(28970, 28980);
        expect(app.getHostPort(28970), 28980);
        expect(app.getEmulatorPort(28980), 28970);
        app.mapPort(28970, 28970);
        expect(app.getHostPort(28970), 28970);
      } finally {
        app.dispose();
      }
      app.dispose();
      expect(app.isDisposed, isTrue);
      expect(() => app.backendName, throwsStateError);
    },
    skip: unavailable.isEmpty
        ? false
        : 'Set ${unavailable.join(', ')} to run the Windows native test.',
  );
}
