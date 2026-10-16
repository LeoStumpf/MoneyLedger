/// G48 rotating on-device snapshots: the pure rotation policy, the daily
/// "write only if changed" step, listing / reading them back, and deleting
/// local mode's snapshots with its ledger.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/database/app_database.dart';
import 'package:money_ledger/core/database/daos/expenses_dao.dart';
import 'package:money_ledger/core/database/daos/groups_dao.dart';
import 'package:money_ledger/core/database/daos/history_dao.dart';
import 'package:money_ledger/core/database/daos/members_dao.dart';
import 'package:money_ledger/core/database/daos/settings_dao.dart';
import 'package:money_ledger/core/database/daos/signing_dao.dart';
import 'package:money_ledger/features/backup/backup_service.dart';
import 'package:money_ledger/features/history/restore_points.dart';
import 'package:money_ledger/features/history/snapshot_policy.dart';
import 'package:money_ledger/features/history/snapshot_store.dart';
import 'package:money_ledger/features/history/snapshot_store_io.dart';
import 'package:money_ledger/models/expense_model.dart';
import 'package:money_ledger/models/group_model.dart';

import '../helpers/fake_ledger_network.dart';
import '../helpers/in_memory_database.dart';

const me = '@ann:x.org';

void main() {
  group('policy', () {
    test('file names round-trip; other files are ignored', () {
      final d = DateTime(2026, 3, 7, 18, 30);
      expect(snapshotFileName(d), '2026-03-07.json');
      expect(parseSnapshotFileName('2026-03-07.json'), DateTime(2026, 3, 7));
      expect(parseSnapshotFileName('2026-02-30.json'), isNull);
      expect(parseSnapshotFileName('2026-03-07.json.tmp'), isNull);
      expect(parseSnapshotFileName('notes.txt'), isNull);
    });

    test('keeps the 7 newest days plus the newest of 4 older weeks', () {
      // 60 consecutive days ending Friday 2026-10-16.
      final end = DateTime(2026, 10, 16);
      final days = [
        for (var i = 0; i < 60; i++) DateTime(end.year, end.month, end.day - i),
      ];
      final keep = snapshotsToKeep(days).toList()..sort();
      expect(keep, hasLength(11));
      // Daily: Oct 10 … 16.
      expect(keep.sublist(4), [
        for (var d = 10; d <= 16; d++) DateTime(2026, 10, d),
      ]);
      // Weekly: Sundays of the four weeks before (Oct 10's week = Oct 5–11
      // is covered by the dailies).
      expect(keep.sublist(0, 4), [
        DateTime(2026, 9, 13),
        DateTime(2026, 9, 20),
        DateTime(2026, 9, 27),
        DateTime(2026, 10, 4),
      ]);
    });

    test('few or sparse snapshots are all kept', () {
      final days = [
        DateTime(2026, 1, 1),
        DateTime(2026, 3, 1),
        DateTime(2026, 6, 1),
      ];
      expect(snapshotsToKeep(days), days.toSet());
    });

    test('a check is due once per local day', () {
      final t = DateTime(2026, 10, 16, 9);
      expect(snapshotCheckDue(null, t), isTrue);
      expect(snapshotCheckDue('2026-10-16', t), isFalse);
      expect(snapshotCheckDue('2026-10-15', t), isTrue);
    });
  });

  group('RestorePointsService', () {
    late AppDatabase db;
    late InMemorySnapshotStore store;
    late RestorePointsService service;

    setUp(() {
      db = openTestDatabase();
      store = InMemorySnapshotStore();
      service = RestorePointsService(
        db: db,
        history: HistoryDao(db),
        backup: BackupService(
          db: db,
          groups: GroupsDao(db),
          members: MembersDao(db),
          expenses: ExpensesDao(db),
          settings: SettingsDao(db),
          signing: SigningDao(db),
          transport: Future.value(FakeMatrixNetwork().clientFor(me)),
        ),
        store: store,
        account: me,
      );
    });
    tearDown(() => db.close());

    Future<void> addExpense(String id, String what) =>
        ExpensesDao(db).upsertExpenseLww(
          expenseCompanion(
            ExpenseModel(
              id: id,
              roomId: 'g1',
              description: what,
              amountCents: 100,
              currency: 'EUR',
              paidBy: me,
              splitsJson: '{"$me":100}',
              createdAt: 1,
              updatedAt: 1,
            ),
          ),
        );

    test('nothing to protect → no snapshot', () async {
      expect(await service.snapshotIfDue(DateTime(2026, 10, 16)), isFalse);
      expect(store.files, isEmpty);
    });

    test('written once a day, only when the ledger changed', () async {
      await GroupsDao(db).upsertGroupLww(
        groupCompanion(
          const GroupModel(roomId: 'g1', name: 'Trip', currency: 'EUR'),
        ),
      );
      await addExpense('e1', 'Dinner');
      final day1 = DateTime(2026, 10, 16, 9);
      expect(await service.snapshotIfDue(day1), isTrue);
      expect(store.files.keys, ['2026-10-16.json']);
      // Same day: not again (even after a change).
      await addExpense('e2', 'Taxi');
      expect(await service.snapshotIfDue(day1), isFalse);
      // Next day: changed since → written.
      expect(await service.snapshotIfDue(DateTime(2026, 10, 17, 9)), isTrue);
      // Day after: unchanged → nothing.
      expect(await service.snapshotIfDue(DateTime(2026, 10, 18, 9)), isFalse);
      expect(store.files.keys, ['2026-10-16.json', '2026-10-17.json']);

      final points = await service.list();
      expect(points.map((p) => p.name), ['2026-10-17.json', '2026-10-16.json']);
      expect(points.first.groups, 1);
      expect(points.first.records, 2);
      expect(points.last.records, 1);
      expect(
        points.first.exportedAt,
        DateTime(2026, 10, 17, 9).millisecondsSinceEpoch,
      );
      final backup = await service.read('2026-10-16.json');
      expect(backup.account, me);
      expect(backup.groups.single['group'], 'g1');
    });

    test('old snapshots are rotated out', () async {
      for (var i = 1; i <= 40; i++) {
        store.files[snapshotFileName(DateTime(2026, 8, i))] = '{}';
      }
      store.files['README.txt'] = 'not a snapshot';
      await GroupsDao(db).upsertGroupLww(
        groupCompanion(
          const GroupModel(roomId: 'g1', name: 'Trip', currency: 'EUR'),
        ),
      );
      expect(await service.snapshotIfDue(DateTime(2026, 10, 16)), isTrue);
      final names = store.files.keys.where((n) => n.endsWith('.json'));
      expect(names, hasLength(11));
      expect(names, contains('2026-10-16.json'));
      expect(store.files, contains('README.txt'));
      // Unreadable snapshots are skipped when listing.
      expect((await service.list()).map((p) => p.name), ['2026-10-16.json']);
    });

    test('maintain prunes the history and never throws', () async {
      await addExpense('e1', 'Dinner');
      final failing = RestorePointsService(
        db: db,
        history: HistoryDao(db),
        backup: service.backup,
        store: _ThrowingStore(),
        account: me,
      );
      await GroupsDao(db).upsertGroupLww(
        groupCompanion(
          const GroupModel(roomId: 'g1', name: 'Trip', currency: 'EUR'),
        ),
      );
      await failing.maintain(now: DateTime(2026, 10, 16));
      expect(await HistoryDao(db).floor(), greaterThan(0));
    });

    test('no store (web) → nothing, empty list', () async {
      final web = RestorePointsService(
        db: db,
        history: HistoryDao(db),
        backup: service.backup,
        store: null,
        account: me,
      );
      await addExpense('e1', 'Dinner');
      expect(await web.snapshotIfDue(DateTime(2026, 10, 16)), isFalse);
      expect(await web.list(), isEmpty);
    });
  });

  test('file store: atomic write, list, read, delete, deleteAll', () async {
    final tmp = await Directory.systemTemp.createTemp('snapshots');
    addTearDown(() async {
      if (await tmp.exists()) await tmp.delete(recursive: true);
    });
    final dir = Directory('${tmp.path}/snapshots/money_ledger_x');
    final store = FileSnapshotStore(() async => dir);
    expect(await store.list(), isEmpty);
    await store.write('2026-10-16.json', '{"a":1}');
    await store.write('2026-10-15.json', '{}');
    expect(
      await store.list(),
      unorderedEquals(['2026-10-16.json', '2026-10-15.json']),
    );
    expect(await store.read('2026-10-16.json'), '{"a":1}');
    await store.delete('2026-10-15.json');
    expect(await store.list(), ['2026-10-16.json']);
    expect(() => store.write('../evil.json', ''), throwsArgumentError);
    await store.deleteAll();
    expect(await dir.exists(), isFalse);
  });

  test('local data deleted → its snapshots go too', () async {
    final store = InMemorySnapshotStore()..files['2026-10-16.json'] = '{}';
    expect(
      await deleteLedgerFilesAndSnapshots(() async => true, store),
      isTrue,
    );
    expect(store.files, isEmpty);
    // A failing snapshot deletion doesn't hide the DB result.
    expect(
      await deleteLedgerFilesAndSnapshots(() async => false, _ThrowingStore()),
      isFalse,
    );
  });
}

class _ThrowingStore extends InMemorySnapshotStore {
  @override
  Future<void> write(String name, String content) =>
      Future.error(StateError('disk full'));
  @override
  Future<void> deleteAll() => Future.error(StateError('denied'));
}
