/// G79 group at the end: normal-font truncations at 360 dp (effect line,
/// app-bar titles, the exact cell's suffix) and word-safe section headers.
///
/// DEV-I device pass (G71 §11.5, 360 dp, German, system font size 200 %):
/// rows that put a name next to an amount ellipsized both on a real phone
/// (Roboto) — "Du bekommst 310,…", "C… za… 134,37 €", a former member
/// without a name, split-mode labels broken mid-word ("Gleic/h"), the exact
/// amount cell showing "6 EUR" for 617,28. At a large font size those rows
/// now stack (`isLargeText`), labels shrink to one line, and input cells grow
/// (`scaledCellWidth`). The test font's glyphs are square, so these tests
/// check the layout decisions, not pixel fit; the device screenshots are in
/// the DEV-I report.
library;

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/features/link/link_invite.dart';
import 'package:go_router/go_router.dart';
import 'package:money_ledger/core/database/account_database.dart';
import 'package:money_ledger/core/database/app_database.dart';
import 'package:money_ledger/core/database/daos/groups_dao.dart';
import 'package:money_ledger/core/database/daos/members_dao.dart';
import 'package:money_ledger/core/matrix/transport_provider.dart';
import 'package:money_ledger/core/sync/sync_status_provider.dart';
import 'package:money_ledger/core/theme/app_theme.dart';
import 'package:money_ledger/core/widgets/large_text.dart';
import 'package:money_ledger/core/widgets/settings_section.dart';
import 'package:money_ledger/features/auth/auth_provider.dart';
import 'package:money_ledger/features/balance/balance_calculator.dart';
import 'package:money_ledger/features/balance/balance_page.dart';
import 'package:money_ledger/features/devices/device_provider.dart';
import 'package:money_ledger/features/expenses/add_expense_page.dart';
import 'package:money_ledger/features/expenses/expenses_page.dart';
import 'package:money_ledger/features/expenses/expenses_provider.dart';
import 'package:money_ledger/features/expenses/split_editor.dart';
import 'package:money_ledger/features/groups/group_members_page.dart';
import 'package:money_ledger/features/groups/group_provider.dart';
import 'package:money_ledger/features/groups/groups_page.dart';
import 'package:money_ledger/features/history/restore_points.dart';
import 'package:money_ledger/models/expense_model.dart';
import 'package:money_ledger/models/group_model.dart';
import 'package:money_ledger/models/member_model.dart';

import 'helpers/fake_auth_gateway.dart';
import 'helpers/fake_device_gateway.dart';
import 'helpers/fake_ledger_network.dart';
import 'helpers/in_memory_database.dart';
import 'helpers/l10n.dart';
import 'helpers/test_providers.dart';

const _g = 'g1';
const _me = '@anna:x.org';
const _bob = '@bob:x.org';

MemberModel _member(
  String id,
  String name, {
  String? mxid,
  String status = 'active',
}) => MemberModel(
  groupId: _g,
  userId: id,
  displayName: name,
  matrixId: mxid,
  status: status,
  updatedAt: 1,
);

final _members = [
  _member(_me, 'Anna', mxid: _me),
  _member(_bob, 'Bob', mxid: _bob),
  _member('p-dora', 'Dora', status: 'removed'),
];

const _group = GroupModel(roomId: _g, name: 'Rome 2026', currency: 'EUR');

const _expenses = [
  ExpenseModel(
    id: 'e1',
    roomId: _g,
    description: 'Pizza',
    amountCents: 4200,
    currency: 'EUR',
    paidBy: _me,
    splitsJson: '{"$_me":2100,"$_bob":2100}',
    createdAt: 5000,
    category: 'food',
  ),
];

const _debts = [DebtEntry(from: _bob, to: _me, cents: 2100, currency: 'EUR')];

/// A 360 dp phone; [scale] = the system font size.
void _phone(WidgetTester tester, {double scale = 1, double height = 780}) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(360, height);
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

List<dynamic> _overrides() => [
  ...testOverrides(
    syncStatus: const GroupSyncStatus(pendingPeers: {}, minPeerInSyncAt: null),
    isLoggedIn: true,
    members: _members,
    groups: const [_group],
    expenses: _expenses,
    debts: _debts,
  ),
  currentUserIdProvider.overrideWith((_) => _me),
  currentParticipantProvider.overrideWith((ref, g) async => _members.first),
  snapshotsSupportedProvider.overrideWithValue(true),
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
];

Widget _routed(Widget page, List<dynamic> overrides) {
  final router = GoRouter(
    initialLocation: '/page',
    routes: [GoRoute(path: '/page', builder: (_, _) => page)],
  );
  return ProviderScope(
    overrides: [...overrides],
    child: MaterialApp.router(
      theme: AppTheme.light(isWeb: false),
      locale: const Locale('de'),
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      routerConfig: router,
    ),
  );
}

