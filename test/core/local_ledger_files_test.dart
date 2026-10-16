/// G41: local mode's ledger files are deleted only once every instance is
/// closed, and a reopen during the deletion waits for it (fresh, empty DB).
library;

import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show LazyDatabase;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/database/account_database.dart';
import 'package:money_ledger/core/database/app_database.dart';
import 'package:money_ledger/core/database/daos/groups_dao.dart';
import 'package:money_ledger/models/group_model.dart';

void main() {
  late Directory tmp;
  late File file;
  late List<AppDatabase> opened;
  late Completer<void>? gate;
  late LocalLedgerFiles files;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('local_files_');
    file = File('${tmp.path}/money_ledger_local.sqlite');
    opened = [];
    gate = null;
    files = LocalLedgerFiles(
      open: (after) {
        final db = AppDatabase.forTesting(
          LazyDatabase(() async {
            await after;
            return NativeDatabase(file);
          }),
        );
        opened.add(db);
        return db;
      },
      delete: () async {
        await gate?.future;
        for (final suffix in const ['', '-journal', '-wal', '-shm']) {
          final f = File('${file.path}$suffix');
          if (await f.exists()) await f.delete();
        }
      },
    );
  });

  tearDown(() async {
    for (final db in opened) {
      await db.close();
    }
    await tmp.delete(recursive: true);
  });

  Future<void> addGroup(AppDatabase db) => GroupsDao(db).upsertGroupLww(
    groupCompanion(
      const GroupModel(roomId: 'g', name: 'Trip', currency: 'EUR'),
    ),
  );

  test('refuses while an instance is open; deletes once closed', () async {
    final db = files.open();
    await addGroup(db);
    expect(await file.exists(), isTrue);

    expect(await files.delete(), isFalse, reason: 'still open');
    expect(await file.exists(), isTrue);

    await db.close();
    expect(await files.delete(), isTrue);
    expect(await file.exists(), isFalse);

    // Local mode again: a fresh, empty DB.
    final again = files.open();
    expect(await GroupsDao(again).getAllGroups(), isEmpty);
    expect(await file.exists(), isTrue);
  });

  test('a close still in progress is awaited before deleting', () async {
    final db = files.open();
    await addGroup(db);
    unawaited(db.close()); // e.g. the provider's dispose
    expect(await files.delete(), isTrue);
    expect(await file.exists(), isFalse);
  });

  test('an open during the deletion connects after it', () async {
    final db = files.open();
    await addGroup(db);
    await db.close();
    gate = Completer<void>();
    final deleting = files.delete();
    final again = files.open();
    final read = GroupsDao(again).getAllGroups();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    gate!.complete();
    expect(await deleting, isTrue);
    expect(await read, isEmpty, reason: 'not the deleted ledger');
  });

  test('a failing deletion is reported, not thrown', () async {
    final broken = LocalLedgerFiles(
      open: (_) => AppDatabase.forTesting(NativeDatabase.memory()),
      delete: () async => throw const FileSystemException('busy'),
    );
    final db = broken.open();
    await db.close();
    expect(await broken.delete(), isFalse);
  });
}
