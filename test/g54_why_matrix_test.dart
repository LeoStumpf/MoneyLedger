/// G54: the calm "Why Matrix?" page (design doc §10.2 / §10.3) — its three
/// pages and the action that fits the session, the entry points (link
/// group ⋮, How it works, the link disclosure, the no-account sheet, the
/// one-time groups-page hint) and the reordered welcome choices (EN + DE,
/// 360 dp, 200 % font).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:money_ledger/core/session/app_session.dart';
import 'package:money_ledger/core/session/device_prefs.dart';
import 'package:money_ledger/features/expenses/expenses_page.dart';
import 'package:money_ledger/features/groups/group_provider.dart';
import 'package:money_ledger/features/groups/groups_page.dart';
import 'package:money_ledger/features/link/link_invite.dart';
import 'package:money_ledger/features/welcome/welcome_page.dart';
import 'package:money_ledger/features/welcome/why_matrix_hint.dart';
import 'package:money_ledger/features/welcome/why_matrix_page.dart';
import 'package:money_ledger/models/expense_model.dart';
import 'package:money_ledger/models/group_model.dart';
import 'package:money_ledger/models/member_model.dart';

import 'helpers/l10n.dart';
import 'helpers/test_providers.dart';

const _g = 'g1';

const _group = GroupModel(
  roomId: _g,
  name: 'Trip',
  currency: 'EUR',
  updatedAt: 1,
);

const _me = MemberModel(
  groupId: _g,
  userId: 'p-me',
  displayName: 'Anna',
  status: 'active',
  updatedAt: 1,
);

List<ExpenseModel> _expenses(int n) => [
  for (var i = 0; i < n; i++)
    ExpenseModel(
      id: 'e$i',
      roomId: _g,
      description: 'Dinner $i',
      amountCents: 1000,
      currency: 'EUR',
      paidBy: 'p-me',
      splitsJson: '{"p-me":1000}',
      createdAt: 1000 + i,
      updatedAt: 1000 + i,
    ),
];

/// A router with the page under test plus placeholders for where it leads.
Widget _app(
  String initial, {
  required List<dynamic> overrides,
  Locale locale = const Locale('en'),
}) {
  final router = GoRouter(
    initialLocation: initial,
    routes: [
      GoRoute(
        path: '/host',
        builder: (context, _) => Scaffold(
          body: TextButton(
            onPressed: () => context.push(kWhyMatrixLocation),
            child: const Text('host'),
          ),
        ),
      ),
      GoRoute(
        path: kWhyMatrixLocation,
        builder: (_, _) => const WhyMatrixPage(),
      ),
      GoRoute(path: '/welcome', builder: (_, _) => const WelcomePage()),
      GoRoute(
        path: '/how-it-works',
        builder: (_, s) => WelcomePage(
          revisit: true,
          initialTopic: WelcomeTopic.fromName(s.uri.queryParameters['topic']),
        ),
      ),
      GoRoute(path: '/groups', builder: (_, _) => const GroupsPage()),
      GoRoute(
        path: '/groups/:id/expenses',
        builder: (_, _) => const ExpensesPage(roomId: _g),
      ),
      for (final p in ['/login', '/register', '/local-setup', '/join'])
        GoRoute(
          path: p,
          builder: (_, _) => Scaffold(body: Text('page:$p')),
        ),
    ],
  );
  return ProviderScope(
    overrides: [...overrides],
    child: MaterialApp.router(
      locale: locale,
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      routerConfig: router,
    ),
  );
}

Future<void> _toLast(WidgetTester tester) async {
  for (var i = 0; i < 2; i++) {
    await tester.tap(find.byKey(const Key('whyMatrixNext')));
    await tester.pumpAndSettle();
  }
}

