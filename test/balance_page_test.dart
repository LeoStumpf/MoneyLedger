import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/models/expense_date.dart';
import 'package:money_ledger/core/database/app_database.dart';
import 'package:money_ledger/core/database/daos/expenses_dao.dart';
import 'package:money_ledger/core/database/daos/members_dao.dart';
import 'package:money_ledger/core/matrix/ledger_transport.dart';
import 'package:money_ledger/core/matrix/transport_provider.dart';
import 'package:money_ledger/core/widgets/names_line.dart';
import 'package:money_ledger/features/balance/balance_provider.dart';
import 'package:money_ledger/features/expenses/expenses_provider.dart';
import 'package:money_ledger/models/expense_model.dart';
import 'package:money_ledger/models/group_model.dart';
import 'package:money_ledger/features/balance/balance_calculator.dart';
import 'package:money_ledger/features/balance/balance_page.dart';
import 'package:money_ledger/features/groups/group_provider.dart';
import 'package:money_ledger/models/member_model.dart';
import 'package:money_ledger/features/payment/payment_details_provider.dart';

import 'helpers/fake_ledger_network.dart';
import 'helpers/in_memory_database.dart';
import 'helpers/test_providers.dart';
import 'helpers/eventually.dart';

const _roomId = '!test:matrix.org';

/// A suggested-payment title (G33: a [NamesLine], each name its own Text).
Finder _debtTitle(String text) =>
    find.byWidgetPredicate((w) => w is NamesLine && w.fullText == text);

