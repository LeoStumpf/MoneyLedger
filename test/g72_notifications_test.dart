/// G72: the notification settings switch (EN + DE, 360 dp, 200 % font),
/// the one-time permission prompt and opening a tapped notification's
/// group.
library;

import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/background/background_sync_provider.dart';
import 'package:money_ledger/core/database/account_database.dart';
import 'package:money_ledger/core/database/app_database.dart';
import 'package:money_ledger/core/database/daos/members_dao.dart';
import 'package:money_ledger/core/database/daos/settings_dao.dart';
import 'package:money_ledger/core/session/app_session.dart';
import 'package:money_ledger/features/groups/group_provider.dart';
import 'package:money_ledger/features/notifications/notifications_provider.dart';
import 'package:money_ledger/features/onboarding/onboarding_provider.dart';
import 'package:money_ledger/features/settings/settings_page.dart';
import 'package:money_ledger/models/member_model.dart';

import 'helpers/fake_notifications.dart';
import 'helpers/l10n.dart';
import 'helpers/test_providers.dart';

const _me = '@anna:example.org';

/// Records the writes of the settings switch (no database).
class _SpySettingsDao extends SettingsDao {
  _SpySettingsDao() : super(AppDatabase.signedOut(SignedOutExecutor()));

  final enabledWrites = <bool>[];
  int askedMarks = 0;

  @override
  Future<void> setNotificationsEnabled(bool enabled) async =>
      enabledWrites.add(enabled);

  @override
  Future<void> markNotificationPermissionAsked() async => askedMarks++;
}

List<dynamic> _overrides({
  required FakeNotificationPlatform platform,
  required SettingsDao dao,
  bool enabled = true,
  bool background = true,
}) => [
  ...testOverrides(isLoggedIn: true),
  currentUserIdProvider.overrideWith((_) => _me),
  backgroundSyncSupportedProvider.overrideWithValue(true),
  backgroundSyncEnabledProvider.overrideWith((_) => Stream.value(background)),
  notificationPlatformProvider.overrideWithValue(platform),
  notificationsEnabledProvider.overrideWith((_) => Stream.value(enabled)),
  settingsDaoProvider.overrideWithValue(dao),
];

