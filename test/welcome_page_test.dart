/// G39: the first-open welcome (pages + the three choices, EN / DE, revisit
/// mode) and G40's local setup page / local-mode indicator.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:money_ledger/core/session/device_prefs.dart';
import 'package:money_ledger/features/groups/groups_page.dart';
import 'package:money_ledger/features/settings/settings_page.dart';
import 'package:money_ledger/features/groups/group_members_page.dart';
import 'package:money_ledger/features/local/local_setup_page.dart';
import 'package:money_ledger/features/welcome/welcome_page.dart';
import 'package:money_ledger/models/member_model.dart';

import 'helpers/l10n.dart';
import 'helpers/test_providers.dart';

/// The welcome under a router whose other destinations are placeholders.
Widget _welcomeApp(
  InMemoryDevicePrefsStore store, {
  Locale locale = const Locale('en'),
  String initial = '/welcome',
}) {
  final router = GoRouter(
    initialLocation: initial,
    routes: [
      GoRoute(path: '/welcome', builder: (_, _) => const WelcomePage()),
      GoRoute(
        path: '/how-it-works',
        builder: (_, s) => WelcomePage(
          revisit: true,
          initialTopic: WelcomeTopic.fromName(s.uri.queryParameters['topic']),
        ),
      ),
      GoRoute(
        path: '/host',
        builder: (context, _) => Scaffold(
          body: TextButton(
            onPressed: () => context.push('/how-it-works?topic=matrix'),
            child: const Text('host'),
          ),
        ),
      ),
      for (final p in ['/login', '/register', '/local-setup'])
        GoRoute(
          path: p,
          builder: (_, _) => Scaffold(body: Text('page:$p')),
        ),
    ],
  );
  return ProviderScope(
    overrides: [devicePrefsStoreProvider.overrideWithValue(store)],
    child: MaterialApp.router(
      locale: locale,
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      routerConfig: router,
    ),
  );
}

