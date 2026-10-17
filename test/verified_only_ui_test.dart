/// G11 UI: the "Only sync with verified devices" switch, the members-page
/// warning + peer device sheet (verify a member's device), the app-wide
/// incoming-verification prompt and the record details' "verified by you"
/// line. No matrix import — fake gateway + in-memory trust store.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/database/daos/settings_dao.dart';
import 'package:money_ledger/core/matrix/device_gateway.dart';
import 'package:money_ledger/core/matrix/record_crypto.dart';
import 'package:money_ledger/features/auth/auth_provider.dart';
import 'package:money_ledger/features/devices/device_provider.dart';
import 'package:money_ledger/features/devices/devices_page.dart';
import 'package:money_ledger/features/expenses/record_attribution.dart';
import 'package:money_ledger/features/groups/group_members_page.dart';
import 'package:money_ledger/features/groups/group_provider.dart';
import 'package:money_ledger/features/settings/settings_page.dart';
import 'package:money_ledger/features/onboarding/onboarding_provider.dart';
import 'package:money_ledger/models/member_model.dart';
import 'package:money_ledger/models/record_signature.dart';

import 'helpers/fake_device_gateway.dart';
import 'helpers/in_memory_database.dart';
import 'helpers/l10n.dart';
import 'helpers/test_providers.dart';

const me = '@alice:x.org';
const bob = '@bob:y.org';

MemberModel claimed(String mxid, String name) => MemberModel(
  groupId: 'g1',
  userId: mxid,
  displayName: name,
  matrixId: mxid,
  status: 'active',
  updatedAt: 1,
);

DeviceInfo bobDevice(String id, {String? name}) => DeviceInfo(
  deviceId: id,
  displayName: name,
  userId: bob,
  ed25519Key: 'key-$id',
  isThisDevice: false,
  verified: false,
);

class _FakeIncoming implements IncomingVerification {
  _FakeIncoming(this.gateway);
  final FakeDeviceGateway gateway;
  bool rejected = false;

  @override
  String get userId => bob;

  @override
  String? get deviceId => 'B1';

  @override
  VerificationSession accept() =>
      FakeVerificationSession(gateway, 'B1', peerUserId: bob);

  @override
  Future<void> reject() async => rejected = true;
}

