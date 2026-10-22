/// G53 round 3 (Leo 2026-10-22, decision 6): schema v19 → v20. A v19
/// database is opened by the current AppDatabase: `link_peers` gains the
/// nullable `left_at` (NULL for existing rows — every known publisher still
/// has its copy), the peer rows survive, "left" round-trips, and the
/// migrated schema equals a fresh database's.
library;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/database/app_database.dart';
import 'package:money_ledger/core/database/daos/link_dao.dart';

Future<List<String>> _schemaOf(AppDatabase db) async => [
  for (final r
      in await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE sql IS NOT NULL "
            "AND name NOT LIKE 'sqlite_%' ORDER BY name",
          )
          .get())
    r.read<String>('name'),
  for (final c
      in await db
          .customSelect(
            "SELECT * FROM pragma_table_info('link_peers') ORDER BY name",
          )
          .get())
    'link_peers.${c.read<String>('name')}:${c.read<String>('type')}:'
        '${c.read<int>('notnull')}:${c.readNullable<String>('dflt_value')}',
];

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('ml_v20_'));
  tearDown(() => dir.deleteSync(recursive: true));

  /// A v19 database file: today's schema without `link_peers.left_at`,
  /// one peer row, `user_version` 19.
  Future<File> v19File() async {
    final file = File('${dir.path}/v19.sqlite');
    final fresh = AppDatabase.forTesting(NativeDatabase(file));
    await fresh.customStatement(
      'ALTER TABLE link_peers DROP COLUMN left_at',
    ); // the first statement creates today's schema
    await fresh.customStatement(
      "INSERT INTO link_peers (group_id, pubkey, me, event_ids_json, "
      "last_created_at, last_seen_at, snapshot_digest) "
      "VALUES ('g1', 'aa', 'p1', '{\"0\":\"e1\"}', 10, 1000, 'D')",
    );
    await fresh.customStatement('PRAGMA user_version = 19');
    await fresh.close();
    return file;
  }

  test('v19 → v20: existing peers keep their row and are not "left"; '
      'left_at round-trips', () async {
    final db = AppDatabase.forTesting(NativeDatabase(await v19File()));
    addTearDown(db.close);
    expect(db.schemaVersion, greaterThanOrEqualTo(20));
    final dao = LinkDao(db);
    final p = (await dao.getPeers('g1')).single;
    expect(
      (p.pubkey, p.me, p.snapshotDigest, p.left),
      ('aa', 'p1', 'D', false),
    );
    expect(await dao.isProcessed('g1', 'aa', 0, 'e1'), isTrue);

    await dao.markPeerLeft(
      groupId: 'g1',
      pubkey: 'aa',
      part: 0,
      eventId: 'l',
      createdAt: 20,
      seenAt: 2000,
    );
    expect((await dao.getPeers('g1')).single.leftAt, 2000);
  });

  test('the migrated schema equals a fresh database', () async {
    final migrated = AppDatabase.forTesting(NativeDatabase(await v19File()));
    final fresh = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(migrated.close);
    addTearDown(fresh.close);
    expect(await _schemaOf(migrated), await _schemaOf(fresh));
  });
}
