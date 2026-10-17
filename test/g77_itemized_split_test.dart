/// G77: itemized split — the SplitEditor's *Split by items…* opens the item
/// editor; its result lands in Exact as typed amounts and is saved as the
/// usual cents map. Pure math: `split_calculator_test.dart` (G77 group).
library;

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/database/app_database.dart';
import 'package:money_ledger/core/database/daos/expenses_dao.dart';
import 'package:money_ledger/core/database/daos/groups_dao.dart';
import 'package:money_ledger/core/database/daos/members_dao.dart';
import 'package:money_ledger/core/matrix/ledger_transport.dart';
import 'package:money_ledger/core/matrix/transport_provider.dart';
import 'package:money_ledger/core/theme/app_theme.dart';
import 'package:money_ledger/features/expenses/add_expense_page.dart';
import 'package:money_ledger/features/expenses/expenses_provider.dart';
import 'package:money_ledger/features/expenses/item_split_page.dart';
import 'package:money_ledger/features/expenses/split_editor.dart';
import 'package:money_ledger/models/member_model.dart';

import 'helpers/fake_ledger_network.dart';
import 'helpers/in_memory_database.dart';
import 'helpers/test_providers.dart';

MemberModel _m(String id, String name, {String status = 'active'}) =>
    MemberModel(
      groupId: 'g1',
      userId: id,
      displayName: name,
      status: status,
      updatedAt: 1,
    );

final _members = [_m('a', 'Anna'), _m('b', 'Bob'), _m('c', 'Carl')];

/// A 360 × 780 dp phone at [scale] text size.
void _phone(WidgetTester tester, {double scale = 1}) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(360, 780);
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

