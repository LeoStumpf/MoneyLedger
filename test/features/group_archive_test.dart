/// G16: device-local group archive — the codec, the ledger fingerprint, the
/// SettingsDao storage and the derived "still archived?" provider (new
/// activity un-archives automatically; leaving a group drops the entry).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/database/daos/expenses_dao.dart';
import 'package:money_ledger/core/database/daos/settings_dao.dart';
import 'package:money_ledger/core/sync/left_groups.dart';
import 'package:money_ledger/features/expenses/expenses_provider.dart';
import 'package:money_ledger/features/groups/group_archive_provider.dart';
import 'package:money_ledger/models/expense_model.dart';
import 'package:money_ledger/models/group_archive.dart';

import '../helpers/eventually.dart';
import '../helpers/in_memory_database.dart';

ExpenseModel _e(String id, int updatedAt, {bool deleted = false}) =>
    ExpenseModel(
      id: id,
      roomId: 'g1',
      description: 'x',
      amountCents: 100,
      currency: 'EUR',
      paidBy: 'p1',
      splitsJson: '{"p1":100}',
      createdAt: 1,
      updatedAt: updatedAt,
      deleted: deleted,
    );

SettlementModel _s(String id, int updatedAt) => SettlementModel(
  id: id,
  roomId: 'g1',
  amountCents: 100,
  currency: 'EUR',
  fromUser: 'p1',
  toUser: 'p2',
  createdAt: 1,
  updatedAt: updatedAt,
);

void main() {
  group('GroupArchive codec', () {
    test('round-trips; corrupt or missing = not archived', () {
      const a = GroupArchive(archivedAt: 5, fingerprint: 'abc');
      final back = GroupArchive.decode(a.encode())!;
      expect((back.archivedAt, back.fingerprint), (5, 'abc'));
      expect(GroupArchive.decode(null), isNull);
      expect(GroupArchive.decode('not json'), isNull);
      expect(GroupArchive.decode('{"at":1}'), isNull);
    });
  });

  group('ledgerFingerprint', () {
    final base = ledgerFingerprint([_e('a', 10), _e('b', 20)], [_s('s', 30)]);

    test('order-independent and stable', () {
      expect(
        ledgerFingerprint([_e('b', 20), _e('a', 10)], [_s('s', 30)]),
        base,
      );
      expect(base, hasLength(16));
    });

    test('any add / edit / delete changes it', () {
      final changed = [
        ledgerFingerprint(
          [_e('a', 10), _e('b', 20), _e('c', 5)],
          [_s('s', 30)],
        ),
        // An edit of an older record (its clock stays below the newest).
        ledgerFingerprint([_e('a', 11), _e('b', 20)], [_s('s', 30)]),
        ledgerFingerprint(
          [_e('a', 10), _e('b', 21, deleted: true)],
          [_s('s', 30)],
        ),
        ledgerFingerprint([_e('a', 10), _e('b', 20)], [_s('s', 31)]),
        ledgerFingerprint([_e('a', 10), _e('b', 20)], []),
      ];
      for (final f in changed) {
        expect(f, isNot(base));
      }
      expect(
        const GroupArchive(archivedAt: 0, fingerprint: 'x').holdsFor('x'),
        isTrue,
      );
    });
  });

  group('storage + groupArchivedProvider', () {
    late ProviderContainer container;
    late ExpensesDao expenses;
    late SettingsDao settings;

    setUp(() async {
      final db = openTestDatabase();
      expenses = ExpensesDao(db);
      settings = SettingsDao(db);
      await expenses.upsertExpenseLww(expenseCompanion(_e('a', 10)));
      container = ProviderContainer(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
      );
      addTearDown(() async {
        container.dispose();
        await db.close();
      });
      container.listen(groupArchiverProvider, (_, _) {});
      container.listen(groupArchivedProvider('g1'), (_, _) {});
      container.listen(groupArchivedProvider('g2'), (_, _) {});
    });

    bool archived(String g) => container.read(groupArchivedProvider(g));

    test('archive → archived; unarchive → back', () async {
      expect(archived('g1'), isFalse);
      await container.read(groupArchiverProvider.notifier).archive('g1');
      await eventually(() => archived('g1'));
      expect(archived('g2'), isFalse);
      await container.read(groupArchiverProvider.notifier).unarchive('g1');
      await eventually(() => !archived('g1'));
    });

    test('a new or changed record un-archives it automatically', () async {
      await container.read(groupArchiverProvider.notifier).archive('g1');
      await eventually(() => archived('g1'));

      // A peer's new expense arrives (any path that writes the DB).
      await expenses.upsertExpenseLww(expenseCompanion(_e('b', 5)));
      await eventually(() => !archived('g1'));

      // Re-archive; then an edit of an existing record.
      await container.read(groupArchiverProvider.notifier).archive('g1');
      await eventually(() => archived('g1'));
      await expenses.upsertExpenseLww(expenseCompanion(_e('a', 11)));
      await eventually(() => !archived('g1'));
      // The stale entry stays, but no longer holds.
      expect(
        (await settings.watchArchivedGroups().first).containsKey('g1'),
        isTrue,
      );
    });

    test('leaving / deleting the group drops its archive entry', () async {
      await container.read(groupArchiverProvider.notifier).archive('g1');
      await eventually(() => archived('g1'));
      await settings.purgeGroupAsLeft(
        'g1',
        const LeftGroupTombstone(leftAt: 1),
      );
      expect(await settings.watchArchivedGroups().first, isEmpty);
    });
  });
}
