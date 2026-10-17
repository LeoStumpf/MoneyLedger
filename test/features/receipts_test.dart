/// G78: receipt photos, this device only — the store, its lifecycle (expense
/// deleted, group left / deleted, local data deleted / adopted) and the
/// privacy text.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/database/app_database.dart';
import 'package:money_ledger/core/matrix/transport_provider.dart';
import 'package:money_ledger/core/sync/sync_engine.dart';
import 'package:money_ledger/features/expenses/expenses_provider.dart';
import 'package:money_ledger/features/groups/group_provider.dart';
import 'package:money_ledger/features/history/snapshot_store.dart';
import 'package:money_ledger/features/receipts/receipt_store.dart';
import 'package:money_ledger/features/receipts/receipt_store_io.dart';
import 'package:money_ledger/models/expense_model.dart';

import '../helpers/fake_ledger_network.dart';
import '../helpers/in_memory_database.dart';

const alice = '@alice:x.org';

Uint8List _bytes(int n) => Uint8List.fromList([n, n + 1, n + 2]);

ExpenseModel _expense(String id, {bool deleted = false}) => ExpenseModel(
  id: id,
  roomId: 'g',
  description: 'x',
  amountCents: 100,
  currency: 'EUR',
  paidBy: alice,
  splitsJson: '{"$alice":100}',
  createdAt: 1,
  updatedAt: 2,
  deleted: deleted,
);

