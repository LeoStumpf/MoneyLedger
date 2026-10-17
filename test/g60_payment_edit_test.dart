/// G60 widget tests: a recorded payment can be edited — tapping its ledger
/// row (or ⋮ → Edit) opens the payment dialog in edit mode, prefilled; Save
/// writes a new signed version through the real ExpenseAdder (origin kept);
/// read-only groups offer no edit.
library;

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/database/app_database.dart';
import 'package:money_ledger/core/database/daos/expenses_dao.dart';
import 'package:money_ledger/core/database/daos/members_dao.dart';
import 'package:money_ledger/core/matrix/ledger_transport.dart';
import 'package:money_ledger/core/matrix/transport_provider.dart';
import 'package:money_ledger/features/expenses/expenses_page.dart';
import 'package:money_ledger/features/expenses/expenses_provider.dart';
import 'package:money_ledger/features/groups/group_archive_provider.dart';
import 'package:money_ledger/features/groups/group_provider.dart';
import 'package:money_ledger/models/expense_date.dart';
import 'package:money_ledger/models/expense_model.dart';
import 'package:money_ledger/models/group_model.dart';
import 'package:money_ledger/models/member_model.dart';

import 'helpers/eventually.dart';
import 'helpers/fake_ledger_network.dart';
import 'helpers/in_memory_database.dart';
import 'helpers/test_providers.dart';

const _g = 'g1';
const _alice = '@alice:x.org';
const _bob = '@bob:y.org';
const _carl = 'carl-local';

MemberModel _m(
  String id,
  String? mx,
  String name, {
  String status = 'active',
}) => MemberModel(
  groupId: _g,
  userId: id,
  displayName: name,
  matrixId: mx,
  status: status,
  updatedAt: 1,
);

