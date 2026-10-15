/// G24: the pure send-target decision behind MatrixLedgerTransport.sendToUsers.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/matrix/ledger_transport.dart';

const self = '@alice:x.org';
const bob = '@bob:y.org';

DevicePlan plan(Set<String> targets,
        Map<String, Iterable<TransportDevice>> devices) =>
    planDeviceSend(
        targets: targets,
        selfUserId: self,
        selfDeviceId: 'A1',
        devicesByUser: devices);

void main() {
  test('sends to every device of other users and to own other devices', () {
    final p = plan({self, bob}, {
      self: [(deviceId: 'A1', blocked: false), (deviceId: 'A2', blocked: false)],
      bob: [(deviceId: 'B1', blocked: false)],
    });
    expect(p.devices, {
      self: ['A2'],
      bob: ['B1'],
    });
    expect(p.unreachableUsers, isEmpty);
    expect(p.deviceCount, 2);
  });

  test('another user with no device is unreachable (not an error)', () {
    final p = plan({self, bob}, {
      self: [(deviceId: 'A2', blocked: false)],
      bob: const [],
    });
    expect(p.unreachableUsers, {bob});
    expect(p.devices.keys, [self]);
  });

  test('an unknown user (no device list at all) is unreachable', () {
    expect(plan({bob}, const {}).unreachableUsers, {bob});
  });

  test('self with only the current device is normal, not unreachable', () {
    final p = plan({self}, {
      self: [(deviceId: 'A1', blocked: false)],
    });
    expect(p.devices, isEmpty);
    expect(p.unreachableUsers, isEmpty);
    expect(p.deviceCount, 0);
  });

  test('blocked devices are skipped; only-blocked means unreachable', () {
    final p = plan({bob}, {
      bob: [(deviceId: 'B1', blocked: true)],
    });
    expect(p.devices, isEmpty);
    expect(p.unreachableUsers, {bob});
  });

  test('empty MXIDs are ignored', () {
    final p = plan({''}, const {});
    expect(p.devices, isEmpty);
    expect(p.unreachableUsers, isEmpty);
  });
}
