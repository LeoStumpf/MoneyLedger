/// G69: the balance page's *Share* action (U17) and overview (U19), and the
/// groups list order (U20) — at 360 dp, English and German.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:money_ledger/core/database/account_database.dart';
import 'package:money_ledger/core/database/app_database.dart';
import 'package:money_ledger/core/l10n/formatting.dart';
import 'package:money_ledger/core/matrix/transport_provider.dart';
import 'package:money_ledger/core/platform/text_sharer.dart';
import 'package:money_ledger/core/theme/app_theme.dart';
import 'package:money_ledger/features/auth/auth_provider.dart';
import 'package:money_ledger/features/balance/balance_calculator.dart';
import 'package:money_ledger/features/balance/balance_page.dart';
import 'package:money_ledger/features/devices/device_provider.dart';
import 'package:money_ledger/features/expenses/expenses_provider.dart';
import 'package:money_ledger/features/groups/group_archive_provider.dart';
import 'package:money_ledger/features/groups/group_overview_provider.dart';
import 'package:money_ledger/features/groups/group_provider.dart';
import 'package:money_ledger/features/groups/groups_page.dart';
import 'package:money_ledger/models/expense_model.dart';
import 'package:money_ledger/models/group_model.dart';
import 'package:money_ledger/models/member_model.dart';

import 'helpers/fake_auth_gateway.dart';
import 'helpers/fake_device_gateway.dart';
import 'helpers/fake_ledger_network.dart';
import 'helpers/l10n.dart';
import 'helpers/test_providers.dart';

const _g = 'g1';
const _me = '@anna:x.org';
const _ben = '@ben:x.org';

MemberModel _member(String id, String name, {String? mxid}) => MemberModel(
  groupId: _g,
  userId: id,
  displayName: name,
  matrixId: mxid,
  status: 'active',
  updatedAt: 1,
);

final _members = [
  _member(_me, 'Anna', mxid: _me),
  _member(_ben, 'Ben', mxid: _ben),
  _member('p-chris', 'Chris'),
];

const _group = GroupModel(roomId: _g, name: 'Rom 2026', currency: 'EUR');

const _expenses = [
  ExpenseModel(
    id: 'e1',
    roomId: _g,
    description: 'Pizza',
    amountCents: 6000,
    currency: 'EUR',
    paidBy: _me,
    splitsJson: '{"$_me":2000,"$_ben":2000,"p-chris":2000}',
    createdAt: 5000,
    category: 'food',
  ),
  ExpenseModel(
    id: 'e2',
    roomId: _g,
    description: 'Taxi',
    amountCents: 1500,
    currency: 'EUR',
    paidBy: _ben,
    splitsJson: '{"$_me":500,"$_ben":500,"p-chris":500}',
    createdAt: 6000,
    category: 'transport',
  ),
];

const _debts = [
  DebtEntry(from: 'p-chris', to: _me, cents: 2500, currency: 'EUR'),
  DebtEntry(from: _ben, to: _me, cents: 1000, currency: 'EUR'),
];

void _phone(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(360, 780);
  addTearDown(tester.view.reset);
}

List<dynamic> _overrides({
  List<DebtEntry> debts = _debts,
  List<ExpenseModel> expenses = _expenses,
  List<GroupModel> groups = const [_group],
  List<dynamic> extra = const [],
}) => [
  ...testOverrides(
    isLoggedIn: true,
    members: _members,
    groups: groups,
    expenses: expenses,
    debts: debts,
  ),
  currentUserIdProvider.overrideWith((_) => _me),
  currentParticipantProvider.overrideWith((ref, g) async => _members.first),
  appDatabaseProvider.overrideWithValue(
    AppDatabase.signedOut(SignedOutExecutor()),
  ),
  ledgerTransportProvider.overrideWith(
    (ref) => FakeMatrixNetwork().clientFor(_me),
  ),
  authGatewayProvider.overrideWith(
    (ref) async => FakeAuthGateway(initialUserId: _me),
  ),
  deviceGatewayProvider.overrideWith(
    (ref) async => FakeDeviceGateway(const []),
  ),
  ...extra,
];

