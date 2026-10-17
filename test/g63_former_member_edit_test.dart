/// G63 / U11: editing an expense that involves a participant who has since
/// left or been removed must not drop them from the split or empty the payer
/// — saving after changing only the description keeps payer + split exactly.
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
import 'package:money_ledger/features/expenses/add_expense_page.dart';
import 'package:money_ledger/features/expenses/expenses_provider.dart';
import 'package:money_ledger/features/groups/create_group_page.dart';
import 'package:money_ledger/models/expense_model.dart';
import 'package:money_ledger/models/member_model.dart';

import 'helpers/fake_ledger_network.dart';
import 'helpers/in_memory_database.dart';
import 'helpers/test_providers.dart';

const _alice = '@alice:x.org';
const _bob = '@bob:x.org';
const _carol = 'carol-local'; // a local person, removed later

MemberModel _member(String id, {String status = 'active', String name = ''}) =>
    MemberModel(
      groupId: 'g1',
      userId: id,
      displayName: name,
      status: status,
      updatedAt: 1,
    );

ExpenseModel _expense({
  required String paidBy,
  required String splitsJson,
  int amount = 10000,
}) => ExpenseModel(
  id: 'e1',
  roomId: 'g1',
  description: 'Hotel',
  amountCents: amount,
  currency: 'CHF',
  paidBy: paidBy,
  splitsJson: splitsJson,
  createdAt: 1000,
  updatedAt: 1000,
);