void main() {
  late ValueNotifier<int> total;
  SplitPlan? plan;

  setUp(() {
    total = ValueNotifier(0);
    plan = null;
  });

  Future<void> pumpEditor(
    WidgetTester tester, {
    int totalCents = 3000,
    List<MemberModel>? members,
    Map<String, int>? initial,
    Locale? locale,
    String currency = 'EUR',
  }) async {
    total.value = totalCents;
    await tester.pumpWidget(
      testApp(
        Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(Insets.page),
            child: ValueListenableBuilder<int>(
              valueListenable: total,
              builder: (_, t, _) => SplitEditor(
                members: members ?? _members,
                totalCents: t,
                currency: currency,
                initialSplit: initial,
                onPlanChanged: (p) => plan = p,
                onSetTotal: (c) => total.value = c,
              ),
            ),
          ),
        ),
        locale: locale,
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tapKey(WidgetTester tester, String key) async {
    final f = find.byKey(Key(key));
    await tester.ensureVisible(f);
    await tester.pumpAndSettle();
    await tester.tap(f);
    await tester.pumpAndSettle();
  }

  Future<void> enter(WidgetTester tester, String key, String text) async {
    final f = find.byKey(Key(key));
    await tester.ensureVisible(f);
    await tester.enterText(f, text);
    await tester.pumpAndSettle();
  }

  /// The receipt of the examples: Pizza 12 € (Anna), Pasta 9 € (Bob),
  /// Wine 2 × 3 € (everyone) — 27 € of items.
  Future<void> enterReceipt(WidgetTester tester) async {
    await tapKey(tester, 'splitItemize');
    expect(find.byType(ItemSplitPage), findsOneWidget);
    await enter(tester, 'itemName-0', 'Pizza');
    await enter(tester, 'itemAmount-0', '12');
    await tapKey(tester, 'itemPerson-0-b');
    await tapKey(tester, 'itemPerson-0-c');
    await tapKey(tester, 'itemsAdd');
    await enter(tester, 'itemAmount-1', '9');
    // "Everyone" toggles all off, then Bob on.
    await tapKey(tester, 'itemEveryone-1');
    await tapKey(tester, 'itemPerson-1-b');
    await tapKey(tester, 'itemsAdd');
    await enter(tester, 'itemAmount-2', '2*3'); // a pasted expression (G75/G79)
  }

  FilledButton applyButton(WidgetTester tester) =>
      tester.widget<FilledButton>(find.byKey(const Key('itemsApply')));

  testWidgets('items → Exact amounts; the rest is shared proportionally', (
    tester,
  ) async {
    _phone(tester);
    await pumpEditor(tester);
    await enterReceipt(tester);

    expect(find.text('Rest (tax, tip, not itemized): €3.00'), findsOneWidget);
    expect(find.text('€2.00 each'), findsOneWidget); // the wine
    expect(find.text('= €6.00'), findsOneWidget);
    // Subtotals 14 / 11 / 2 → the 3 € rest in proportion.
    expect(find.byKey(const Key('itemsResult-a')), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('itemsResult-a'))).data,
      '€15.56',
    );

    await tapKey(tester, 'itemsApply');
    expect(find.byType(ItemSplitPage), findsNothing);
    expect(plan!.mode, SplitMode.exact);
    expect(plan!.exact, {'a': 1556, 'b': 1222, 'c': 222});
    expect(plan!.resolve(3000).isValid, isTrue);
    expect(find.text('Adds up to the total'), findsOneWidget);
    expect(find.widgetWithText(TextField, '15.56'), findsOneWidget);

    // The items stay while the form is open.
    await tapKey(tester, 'splitItemize');
    expect(find.widgetWithText(TextField, 'Pizza'), findsOneWidget);
    expect(find.widgetWithText(TextField, '2*3'), findsOneWidget);
    // Back without applying changes nothing.
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(plan!.exact, {'a': 1556, 'b': 1222, 'c': 222});
  });

  testWidgets('the rest equally among everyone with an item', (tester) async {
    _phone(tester);
    await pumpEditor(tester);
    await enterReceipt(tester);
    await tester.ensureVisible(find.text('Equally').last);
    await tester.tap(find.text('Equally').last);
    await tester.pumpAndSettle();
    await tapKey(tester, 'itemsApply');
    expect(plan!.exact, {'a': 1500, 'b': 1200, 'c': 300});
  });

  testWidgets('items over the total: "too much", Set total to the sum', (
    tester,
  ) async {
    _phone(tester);
    await pumpEditor(tester, totalCents: 1000);
    await tapKey(tester, 'splitItemize');
    await enter(tester, 'itemAmount-0', '12');
    expect(find.text('€2.00 too much'), findsOneWidget);
    expect(applyButton(tester).onPressed, isNull);

    await tapKey(tester, 'itemsSetTotal');
    expect(find.text('Total: €12.00'), findsOneWidget);
    await tapKey(tester, 'itemsApply');
    expect(total.value, 1200);
    expect(plan!.exact, {'a': 400, 'b': 400, 'c': 400});
    expect(plan!.resolve(total.value).isValid, isTrue);
  });

  testWidgets('no amount yet: the items sum becomes the total', (tester) async {
    _phone(tester);
    await pumpEditor(tester, totalCents: 0);
    await tapKey(tester, 'splitItemize');
    expect(find.text('No amount yet'), findsOneWidget);
    await enter(tester, 'itemAmount-0', '10');
    expect(applyButton(tester).onPressed, isNull);
    await tapKey(tester, 'itemsSetTotal');
    await tapKey(tester, 'itemsApply');
    expect(total.value, 1000);
    expect(plan!.exact, {'a': 334, 'b': 333, 'c': 333});
  });

  testWidgets('an item with nobody or an invalid amount blocks applying', (
    tester,
  ) async {
    _phone(tester);
    await pumpEditor(tester);
    await tapKey(tester, 'splitItemize');
    expect(find.text('Enter at least one item amount'), findsOneWidget);
    await enter(tester, 'itemAmount-0', '12+');
    expect(find.text('Invalid number'), findsOneWidget);
    expect(applyButton(tester).onPressed, isNull);
    await enter(tester, 'itemAmount-0', '12');
    expect(applyButton(tester).onPressed, isNotNull);
    await tapKey(tester, 'itemEveryone-0');
    expect(find.text('Select at least one person'), findsOneWidget);
    expect(applyButton(tester).onPressed, isNull);
    // Removing the last item leaves a fresh blank one.
    await tapKey(tester, 'itemRemove-0');
    expect(find.byKey(const Key('itemAmount-0')), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('itemAmount-0')))
          .controller!
          .text,
      '',
    );
  });

  testWidgets('0-decimal currency: whole yen', (tester) async {
    _phone(tester);
    await pumpEditor(tester, totalCents: 120000, currency: 'JPY');
    await tapKey(tester, 'splitItemize');
    await enter(tester, 'itemAmount-0', '1000');
    await tester.ensureVisible(find.text('Equally').last);
    await tester.tap(find.text('Equally').last);
    await tester.pumpAndSettle();
    await tapKey(tester, 'itemsApply');
    expect(plan!.exact, {'a': 40100, 'b': 40000, 'c': 39900});
  });

  testWidgets('former members are not offered as item people', (tester) async {
    _phone(tester);
    await pumpEditor(
      tester,
      members: [
        ..._members,
        _m('d', 'Dora', status: 'removed'),
      ],
      initial: const {'a': 1000, 'd': 2000},
    );
    await tapKey(tester, 'splitItemize');
    expect(find.byKey(const Key('itemPerson-0-d')), findsNothing);
    await enter(tester, 'itemAmount-0', '30');
    await tapKey(tester, 'itemsApply');
    // Dora's row becomes 0 (not involved).
    expect(plan!.exact, {'a': 1000, 'b': 1000, 'c': 1000});
  });

  for (final locale in [const Locale('en'), const Locale('de')]) {
    testWidgets('360 dp at 200 % font, ${locale.languageCode}: no overflow', (
      tester,
    ) async {
      _phone(tester, scale: 2);
      await pumpEditor(
        tester,
        locale: locale,
        members: [
          _m('a', 'Anna-Lena Musterfrau'),
          _m('b', 'moneyledger-test-b-c725'),
          _m('c', 'Carl'),
        ],
      );
      expect(tester.takeException(), isNull);
      await tapKey(tester, 'splitItemize');
      await enter(tester, 'itemName-0', 'Pizza Margherita');
      await enter(tester, 'itemAmount-0', '12,50');
      await tapKey(tester, 'itemPerson-0-b');
      await tapKey(tester, 'itemsAdd');
      await enter(tester, 'itemAmount-1', '9');
      expect(find.byKey(const Key('itemsRemaining')), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('itemsRemaining')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tapKey(tester, 'itemsApply');
      expect(tester.takeException(), isNull);
      expect(plan!.resolve(3000).isValid, isTrue);
    });
  }

  group('AddExpensePage', () {
    const alice = '@alice:x.org';
    const bob = '@bob:x.org';

    Future<AppDatabase> seed() async {
      final db = openTestDatabase();
      await GroupsDao(db).upsertGroupLww(
        const GroupsCompanion(
          roomId: Value('g1'),
          name: Value('Trip'),
          currency: Value('EUR'),
          updatedAt: Value(1000),
        ),
      );
      for (final (u, name) in [(alice, 'Alice'), (bob, 'Bob')]) {
        await MembersDao(db).upsertMemberLww(
          MembersCompanion(
            groupId: const Value('g1'),
            userId: Value(u),
            displayName: Value(name),
            matrixId: Value(u),
            status: const Value('active'),
            updatedAt: const Value(1),
          ),
        );
      }
      return db;
    }

    testWidgets('save → the itemized split is stored exactly', (tester) async {
      final db = await seed();
      addTearDown(db.close);
      final net = FakeMatrixNetwork();
      final received = <TransportMessage>[];
      net.clientFor(bob).onMessage.listen(received.add);
      await tester.pumpWidget(
        testRouterApp(
          const AddExpensePage(roomId: 'g1'),
          overrides: [
            ...signingUiOverrides(),
            appDatabaseProvider.overrideWith((ref) => db),
            ledgerTransportProvider.overrideWith((ref) => net.clientFor(alice)),
          ],
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Description'),
        'Dinner',
      );
      await tester.enterText(find.byKey(const Key('expenseAmount')), '20');
      await tester.pumpAndSettle();
      bool canPop() => tester
          .widget<PopScope<Object?>>(find.byType(PopScope<Object?>))
          .canPop;

      await tapKey(tester, 'splitItemize');
      await enter(tester, 'itemAmount-0', '7');
      await tapKey(tester, 'itemPerson-0-$bob');
      await tapKey(tester, 'itemsAdd');
      await enter(tester, 'itemAmount-1', '10');
      // Back without applying keeps the items for the next visit.
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(ItemSplitPage), findsNothing);
      await tapKey(tester, 'splitItemize');
      // 3 € rest, proportional to 12 / 5.
      await tapKey(tester, 'itemsApply');
      // G56: the split was touched → leaving asks.
      expect(canPop(), isFalse);
      expect(find.text('Adds up to the total'), findsOneWidget);

      await tester.tap(find.byKey(const Key('submitExpense')));
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 25));
      }
      final stored = await ExpensesDao(db).getExpensesForRoom('g1');
      expect(stored, hasLength(1));
      expect(stored.single.amountCents, 2000);
      // 12 → 1412 (+212), 5 → 588 (+88).
      expect(stored.single.splitsJson, '{"$alice":1412,"$bob":588}');
      expect(received.single.content['split'], {alice: 1412, bob: 588});
    });
  });
}