/// [below] starts under [above] (a line of its own), not next to it.
void _expectBelow(WidgetTester tester, Finder below, Finder above) {
  expect(
    tester.getTopLeft(below).dy,
    greaterThanOrEqualTo(tester.getBottomLeft(above).dy - 1),
  );
}

/// [a] and [b] share a line.
void _expectSameLine(WidgetTester tester, Finder a, Finder b) {
  expect(tester.getTopLeft(a).dy, lessThan(tester.getBottomLeft(b).dy));
  expect(tester.getTopLeft(b).dy, lessThan(tester.getBottomLeft(a).dy));
}

Future<AppDatabase> _seed() async {
  final db = openTestDatabase();
  await GroupsDao(db).upsertGroupLww(
    const GroupsCompanion(
      roomId: Value(_g),
      name: Value('Rome 2026'),
      currency: Value('EUR'),
      updatedAt: Value(1000),
    ),
  );
  for (final (id, name) in [(_me, 'Anna'), (_bob, 'Bob')]) {
    await MembersDao(db).upsertMemberLww(
      MembersCompanion(
        groupId: const Value(_g),
        userId: Value(id),
        displayName: Value(name),
        matrixId: Value(id),
        status: const Value('active'),
        updatedAt: const Value(1),
      ),
    );
  }
  return db;
}

