/// G37 micro-benchmark: how long building a digest for a 5k-record group
/// takes on a device — the DB read + the G27 version hashes (SHA-256 over
/// canonical JSON per record) + packing (`buildDigestMessages`), and the
/// receiver's local hashing (`compareDigest` input).
///
/// Uses an **in-memory** database only (never the real account DB). Run it as
/// a separate package so it can't touch an installed app's data: temporarily
/// set `applicationId = "io.github.leostumpf.moneyledger.bench"` in
/// `android/app/build.gradle.kts`, `flutter build apk --profile -t
/// tool/bench/digest_bench.dart`, revert the gradle file, check the package
/// name (`aapt2 dump badging`), `adb install` + launch it, read `adb logcat |
/// grep '\[bench\]'`, then `adb uninstall io.github.leostumpf.moneyledger.bench`.
/// Never `flutter run` it over the real app (a signature mismatch makes the
/// tool uninstall the app and its data). Results go to the screen and to the
/// log (`[bench]`).
library;

import 'dart:math';

import 'package:drift/drift.dart' show Batch;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:money_ledger/core/database/app_database.dart';
import 'package:money_ledger/core/database/daos/expenses_dao.dart';
import 'package:money_ledger/core/database/daos/groups_dao.dart';
import 'package:money_ledger/core/database/daos/members_dao.dart';
import 'package:money_ledger/core/sync/payload_budget.dart';
import 'package:money_ledger/core/sync/record_version.dart';
import 'package:money_ledger/core/sync/sync_engine.dart';
import 'package:money_ledger/models/expense_model.dart';
import 'package:money_ledger/models/group_model.dart';
import 'package:money_ledger/models/member_model.dart';
import 'package:money_ledger/models/record_signature.dart';

const _records = 5000;
const _runs = 7;
const _gid = '0199e3a0-5a1b-7c2d-8e3f-4a5b6c7d8e9f';
const _users = [
  '@moneyledger-test-a-c725:matrix.org',
  '@moneyledger-test-b-c725:matrix.org',
  '@carla.mustermann:example.org',
  '@dominik:fosdem.org',
];

void main() {
  runApp(const MaterialApp(home: _BenchPage()));
}

class _BenchPage extends StatefulWidget {
  const _BenchPage();
  @override
  State<_BenchPage> createState() => _BenchPageState();
}

class _BenchPageState extends State<_BenchPage> {
  final _lines = <String>['running…'];

  @override
  void initState() {
    super.initState();
    _run();
  }

  void _log(String s) {
    debugPrint('[bench] $s');
    setState(() => _lines.add(s));
  }

  Future<void> _run() async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    await _seed(db);
    // Rows inserted directly carry no cached hash (like pre-v8 rows) …
    await _measure(db, 'uncached');
    // … the v8 migration / every DAO write stores it (G37).
    final sw = Stopwatch()..start();
    await backfillVersionHashes(db);
    _log('backfill (v8 migration) of all rows: ${sw.elapsedMilliseconds} ms');
    await _measure(db, 'cached');
    await db.close();
    _log('done');
  }

  Future<void> _measure(AppDatabase db, String label) async {
    final groups = GroupsDao(db), members = MembersDao(db);
    final expenses = ExpensesDao(db);
    final read = <int>[], hash = <int>[], build = <int>[];
    for (var i = 0; i < _runs; i++) {
      final sw = Stopwatch()..start();
      final g = (await groups.getGroup(_gid))!;
      final m = await members.getMembers(_gid);
      final ex = await expenses.getAllExpensesForGroup(_gid);
      final st = await expenses.getAllSettlementsForGroup(_gid);
      read.add(sw.elapsedMilliseconds);
      sw.reset();
      // What the receiver's compareDigest needs: every local version hash.
      for (final e in ex) {
        expenseVersionHash(e);
      }
      for (final s in st) {
        settlementVersionHash(s);
      }
      hash.add(sw.elapsedMilliseconds);
      sw.reset();
      // ignore: invalid_use_of_visible_for_testing_member
      final msgs = buildDigestMessages(
        g,
        m,
        ex,
        st,
        reply: false,
        budget: kMaxPayloadBytes,
      );
      build.add(sw.elapsedMilliseconds);
      if (i == 0) {
        _log('[$label] ${ex.length + st.length} records, ${msgs.length} msg');
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    int median(List<int> l) => (l.toList()..sort())[l.length ~/ 2];
    _log('[$label] DB read: median ${median(read)} ms  $read');
    _log('[$label] version hashes: median ${median(hash)} ms  $hash');
    _log('[$label] buildDigestMessages: median ${median(build)} ms  $build');
    _log(
      '[$label] digest total (read + build): median '
      '${median([for (var i = 0; i < _runs; i++) read[i] + build[i]])} ms',
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [for (final l in _lines) Text(l)],
      ),
    ),
  );
}

Future<void> _seed(AppDatabase db) async {
  final r = Random(1);
  String b64(int n) {
    const abc =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
    return String.fromCharCodes(
      List.generate(n, (_) => abc.codeUnitAt(r.nextInt(abc.length))),
    );
  }

  RecordSignature sig(String u) => RecordSignature(
    user: u,
    device: 'DEV${r.nextInt(9)}',
    key: b64(43),
    sig: b64(86),
  );
  String uuid() => [8, 4, 4, 4, 12]
      .map(
        (n) => List.generate(n, (_) => r.nextInt(16).toRadixString(16)).join(),
      )
      .join('-');
  const t0 = 1760000000000;
  await db.batch((Batch b) {
    b.insert(
      db.groups,
      groupCompanion(
        GroupModel(
          roomId: _gid,
          name: 'Summer trip 2026',
          currency: 'EUR',
          updatedAt: t0,
          sig: sig(_users.first),
        ),
      ),
    );
    for (final u in _users) {
      b.insert(
        db.members,
        memberCompanion(
          MemberModel(
            groupId: _gid,
            userId: u,
            displayName: u.substring(1, 6),
            matrixId: u,
            status: 'active',
            updatedAt: t0,
            sig: sig(_users.first),
          ),
        ),
      );
    }
    for (var i = 0; i < _records; i++) {
      final created = t0 + i * 60000;
      final payer = _users[r.nextInt(4)];
      if (i % 10 == 9) {
        b.insert(
          db.settlements,
          settlementCompanion(
            SettlementModel(
              id: uuid(),
              roomId: _gid,
              amountCents: 100 + r.nextInt(50000),
              currency: 'EUR',
              fromUser: payer,
              toUser: _users[(_users.indexOf(payer) + 1) % 4],
              createdAt: created,
              updatedAt: created,
              origin: sig(payer),
              sig: sig(payer),
            ),
          ),
        );
        continue;
      }
      final amount = 100 + r.nextInt(30000), share = amount ~/ 4;
      b.insert(
        db.expenses,
        expenseCompanion(
          ExpenseModel(
            id: uuid(),
            roomId: _gid,
            description: 'Supermarket: drinks and snacks #$i',
            amountCents: amount,
            currency: 'EUR',
            paidBy: payer,
            splitsJson:
                '{"${_users[0]}":${amount - 3 * share},"${_users[1]}":$share,'
                '"${_users[2]}":$share,"${_users[3]}":$share}',
            createdAt: created,
            updatedAt: created + r.nextInt(86400000),
            origin: sig(payer),
            sig: sig(_users[r.nextInt(4)]),
          ),
        ),
      );
    }
  });
}
