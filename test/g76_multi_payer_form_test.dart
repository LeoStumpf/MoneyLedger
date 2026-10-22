/// G76: several payers in the expense form — *Paid by* → *Several
/// people…* opens one amount per person (live remainder, *Put the rest
/// here*); *Add* stays disabled until they add up; the saved / relayed
/// version carries `payers` + an empty `paid_by`; an edit reopens them;
/// the ledger row and the read-only details name the payers; 360 dp at
/// 200 % in EN + DE doesn't overflow.
library;

import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/database/app_database.dart';
import 'package:money_ledger/core/database/daos/expenses_dao.dart';
import 'package:money_ledger/core/database/daos/groups_dao.dart';
import 'package:money_ledger/core/database/daos/members_dao.dart';
import 'package:money_ledger/core/matrix/ledger_transport.dart';
import 'package:money_ledger/core/matrix/transport_provider.dart';
import 'package:money_ledger/features/expenses/add_expense_page.dart';
import 'package:money_ledger/features/expenses/expenses_provider.dart';
import 'package:money_ledger/features/expenses/record_details_sheet.dart';
import 'package:money_ledger/models/expense_model.dart';
import 'package:money_ledger/models/expense_payers.dart';

import 'helpers/fake_ledger_network.dart';
import 'helpers/in_memory_database.dart';
import 'helpers/test_providers.dart';

const _alice = '@alice:x.org';
const _bob = '@bob:x.org';
const _carl = 'carl-local';

/// A 360 × 780 dp phone at [scale] text size.
void _phone(WidgetTester tester, {double scale = 1}) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(360, 780);
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

Future<AppDatabase> _seed() async {
  final db = openTestDatabase();
  await GroupsDao(db).upsertGroupLww(
    const GroupsCompanion(
      roomId: Value('g1'),
      name: Value('Trip'),
      currency: Value('EUR'),
      updatedAt: Value(1000),
    ),
  );
  for (final (u, name, mxid) in [
    (_alice, 'Alice', _alice),
    (_bob, 'Bob', _bob),
    (_carl, 'Carl Maximilian Longname-Example', null),
  ]) {
    await MembersDao(db).upsertMemberLww(
      MembersCompanion(
        groupId: const Value('g1'),
        userId: Value(u),
        displayName: Value(name),
        matrixId: Value(mxid),
        status: const Value('active'),
        updatedAt: const Value(1),
      ),
    );
  }
  return db;
}

ExpenseModel _twoPayers() => ExpenseModel(
  id: 'e1',
  roomId: 'g1',
  description: 'Dinner',
  amountCents: 9000,
  currency: 'EUR',
  paidBy: '',
  payersJson: jsonEncode({_alice: 6000, _bob: 3000}),
  splitsJson: jsonEncode({_alice: 3000, _bob: 3000, _carl: 3000}),
  createdAt: 1000,
  updatedAt: 1000,
);

