@Tags(<String>['native', 'linux', 'unicorn'])
library;

import 'package:sogen/linux.dart';
import 'package:test/test.dart';

void main() {
  test('exposes Linux state, process, scheduler, and memory core', () {
    final app = createEmpty();
    try {
      expect(app.backendName, 'Unicorn Engine');
      expect(app.process.exitStatus, isNull);
      expect(app.process.threadCount, 0);
      expect(app.process.activeThreadId, isNull);
      expect(app.currentThread, isNull);
      expect(app.activateThread(1), isFalse);
      expect(app.performThreadSwitch(), isFalse);
      app.yieldThread();
      expect(app.lastStopReasonCode, 0);
      expect(app.lastStopReason, 'none');
      expect(app.lastStopDetail, '');

      final originalMmapBase = app.memory.mmapBase;
      app.memory.mmapBase = originalMmapBase + 0x10000;
      expect(app.memory.mmapBase, originalMmapBase + 0x10000);

      final address = app.memory.allocateMemory(0x1000, .readWrite);
      final writeExec = app.memory.allocateMemory(0x1000, .writeExec);
      app.writeMemory(address, [1, 2, 3, 4]);
      expect(app.readMemory(address, 4), [1, 2, 3, 4]);
      expect(app.memory.findFreeAllocationBase(0x1000), isNot(address));

      final region = app.memory.getRegionInfo(address);
      expect(region, isNotNull);
      expect(region!.start, address);
      expect(region.length, 0x1000);
      expect(region.permissions, MemoryPermission.readWrite);
      expect(region.allocationBase, address);
      expect(region.allocationLength, 0x1000);
      expect(region.isReserved, isFalse);
      expect(region.isCommitted, isTrue);
      expect(region.initialPermissions, MemoryPermission.readWrite);
      expect(region.kind, MemoryRegionKind.privateAllocation);
      expect(app.memory.getRegionInfo(address + 0x80)!.start, address);
      expect(app.memory.getRegionInfo(0x90000000), isNull);
      expect(
        app.memory.getRegionInfo(writeExec)!.permissions,
        MemoryPermission.writeExec,
      );

      final stats = app.memory.computeMemoryStats();
      expect(stats.regionCount, 3);
      expect(stats.mappedBytes, 0x3000);
      expect(stats.executableBytes, 0x1000);

      final state = app.serializeState();
      app.writeMemory(address, [9, 9, 9, 9]);
      app.deserializeState(state);
      expect(app.readMemory(address, 4), [1, 2, 3, 4]);
      expect(app.memory.mmapBase, originalMmapBase + 0x10000);

      app.saveSnapshot();
      app.writeMemory(address, [8, 8, 8, 8]);
      app.restoreSnapshot();
      expect(app.readMemory(address, 4), [1, 2, 3, 4]);
    } finally {
      app.dispose();
    }

    app.dispose();
    expect(app.isDisposed, isTrue);
    expect(() => app.backendName, throwsStateError);
    expect(() => app.process.pid, throwsStateError);
    expect(() => app.memory.computeMemoryStats(), throwsStateError);
    expect(() => app.readRegister(.rip), throwsStateError);
  });
}