void main() {
  group('editorParticipants (pure)', () {
    final all = [
      _member(_alice),
      _member(_carol, status: 'removed', name: 'Carol'),
      _member('dave', status: 'removed', name: 'Dave'),
      _member(_bob),
    ];

    test('a new expense offers active participants only', () {
      final ids = editorParticipants(
        groupId: 'g1',
        all: all,
      ).map((m) => m.userId);
      expect(ids, [_alice, _bob]);
    });

    test('an edit keeps the former participants it references, last', () {
      final ids = editorParticipants(
        groupId: 'g1',
        all: all,
        initial: _expense(
          paidBy: _alice,
          splitsJson: '{"$_carol":5000,"$_alice":5000}',
        ),
      ).map((m) => m.userId);
      // Dave isn't part of this expense → not offered.
      expect(ids, [_alice, _bob, _carol]);
    });

    test('a former payer outside the split is kept too', () {
      final ids = editorParticipants(
        groupId: 'g1',
        all: all,
        initial: _expense(
          paidBy: 'dave',
          splitsJson: '{"$_alice":5000,"$_bob":5000}',
        ),
      ).map((m) => m.userId);
      expect(ids, [_alice, _bob, 'dave']);
    });

    test('a referenced id without any participant row stays (as former)', () {
      final out = editorParticipants(
        groupId: 'g1',
        all: all,
        initial: _expense(
          paidBy: _alice,
          splitsJson: '{"ghost":5000,"$_alice":5000}',
        ),
      );
      final ghost = out.singleWhere((m) => m.userId == 'ghost');
      expect(ghost.isActive, isFalse);
    });
  });

  group('AddExpensePage edit with a former member (U11)', () {
    Future<AppDatabase> seed() async {
      final db = openTestDatabase();
      await GroupsDao(db).upsertGroupLww(
        const GroupsCompanion(
          roomId: Value('g1'),
          name: Value('Trip'),
          currency: Value('CHF'),
          updatedAt: Value(1000),
        ),
      );
      final dao = MembersDao(db);
      final now = DateTime.now().millisecondsSinceEpoch;
      for (final u in [_alice, _bob]) {
        await dao.upsertMemberLww(
          MembersCompanion(
            groupId: const Value('g1'),
            userId: Value(u),
            matrixId: Value(u),
            status: const Value('active'),
            updatedAt: Value(now),
          ),
        );
      }
      await dao.upsertMemberLww(
        MembersCompanion(
          groupId: const Value('g1'),
          userId: const Value(_carol),
          displayName: const Value('Carol'),
          status: const Value('removed'),
          updatedAt: Value(now),
        ),
      );
      return db;
    }

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
            ledgerTransportProvider.overrideWith(
              (ref) => net.clientFor(_alice),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      return received;
    }

    Future<void> save(WidgetTester tester) async {
      await tester.pump();
      await tester.tap(find.byKey(const Key('submitExpense')));
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 25));
      }
    }

    bool canPop(WidgetTester tester) =>
        tester.widget<PopScope<Object?>>(find.byType(PopScope<Object?>)).canPop;

    // 100.00 ÷ 3: the remainder cent sits with Carol (listed first) — a
    // re-resolved equal split in row order would move it to Alice.
    const equalJson = '{"$_carol":3334,"$_alice":3333,"$_bob":3333}';

    testWidgets('equal split with a removed member: only the description '
        'changes, payer + split stay byte-identical', (tester) async {
      final db = await seed();
      addTearDown(db.close);
      final initial = _expense(paidBy: _carol, splitsJson: equalJson);
      final received = await pumpPage(tester, db, initial: initial);

      // No assert from a payer missing in the dropdown; Carol is shown, marked.
      expect(tester.takeException(), isNull);
      expect(find.text('Carol'), findsWidgets);
      expect(find.text('no longer in the group'), findsWidgets);
      expect(find.textContaining('Split equally among 3'), findsOneWidget);
      // Opening the form changed nothing (G56 baseline).
      expect(canPop(tester), isTrue);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Description'),
        'Hotel Rome',
      );
      await save(tester);

      expect(received, hasLength(1));
      final c = received.single.content;
      expect(c['description'], 'Hotel Rome');
      expect(c['paid_by'], _carol);
      expect(c['split'], {_carol: 3334, _alice: 3333, _bob: 3333});
      final stored = await ExpensesDao(db).getExpenseById('e1');
      expect(stored!.splitsJson, equalJson);
      expect(stored.paidBy, _carol);
    });

    testWidgets('exact split with a removed member: nothing left over, saved '
        'unchanged', (tester) async {
      final db = await seed();
      addTearDown(db.close);
      const json = '{"$_alice":2000,"$_carol":8000}';
      final initial = _expense(paidBy: _alice, splitsJson: json);
      final received = await pumpPage(tester, db, initial: initial);

      expect(tester.takeException(), isNull);
      expect(find.widgetWithText(TextField, '80.00'), findsOneWidget);
      expect(find.text('Adds up to the total'), findsOneWidget);
      expect(canPop(tester), isTrue);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Description'),
        'Hotel Rome',
      );
      await save(tester);

      expect(received.single.content['split'], {_alice: 2000, _carol: 8000});
      expect((await ExpensesDao(db).getExpenseById('e1'))!.splitsJson, json);
    });

    testWidgets('a new expense does not offer the removed member', (
      tester,
    ) async {
      final db = await seed();
      addTearDown(db.close);
      await pumpPage(tester, db);
      expect(find.text('Carol'), findsNothing);
      expect(find.textContaining('Split equally among 2'), findsOneWidget);
    });

    testWidgets('German: the former member is marked', (tester) async {
      final db = await seed();
      addTearDown(db.close);
      await pumpPage(
        tester,
        db,
        initial: _expense(paidBy: _carol, splitsJson: equalJson),
        locale: const Locale('de'),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('nicht mehr dabei'), findsWidgets);
    });
  });

  // U5: a name / description of only spaces is rejected (it used to be saved
  // trimmed — as an empty name).
  group('blank names are rejected (U5)', () {
    testWidgets('new group: "   " → Required, nothing created', (tester) async {
      final db = openTestDatabase();
      addTearDown(db.close);
      final net = FakeMatrixNetwork();
      await tester.pumpWidget(
        testRouterApp(
          const CreateGroupPage(),
          overrides: [
            ledgerTransportProvider.overrideWith(
              (ref) => net.clientFor(_alice),
            ),
            appDatabaseProvider.overrideWithValue(db),
          ],
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), '   ');
      await tester.tap(find.widgetWithText(FilledButton, 'Create'));
      await tester.pumpAndSettle();
      expect(find.text('Required'), findsOneWidget);
      await tester.runAsync(() async {
        expect(await GroupsDao(db).getAllGroups(), isEmpty);
      });
    });

    testWidgets('expense: a blank description → Required, nothing sent', (
      tester,
    ) async {
      final db = openTestDatabase();
      addTearDown(db.close);
      await GroupsDao(db).upsertGroupLww(
        const GroupsCompanion(
          roomId: Value('g1'),
          name: Value('Trip'),
          currency: Value('CHF'),
          updatedAt: Value(1000),
        ),
      );
      for (final u in [_alice, _bob]) {
        await MembersDao(db).upsertMemberLww(
          MembersCompanion(
            groupId: const Value('g1'),
            userId: Value(u),
            matrixId: Value(u),
            status: const Value('active'),
            updatedAt: const Value(1),
          ),
        );
      }
      final net = FakeMatrixNetwork();
      final received = <TransportMessage>[];
      net.clientFor(_bob).onMessage.listen(received.add);
      await tester.pumpWidget(
        testRouterApp(
          const AddExpensePage(roomId: 'g1'),
          overrides: [
            ...signingUiOverrides(),
            appDatabaseProvider.overrideWith((ref) => db),
            ledgerTransportProvider.overrideWith(
              (ref) => net.clientFor(_alice),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Description'),
        '   ',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Amount'),
        '20',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('submitExpense')));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 25));
      }
      expect(find.text('Required'), findsOneWidget);
      expect(received, isEmpty);
    });
  });
}