Widget _routed(
  Widget page,
  List<dynamic> overrides,
  Locale locale, {
  double textScale = 1,
}) {
  final router = GoRouter(
    initialLocation: '/page',
    routes: [GoRoute(path: '/page', builder: (_, _) => page)],
  );
  return ProviderScope(
    overrides: [...overrides],
    child: MaterialApp.router(
      theme: AppTheme.light(isWeb: false),
      locale: locale,
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      routerConfig: router,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
    ),
  );
}

/// Records what the page hands to the share sheet; [available] false =
/// no share sheet (desktop browser).
class _Recorder {
  final bool available;
  _Recorder({this.available = true});
  final texts = <String>[];
  final subjects = <String?>[];
  Future<bool> call(String text, {String? subject}) async {
    texts.add(text);
    subjects.add(subject);
    return available;
  }
}

void main() {
  group('balance page: share (U17)', () {
    for (final locale in const [Locale('en'), Locale('de')]) {
      testWidgets('shares who pays whom (${locale.languageCode})', (
        tester,
      ) async {
        _phone(tester);
        final l = locale.languageCode == 'de' ? de : en;
        final rec = _Recorder();
        await tester.pumpWidget(
          _routed(
            const BalancePage(roomId: _g),
            _overrides(extra: [textSharerProvider.overrideWithValue(rec.call)]),
            locale,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byTooltip(l.shareBalances), findsOneWidget);
        await tester.tap(find.byKey(const Key('shareBalances')));
        await tester.pumpAndSettle();
        String money(int c) => formatMoney(c, 'EUR', l.localeName);
        expect(
          rec.texts.single,
          [
            l.shareBalanceTitle('Rom 2026'),
            '',
            'Chris → Anna: ${money(2500)}',
            'Ben → Anna: ${money(1000)}',
            '',
            l.shareFooter,
          ].join('\n'),
        );
        expect(rec.subjects.single, l.shareBalanceTitle('Rom 2026'));
        expect(find.byType(SnackBar), findsNothing);
      });
    }

    testWidgets('no share sheet → copied to the clipboard + snackbar (de)', (
      tester,
    ) async {
      _phone(tester);
      String? clip;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            clip = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final rec = _Recorder(available: false);
      await tester.pumpWidget(
        _routed(
          const BalancePage(roomId: _g),
          _overrides(extra: [textSharerProvider.overrideWithValue(rec.call)]),
          const Locale('de'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('shareBalances')));
      await tester.pumpAndSettle();
      expect(clip, rec.texts.single);
      expect(find.text(de.shareCopiedFallback), findsOneWidget);
    });

    testWidgets('settled with expenses: settled card, overview, share '
        '"Alles ausgeglichen"', (tester) async {
      _phone(tester);
      final rec = _Recorder();
      await tester.pumpWidget(
        _routed(
          const BalancePage(roomId: _g),
          _overrides(
            debts: const [],
            extra: [textSharerProvider.overrideWithValue(rec.call)],
          ),
          const Locale('de'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('allSettledUpCard')), findsOneWidget);
      expect(find.byKey(const Key('stats-EUR')), findsOneWidget);
      await tester.tap(find.byKey(const Key('shareBalances')));
      await tester.pumpAndSettle();
      expect(rec.texts.single, contains('\n\nAlles ausgeglichen.\n\n'));
    });

    testWidgets('nothing at all: the empty state, no share action', (
      tester,
    ) async {
      _phone(tester);
      await tester.pumpWidget(
        _routed(
          const BalancePage(roomId: _g),
          _overrides(debts: const [], expenses: const []),
          const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('allSettledUp')), findsOneWidget);
      expect(find.byKey(const Key('shareBalances')), findsNothing);
      expect(find.byKey(const Key('stats-EUR')), findsNothing);
    });
  });

  group('balance page: overview (U19)', () {
    for (final locale in const [Locale('en'), Locale('de')]) {
      testWidgets('total, paid vs. share, categories '
          '(${locale.languageCode}, 360 dp)', (tester) async {
        _phone(tester);
        final l = locale.languageCode == 'de' ? de : en;
        String money(int c) => formatMoney(c, 'EUR', l.localeName);
        await tester.pumpWidget(
          _routed(const BalancePage(roomId: _g), _overrides(), locale),
        );
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.byKey(const Key('statsCategory-EUR-transport')),
          200,
        );
        await tester.pumpAndSettle();
        expect(find.text(l.statsSection), findsOneWidget);
        expect(find.text(money(7500)), findsOneWidget);
        expect(find.text(l.statsExpenseCount(2)), findsOneWidget);
        // Anna paid 60, her share 25 — shown as "You".
        final anna = find.byKey(const Key('statsPerson-EUR-$_me'));
        expect(
          find.descendant(of: anna, matching: find.text(l.you)),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: anna,
            matching: find.text(l.statsPaid(money(6000))),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: anna,
            matching: find.text(l.statsShare(money(2500))),
          ),
          findsOneWidget,
        );
        expect(find.byKey(const Key('statsCategory-EUR-food')), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('German at 200 % font size: no overflow (person rows too)', (
      tester,
    ) async {
      _phone(tester);
      await tester.pumpWidget(
        _routed(
          const BalancePage(roomId: _g),
          _overrides(),
          const Locale('de'),
          textScale: 2,
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const Key('statsCategory-EUR-transport')),
        200,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('more than five categories: the rest in one row', (
      tester,
    ) async {
      _phone(tester);
      const cats = [
        'food',
        'groceries',
        'transport',
        'accommodation',
        'entertainment',
        'shopping',
        'home',
      ];
      final expenses = [
        for (final (i, c) in cats.indexed)
          ExpenseModel(
            id: 'x$i',
            roomId: _g,
            description: c,
            amountCents: 1000 - i * 10,
            currency: 'EUR',
            paidBy: _me,
            splitsJson: '{"$_me":${1000 - i * 10}}',
            createdAt: i,
            category: c,
          ),
      ];
      await tester.pumpWidget(
        _routed(
          const BalancePage(roomId: _g),
          _overrides(debts: const [], expenses: expenses),
          const Locale('de'),
        ),
      );
      await tester.pumpAndSettle();
      final rest = find.byKey(const Key('statsCategoryRest-EUR'));
      await tester.scrollUntilVisible(rest, 200);
      expect(
        find.descendant(
          of: rest,
          matching: find.text(de.statsMoreCategories(2)),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: rest,
          matching: find.text(formatMoney(950 + 940, 'EUR', 'de')),
        ),
        findsOneWidget,
      );
    });
  });

  testWidgets('groups page: most recently active first, archive unchanged '
      '(U20)', (tester) async {
    _phone(tester);
    const groups = [
      GroupModel(roomId: 'old', name: 'Old trip', currency: 'EUR'),
      GroupModel(roomId: 'arch2', name: 'Archived B', currency: 'EUR'),
      GroupModel(roomId: 'cur', name: 'Current trip', currency: 'EUR'),
      GroupModel(roomId: 'arch1', name: 'Archived A', currency: 'EUR'),
    ];
    GroupOverview at(int? t) => GroupOverview(
      members: const [],
      me: null,
      myBalance: const {},
      lastActivityAt: t,
      recordCount: 0,
    );
    final activity = {'old': 100, 'cur': 900, 'arch2': 50, 'arch1': 999};
    await tester.pumpWidget(
      _routed(
        const GroupsPage(),
        _overrides(
          groups: groups,
          extra: [
            groupOverviewProvider.overrideWith((ref, id) => at(activity[id])),
            groupArchivedProvider.overrideWith(
              (ref, id) => id.startsWith('arch'),
            ),
          ],
        ),
        const Locale('en'),
      ),
    );
    await tester.pumpAndSettle();
    final cur = tester.getTopLeft(find.byKey(const Key('groupCard-cur')));
    final old = tester.getTopLeft(find.byKey(const Key('groupCard-old')));
    expect(cur.dy, lessThan(old.dy));
    // The archived section (collapsed) keeps its DB order when opened.
    await tester.scrollUntilVisible(
      find.byKey(const Key('archivedSection')),
      200,
    );
    await tester.tap(find.byKey(const Key('archivedSection')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('groupCard-arch1')),
      200,
    );
    final b = tester.getTopLeft(find.byKey(const Key('groupCard-arch2')));
    final a = tester.getTopLeft(find.byKey(const Key('groupCard-arch1')));
    expect(b.dy, lessThan(a.dy));
  });
}
