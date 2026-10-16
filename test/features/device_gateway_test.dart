/// Device view-model (Phase F, M6): the pure ordering + trust-summary the
/// devices screen relies on. No matrix import.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/matrix/device_gateway.dart';
import 'package:money_ledger/core/matrix/record_crypto.dart';
import '../helpers/fake_device_gateway.dart';
import '../helpers/l10n.dart';

DeviceInfo _d(
  String id, {
  String? name,
  bool thisDevice = false,
  bool verified = false,
}) => DeviceInfo(
  deviceId: id,
  displayName: name,
  isThisDevice: thisDevice,
  verified: verified,
);

void main() {
  group('DeviceInfo', () {
    test('needsVerification only for other, unverified devices', () {
      expect(_d('a').needsVerification, isTrue);
      expect(_d('a', verified: true).needsVerification, isFalse);
      expect(_d('a', thisDevice: true).needsVerification, isFalse);
    });

    test('label falls back to the device id', () {
      expect(_d('DEV1').label, 'DEV1');
      expect(_d('DEV1', name: 'Pixel').label, 'Pixel');
    });
  });

  group('sortDevices', () {
    test('this device first, then unverified, then verified', () {
      final sorted = sortDevices([
        _d('v', name: 'Verified one', verified: true),
        _d('u', name: 'Unverified one'),
        _d('me', name: 'This one', thisDevice: true),
      ]);
      expect(sorted.map((d) => d.deviceId), ['me', 'u', 'v']);
    });

    test('alphabetical by label within a group', () {
      final sorted = sortDevices([
        _d('b', name: 'Beta'),
        _d('a', name: 'Alpha'),
      ]);
      expect(sorted.map((d) => d.deviceId), ['a', 'b']);
    });
  });

  group('deviceTrustSummary', () {
    test('only device', () {
      expect(
        deviceTrustSummary([_d('me', thisDevice: true)], en),
        'This is your only device.',
      );
    });

    test('all verified', () {
      expect(
        deviceTrustSummary([
          _d('me', thisDevice: true),
          _d('a', verified: true),
        ], en),
        'All your devices are verified.',
      );
    });

    test('counts the ones needing verification', () {
      expect(
        deviceTrustSummary([_d('me', thisDevice: true), _d('a'), _d('b')], en),
        '2 devices need verification.',
      );
      expect(
        deviceTrustSummary([_d('me', thisDevice: true), _d('a')], en),
        '1 device needs verification.',
      );
    });

    test('German plural', () {
      expect(
        deviceTrustSummary([_d('me', thisDevice: true), _d('a'), _d('b')], de),
        '2 Geräte müssen verifiziert werden.',
      );
    });
  });

  group('G11 trust', () {
    final trusted = {const SignerId(user: '@b:x', device: 'B1', key: 'kB1')};
    DeviceInfo peer(String id, String? key, {bool sdk = false}) => DeviceInfo(
      deviceId: id,
      userId: '@b:x',
      ed25519Key: key,
      isThisDevice: false,
      verified: sdk,
    );

    test('withTrust honours the app record (exact key) and the SDK flag', () {
      expect(peer('B1', 'kB1').withTrust(trusted).verified, isTrue);
      expect(peer('B1', 'other').withTrust(trusted).verified, isFalse);
      expect(peer('B2', 'kB2').withTrust(trusted).verified, isFalse);
      expect(peer('B2', 'kB2', sdk: true).withTrust(trusted).verified, isTrue);
      final d = peer('B1', 'kB1').withTrust(trusted);
      expect((d.userId, d.ed25519Key, d.deviceId), ('@b:x', 'kB1', 'B1'));
    });

    test('peerDeviceTrust counts unverified devices', () {
      final none = peerDeviceTrust(const []);
      expect((none.needsAttention, none.noneVerified), (false, false));
      final some = peerDeviceTrust([
        peer('B1', 'kB1').withTrust(trusted),
        peer('B2', 'kB2').withTrust(trusted),
      ]);
      expect(some.unverified, 1);
      expect(some.needsAttention, isTrue);
      expect(some.noneVerified, isFalse);
      final all = peerDeviceTrust([peer('B2', 'kB2')]);
      expect(all.noneVerified, isTrue);
    });

    test('recordingTrust records a success once, even without a UI', () async {
      final gateway = FakeDeviceGateway(
        const [],
        peers: {
          '@b:x': [peer('B1', 'kB1')],
        },
      );
      final recorded = <SignerId>[];
      final session = recordingTrust(
        gateway.verifyDevice('B1', userId: '@b:x'),
        (d) async => recorded.add(d),
      );
      await session.confirmMatch();
      await session.confirmMatch();
      await Future<void>.delayed(Duration.zero);
      expect(recorded, [
        const SignerId(user: '@b:x', device: 'B1', key: 'kB1'),
      ]);
      session.dispose();
    });

    test('recordingTrust records nothing when cancelled', () async {
      final gateway = FakeDeviceGateway([
        const DeviceInfo(deviceId: 'O', isThisDevice: false, verified: false),
      ]);
      final recorded = <SignerId>[];
      final session = recordingTrust(
        gateway.verifyDevice('O'),
        (d) async => recorded.add(d),
      );
      await session.cancel();
      await Future<void>.delayed(Duration.zero);
      expect(recorded, isEmpty);
      session.dispose();
    });
  });
}