void main() {
  group('FileReceiptStore', () {
    late Directory dir;
    late FileReceiptStore store;
    setUp(() async {
      dir = await Directory.systemTemp.createTemp('receipts_test');
      store = FileReceiptStore(() async => Directory('${dir.path}/db1'));
    });
    tearDown(() => dir.delete(recursive: true));

    test('write / read / list / delete / deleteAll', () async {
      expect(await store.list(), isEmpty);
      expect(await store.read('e1'), isNull);
      await store.write('e1', _bytes(1));
      await store.write('e2', _bytes(2));
      expect(await store.list(), {'e1', 'e2'});
      expect(await store.read('e1'), _bytes(1));
      expect(File('${dir.path}/db1/e1.jpg').existsSync(), isTrue);
      // Replacing keeps one file.
      await store.write('e1', _bytes(5));
      expect(await store.read('e1'), _bytes(5));
      await store.delete('e1');
      await store.delete('e1'); // idempotent
      expect(await store.list(), {'e2'});
      await store.deleteAll();
      expect(Directory('${dir.path}/db1').existsSync(), isFalse);
      expect(await store.list(), isEmpty);
    });

    test(
      'an unfinished write (temp file) is no photo and is cleaned',
      () async {
        await store.write('e1', _bytes(1));
        File('${dir.path}/db1/e2.jpg.tmp').writeAsBytesSync([1]);
        expect(await store.list(), {'e1'});
        expect(File('${dir.path}/db1/e2.jpg.tmp').existsSync(), isFalse);
      },
    );

    test('ids that could leave the directory are refused', () async {
      for (final id in ['', '../x', 'a/b', r'a\b', '.hidden']) {
        expect(isValidReceiptId(id), isFalse, reason: id);
        await expectLater(store.write(id, _bytes(1)), throwsArgumentError);
      }
      expect(isValidReceiptId('0192f0c4-7d1e-7abc-8def-0123456789ab'), isTrue);
    });

    test('not offered on the test VM (Android only)', () {
      expect(platformReceiptStoreFactory(), isNull);
    });
  });

  group('lifecycle helpers', () {
    test('sweep: photos of deleted (tombstoned) or gone expenses go, '
        'live ones stay', () async {
      final store = InMemoryReceiptStore();
      for (final id in ['live', 'tomb', 'gone']) {
        await store.write(id, _bytes(1));
      }
      final rows = {
        'live': _expense('live'),
        'tomb': _expense('tomb', deleted: true),
      };
      expect(await sweepReceipts(store, (id) async => rows[id]), 2);
      expect(await store.list(), {'live'});
    });

    test('deleteReceiptsOf / moveReceipts', () async {
      final from = InMemoryReceiptStore();
      final to = InMemoryReceiptStore();
      await from.write('a', _bytes(1));
      await from.write('b', _bytes(2));
      await to.write('b', _bytes(9)); // already there: kept
      await moveReceipts(from, to);
      expect(to.files['a'], _bytes(1));
      expect(to.files['b'], _bytes(9));
      await deleteReceiptsOf(to, ['a', 'missing']);
      expect(await to.list(), {'b'});
      // No store (web / demo): nothing to do, no error.
      await moveReceipts(null, to);
      await deleteReceiptsOf(null, ['b']);
    });

    test('local data deleted → its receipt photos go with the DB files and '
        'snapshots', () async {
      final receipts = InMemoryReceiptStore();
      await receipts.write('e1', _bytes(1));
      final snapshots = InMemorySnapshotStore()..files['x.json'] = '{}';
      final ok = await deleteLedgerFilesAndSnapshots(
        () async => true,
        snapshots,
        receipts: receipts,
      );
      expect(ok, isTrue);
      expect(receipts.files, isEmpty);
      expect(snapshots.files, isEmpty);
    });
  });

  group('with a ledger', () {
    late AppDatabase db;
    late ProviderContainer c;
    late InMemoryReceiptStore store;

    setUp(() {
      final net = FakeMatrixNetwork();
      db = openTestDatabase();
      store = InMemoryReceiptStore();
      c = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          ledgerTransportProvider.overrideWith((ref) => net.clientFor(alice)),
          receiptStoreProvider.overrideWithValue(store),
          pokeDebounceProvider.overrideWithValue(const Duration(hours: 1)),
          syncIntervalProvider.overrideWithValue(const Duration(hours: 1)),
        ],
      );
    });
    tearDown(() async {
      c.dispose();
      await db.close();
    });

    Future<(String, String)> groupWithExpense() async {
      await c.read(groupCreatorProvider.notifier).create('Trip', 'EUR');
      final g = (await c.read(groupsDaoProvider).getAllGroups()).single.roomId;
      final w = await c
          .read(expenseAdderProvider.notifier)
          .addExpense(
            roomId: g,
            description: 'Dinner',
            amountCents: 4000,
            currency: 'EUR',
            paidBy: (await c.read(
              currentParticipantProvider(g).future,
            ))!.userId,
            splits: {
              (await c.read(currentParticipantProvider(g).future))!.userId:
                  4000,
            },
          );
      return (g, w!.recordId);
    }

    test('the index lists photos and follows save / remove', () async {
      await store.write('old', _bytes(1));
      final sub = c.listen(receiptIndexProvider, (_, _) {});
      addTearDown(sub.close);
      expect(await c.read(receiptIndexProvider.future), {'old'});
      final index = c.read(receiptIndexProvider.notifier);
      await index.save('new', _bytes(2));
      expect(c.read(receiptIndexProvider).value, {'old', 'new'});
      expect(await index.read('new'), _bytes(2));
      await index.remove('old');
      expect(c.read(receiptIndexProvider).value, {'new'});
      expect(await store.list(), {'new'});
    });

    test('deleting an expense keeps its photo for Undo; the next start '
        'removes it', () async {
      final (g, id) = await groupWithExpense();
      await store.write(id, _bytes(1));
      await c.read(expenseAdderProvider.notifier).deleteExpense(id, g);
      expect(await store.list(), {id}, reason: 'Undo must not lose it');
      // App start (per ledger DB open): the tombstoned expense's photo goes.
      final sub = c.listen(receiptMaintenanceProvider, (_, _) {});
      addTearDown(sub.close);
      await c.read(receiptMaintenanceProvider.future);
      expect(await store.list(), isEmpty);
    });

    test('a live expense keeps its photo across starts', () async {
      final (_, id) = await groupWithExpense();
      await store.write(id, _bytes(1));
      final sub = c.listen(receiptMaintenanceProvider, (_, _) {});
      addTearDown(sub.close);
      await c.read(receiptMaintenanceProvider.future);
      expect(await store.list(), {id});
    });

    test('deleting the group removes its photos at once', () async {
      final (g, id) = await groupWithExpense();
      await store.write(id, _bytes(1));
      await store.write('other-group-expense', _bytes(2));
      await c.read(groupExiterProvider.notifier).delete(g);
      expect(c.read(groupExiterProvider).hasError, isFalse);
      expect(await store.list(), {'other-group-expense'});
    });
  });

  test('PRIVACY.md and the in-app text say the same about receipt photos', () {
    String norm(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();
    final privacy = norm(File('PRIVACY.md').readAsStringSync());
    for (final file in ['app_en', 'app_de']) {
      final arb =
          jsonDecode(File('lib/l10n/$file.arb').readAsStringSync())
              as Map<String, Object?>;
      expect(arb['privacyReceiptsBody'], isA<String>(), reason: file);
      if (file == 'app_en') {
        expect(privacy, contains(norm(arb['privacyReceiptsBody']! as String)));
        expect(privacy, contains('## ${arb['privacyReceiptsTitle']}'));
      }
    }
  });
}
