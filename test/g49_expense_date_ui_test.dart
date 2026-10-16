/// G49 widget test: the ledger list groups and sorts expenses by their
/// display date (`date ?? created_at`) — a back-dated expense lands under
/// the day it happened, not the day it was entered.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/l10n/formatting.dart';
import 'package:money_ledger/features/expenses/expenses_page.dart';
import 'package:money_ledger/features/groups/group_archive_provider.dart';
import 'package:money_ledger/features/groups/group_provider.dart';
import 'package:money_ledger/models/expense_date.dart';
import 'package:money_ledger/models/expense_model.dart';
import 'package:money_ledger/models/group_model.dart';
import 'package:money_ledger/models/member_model.dart';

import 'helpers/test_providers.dart';

const _roomId = 'g1';
const _me = '@alice:x.org';

const _alice = MemberModel(
  groupId: _roomId,
  userId: _me,
  displayName: 'Alice',
  matrixId: _me,
  status: 'active',
  updatedAt: 1,
);

ExpenseModel _e(
  String id,
  String description,
  DateTime created, {
  String? date,
}) => ExpenseModel(
  id: id,
  roomId: _roomId,
  description: description,
  amountCents: 2000,
  currency: 'EUR',
  paidBy: _me,
  splitsJson: '{"$_me":1000,"@bob:x.org":1000}',
  createdAt: created.millisecondsSinceEpoch,
  updatedAt: created.millisecondsSinceEpoch,
  date: date,
);

void main() {
  testWidgets('a back-dated expense sits under its own day, days newest '
      'first', (tester) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day, 9);
    final twoDaysAgo = DateTime(now.year, now.month, now.day - 2, 9);
    final fiveDaysAgo = DateTime(now.year, now.month, now.day - 5);
    final expenses = [
      // Entered today (latest), but it happened five days ago.
      _e(
        'old',
        'Old dinner',
        today.add(const Duration(hours: 2)),
        date: expenseDateOf(fiveDaysAgo),
      ),
      _e('lunch', 'Lunch', today),
      _e('taxi', 'Taxi', twoDaysAgo),
    ];
    await tester.pumpWidget(
      testApp(
        const ExpensesPage(roomId: _roomId),
        overrides: [
          ...testOverrides(
            isLoggedIn: true,
            expenses: expenses,
            members: [_alice],
            groups: [
              const GroupModel(roomId: _roomId, name: 'Trip', currency: 'EUR'),
            ],
          ),
          currentUserIdProvider.overrideWith((_) => _me),
          currentParticipantProvider.overrideWith((_, _) async => _alice),
          groupLedgerFingerprintProvider.overrideWith((_, _) => 'fp'),
        ],
      ),
    );
    await tester.pump();
    await tester.pump();

    double y(Finder f) => tester.getTopLeft(f).dy;
    final todayHeader = find.text('Today');
    final twoDaysHeader = find.text(
      formatDayHeader(twoDaysAgo.millisecondsSinceEpoch, 'en'),
    );
    final fiveDaysHeader = find.text(
      formatDayHeader(fiveDaysAgo.millisecondsSinceEpoch, 'en'),
    );
    for (final f in [todayHeader, twoDaysHeader, fiveDaysHeader]) {
      expect(f, findsOneWidget);
    }
    expect(find.byKey(const Key('dayHeader')), findsNWidgets(3));

    // Today: only Lunch; two days ago: Taxi; five days ago: Old dinner.
    expect(y(todayHeader), lessThan(y(find.text('Lunch'))));
    expect(y(find.text('Lunch')), lessThan(y(twoDaysHeader)));
    expect(y(twoDaysHeader), lessThan(y(find.text('Taxi'))));
    expect(y(find.text('Taxi')), lessThan(y(fiveDaysHeader)));
    expect(y(fiveDaysHeader), lessThan(y(find.text('Old dinner'))));
  });

  test('displayDay drives the order: date first, then creation time', () {
    final created = DateTime(2026, 10, 17, 9).millisecondsSinceEpoch;
    final a = _e('a', 'a', DateTime.fromMillisecondsSinceEpoch(created));
    final b = _e(
      'b',
      'b',
      DateTime.fromMillisecondsSinceEpoch(created),
      date: '2026-10-16',
    );
    expect(a.displayDay.isAfter(b.displayDay), isTrue);
  });
}
