/// G24: the pure send-target decision behind MatrixLedgerTransport.sendToUsers.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/matrix/ledger_transport.dart';

const self = '@alice:x.org';
const bob = '@bob:y.org';

DevicePlan plan(
  Set<String> targets,
  Map<String, Iterable<TransportDevice>> devices,
) => planDeviceSend(
  targets: targets,
  selfUserId: self,
  selfDeviceId: 'A1',
  devicesByUser: devices,
);

void main() {
  test('sends to every device of other users and to own other devices', () {
    final p = plan(
      {self, bob},
      {
        self: [TransportDevice('A1'), TransportDevice('A2')],
        bob: [TransportDevice('B1')],
      },
    );
    expect(p.devices, {
      self: ['A2'],
      bob: ['B1'],
    });
    expect(p.unreachableUsers, isEmpty);
    expect(p.deviceCount, 2);
  });

  test('another user with no device is unreachable (not an error)', () {
    final p = plan(
      {self, bob},
      {
        self: [TransportDevice('A2')],
        bob: const [],
      },
    );
    expect(p.unreachableUsers, {bob});
    expect(p.devices.keys, [self]);
  });

  test('an unknown user (no device list at all) is unreachable', () {
    expect(plan({bob}, const {}).unreachableUsers, {bob});
  });

  test('self with only the current device is normal, not unreachable', () {
    final p = plan(
      {self},
      {
        self: [TransportDevice('A1')],
      },
    );
    expect(p.devices, isEmpty);
    expect(p.unreachableUsers, isEmpty);
    expect(p.deviceCount, 0);
  });

  test('blocked devices are skipped; only-blocked means unreachable', () {
    final p = plan(
      {bob},
      {
        bob: [TransportDevice('B1', blocked: true)],
      },
    );
    expect(p.devices, isEmpty);
    expect(p.unreachableUsers, {bob});
  });

  test('empty MXIDs are ignored', () {
    final p = plan({''}, const {});
    expect(p.devices, isEmpty);
    expect(p.unreachableUsers, isEmpty);
  });

  group('G11 verified-only policy', () {
    const bobKey = 'kB1';
    DevicePlan planWith(
      DeliveryPolicy policy,
      Map<String, Iterable<TransportDevice>> devices,
    ) => planDeviceSend(
      targets: {self, bob},
      selfUserId: self,
      selfDeviceId: 'A1',
      devicesByUser: devices,
      policy: policy,
    );

    final devices = {
      self: [
        const TransportDevice('A1', key: 'kA1'),
        const TransportDevice('A2', key: 'kA2'),
      ],
      bob: [
        const TransportDevice('B1', key: bobKey),
        const TransportDevice('B2', key: 'kB2'),
      ],
    };

    test('the default policy sends to every device', () {
      final p = planWith(DeliveryPolicy.everyone, devices);
      expect(p.devices, {
        self: ['A2'],
        bob: ['B1', 'B2'],
      });
      expect(p.withheldDevices, 0);
      expect(p.unverifiedUsers, isEmpty);
    });

    test('only devices verified by key (or by the SDK) receive', () {
      final p = planWith(
        DeliveryPolicy(
          verifiedOnly: true,
          trusted: {const SignerId(user: bob, device: 'B1', key: bobKey)},
        ),
        devices,
      );
      expect(p.devices, {
        bob: ['B1'],
      });
      expect(p.withheldDevices, 2, reason: 'own A2 + bob B2');
      expect(p.unreachableUsers, isEmpty, reason: 'self is never reported');
    });

    test('an SDK-verified device counts as verified', () {
      final p = planWith(const DeliveryPolicy(verifiedOnly: true), {
        bob: [const TransportDevice('B1', verified: true)],
      });
      expect(p.devices, {
        bob: ['B1'],
      });
    });

    test('a changed key voids the recorded verification', () {
      final p = planWith(
        DeliveryPolicy(
          verifiedOnly: true,
          trusted: {const SignerId(user: bob, device: 'B1', key: 'old')},
        ),
        devices,
      );
      expect(p.devices, isEmpty);
    });

    test('a peer whose devices are all unverified is unreachable as '
        '"unverified"; one with no device at all is not', () {
      final p = planDeviceSend(
        targets: {bob, '@carol:z.org'},
        selfUserId: self,
        selfDeviceId: 'A1',
        devicesByUser: {
          bob: [const TransportDevice('B1')],
        },
        policy: const DeliveryPolicy(verifiedOnly: true),
      );
      expect(p.unreachableUsers, {bob, '@carol:z.org'});
      expect(p.unverifiedUsers, {bob});
    });

    test('blocked devices are not counted as withheld', () {
      final p = planWith(const DeliveryPolicy(verifiedOnly: true), {
        bob: [const TransportDevice('B1', blocked: true)],
      });
      expect(p.withheldDevices, 0);
      expect(p.unverifiedUsers, isEmpty);
      expect(p.unreachableUsers, {bob});
    });
  });

  test('isDeviceTrusted needs the exact user, device and key', () {
    final t = {const SignerId(user: bob, device: 'B1', key: 'k')};
    bool trusted(String user, String device, String? key) => isDeviceTrusted(
      user: user,
      deviceId: device,
      key: key,
      sdkVerified: false,
      trusted: t,
    );
    expect(trusted(bob, 'B1', 'k'), isTrue);
    expect(trusted(bob, 'B1', 'x'), isFalse);
    expect(trusted(bob, 'B2', 'k'), isFalse);
    expect(trusted(self, 'B1', 'k'), isFalse);
    expect(trusted(bob, 'B1', null), isFalse);
  });
}
