/// Device view-model (Phase F, M6): the pure ordering + trust-summary the
/// devices screen relies on. No matrix import.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/matrix/device_gateway.dart';
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
}