void main() {
  group('BalancePage', () {
    testWidgets('shows "All settled up!" when there are no debts', (
      tester,
    ) async {
      await tester.pumpWidget(
        testApp(
          const BalancePage(roomId: _roomId),
          overrides: testOverrides(isLoggedIn: true, debts: []),
        ),
      );
      await tester.pump();

      expect(find.textContaining('All settled up'), findsOneWidget);
    });

    testWidgets('renders debt cards when debts exist', (tester) async {
      final debts = [
        const DebtEntry(
          from: '@bob:matrix.org',
          to: '@alice:matrix.org',
          cents: 2100,
          currency: 'EUR',
        ),
        const DebtEntry(
          from: '@carol:matrix.org',
          to: '@alice:matrix.org',
          cents: 1050,
          currency: 'EUR',
        ),
      ];

      await tester.pumpWidget(
        testApp(
          const BalancePage(roomId: _roomId),
          overrides: testOverrides(isLoggedIn: true, debts: debts),
        ),
      );
      await tester.pump();

      // G17: per-person balances (names fall back to the MXID localpart)…
      // (The suggested-payment lines are one Text each, G18 review 2.)
      expect(find.text('bob'), findsOneWidget);
      expect(find.text('carol'), findsOneWidget);
      expect(find.text('alice'), findsOneWidget);
      expect(find.text('gets back'), findsOneWidget);
      expect(find.text('owes'), findsNWidgets(2));
      // …and the suggested payments.
      expect(_debtTitle('bob pays alice'), findsOneWidget);
      expect(_debtTitle('carol pays alice'), findsOneWidget);
    });

    testWidgets('G33 / G18 review 2: a suggested payment between two long '
        'names wraps onto two lines, both names readable', (tester) async {
      // (The test font draws every glyph as a square — much wider than a
      // real one — so give the line some room.)
      tester.view.physicalSize = const Size(600, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      const longA = 'bartholomew-maximilian-featherstonehaugh';
      const longB = 'wilhelmina-constance-ashby-montgomery';
      await tester.pumpWidget(
        testApp(
          const BalancePage(roomId: _roomId),
          overrides: testOverrides(
            isLoggedIn: true,
            debts: [
              const DebtEntry(
                from: '@$longA:matrix.org',
                to: '@$longB:matrix.org',
                cents: 2100,
                currency: 'EUR',
              ),
            ],
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      final title = _debtTitle('$longA pays $longB');
      expect(title, findsOneWidget);
      final shown = tester
          .widget<Text>(
            find.descendant(
              of: title,
              matching: find.byKey(const Key('namesLineText')),
            ),
          )
          .data!;
      // Both names keep a real part (cut evenly, never dropped), the literal
      // stays whole.
      final parts = shown.split(' pays ');
      expect(parts, hasLength(2));
      expect(parts[0], startsWith(longA.substring(0, 15)));
      expect(parts[1], startsWith(longB.substring(0, 15)));
      // Two lines at most.
      expect(tester.getSize(title).height, lessThanOrEqualTo(2 * 20 + 1));
    });

    testWidgets('G18 review 2 (German): "… zahlt an dich" shows the whole '
        'long name on two lines', (tester) async {
      // (The test font's square glyphs are about twice as wide as a real
      // font's: 600 test px ≈ a phone's line.)
      tester.view.physicalSize = const Size(600, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      const me = '@me:matrix.org';
      const longA = 'moneyledger test a';
      await tester.pumpWidget(
        testApp(
          const BalancePage(roomId: _roomId),
          locale: const Locale('de'),
          overrides: [
            ...testOverrides(
              isLoggedIn: true,
              debts: [
                const DebtEntry(
                  from: '@mltest:matrix.org',
                  to: me,
                  cents: 2100,
                  currency: 'EUR',
                ),
              ],
            ),
            participantNamesProvider.overrideWith(
              (ref, g) => {'@mltest:matrix.org': longA, me: 'Ich'},
            ),
            currentParticipantProvider.overrideWith(
              (ref, g) => Future<MemberModel?>.value(
                const MemberModel(
                  groupId: _roomId,
                  userId: me,
                  matrixId: me,
                  status: 'active',
                  updatedAt: 1,
                ),
              ),
            ),
          ],
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(tester.takeException(), isNull);
      final title = _debtTitle('$longA zahlt an dich');
      expect(title, findsOneWidget);
      final shown = tester
          .widget<Text>(
            find.descendant(
              of: title,
              matching: find.byKey(const Key('namesLineText')),
            ),
          )
          .data!;
      // Before: one line, "mo… zahlt an dich".
      expect(shown, '$longA zahlt an dich');
      expect(tester.getSize(title).height, greaterThan(20 + 1));
    });

    testWidgets('shows "Balance" AppBar title', (tester) async {
      await tester.pumpWidget(
        testApp(
          const BalancePage(roomId: _roomId),
          overrides: testOverrides(isLoggedIn: true),
        ),
      );
      await tester.pump();

      expect(find.text('Balance'), findsOneWidget);
      expect(find.byType(AppBar), findsOneWidget);
    });

    testWidgets('shows arrow_forward icon for each debt', (tester) async {
      final debts = [
        const DebtEntry(
          from: '@bob:matrix.org',
          to: '@alice:matrix.org',
          cents: 500,
          currency: 'EUR',
        ),
      ];

      await tester.pumpWidget(
        testApp(
          const BalancePage(roomId: _roomId),
          overrides: testOverrides(isLoggedIn: true, debts: debts),
        ),
      );
      await tester.pump();

      expect(find.byIcon(Icons.arrow_forward), findsOneWidget);
    });

    // G26: a participant removed by another member can't record settlements.
    for (final status in ['active', 'removed']) {
      testWidgets('own debt is settleable only while active ($status)', (
        tester,
      ) async {
        const me = '@bob:matrix.org';
        await tester.pumpWidget(
          testApp(
            const BalancePage(roomId: _roomId),
            overrides: [
              ...testOverrides(
                isLoggedIn: true,
                debts: const [
                  DebtEntry(
                    from: me,
                    to: '@alice:matrix.org',
                    cents: 500,
                    currency: 'EUR',
                  ),
                ],
              ),
              currentParticipantProvider.overrideWith(
                (ref, g) => Future<MemberModel?>.value(
                  MemberModel(
                    groupId: g,
                    userId: me,
                    matrixId: me,
                    status: status,
                    updatedAt: 1,
                  ),
                ),
              ),
            ],
          ),
        );
        await tester.pump();
        await tester.pump();

        final tile = tester.widget<ListTile>(find.byType(ListTile));
        expect(tile.onTap != null, status == 'active');
      });
    }
  });

  // G28: any active member records a payment between any two participants.
  group('BalancePage — record payments (G28)', () {
    const alice = '@alice:x.org';
    const bob = '@bob:x.org';
    const carl = 'carl-local-id';

    MemberModel member(
      String id,
      String? mx,
      String name, {
      String status = 'active',
    }) => MemberModel(
      groupId: 'g1',
      userId: id,
      displayName: name,
      matrixId: mx,
      status: status,
      updatedAt: 1000,
    );

    /// Group g1 (CHF): alice (us), bob (claimed) and Carl (local, no
    /// account); bob and Carl each owe alice 10.00. The page's reads are
    /// stubbed; the write goes through the real ExpenseAdder into [db].
    Future<void> pumpPage(
      WidgetTester tester,
      AppDatabase db,
      FakeMatrixNetwork net, {
      String aliceStatus = 'active',
    }) async {
      final members = [
        member(alice, alice, 'Alice', status: aliceStatus),
        member(bob, bob, 'Bob'),
        member(carl, null, 'Carl'),
      ];
      await tester.pumpWidget(
        testApp(
          const BalancePage(roomId: 'g1'),
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            ledgerTransportProvider.overrideWith((ref) => net.clientFor(alice)),
            currentUserIdProvider.overrideWith((ref) => alice),
            groupMembersProvider.overrideWith(
              (ref, g) => Stream.value(members),
            ),
            currentParticipantProvider.overrideWith(
              (ref, g) => Future<MemberModel?>.value(members.first),
            ),
            ledgerGroupsProvider.overrideWith(
              (ref) => Stream.value(const [
                GroupModel(
                  roomId: 'g1',
                  name: 'Trip',
                  currency: 'CHF',
                  updatedAt: 1000,
                ),
              ]),
            ),
            // G74: no own payment details (a Drift watch never settles).
            myPaymentDetailsProvider.overrideWith((_) => Stream.value(null)),
            // G69: the overview reads the expenses — static, a Drift watch
            // stream never settles under the fake clock (G33).
            expensesForRoomProvider.overrideWith(
              (ref, g) => Stream.value(const <ExpenseModel>[]),
            ),
            balanceForRoomProvider.overrideWith(
              (ref, g) => const [
                DebtEntry(from: bob, to: alice, cents: 1000, currency: 'CHF'),
                DebtEntry(from: carl, to: alice, cents: 1000, currency: 'CHF'),
              ],
            ),
          ],
        ),
      );
      await tester.pump();
      await tester.pump();
    }

    /// Taps the dialog's Record button and lets the Drift write + relay run
    /// on the real event loop (see create_group_page_test.dart).
    Future<List<SettlementModel>> recordAndRead(
      WidgetTester tester,
      AppDatabase db,
    ) async {
      late List<SettlementModel> result;
      await tester.runAsync(() async {
        await tester.tap(find.widgetWithText(FilledButton, 'Record'));
        await eventually(
          () async =>
              (await ExpensesDao(db).getSettlementsForRoom('g1')).isNotEmpty,
          tester: tester,
        );
        result = await ExpensesDao(db).getSettlementsForRoom('g1');
      });
      return result;
    }

    testWidgets('tapping a local person\'s debt records Carl → Alice', (
      tester,
    ) async {
      final db = openTestDatabase();
      addTearDown(db.close);
      final net = FakeMatrixNetwork();
      final received = <TransportMessage>[];
      net.clientFor(bob).onMessage.listen(received.add);
      // The relay targets the claimed members stored in the DB.
      await tester.runAsync(() async {
        for (final id in [alice, bob]) {
          await MembersDao(db).upsertMemberLww(
            MembersCompanion(
              groupId: const Value('g1'),
              userId: Value(id),
              matrixId: Value(id),
              status: const Value('active'),
              updatedAt: const Value(1000),
            ),
          );
        }
      });
      await pumpPage(tester, db, net);

      await tester.tap(_debtTitle('Carl pays you'));
      await tester.pumpAndSettle();
      expect(find.text('Record payment'), findsOneWidget);
      // Prefilled with the debt's amount; no "exceeds" warning.
      expect(find.widgetWithText(TextField, '10.00'), findsOneWidget);
      expect(find.byKey(const Key('paymentExceedsWarning')), findsNothing);

      final settlements = await recordAndRead(tester, db);
      expect(settlements, hasLength(1));
      final s = settlements.single;
      expect(
        (s.fromUser, s.toUser, s.amountCents, s.currency),
        (carl, alice, 1000, 'CHF'),
      );
      // Replicated to the claimed members like any settlement.
      expect(
        received.where((m) => m.type == settlementEventType),
        hasLength(1),
      );
      expect(received.first.content['from'], carl);
    });

    testWidgets('warns when the amount exceeds the debt', (tester) async {
      final db = openTestDatabase();
      addTearDown(db.close);
      await pumpPage(tester, db, FakeMatrixNetwork());

      await tester.tap(_debtTitle('Bob pays you'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('paymentAmount')), '12');
      await tester.pump();
      expect(find.byKey(const Key('paymentExceedsWarning')), findsOneWidget);
    });

    testWidgets('G60: the Yesterday chip back-dates the payment', (
      tester,
    ) async {
      final db = openTestDatabase();
      addTearDown(db.close);
      await pumpPage(tester, db, FakeMatrixNetwork());

      await tester.tap(_debtTitle('Bob pays you'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.byKey(const Key('paymentDateValue'))).data,
        'Today',
      );
      await tester.ensureVisible(find.byKey(const Key('paymentDateYesterday')));
      await tester.tap(find.byKey(const Key('paymentDateYesterday')));
      await tester.pump();
      expect(
        tester.widget<Text>(find.byKey(const Key('paymentDateValue'))).data,
        'Yesterday',
      );

      final s = (await recordAndRead(tester, db)).single;
      final now = DateTime.now();
      expect(s.date, expenseDateOf(DateTime(now.year, now.month, now.day - 1)));
    });

    testWidgets('"Record payment" action: creditor records bob paid them', (
      tester,
    ) async {
      final db = openTestDatabase();
      addTearDown(db.close);
      await pumpPage(tester, db, FakeMatrixNetwork());

      await tester.tap(find.byKey(const Key('recordPayment')));
      await tester.pumpAndSettle();
      // Defaults: from = us, currency = the group's.
      expect(find.text('CHF'), findsWidgets);
      await tester.tap(find.byKey(const Key('paymentFrom')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bob').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('paymentTo')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Alice').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('paymentAmount')), '4.50');
      await tester.pump();

      final s = (await recordAndRead(tester, db)).single;
      expect(
        (s.fromUser, s.toUser, s.amountCents, s.currency),
        (bob, alice, 450, 'CHF'),
      );
    });

    // G18 review (findings 6, 14): no zero payments; a live preview.
    testWidgets('a zero amount is refused, a valid one previewed', (
      tester,
    ) async {
      final db = openTestDatabase();
      addTearDown(db.close);
      await pumpPage(tester, db, FakeMatrixNetwork());

      await tester.tap(find.byKey(const Key('recordPayment')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('paymentFrom')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bob').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('paymentTo')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Alice').last);
      await tester.pumpAndSettle();
      FilledButton record() => tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Record'),
      );
      await tester.enterText(find.byKey(const Key('paymentAmount')), '0');
      await tester.pump();
      expect(record().onPressed, isNull);
      expect(find.text('Enter an amount greater than 0'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('paymentAmount')), '1,234');
      await tester.pump();
      expect(record().onPressed, isNotNull);
      expect(find.text('= CHF\u00a01,234.00'), findsOneWidget);
    });

    testWidgets('same payer and recipient cannot be recorded', (tester) async {
      final db = openTestDatabase();
      addTearDown(db.close);
      await pumpPage(tester, db, FakeMatrixNetwork());

      await tester.tap(find.byKey(const Key('recordPayment')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('paymentTo')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Alice').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('paymentAmount')), '5');
      await tester.pump();
      final record = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Record'),
      );
      expect(record.onPressed, isNull);
    });

    testWidgets('removed from the group → nothing can be recorded', (
      tester,
    ) async {
      final db = openTestDatabase();
      addTearDown(db.close);
      await pumpPage(tester, db, FakeMatrixNetwork(), aliceStatus: 'removed');

      expect(find.byKey(const Key('recordPayment')), findsNothing);
      expect(find.byType(ListTile), findsNWidgets(2));
      for (final tile in tester.widgetList<ListTile>(find.byType(ListTile))) {
        expect(tile.onTap, isNull);
      }
    });
  });
}
