/// G67 (U13): the pure undo planner.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/features/expenses/record_undo.dart';
import 'package:money_ledger/features/history/group_history.dart';
import 'package:money_ledger/models/expense_model.dart';

ExpenseModel _expense({
  int updatedAt = 100,
  bool deleted = false,
  String description = 'Pizza',
  int amount = 1000,
}) => ExpenseModel(
  id: 'e1',
  roomId: 'g',
  description: description,
  amountCents: amount,
  currency: 'EUR',
  paidBy: 'p1',
  splitsJson: '{"p1":${amount ~/ 2},"p2":${amount - amount ~/ 2}}',
  createdAt: 50,
  updatedAt: updatedAt,
  deleted: deleted,
);

SettlementModel _payment({int updatedAt = 100, bool deleted = false}) =>
    SettlementModel(
      id: 's1',
      roomId: 'g',
      amountCents: 500,
      currency: 'EUR',
      fromUser: 'p2',
      toUser: 'p1',
      createdAt: 50,
      updatedAt: updatedAt,
      deleted: deleted,
    );

void main() {
  test('undo of a delete brings the earlier content back', () {
    final before = _expense();
    final tomb = _expense(updatedAt: 200, deleted: true);
    final change = planUndo(
      UndoableWrite.expense(writtenExpense: tomb, beforeExpense: before),
      currentExpense: tomb,
      now: 150,
    )!;
    expect(change.effect, ResetEffect.restored);
    expect(change.expense!.deleted, isFalse);
    expect(change.expense!.description, 'Pizza');
    expect(change.expense!.updatedAt, 201); // nextLwwClock(stored)
    expect(change.expense!.createdAt, 50);
  });

  test('undo of an edit reverts to the earlier content', () {
    final before = _expense();
    final edited = _expense(updatedAt: 200, description: 'Pasta', amount: 800);
    final change = planUndo(
      UndoableWrite.expense(writtenExpense: edited, beforeExpense: before),
      currentExpense: edited,
      now: 1000,
    )!;
    expect(change.effect, ResetEffect.reverted);
    expect(change.expense!.description, 'Pizza');
    expect(change.expense!.amountCents, 1000);
    expect(change.expense!.updatedAt, 1000);
  });

  test('undo of a creation is a tombstone', () {
    final created = _payment();
    final change = planUndo(
      UndoableWrite.settlement(writtenSettlement: created),
      currentSettlement: created,
      now: 0,
    )!;
    expect(change.effect, ResetEffect.removed);
    expect(change.settlement!.deleted, isTrue);
    expect(change.settlement!.amountCents, 500);
    expect(change.settlement!.updatedAt, 101);
  });

  test('nothing when the record changed after the write', () {
    final tomb = _expense(updatedAt: 200, deleted: true);
    final write = UndoableWrite.expense(
      writtenExpense: tomb,
      beforeExpense: _expense(),
    );
    // Newer version from someone else.
    expect(planUndo(write, currentExpense: _expense(updatedAt: 300)), isNull);
    // Same clock, other content (G27 tie-break winner).
    expect(
      planUndo(write, currentExpense: _expense(updatedAt: 200, amount: 1)),
      isNull,
    );
    // Gone.
    expect(planUndo(write), isNull);
  });
}