void main() {
  group('WelcomePage (first open)', () {
    testWidgets('walks through the four explanations to the choices', (
      tester,
    ) async {
      final store = InMemoryDevicePrefsStore();
      await tester.pumpWidget(_welcomeApp(store));
      await tester.pumpAndSettle();

      expect(find.text('Share expenses, fairly'), findsOneWidget);
      expect(find.textContaining('Splitwise or Tricount'), findsOneWidget);
      await tester.tap(find.byKey(const Key('welcomeNext')));
      await tester.pumpAndSettle();
      expect(find.text('Free, open source, no server'), findsOneWidget);
      expect(find.textContaining('AGPL-3.0-or-later'), findsOneWidget);
      expect(find.byKey(const Key('welcomeSourceLink')), findsOneWidget);
      await tester.tap(find.byKey(const Key('welcomeNext')));
      await tester.pumpAndSettle();
      expect(find.text('What is Matrix?'), findsOneWidget);
      expect(find.textContaining('matrix.org'), findsOneWidget);
      await tester.tap(find.byKey(const Key('welcomeNext')));
      await tester.pumpAndSettle();
      expect(find.text('Who sees what'), findsOneWidget);
      expect(find.textContaining('end-to-end encrypted'), findsOneWidget);
      expect(find.textContaining('never the content'), findsOneWidget);
      await tester.tap(find.byKey(const Key('welcomeNext')));
      await tester.pumpAndSettle();

      expect(find.text('How do you want to start?'), findsOneWidget);
      expect(find.byKey(const Key('welcomeSignIn')), findsOneWidget);
      expect(find.byKey(const Key('welcomeCreateAccount')), findsOneWidget);
      expect(find.byKey(const Key('welcomeUseLocal')), findsOneWidget);
      expect(find.byKey(const Key('welcomeNext')), findsNothing);
      expect(store.values, isEmpty, reason: 'not seen until a choice');
    });

    testWidgets('"Use without an account" marks the welcome seen', (
      tester,
    ) async {
      final store = InMemoryDevicePrefsStore();
      await tester.pumpWidget(_welcomeApp(store));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('welcomeSkip')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('welcomeUseLocal')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('welcomeUseLocal')));
      await tester.pumpAndSettle();
      expect(find.text('page:/local-setup'), findsOneWidget);
      expect(store.values['welcome_seen'], '1');
    });

    for (final (key, page) in [
      ('welcomeSignIn', '/login'),
      ('welcomeCreateAccount', '/register'),
    ]) {
      testWidgets('$key → $page', (tester) async {
        final store = InMemoryDevicePrefsStore();
        await tester.pumpWidget(_welcomeApp(store));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('welcomeSkip')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(Key(key)));
        await tester.pumpAndSettle();
        expect(find.text('page:$page'), findsOneWidget);
        expect(store.values['welcome_seen'], '1');
      });
    }

    testWidgets('German', (tester) async {
      await tester.pumpWidget(
        _welcomeApp(InMemoryDevicePrefsStore(), locale: const Locale('de')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Ausgaben fair teilen'), findsOneWidget);
      await tester.tap(find.byKey(const Key('welcomeSkip')));
      await tester.pumpAndSettle();
      expect(find.text('Wie möchtest du starten?'), findsOneWidget);
      expect(find.text('Mit Matrix anmelden'), findsOneWidget);
      expect(find.text('Matrix-Konto erstellen'), findsOneWidget);
      expect(find.text('Ohne Konto nutzen'), findsOneWidget);
    });
  });

  testWidgets('"What is Matrix?" opens the pages again — no choices', (
    tester,
  ) async {
    final store = InMemoryDevicePrefsStore({'welcome_seen': '1'});
    await tester.pumpWidget(_welcomeApp(store, initial: '/host'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('host'));
    await tester.pumpAndSettle();

    expect(find.text('How MoneyLedger works'), findsOneWidget);
    expect(find.text('What is Matrix?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('welcomeNext')));
    await tester.pumpAndSettle();
    expect(find.text('Who sees what'), findsOneWidget);
    expect(find.byKey(const Key('welcomeChoices')), findsNothing);
    // The last page closes the pages again.
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('host'), findsOneWidget);
  });

  group('LocalSetupPage (G40)', () {
    Widget app(InMemoryDevicePrefsStore store) => ProviderScope(
      overrides: [devicePrefsStoreProvider.overrideWithValue(store)],
      child: MaterialApp(
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
        home: const LocalSetupPage(),
      ),
    );

    testWidgets('explains local mode and needs a name', (tester) async {
      final store = InMemoryDevicePrefsStore({'welcome_seen': '1'});
      await tester.pumpWidget(app(store));
      await tester.pumpAndSettle();
      expect(find.textContaining('nothing is sent anywhere'), findsOneWidget);
      expect(find.textContaining('Back up regularly'), findsOneWidget);
      expect(find.byKey(const Key('localSetupAdoptedNotice')), findsNothing);

      await tester.tap(find.byKey(const Key('localStartBtn')));
      await tester.pumpAndSettle();
      expect(find.text('Enter a name'), findsOneWidget);
      expect(store.values.containsKey('local_profile'), isFalse);

      await tester.enterText(find.byKey(const Key('localNameField')), ' Lea ');
      await tester.tap(find.byKey(const Key('localStartBtn')));
      await tester.pumpAndSettle();
      expect(LocalProfile.fromJson(store.values['local_profile'])?.name, 'Lea');
    });

    testWidgets('says where earlier local groups went', (tester) async {
      await tester.pumpWidget(
        app(
          InMemoryDevicePrefsStore({
            'welcome_seen': '1',
            'local_last_adopted_into': '@lea:x.org',
          }),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('localSetupAdoptedNotice')), findsOneWidget);
      expect(find.textContaining('@lea:x.org'), findsOneWidget);
    });
  });

  group('local mode indicator (G40)', () {
    testWidgets('groups page: "Local only" chip, no devices / sign-out', (
      tester,
    ) async {
      await tester.pumpWidget(
        testApp(
          const GroupsPage(),
          overrides: testOverrides(localProfile: 'Lea'),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.byKey(const Key('localModeChip')), findsOneWidget);
      expect(find.text('Local only'), findsOneWidget);
      expect(find.byTooltip('Sign out'), findsNothing);
      expect(find.byIcon(Icons.devices), findsNothing);

      await tester.tap(find.byKey(const Key('localModeChip')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('localModeSheet')), findsOneWidget);
      expect(find.textContaining('never leave this device'), findsOneWidget);
      expect(find.byKey(const Key('localSheetConnect')), findsOneWidget);
      expect(find.byKey(const Key('localSheetBackup')), findsOneWidget);
    });

    testWidgets('settings: connect + delete local data, no sync settings', (
      tester,
    ) async {
      await tester.pumpWidget(
        testApp(
          const SettingsPage(),
          overrides: testOverrides(localProfile: 'Lea'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Your name: Lea'), findsOneWidget);
      // G65: no Matrix account tile / sign-out in local mode.
      expect(find.byKey(const Key('signOutTile')), findsNothing);
      expect(find.byKey(const Key('devicesTile')), findsNothing);
      expect(find.byKey(const Key('connectAccountTile')), findsOneWidget);
      expect(find.byKey(const Key('deleteLocalDataTile')), findsOneWidget);
      expect(find.byKey(const Key('backgroundSyncSwitch')), findsNothing);
      expect(find.byKey(const Key('verifiedOnlySwitch')), findsNothing);
      expect(find.byKey(const Key('backupPageTile')), findsOneWidget);
    });

    testWidgets('German chip', (tester) async {
      await tester.pumpWidget(
        testApp(
          const GroupsPage(),
          locale: const Locale('de'),
          overrides: testOverrides(localProfile: 'Lea'),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('Nur lokal'), findsOneWidget);
    });

    testWidgets('a Matrix session shows no chip', (tester) async {
      await tester.pumpWidget(
        testApp(const GroupsPage(), overrides: testOverrides(isLoggedIn: true)),
      );
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const Key('localModeChip')), findsNothing);
      // G65: sign-out lives on the settings page now.
      expect(find.byKey(const Key('settingsButton')), findsOneWidget);
    });

    testWidgets('members page: names only, no invite', (tester) async {
      await tester.pumpWidget(
        testApp(
          const GroupMembersPage(roomId: 'g'),
          overrides: testOverrides(
            localProfile: 'Lea',
            members: const [
              MemberModel(
                groupId: 'g',
                userId: 'p1',
                displayName: 'Lea',
                matrixId: 'local:self',
                status: 'active',
                updatedAt: 1,
              ),
              MemberModel(
                groupId: 'g',
                userId: 'p2',
                displayName: 'Max',
                status: 'active',
                updatedAt: 1,
              ),
            ],
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const Key('localMembersHint')), findsOneWidget);
      expect(find.byTooltip('Invite by Matrix ID'), findsNothing);
      expect(find.text('local:self'), findsNothing);
      expect(find.text('You (on this device)'), findsOneWidget);

      await tester.tap(find.text('Add person'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('addPersonName')), findsOneWidget);
      expect(find.byKey(const Key('addPersonMatrixId')), findsNothing);
    });
  });
}