void main() {
  testWidgets('isLargeText / scaledCellWidth follow the font size', (
    tester,
  ) async {
    for (final (scale, large, width) in [
      (1.0, false, 96.0),
      (1.2, false, 115.2),
      (2.0, true, 140.0),
    ]) {
      late bool got;
      late double cell;
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: Builder(
            builder: (context) {
              got = isLargeText(context);
              cell = scaledCellWidth(context, 96, 140);
              return const SizedBox();
            },
          ),
        ),
      );
      expect(got, large, reason: 'scale $scale');
      expect(cell, closeTo(width, 0.01), reason: 'scale $scale');
    }
  });

  group('ledger row', () {
    for (final scale in [1.0, 2.0]) {
      testWidgets('amount + "you lent" at font scale $scale', (tester) async {
        _phone(tester, scale: scale, height: 1400);
        await tester.pumpWidget(
          _routed(const ExpensesPage(roomId: _g), _overrides()),
        );
        await tester.pumpAndSettle();
        final title = find.byKey(const Key('expenseTitle'));
        final amount = find.byKey(const Key('ledgerRowAmount'));
        final effect = find.byKey(const Key('expenseEffect'));
        final payer = find.text(de.youPaid);
        if (scale > 1) {
          // Title, amount, payer and effect each on their own line.
          _expectBelow(tester, amount, title);
          _expectBelow(tester, effect, payer);
          expect(
            tester.renderObject<RenderParagraph>(effect).maxLines,
            2,
            reason: 'the effect may wrap instead of losing its amount',
          );
        } else {
          _expectSameLine(tester, amount, title);
          _expectSameLine(tester, effect, payer);
        }
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(minutes: 1));
      });
    }
  });

  group('balance page', () {
    for (final scale in [1.0, 2.0]) {
      testWidgets('suggested payment at font scale $scale', (tester) async {
        _phone(tester, scale: scale, height: 1400);
        await tester.pumpWidget(
          _routed(const BalancePage(roomId: _g), _overrides()),
        );
        await tester.pumpAndSettle();
        final title = find.byKey(Key('debtTitle-$_bob-$_me-EUR'));
        final amount = find.byKey(Key('debtAmount-$_bob-$_me-EUR'));
        expect(amount, findsOneWidget);
        if (scale > 1) {
          _expectBelow(tester, amount, title);
        } else {
          _expectSameLine(tester, amount, title);
        }
        // "Gesamtausgaben" shrinks on one line instead of breaking mid-word.
        final label = find.byKey(const Key('statsTotalLabel'));
        await tester.scrollUntilVisible(label, 200);
        expect(
          find.ancestor(of: label, matching: find.byType(FittedBox)),
          findsOneWidget,
        );
        expect(tester.renderObject<RenderParagraph>(label).maxLines, 1);
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(minutes: 1));
      });
    }
  });

  group('people page: former member', () {
    for (final scale in [1.0, 2.0]) {
      testWidgets('name stays visible at font scale $scale', (tester) async {
        _phone(tester, scale: scale, height: 1400);
        await tester.pumpWidget(
          _routed(const GroupMembersPage(roomId: _g), [
            currentUserIdProvider.overrideWithValue(_me),
            groupMembersProvider(
              _g,
            ).overrideWith((ref) => Stream.value(_members)),
            ledgerGroupsProvider.overrideWith((_) => Stream.value([_group])),
            linkInviteStateProvider(
              _g,
            ).overrideWith((ref) async => LinkInviteState.unavailable),
            ...FakeTrustStore().overrides(FakeDeviceGateway(const [])),
          ]),
        );
        await tester.pumpAndSettle();
        final name = find.text('Dora');
        await tester.scrollUntilVisible(name, 200);
        if (scale > 1) {
          // (At 1.0 the test font's square glyphs make "Wieder hinzufügen"
          // ~2× wider than Roboto — the device shows the name there.)
          expect(tester.getSize(name).width, greaterThan(0));
          expect(
            tester.renderObject<RenderParagraph>(name).didExceedMaxLines,
            isFalse,
          );
        }
        final readd = find.byKey(const Key('readd-p-dora'));
        expect(readd, findsOneWidget);
        if (scale > 1) {
          // An icon button (tooltip "Wieder hinzufügen") instead of the
          // text button that pushed the name out of the row.
          expect(tester.widget(readd), isA<IconButton>());
          expect(find.byTooltip(de.readd), findsOneWidget);
        } else {
          expect(tester.widget(readd), isA<TextButton>());
          expect(find.text(de.readd), findsOneWidget);
        }
      });
    }
  });

  group('split editor', () {
    for (final scale in [1.0, 2.0]) {
      testWidgets('mode labels + exact cells at font scale $scale', (
        tester,
      ) async {
        _phone(tester, scale: scale, height: 1400);
        await tester.pumpWidget(
          testApp(
            Scaffold(
              body: SingleChildScrollView(
                child: SplitEditor(
                  members: [_member('a', 'Anna'), _member('b', 'Ben')],
                  totalCents: 123456,
                  currency: 'EUR',
                  onPlanChanged: (_) {},
                ),
              ),
            ),
            locale: const Locale('de'),
          ),
        );
        await tester.pumpAndSettle();
        for (final label in [de.splitEqual, de.splitExact, de.splitShares]) {
          final text = find.text(label);
          expect(
            find.ancestor(of: text, matching: find.byType(FittedBox)),
            findsOneWidget,
            reason: '$label shrinks instead of breaking mid-word',
          );
          expect(tester.renderObject<RenderParagraph>(text).maxLines, 1);
        }
        await tester.tap(find.text(de.splitExact));
        await tester.pumpAndSettle();
        final cell = find.byKey(const Key('splitExactCell')).first;
        final width = tester.getSize(cell).width;
        final suffix = find.descendant(of: cell, matching: find.text('EUR'));
        if (scale > 1) {
          expect(width, greaterThan(96));
          expect(suffix, findsNothing, reason: 'room for the amount');
        } else {
          expect(width, 96);
          // G79: "617,28" + "EUR" don't fit 96 dp together (in the test
          // font) → the suffix gives way instead of cutting the value; the
          // suffix-when-it-fits case is the G79 group below.
          expect(suffix, findsNothing);
        }
      });
    }
  });

  group('groups page', () {
    testWidgets('monogram stays on one line at font scale 2', (tester) async {
      _phone(tester, scale: 2);
      await tester.pumpWidget(
        testApp(
          const Scaffold(
            body: Center(
              child: GroupBadge(id: _g, name: 'Ski weekend'),
            ),
          ),
        ),
      );
      final initials = find.text('SW');
      expect(
        find.ancestor(of: initials, matching: find.byType(FittedBox)),
        findsOneWidget,
      );
      expect(tester.renderObject<RenderParagraph>(initials).maxLines, 1);
      // Painted (scaled) width fits the ring.
      expect(
        tester.getRect(initials).width,
        lessThanOrEqualTo(tester.getSize(find.byType(GroupBadge)).width),
      );
    });
  });

  group('item editor (G77)', () {
    for (final scale in [1.0, 2.0]) {
      testWidgets('name / amount at font scale $scale', (tester) async {
        _phone(tester, scale: scale, height: 2400);
        final db = await _seed();
        addTearDown(db.close);
        final net = FakeMatrixNetwork();
        await tester.pumpWidget(
          _routed(const AddExpensePage(roomId: _g), [
            ...signingUiOverrides(),
            appDatabaseProvider.overrideWithValue(db),
            ledgerTransportProvider.overrideWith((ref) => net.clientFor(_me)),
          ]),
        );
        await tester.pumpAndSettle();
        await tester.enterText(find.byKey(const Key('expenseAmount')), '10');
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byKey(const Key('splitItemize')));
        await tester.tap(find.byKey(const Key('splitItemize')));
        await tester.pumpAndSettle();
        final name = find.byKey(const Key('itemName-0'));
        final amount = find.byKey(const Key('itemAmount-0'));
        if (scale > 1) {
          _expectBelow(tester, amount, name);
          // The amount field spans the card instead of a 2/5 column.
          expect(
            tester.getSize(amount).width,
            greaterThan(tester.getSize(name).width * 0.8),
          );
        } else {
          _expectSameLine(tester, amount, name);
        }
      });
    }
  });

  group('G79', () {
    testWidgets('ledger row: the effect wraps instead of losing its amount '
        '(360 dp, normal font)', (tester) async {
      _phone(tester, height: 1400);
      await tester.pumpWidget(
        _routed(const ExpensesPage(roomId: _g), _overrides()),
      );
      await tester.pumpAndSettle();
      final effect = tester.renderObject<RenderParagraph>(
        find.byKey(const Key('expenseEffect')),
      );
      expect(effect.maxLines, 2);
      expect(effect.didExceedMaxLines, isFalse, reason: 'nothing cut');
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(minutes: 1));
    });

    for (final locale in const [Locale('en'), Locale('de')]) {
      testWidgets('app-bar title fits at 360 dp (${locale.languageCode})', (
        tester,
      ) async {
        _phone(tester);
        final l = locale.languageCode == 'de' ? de : en;
        await tester.pumpWidget(
          testApp(
            Scaffold(
              appBar: AppBar(
                title: AppBarTitle(l.editExpense),
                actions: [
                  IconButton(onPressed: () {}, icon: const Icon(Icons.copy)),
                  IconButton(onPressed: () {}, icon: const Icon(Icons.delete)),
                ],
              ),
            ),
            locale: locale,
          ),
        );
        await tester.pumpAndSettle();
        final title = tester.renderObject<RenderParagraph>(
          find.text(l.editExpense),
        );
        expect(title.didExceedMaxLines, isFalse, reason: 'not ellipsized');
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('a short app-bar title keeps its size', (tester) async {
      _phone(tester);
      await tester.pumpWidget(
        testApp(Scaffold(appBar: AppBar(title: AppBarTitle(en.balanceTitle)))),
      );
      await tester.pumpAndSettle();
      final title = tester.renderObject<RenderParagraph>(
        find.text(en.balanceTitle),
      );
      expect(title.textScaler, isNot(isA<ScaledTextScaler>()));
      expect(title.maxLines, 1);
    });

    for (final locale in const [Locale('en'), Locale('de')]) {
      testWidgets('exact cell: suffix only while it fits next to the value '
          '(${locale.languageCode})', (tester) async {
        _phone(tester, height: 1400);
        await tester.pumpWidget(
          testApp(
            Scaffold(
              body: SingleChildScrollView(
                child: SplitEditor(
                  members: [_member('a', 'Anna'), _member('b', 'Ben')],
                  totalCents: 0,
                  currency: 'CHF',
                  onPlanChanged: (_) {},
                ),
              ),
            ),
            locale: locale,
          ),
        );
        await tester.pumpAndSettle();
        final l = locale.languageCode == 'de' ? de : en;
        await tester.tap(find.text(l.splitExact));
        await tester.pumpAndSettle();
        final cell = find.byKey(const Key('splitExactCell')).first;
        Finder suffix() =>
            find.descendant(of: cell, matching: find.text('CHF'));
        expect(suffix(), findsOneWidget, reason: 'empty row: room enough');
        await tester.enterText(
          find.descendant(of: cell, matching: find.byType(TextField)),
          '411,50',
        );
        await tester.pump();
        expect(suffix(), findsNothing, reason: 'the value keeps the room');
        expect(tester.getSize(cell).width, 96, reason: 'cell not widened');
      });
    }

    testWidgets('section header: one long word shrinks instead of breaking '
        'mid-word (360 dp, 200 %, DE)', (tester) async {
      _phone(tester, scale: 2);
      await tester.pumpWidget(
        testApp(
          Scaffold(
            body: ListView(
              children: [
                SettingsSectionHeader(de.restorePointsTitle),
                SettingsSectionHeader(de.backupUndoSection),
              ],
            ),
          ),
          locale: const Locale('de'),
        ),
      );
      await tester.pumpAndSettle();
      final long = tester.renderObject<RenderParagraph>(
        find.text(de.restorePointsTitle.toUpperCase()),
      );
      final fontSize = long.text.style!.fontSize!;
      final lineHeight = long.textScaler.scale(fontSize) * 1.5;
      expect(
        long.size.height,
        lessThan(lineHeight),
        reason: 'one line — the word is not broken',
      );
      expect(long.textScaler.scale(fontSize), lessThan(fontSize * 2));
      // Words that fit keep the user's font size (and wrap between words).
      final other = tester.renderObject<RenderParagraph>(
        find.text(de.backupUndoSection.toUpperCase()),
      );
      expect(other.textScaler.scale(fontSize), closeTo(fontSize * 2, 0.01));
    });
  });
}