Future<void> _pump(
  WidgetTester tester,
  List<dynamic> overrides, {
  Locale? locale,
  double textScale = 1,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(360, 780);
  addTearDown(tester.view.reset);
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.pumpWidget(
    testApp(const SettingsPage(), overrides: overrides, locale: locale),
  );
  await tester.pumpAndSettle();
  final tile = find.byKey(const Key('notificationsSwitch'));
  final list = find.descendant(
    of: find.byKey(const Key('settingsList')),
    matching: find.byType(Scrollable),
  );
  await tester.scrollUntilVisible(tile, 150, scrollable: list);
  await tester.pumpAndSettle();
}

void main() {
  group('settings switch', () {
    for (final (locale, l) in [
      (const Locale('en'), en),
      (const Locale('de'), de),
    ]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('on by default, fits 360 dp ($locale, ${scale}x)', (
          tester,
        ) async {
          await _pump(
            tester,
            _overrides(
              platform: FakeNotificationPlatform(granted: true),
              dao: _SpySettingsDao(),
            ),
            locale: locale,
            textScale: scale,
          );
          final sw = tester.widget<SwitchListTile>(
            find.byKey(const Key('notificationsSwitch')),
          );
          expect(sw.value, isTrue);
          expect(find.text(l.notificationsTitle), findsOneWidget);
          expect(find.text(l.notificationsBody), findsOneWidget);
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets('turning it on writes the setting and asks for the '
        'permission', (tester) async {
      final platform = FakeNotificationPlatform(granted: false);
      final dao = _SpySettingsDao();
      await _pump(
        tester,
        _overrides(platform: platform, dao: dao, enabled: false),
      );
      await tester.tap(find.byKey(const Key('notificationsSwitch')));
      await tester.pumpAndSettle();
      expect(dao.enabledWrites, [true]);
      expect(platform.requests, 1);
    });

    testWidgets('blocked by Android → says where to allow them', (
      tester,
    ) async {
      await _pump(
        tester,
        _overrides(
          platform: FakeNotificationPlatform(granted: false),
          dao: _SpySettingsDao(),
        ),
      );
      expect(find.text(en.notificationsBlocked), findsOneWidget);
    });

    testWidgets('background sync off → switch disabled, says why', (
      tester,
    ) async {
      await _pump(
        tester,
        _overrides(
          platform: FakeNotificationPlatform(granted: true),
          dao: _SpySettingsDao(),
          background: false,
        ),
      );
      final sw = tester.widget<SwitchListTile>(
        find.byKey(const Key('notificationsSwitch')),
      );
      expect(sw.onChanged, isNull);
      expect(sw.value, isFalse);
      expect(find.text(en.notificationsNeedBackgroundSync), findsOneWidget);
    });

    testWidgets('no notification platform (web) → no switch', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(360, 780);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        testApp(
          const SettingsPage(),
          overrides: [
            ...testOverrides(isLoggedIn: true),
            currentUserIdProvider.overrideWith((_) => _me),
            backgroundSyncSupportedProvider.overrideWithValue(true),
            backgroundSyncEnabledProvider.overrideWith(
              (_) => Stream.value(true),
            ),
            notificationPlatformProvider.overrideWithValue(null),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('notificationsSwitch')), findsNothing);
    });
  });

  group('permission prompt', () {
    test('shouldAskNotificationPermission', () {
      bool ask({
        bool enabled = true,
        bool background = true,
        bool shared = true,
        bool asked = false,
        bool granted = false,
      }) => shouldAskNotificationPermission(
        enabled: enabled,
        backgroundSync: background,
        sharedGroup: shared,
        asked: asked,
        granted: granted,
      );
      expect(ask(), isTrue);
      expect(ask(enabled: false), isFalse);
      expect(ask(background: false), isFalse);
      expect(ask(shared: false), isFalse);
      expect(ask(asked: true), isFalse);
      expect(ask(granted: true), isFalse);
    });

    Future<(FakeNotificationPlatform, AppDatabase, ProviderContainer)> run({
      required bool shared,
      bool granted = false,
    }) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final platform = FakeNotificationPlatform(granted: granted);
      final c = ProviderContainer(
        overrides: [
          backgroundSyncSupportedProvider.overrideWithValue(true),
          notificationPlatformProvider.overrideWithValue(platform),
          ledgerIdentityProvider.overrideWithValue(_me),
          settingsDaoProvider.overrideWithValue(SettingsDao(db)),
          sharedGroupExistsProvider.overrideWith((_) => Stream.value(shared)),
          notificationsEnabledProvider.overrideWith((_) => Stream.value(true)),
          backgroundSyncEnabledProvider.overrideWith((_) => Stream.value(true)),
        ],
      );
      addTearDown(c.dispose);
      // Let the streams emit, then the prompt run (it rebuilds on them).
      final sub = c.listen(notificationPermissionPromptProvider, (_, _) {});
      for (var i = 0; i < 5; i++) {
        await c.read(sharedGroupExistsProvider.future);
        await c.read(notificationsEnabledProvider.future);
        await c.read(backgroundSyncEnabledProvider.future);
        await c.read(notificationPermissionPromptProvider.future);
      }
      sub.close();
      return (platform, db, c);
    }

    test('asks once a group is shared — and only once', () async {
      final (platform, db, _) = await run(shared: true);
      expect(platform.requests, 1);
      expect(await SettingsDao(db).notificationPermissionAsked(), isTrue);

      // A later start with the flag set asks nothing.
      final c2 = ProviderContainer(
        overrides: [
          backgroundSyncSupportedProvider.overrideWithValue(true),
          notificationPlatformProvider.overrideWithValue(platform),
          ledgerIdentityProvider.overrideWithValue(_me),
          settingsDaoProvider.overrideWithValue(SettingsDao(db)),
          sharedGroupExistsProvider.overrideWith((_) => Stream.value(true)),
          notificationsEnabledProvider.overrideWith((_) => Stream.value(true)),
          backgroundSyncEnabledProvider.overrideWith((_) => Stream.value(true)),
        ],
      );
      addTearDown(c2.dispose);
      final sub = c2.listen(notificationPermissionPromptProvider, (_, _) {});
      for (var i = 0; i < 5; i++) {
        await c2.read(sharedGroupExistsProvider.future);
        await c2.read(notificationPermissionPromptProvider.future);
      }
      sub.close();
      expect(platform.requests, 1);
    });

    test('nothing shared yet → no prompt', () async {
      final (platform, db, _) = await run(shared: false);
      expect(platform.requests, 0);
      expect(await SettingsDao(db).notificationPermissionAsked(), isFalse);
    });

    test('already granted (Android ≤ 12) → no dialog', () async {
      final (platform, _, _) = await run(shared: true, granted: true);
      expect(platform.requests, 0);
    });
  });

  group('tapped notification', () {
    test('notificationOpenAllowed', () {
      expect(notificationOpenAllowed('/groups'), isTrue);
      expect(notificationOpenAllowed('/settings'), isTrue);
      expect(notificationOpenAllowed('/groups/x/expenses'), isTrue);
      for (final p in [
        '',
        '/',
        '/splash',
        '/onboarding',
        '/welcome',
        '/login',
        '/register',
        '/join',
        '/local-setup',
      ]) {
        expect(notificationOpenAllowed(p), isFalse, reason: p);
      }
    });

    testWidgets('the launching notification opens its group once start-up '
        'is done; a tap while running opens at once', (tester) async {
      final platform = FakeNotificationPlatform(launchGroup: 'g 1');
      final location = ValueNotifier('/splash');
      final went = <String>[];
      await tester.pumpWidget(
        ProviderScope(
          overrides: [notificationPlatformProvider.overrideWithValue(platform)],
          child: NotificationTapListener(
            go: (l) {
              went.add(l);
              location.value = l;
            },
            location: () => location.value,
            locationChanges: location,
            child: const SizedBox(),
          ),
        ),
      );
      await tester.pump();
      expect(went, isEmpty, reason: 'still on the splash');
      location.value = '/groups';
      await tester.pump();
      expect(went, ['/groups/g%201/expenses']);

      location.value = '/settings';
      platform.taps.add('g2');
      await tester.pump();
      expect(went.last, '/groups/g2/expenses');
    });
  });

  test('PRIVACY.md and the in-app text say the same about notifications', () {
    String norm(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();
    final privacy = norm(File('PRIVACY.md').readAsStringSync());
    expect(privacy, contains(norm(en.privacyBackgroundBody)));
    expect(en.privacyBackgroundBody, contains('it shows a notification'));
    expect(
      de.privacyBackgroundBody,
      contains('zeigt die App eine Benachrichtigung'),
    );
    expect(en.privacyBackgroundBody, contains('no push service'));
    expect(de.privacyBackgroundBody, contains('kein Push-Dienst'));
  });

  test(
    'watchHasOtherClaimedMember: another active Matrix account only',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final dao = MembersDao(db);
      Future<void> put(String pid, String? mxid, {String status = 'active'}) =>
          dao.upsertMemberLww(
            memberCompanion(
              MemberModel(
                groupId: 'g',
                userId: pid,
                displayName: pid,
                matrixId: mxid,
                status: status,
                updatedAt: 1,
              ),
            ),
          );
      await put('me', _me);
      await put('ben', null);
      await put('local', 'local:self');
      expect(await dao.watchHasOtherClaimedMember(_me).first, isFalse);
      await put('carl', '@carl:x.org', status: 'removed');
      expect(await dao.watchHasOtherClaimedMember(_me).first, isFalse);
      await put('dora', '@dora:x.org');
      expect(await dao.watchHasOtherClaimedMember(_me).first, isTrue);
    },
  );
}