void main() {
  group('pure', () {
    test('whyMatrixOffer follows the session', () {
      expect(whyMatrixOffer(AppSessionKind.local), WhyMatrixOffer.connect);
      expect(whyMatrixOffer(AppSessionKind.signedOut), WhyMatrixOffer.signIn);
      expect(whyMatrixOffer(AppSessionKind.matrix), WhyMatrixOffer.signedIn);
      expect(whyMatrixOffer(AppSessionKind.loading), WhyMatrixOffer.later);
      expect(
        whyMatrixOffer(AppSessionKind.local, infoOnly: true),
        WhyMatrixOffer.later,
      );
      expect(
        whyMatrixOffer(AppSessionKind.signedOut, infoOnly: true),
        WhyMatrixOffer.later,
      );
      expect(
        whyMatrixOffer(AppSessionKind.matrix, infoOnly: true),
        WhyMatrixOffer.signedIn,
      );
    });

    test('the hint: no account, not dismissed, a link group with ≥ 10 '
        'records', () {
      bool show({
        bool noAccount = true,
        bool? dismissed = false,
        List<int> counts = const [3, 10],
      }) => shouldShowWhyMatrixHint(
        noAccount: noAccount,
        dismissed: dismissed,
        linkGroupRecordCounts: counts,
      );
      expect(show(), isTrue);
      expect(show(counts: const [9, 2]), isFalse);
      expect(show(counts: const []), isFalse);
      expect(show(dismissed: true), isFalse);
      expect(show(dismissed: null), isFalse, reason: 'still loading');
      expect(show(noAccount: false), isFalse);
    });
  });

  group('WhyMatrixPage', () {
    testWidgets('no account: three pages, then Connect → connecting + '
        'login page', (tester) async {
      final store = InMemoryDevicePrefsStore({
        'welcome_seen': '1',
        'local_profile': '{"name":"Anna","created_at":1}',
      });
      await tester.pumpWidget(
        _app(
          kWhyMatrixLocation,
          overrides: [
            devicePrefsStoreProvider.overrideWithValue(store),
            matrixStoreExistsProvider.overrideWith((ref) async => false),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Why Matrix?'), findsOneWidget);
      expect(find.text('Links are easy'), findsOneWidget);
      await tester.tap(find.byKey(const Key('whyMatrixNext')));
      await tester.pumpAndSettle();
      expect(find.text("There's another mode"), findsOneWidget);
      expect(find.textContaining('Matrix is free too'), findsOneWidget);
      for (final topic in [
        'Who can see and change a group',
        'Removing someone',
        'New or lost phone',
        'Who sees what',
      ]) {
        await tester.scrollUntilVisible(
          find.text(topic),
          200,
          scrollable: find.descendant(
            of: find.byKey(const Key('whyMatrixCompare')),
            matching: find.byType(Scrollable),
          ),
        );
        expect(find.text(topic), findsOneWidget);
      }
      expect(find.textContaining('Link: anyone who has the link'), findsOne);
      await tester.tap(find.byKey(const Key('whyMatrixNext')));
      await tester.pumpAndSettle();
      expect(find.text('Ready when you are'), findsOneWidget);
      expect(find.textContaining('keep their link'), findsOneWidget);
      expect(find.byKey(const Key('whyMatrixNext')), findsNothing);
      expect(find.byKey(const Key('whyMatrixSignIn')), findsNothing);

      await tester.ensureVisible(find.byKey(const Key('whyMatrixConnect')));
      await tester.tap(find.byKey(const Key('whyMatrixConnect')));
      await tester.pumpAndSettle();
      expect(store.values['local_connecting'], '1');
      expect(find.text('page:/login'), findsOneWidget);
    });

    testWidgets('"Not now" goes back', (tester) async {
      await tester.pumpWidget(
        _app('/host', overrides: testOverrides(localProfile: 'Anna')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('host'));
      await tester.pumpAndSettle();
      await _toLast(tester);
      await tester.ensureVisible(find.byKey(const Key('whyMatrixNotNow')));
      await tester.tap(find.byKey(const Key('whyMatrixNotNow')));
      await tester.pumpAndSettle();
      expect(find.text('host'), findsOneWidget);
    });

    for (final (key, page) in [
      ('whyMatrixSignIn', '/login'),
      ('whyMatrixCreateAccount', '/register'),
    ]) {
      testWidgets('signed out (welcome): $key marks the welcome seen → $page', (
        tester,
      ) async {
        final store = InMemoryDevicePrefsStore();
        await tester.pumpWidget(
          _app(
            kWhyMatrixLocation,
            overrides: [
              devicePrefsStoreProvider.overrideWithValue(store),
              matrixStoreExistsProvider.overrideWith((ref) async => false),
            ],
          ),
        );
        await tester.pumpAndSettle();
        await _toLast(tester);
        expect(find.byKey(const Key('whyMatrixConnect')), findsNothing);
        await tester.ensureVisible(find.byKey(Key(key)));
        await tester.tap(find.byKey(Key(key)));
        await tester.pumpAndSettle();
        expect(store.values['welcome_seen'], '1');
        expect(find.text('page:$page'), findsOneWidget);
      });
    }

    testWidgets('a Matrix account: no sign-in, only Done', (tester) async {
      await tester.pumpWidget(
        _app('/host', overrides: testOverrides(isLoggedIn: true)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('host'));
      await tester.pumpAndSettle();
      await _toLast(tester);
      expect(find.textContaining('already signed in'), findsOneWidget);
      expect(find.byKey(const Key('whyMatrixConnect')), findsNothing);
      expect(find.byKey(const Key('whyMatrixSignIn')), findsNothing);
      await tester.ensureVisible(find.byKey(const Key('whyMatrixDone')));
      await tester.tap(find.byKey(const Key('whyMatrixDone')));
      await tester.pumpAndSettle();
      expect(find.text('host'), findsOneWidget);
    });

    testWidgets('German', (tester) async {
      await tester.pumpWidget(
        _app(
          kWhyMatrixLocation,
          locale: const Locale('de'),
          overrides: testOverrides(localProfile: 'Anna'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Warum Matrix?'), findsOneWidget);
      expect(find.text('Links sind einfach'), findsOneWidget);
      await _toLast(tester);
      expect(find.text('Wenn du so weit bist'), findsOneWidget);
      expect(find.text('Matrix-Konto verbinden'), findsOneWidget);
      expect(find.text('Jetzt nicht'), findsOneWidget);
    });
  });

  group('entry points', () {
    testWidgets('How it works: the Matrix page links it', (tester) async {
      await tester.pumpWidget(
        _app('/how-it-works?topic=matrix', overrides: testOverrides()),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('welcomeWhyMatrix')));
      await tester.tap(find.byKey(const Key('welcomeWhyMatrix')));
      await tester.pumpAndSettle();
      expect(find.byType(WhyMatrixPage), findsOneWidget);
    });

    testWidgets('the link disclosure opens it read-only (no connect), Done '
        'returns to the disclosure', (tester) async {
      await tester.pumpWidget(
        testApp(
          const LinkDisclosurePage(),
          overrides: testOverrides(localProfile: 'Anna'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const Key('linkDisclosureWhyMatrix')),
      );
      await tester.tap(find.byKey(const Key('linkDisclosureWhyMatrix')));
      await tester.pumpAndSettle();
      await _toLast(tester);
      expect(find.byKey(const Key('whyMatrixConnect')), findsNothing);
      expect(find.textContaining('any time later'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('whyMatrixDone')));
      await tester.tap(find.byKey(const Key('whyMatrixDone')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('linkDisclosure')), findsOneWidget);
    });

    for (final state in [LinkInviteState.open, LinkInviteState.canOpen]) {
      testWidgets('group ⋮: "Why Matrix?" only in a link group ($state)', (
        tester,
      ) async {
        await tester.pumpWidget(
          _app(
            '/groups/$_g/expenses',
            overrides: [
              ...testOverrides(
                localProfile: 'Anna',
                members: const [_me],
                groups: const [_group],
              ),
              currentParticipantProvider.overrideWith((ref, g) async => _me),
              linkInviteStateProvider.overrideWith((ref, g) async => state),
            ],
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('groupMenu')));
        await tester.pumpAndSettle();
        final item = find.byKey(const Key('whyMatrixMenuItem'));
        if (state != LinkInviteState.open) {
          expect(item, findsNothing);
          await tester.pumpWidget(const SizedBox());
          await tester.pump(const Duration(seconds: 5));
          return;
        }
        await tester.tap(item);
        await tester.pumpAndSettle();
        expect(find.byType(WhyMatrixPage), findsOneWidget);
        // The link group's sync button started the (idle) link engine.
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 5));
      });
    }

    testWidgets('the no-account sheet links it', (tester) async {
      await tester.pumpWidget(
        _app('/groups', overrides: testOverrides(localProfile: 'Anna')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('localModeChip')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('localSheetWhyMatrix')));
      await tester.tap(find.byKey(const Key('localSheetWhyMatrix')));
      await tester.pumpAndSettle();
      expect(find.byType(WhyMatrixPage), findsOneWidget);
    });
  });

  group('groups-page hint (once)', () {
    List<dynamic> overrides({
      int records = 10,
      bool dismissed = false,
      String? localProfile = 'Anna',
      Set<String> links = const {_g},
      void Function()? onDismiss,
    }) => [
      ...testOverrides(
        localProfile: localProfile,
        isLoggedIn: localProfile == null,
        groups: const [_group],
        members: const [_me],
        expenses: _expenses(records),
        linkGroupIds: links,
        whyMatrixHintDismissed: dismissed,
      ),
      if (onDismiss != null)
        dismissWhyMatrixHintProvider.overrideWithValue(() async => onDismiss()),
    ];

    testWidgets('shown once a link group has 10 records; Tell me more '
        'dismisses it and opens the page', (tester) async {
      var dismissed = 0;
      await tester.pumpWidget(
        _app('/groups', overrides: overrides(onDismiss: () => dismissed++)),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('whyMatrixHint')), findsOneWidget);
      await tester.tap(find.byKey(const Key('whyMatrixHintMore')));
      await tester.pumpAndSettle();
      expect(dismissed, 1);
      expect(find.byType(WhyMatrixPage), findsOneWidget);
    });

    testWidgets('Not now dismisses it', (tester) async {
      var dismissed = 0;
      await tester.pumpWidget(
        _app('/groups', overrides: overrides(onDismiss: () => dismissed++)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('whyMatrixHintDismiss')));
      await tester.pumpAndSettle();
      expect(dismissed, 1);
    });

    for (final (name, o) in [
      ('9 records', overrides(records: 9)),
      ('dismissed', overrides(dismissed: true)),
      ('not a link group', overrides(links: const {})),
      ('a Matrix account', overrides(localProfile: null)),
    ]) {
      testWidgets('hidden: $name', (tester) async {
        await tester.pumpWidget(_app('/groups', overrides: o));
        await tester.pumpAndSettle();
        expect(find.text('Trip'), findsOneWidget);
        expect(find.byKey(const Key('whyMatrixHint')), findsNothing);
      });
    }
  });

  group('360 dp, 200 % font', () {
    void small(WidgetTester tester) {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(360, 740);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    }

    for (final locale in [const Locale('en'), const Locale('de')]) {
      final l = locale.languageCode == 'de' ? de : en;
      testWidgets('${locale.languageCode}: Why Matrix pages fit', (
        tester,
      ) async {
        small(tester);
        await tester.pumpWidget(
          _app(
            kWhyMatrixLocation,
            locale: locale,
            overrides: testOverrides(localProfile: 'Anna'),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        for (var i = 0; i < 2; i++) {
          await tester.tap(find.byKey(const Key('whyMatrixNext')));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
        expect(find.text(l.whyMatrixReadyTitle), findsOneWidget);
      });

      testWidgets('${locale.languageCode}: welcome pages + choices fit', (
        tester,
      ) async {
        small(tester);
        await tester.pumpWidget(
          _app(
            '/welcome',
            locale: locale,
            overrides: [
              devicePrefsStoreProvider.overrideWithValue(
                InMemoryDevicePrefsStore(),
              ),
              matrixStoreExistsProvider.overrideWith((ref) async => false),
            ],
          ),
        );
        await tester.pumpAndSettle();
        for (var i = 0; i < 4; i++) {
          expect(tester.takeException(), isNull);
          await tester.tap(find.byKey(const Key('welcomeNext')));
          await tester.pumpAndSettle();
        }
        expect(find.text(l.welcomeSecureHeading), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('${locale.languageCode}: groups-page hint fits', (
        tester,
      ) async {
        small(tester);
        await tester.pumpWidget(
          _app(
            '/groups',
            locale: locale,
            overrides: testOverrides(
              localProfile: 'Anna',
              groups: const [_group],
              members: const [_me],
              expenses: _expenses(10),
              linkGroupIds: const {_g},
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.scrollUntilVisible(
          find.byKey(const Key('whyMatrixHintMore')),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.byKey(const Key('whyMatrixHint')), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