void main() {
  late AppDatabase db;
  late FakeMatrixNetwork net;
  late SettlementModel payment;

  setUp(() async {
    db = openTestDatabase();
    net = FakeMatrixNetwork();
    net.clientFor(_alice);
    net.clientFor(_bob);
  });
  tearDown(() => db.close());

  /// Bob paid Alice 15.00 EUR, recorded (and signed) by Alice's device.
  Future<void> seed(WidgetTester tester) async {
    await tester.runAsync(() async {
      // The relay targets the claimed members stored in the DB.
      for (final id in [_alice, _bob]) {
        await MembersDao(db).upsertMemberLww(
          MembersCompanion(
            groupId: const Value(_g),
            userId: Value(id),
            matrixId: Value(id),
            status: const Value('active'),
            updatedAt: const Value(1),
          ),
        );
      }
      final c = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          ledgerTransportProvider.overrideWith((ref) => net.clientFor(_alice)),
        ],
      );
      c.listen(expenseAdderProvider, (_, _) {});
      await c
          .read(expenseAdderProvider.notifier)
          .addSettlement(
            roomId: _g,
            amountCents: 1500,
            currency: 'EUR',
            fromUser: _bob,
            toUser: _alice,
          );
      c.dispose();
      payment = (await ExpensesDao(db).getSettlementsForRoom(_g)).single;
    });
    expect(payment.origin?.user, _alice);
  }

  Future<void> pumpPage(WidgetTester tester, {bool removed = false}) async {
    final members = [
      _m(_alice, _alice, 'Alice', status: removed ? 'removed' : 'active'),
      _m(_bob, _bob, 'Bob'),
      _m(_carl, null, 'Carl'),
    ];
    await tester.pumpWidget(
      testApp(
        const ExpensesPage(roomId: _g),
        overrides: [
          ...testOverrides(
            isLoggedIn: true,
            settlements: [payment],
            members: members,
            groups: [
              const GroupModel(roomId: _g, name: 'Trip', currency: 'EUR'),
            ],
          ),
          appDatabaseProvider.overrideWithValue(db),
          ledgerTransportProvider.overrideWith((ref) => net.clientFor(_alice)),
          currentUserIdProvider.overrideWith((_) => _alice),
          currentParticipantProvider.overrideWith(
            (_, _) async => members.first,
          ),
          groupLedgerFingerprintProvider.overrideWith((_, _) => 'fp'),
        ],
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  FilledButton submit(WidgetTester tester) =>
      tester.widget<FilledButton>(find.byKey(const Key('paymentSubmit')));

  testWidgets('tap → edit dialog prefilled; Save writes a new signed '
      'version with the origin kept', (tester) async {
    await seed(tester);
    await pumpPage(tester);

    await tester.tap(find.byKey(const Key('settlementTitle')));
    await tester.pumpAndSettle();
    expect(find.text('Edit payment'), findsOneWidget);
    expect(find.widgetWithText(TextField, '15.00'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Save'), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('paymentDateValue'))).data,
      'Today',
    );
    // Nothing changed yet → nothing to save.
    expect(submit(tester).onPressed, isNull);

    // New amount, payer and day.
    await tester.enterText(find.byKey(const Key('paymentAmount')), '12.50');
    await tester.pump();
    await tester.tap(find.byKey(const Key('paymentFrom')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Carl').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('paymentDateYesterday')));
    await tester.tap(find.byKey(const Key('paymentDateYesterday')));
    await tester.pump();
    expect(submit(tester).onPressed, isNotNull);

    final relayed = <TransportMessage>[];
    net.clientFor(_bob).onMessage.listen(relayed.add);
    late SettlementModel row;
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('paymentSubmit')));
      await eventually(
        () async =>
            (await ExpensesDao(
              db,
            ).getSettlementById(payment.id))!.amountCents ==
            1250,
        tester: tester,
      );
      await net.settle();
      row = (await ExpensesDao(db).getSettlementById(payment.id))!;
    });
    await tester.pump();
    expect(find.text('Payment updated'), findsOneWidget);
    final now = DateTime.now();
    expect(
      (row.fromUser, row.toUser, row.amountCents, row.currency),
      (_carl, _alice, 1250, 'EUR'),
    );
    expect(row.date, expenseDateOf(DateTime(now.year, now.month, now.day - 1)));
    expect(row.createdAt, payment.createdAt);
    expect(row.updatedAt, greaterThan(payment.updatedAt));
    expect(row.origin!.sig, payment.origin!.sig);
    expect(row.sig, isNotNull);
    expect(row.deleted, isFalse);
    // Relayed to the other claimed member like any write.
    expect(relayed.where((m) => m.type == settlementEventType), hasLength(1));
  });

  testWidgets('⋮ offers Edit and Delete; cancel writes nothing', (
    tester,
  ) async {
    await seed(tester);
    await pumpPage(tester);
    await tester.tap(find.byTooltip('Settlement options'));
    await tester.pumpAndSettle();
    expect(find.text('Delete'), findsOneWidget);
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    expect(find.text('Edit payment'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Edit payment'), findsNothing);
    late SettlementModel row;
    await tester.runAsync(() async {
      row = (await ExpensesDao(db).getSettlementById(payment.id))!;
    });
    expect(row.updatedAt, payment.updatedAt);
  });

  testWidgets('German: "Zahlung bearbeiten" / "Speichern"', (tester) async {
    await seed(tester);
    await tester.pumpWidget(
      testApp(
        const ExpensesPage(roomId: _g),
        locale: const Locale('de'),
        overrides: [
          ...testOverrides(
            isLoggedIn: true,
            settlements: [payment],
            members: [_m(_alice, _alice, 'Alice'), _m(_bob, _bob, 'Bob')],
            groups: [
              const GroupModel(roomId: _g, name: 'Trip', currency: 'EUR'),
            ],
          ),
          appDatabaseProvider.overrideWithValue(db),
          ledgerTransportProvider.overrideWith((ref) => net.clientFor(_alice)),
          currentUserIdProvider.overrideWith((_) => _alice),
          currentParticipantProvider.overrideWith(
            (_, _) async => _m(_alice, _alice, 'Alice'),
          ),
          groupLedgerFingerprintProvider.overrideWith((_, _) => 'fp'),
        ],
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.tap(find.byKey(const Key('settlementTitle')));
    await tester.pumpAndSettle();
    expect(find.text('Zahlung bearbeiten'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Speichern'), findsOneWidget);
    expect(find.widgetWithText(TextField, '15,00'), findsOneWidget);
  });

  testWidgets('read-only group (we were removed): no edit, no menu', (
    tester,
  ) async {
    await seed(tester);
    await pumpPage(tester, removed: true);
    await tester.tap(find.byKey(const Key('settlementTitle')));
    await tester.pumpAndSettle();
    expect(find.text('Edit payment'), findsNothing);
    expect(find.byTooltip('Settlement options'), findsNothing);
  });
}