void main() {
  Future<List<TransportMessage>> pumpPage(
    WidgetTester tester,
    AppDatabase db, {
    ExpenseModel? initial,
    Locale? locale,
  }) async {
    final net = FakeMatrixNetwork();
    final received = <TransportMessage>[];
    net.clientFor(_bob).onMessage.listen(received.add);
    await tester.pumpWidget(
      testRouterApp(
        AddExpensePage(roomId: 'g1', initial: initial),
        locale: locale,
        overrides: [
          ...signingUiOverrides(),
          appDatabaseProvider.overrideWith((ref) => db),
          ledgerTransportProvider.overrideWith((ref) => net.clientFor(_alice)),
        ],
      ),
    );
    await tester.pumpAndSettle();
    return received;
  }

  Future<void> chooseSeveral(WidgetTester tester, String label) async {
    await tester.ensureVisible(find.byKey(const Key('expensePayer')));
    await tester.tap(find.byKey(const Key('expensePayer')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  Future<void> enter(WidgetTester tester, Key key, String text) async {
    await tester.ensureVisible(find.byKey(key));
    await tester.enterText(find.byKey(key), text);
    await tester.pumpAndSettle();
  }

  bool canSubmit(WidgetTester tester) =>
      tester
          .widget<FilledButton>(find.byKey(const Key('submitExpense')))
          .onPressed !=
      null;

  Future<void> save(WidgetTester tester) async {
    await tester.ensureVisible(find.byKey(const Key('submitExpense')));
    await tester.tap(find.byKey(const Key('submitExpense')));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 25));
    }
  }

  testWidgets('several payers: remainder, rest button, saved + relayed', (
    tester,
  ) async {
    final db = await _seed();
    addTearDown(db.close);
    final received = await pumpPage(tester, db);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Description'),
      'Dinner',
    );
    await tester.enterText(find.byKey(const Key('expenseAmount')), '90');
    await tester.pumpAndSettle();
    expect(canSubmit(tester), isTrue); // one payer (me), equal split

    await chooseSeveral(tester, 'Several people…');
    expect(find.byKey(const Key('payersEditor')), findsOneWidget);
    expect(canSubmit(tester), isFalse); // nobody typed yet
    expect(find.text('€90.00 left'), findsOneWidget);

    await enter(tester, const Key('payerAmount-$_alice'), '60');
    expect(find.text('€30.00 left'), findsOneWidget);
    expect(canSubmit(tester), isFalse);
    await tester.ensureVisible(find.byKey(const Key('payersRest-$_bob')));
    await tester.tap(find.byKey(const Key('payersRest-$_bob')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('payersRemaining')), findsNothing);
    expect(canSubmit(tester), isTrue);

    // Too much → disabled again.
    await enter(tester, const Key('payerAmount-$_carl'), '1');
    expect(find.text('€1.00 too much'), findsOneWidget);
    expect(canSubmit(tester), isFalse);
    await enter(tester, const Key('payerAmount-$_carl'), '');
    expect(canSubmit(tester), isTrue);

    await save(tester);
    final stored = (await ExpensesDao(db).getExpensesForRoom('g1')).single;
    expect(stored.paidBy, '');
    expect(paidAmountsOf(stored), {_alice: 6000, _bob: 3000});
    final c = received.single.content;
    expect(c['paid_by'], '');
    expect(c['payers'], {_alice: 6000, _bob: 3000});
  });

  testWidgets('one payer and back: the editor shows what will be saved', (
    tester,
  ) async {
    final db = await _seed();
    addTearDown(db.close);
    final received = await pumpPage(tester, db);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Description'),
      'Dinner',
    );
    await tester.enterText(find.byKey(const Key('expenseAmount')), '90');
    await tester.pumpAndSettle();
    await chooseSeveral(tester, 'Several people…');
    await enter(tester, const Key('payerAmount-$_alice'), '60');
    await enter(tester, const Key('payerAmount-$_bob'), '30');
    expect(canSubmit(tester), isTrue);

    await chooseSeveral(tester, 'Bob');
    expect(find.byKey(const Key('payersEditor')), findsNothing);
    await chooseSeveral(tester, 'Several people…');
    // Reopened with the typed amounts — not blank fields over a valid,
    // hidden map.
    String text(String id) => tester
        .widget<TextField>(find.byKey(Key('payerAmount-$id')))
        .controller!
        .text;
    expect(text(_alice), '60.00');
    expect(text(_bob), '30.00');
    expect(canSubmit(tester), isTrue);

    await enter(tester, const Key('payerAmount-$_bob'), '20');
    await enter(tester, const Key('payerAmount-$_carl'), '10');
    await save(tester);
    expect(received.single.content['payers'], {
      _alice: 6000,
      _bob: 2000,
      _carl: 1000,
    });
  });

  testWidgets('one person typed with the whole amount = a plain payer', (
    tester,
  ) async {
    final db = await _seed();
    addTearDown(db.close);
    final received = await pumpPage(tester, db);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Description'),
      'Taxi',
    );
    await tester.enterText(find.byKey(const Key('expenseAmount')), '30');
    await tester.pumpAndSettle();
    await chooseSeveral(tester, 'Several people…');
    await enter(tester, const Key('payerAmount-$_bob'), '30');
    expect(canSubmit(tester), isTrue);
    await save(tester);
    final c = received.single.content;
    expect(c['paid_by'], _bob);
    expect(c.containsKey('payers'), isFalse);
  });

  testWidgets('edit reopens the payers; only the description changes', (
    tester,
  ) async {
    final db = await _seed();
    addTearDown(db.close);
    await ExpensesDao(db).upsertExpenseLww(expenseCompanion(_twoPayers()));
    final received = await pumpPage(tester, db, initial: _twoPayers());
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('payersEditor')), findsOneWidget);
    expect(find.text('Several people…'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('payerAmount-$_alice')))
          .controller!
          .text,
      '60.00',
    );
    // Opening the form changed nothing (G56 baseline).
    expect(
      tester.widget<PopScope<Object?>>(find.byType(PopScope<Object?>)).canPop,
      isTrue,
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Description'),
      'Dinner Rome',
    );
    await save(tester);
    final c = received.single.content;
    expect(c['description'], 'Dinner Rome');
    expect(c['paid_by'], '');
    expect(c['payers'], {_alice: 6000, _bob: 3000});
  });

  testWidgets('edit: switching to one payer drops the payers', (tester) async {
    final db = await _seed();
    addTearDown(db.close);
    await ExpensesDao(db).upsertExpenseLww(expenseCompanion(_twoPayers()));
    final received = await pumpPage(tester, db, initial: _twoPayers());
    await chooseSeveral(tester, 'Bob');
    expect(find.byKey(const Key('payersEditor')), findsNothing);
    await save(tester);
    final c = received.single.content;
    expect(c['paid_by'], _bob);
    expect(c.containsKey('payers'), isFalse);
  });

  testWidgets('details sheet lists who paid how much', (tester) async {
    await tester.pumpWidget(
      testApp(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showExpenseDetails(
              context,
              _twoPayers(),
              names: const {_alice: 'Alice', _bob: 'Bob', _carl: 'Carl'},
            ),
            child: const Text('open'),
          ),
        ),
        overrides: signingUiOverrides(),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('detailsPayers')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('detailsPayers')),
        matching: find.text('€60.00'),
      ),
      findsOneWidget,
    );
    // Unmount, then let drift's stream-close timer run.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  });

  for (final locale in const [Locale('en'), Locale('de')]) {
    testWidgets('360 dp at 200 %: the payers editor fits '
        '[${locale.languageCode}]', (tester) async {
      _phone(tester, scale: 2);
      final db = await _seed();
      addTearDown(db.close);
      await ExpensesDao(db).upsertExpenseLww(expenseCompanion(_twoPayers()));
      await pumpPage(tester, db, initial: _twoPayers(), locale: locale);
      await tester.ensureVisible(find.byKey(const Key('payersEditor')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await enter(tester, const Key('payerAmount-$_carl'), '1234,56');
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('payersRemaining')), findsOneWidget);
    });
  }
}