void main() {
  group('verified-only switch', () {
    testWidgets('off by default; turning on asks first and explains', (
      tester,
    ) async {
      final db = openTestDatabase();
      addTearDown(db.close);
      final dao = SettingsDao(db);
      final flag = StreamController<bool>.broadcast();
      addTearDown(flag.close);
      await tester.pumpWidget(
        testApp(
          const Scaffold(body: VerifiedOnlySyncTile()),
          overrides: [
            settingsDaoProvider.overrideWithValue(dao),
            verifiedOnlySyncProvider.overrideWith(
              (ref) => Stream.value(false).asyncExpand((v) async* {
                yield v;
                yield* flag.stream;
              }),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Only sync with verified devices'), findsOneWidget);
      expect(find.textContaining('Off: every device'), findsOneWidget);
      expect(
        tester
            .widget<SwitchListTile>(find.byKey(const Key('verifiedOnlySwitch')))
            .value,
        isFalse,
      );

      // Cancel → nothing stored.
      await tester.tap(find.byKey(const Key('verifiedOnlySwitch')));
      await tester.pumpAndSettle();
      expect(find.text('Only sync with verified devices?'), findsOneWidget);
      expect(
        find.textContaining('get nothing from this device until you verify'),
        findsOneWidget,
      );
      // G36: it says plainly that only this device's sends are limited and
      // that a new own login can't restore from here until verified.
      expect(
        find.textContaining('This only limits what this device sends'),
        findsOneWidget,
      );
      expect(
        find.textContaining("can't restore your groups from this device"),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(await tester.runAsync(dao.verifiedOnlySync), isFalse);

      // Confirm → stored.
      await tester.tap(find.byKey(const Key('verifiedOnlySwitch')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('verifiedOnlyConfirm')));
      await tester.pumpAndSettle();
      expect(await tester.runAsync(dao.verifiedOnlySync), isTrue);

      flag.add(true);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('On: this device sends nothing'),
        findsOneWidget,
      );
      expect(
        find.textContaining('It only limits what this device sends'),
        findsOneWidget,
      );

      // Turning off doesn't ask.
      await tester.tap(find.byKey(const Key('verifiedOnlySwitch')));
      await tester.pumpAndSettle();
      expect(find.text('Only sync with verified devices?'), findsNothing);
      expect(await tester.runAsync(dao.verifiedOnlySync), isFalse);
    });
  });

  group('members page device warning', () {
    List<Object> overrides(FakeDeviceGateway gateway, FakeTrustStore store) => [
      currentUserIdProvider.overrideWithValue(me),
      groupMembersProvider('g1').overrideWith(
        (ref) => Stream.value([claimed(me, 'Alice'), claimed(bob, 'Bob')]),
      ),
      ...store.overrides(gateway),
    ];

    testWidgets('verified-only on: warns about unverified devices; '
        'verifying one from the sheet records it and clears the warning', (
      tester,
    ) async {
      const b0 = SignerId(user: bob, device: 'B0', key: 'key-B0');
      final gateway = FakeDeviceGateway(
        const [],
        peers: {
          bob: [bobDevice('B0'), bobDevice('B1', name: 'Bob phone')],
        },
      );
      final store = FakeTrustStore(trusted: {b0}, verifiedOnly: true);
      await tester.pumpWidget(
        testApp(
          const GroupMembersPage(roomId: 'g1'),
          overrides: overrides(gateway, store),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('1 unverified device'), findsOneWidget);
      await tester.tap(find.byKey(const Key('peerDeviceWarning:$bob')));
      await tester.pumpAndSettle();
      expect(find.text('Devices of Bob'), findsOneWidget);
      expect(find.text('Bob phone'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'Verify'));
      await tester.pumpAndSettle();
      expect(find.text('🐶'), findsOneWidget);
      await tester.tap(find.text('They match'));
      await tester.pumpAndSettle();
      expect(find.text('Device verified.'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Done'));
      await tester.pumpAndSettle();

      expect(store.trusted, {
        b0,
        const SignerId(user: bob, device: 'B1', key: 'key-B1'),
      });
      expect(find.widgetWithText(TextButton, 'Verify'), findsNothing);
      Navigator.of(tester.element(find.text('Devices of Bob'))).pop();
      await tester.pumpAndSettle();
      expect(find.text('1 unverified device'), findsNothing);
    });

    testWidgets('G46: verified-only off → no device line at all', (
      tester,
    ) async {
      final gateway = FakeDeviceGateway(
        const [],
        peers: {
          bob: [bobDevice('B1'), bobDevice('B2')],
        },
      );
      await tester.pumpWidget(
        testApp(
          const GroupMembersPage(roomId: 'g1'),
          overrides: overrides(gateway, FakeTrustStore()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Bob'), findsOneWidget);
      expect(find.byKey(const Key('peerDeviceWarning:$bob')), findsNothing);
      expect(find.text('2 unverified devices'), findsNothing);
      expect(find.text('Not reachable — no verified device'), findsNothing);
    });

    testWidgets('verified-only on and no verified device → not reachable', (
      tester,
    ) async {
      final gateway = FakeDeviceGateway(
        const [],
        peers: {
          bob: [bobDevice('B1'), bobDevice('B2')],
        },
      );
      await tester.pumpWidget(
        testApp(
          const GroupMembersPage(roomId: 'g1'),
          overrides: overrides(gateway, FakeTrustStore(verifiedOnly: true)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Not reachable — no verified device'), findsOneWidget);
    });

    testWidgets('all devices verified → no warning', (tester) async {
      final gateway = FakeDeviceGateway(
        const [],
        peers: {
          bob: [bobDevice('B1')],
        },
      );
      await tester.pumpWidget(
        testApp(
          const GroupMembersPage(roomId: 'g1'),
          overrides: overrides(
            gateway,
            FakeTrustStore(
              trusted: {const SignerId(user: bob, device: 'B1', key: 'key-B1')},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('peerDeviceWarning:$bob')), findsNothing);
    });
  });

  testWidgets('an incoming verification request is asked, then runs the '
      'emoji dialog and records the device', (tester) async {
    final gateway = FakeDeviceGateway(
      const [],
      peers: {
        bob: [bobDevice('B1')],
      },
    );
    final store = FakeTrustStore();
    final navKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountUserIdProvider.overrideWithValue(me),
          ...store.overrides(gateway),
        ],
        child: MaterialApp(
          navigatorKey: navKey,
          localizationsDelegates: testLocalizationsDelegates,
          supportedLocales: testSupportedLocales,
          builder: (context, child) => IncomingVerificationListener(
            navigatorContext: () => navKey.currentContext,
            child: child!,
          ),
          home: const Scaffold(body: Text('home')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Declined → rejected, nothing recorded.
    final declined = _FakeIncoming(gateway);
    gateway.incoming.add(declined);
    await tester.pumpAndSettle();
    expect(find.text('Verification request'), findsOneWidget);
    expect(find.textContaining('$bob (device B1)'), findsOneWidget);
    await tester.tap(find.text('Decline'));
    await tester.pumpAndSettle();
    expect(declined.rejected, isTrue);
    expect(store.trusted, isEmpty);

    // Accepted → emoji dialog → recorded.
    gateway.incoming.add(_FakeIncoming(gateway));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Accept'));
    await tester.pumpAndSettle();
    expect(find.text('🐶'), findsOneWidget);
    await tester.tap(find.text('They match'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Done'));
    await tester.pumpAndSettle();
    expect(store.trusted, {
      const SignerId(user: bob, device: 'B1', key: 'key-B1'),
    });
  });

  test('signerVerifiedByMe: null for own signatures, else exact match', () {
    const sig = RecordSignature(user: bob, device: 'B1', key: 'k', sig: 's');
    expect(
      signerVerifiedByMe(
        sig,
        myMxid: me,
        trusted: {const SignerId(user: bob, device: 'B1', key: 'k')},
      ),
      isTrue,
    );
    expect(signerVerifiedByMe(sig, myMxid: me, trusted: const {}), isFalse);
    expect(signerVerifiedByMe(sig, myMxid: bob, trusted: const {}), isNull);
  });
}
