import 'dart:convert';

import 'package:drift/drift.dart';

import '../../features/expenses/split_calculator.dart';
import '../database/app_database.dart';
import '../database/daos/expenses_dao.dart';
import '../database/daos/groups_dao.dart';
import '../database/daos/history_dao.dart';
import '../database/daos/members_dao.dart';
import '../database/daos/settings_dao.dart';
import '../database/daos/sync_states_dao.dart';
import '../sync/ledger_payloads.dart';
import '../sync/record_signing.dart' show RecordKind;
import '../sync/record_version.dart';
import '../../models/expense_category.dart';
import '../../models/expense_date.dart';
import '../../models/group_archive.dart';
import '../../models/group_model.dart';
import '../../models/expense_model.dart';
import 'demo_mode.dart';

const _ben = '@ben:example.org';
const _chiara = '@chiara:example.org';
const _david = '@david:example.org';

/// Replaces everything in [db] with the demo dataset (G15 offline demo):
/// four groups (one settled up and archived, G16) with real-sounding people,
/// categories and notes, several currencies, custom splits,
/// a few settlements and dates spread over the last weeks — relative to [now],
/// so the demo always looks fresh. Every peer is marked in sync, so the cloud
/// icons show "synced". Onboarding is marked seen.
///
/// Screenshot extras: a custom category (G47, "Souvenirs" in the Lisbon
/// trip), a back-dated expense (G49) and a back-dated payment (G60), and a
/// version history (G48, [_seedHistory]) — every record's versions with
/// plausible `recorded_at`s, incl. one edited and one deleted expense — so
/// the reset page has restore points.
///
/// Destructive by design — only ever call it on the demo database
/// ([kDemoDatabaseName]) or a test database.
Future<void> seedDemoLedger(AppDatabase db, {DateTime? now}) async {
  final t0 = (now ?? DateTime.now()).millisecondsSinceEpoch;
  int at(int daysAgo, [int hour = 12, int minute = 0]) =>
      t0 -
      Duration(days: daysAgo).inMilliseconds +
      Duration(hours: hour - 12, minutes: minute).inMilliseconds;
  final setup = at(40);
  var seq = 0;
  String id(String prefix) =>
      'demo-$prefix-${(++seq).toString().padLeft(3, '0')}';

  await db.transaction(() async {
    for (final table in db.allTables) {
      await db.delete(table).go();
    }

    // Who wrote each record version (participant / MXID; history source).
    final authors = <String, String>{};
    // G48: the first version of a record that was edited later (by id).
    final firstVersions = <String, Object>{};

    Future<void> group(
      String gid,
      String name,
      String currency, {
      String creator = kDemoUserId,
      List<CustomCategory> categories = const [],
      int? categoriesAt,
    }) async {
      authors[gid] = creator;
      if (categories.isNotEmpty) {
        // The categories came with a later meta edit (G47).
        firstVersions[gid] = GroupModel(
          roomId: gid,
          name: name,
          currency: currency,
          updatedAt: setup,
        );
      }
      await db
          .into(db.groups)
          .insert(
            GroupsCompanion.insert(
              roomId: gid,
              name: name,
              currency: Value(currency),
              updatedAt: Value(categoriesAt ?? setup),
              categoriesJson: Value(encodeCategories(categories)),
            ),
          );
    }

    Future<void> member(String gid, String pid, String name, {String? mxid}) =>
        db
            .into(db.members)
            .insert(
              MembersCompanion.insert(
                groupId: gid,
                userId: pid,
                displayName: Value(name),
                matrixId: Value(mxid),
                updatedAt: setup,
              ),
            );

    Future<void> expense(
      String gid,
      String description,
      int cents,
      String paidBy,
      Map<String, int> split, {
      required int when,
      String currency = 'EUR',
      ExpenseCategory? category,
      String? customCategory,
      String? note,
      int? dayAgo,
      ({int at, int cents, Map<String, int> split})? editedTo,
      int? deletedAt,
    }) {
      assert(split.values.fold(0, (a, b) => a + b) == cents);
      final eid = id('e');
      authors[eid] = paidBy;
      final first = ExpensesCompanion.insert(
        id: eid,
        roomId: gid,
        description: description,
        amountCents: cents,
        currency: currency,
        paidBy: paidBy,
        splitsJson: jsonEncode(split),
        createdAt: when,
        updatedAt: Value(when),
        category: Value(customCategory ?? category?.wire),
        note: Value(note),
        // G49: back-dated to the day [dayAgo] days ago.
        expenseDate: Value(
          dayAgo == null
              ? null
              : storedExpenseDate(
                  DateTime.fromMillisecondsSinceEpoch(at(dayAgo)),
                  when,
                ),
        ),
      );
      var row = first;
      if (editedTo != null) {
        assert(
          editedTo.split.values.fold(0, (a, b) => a + b) == editedTo.cents,
        );
        firstVersions[eid] = first;
        row = first.copyWith(
          amountCents: Value(editedTo.cents),
          splitsJson: Value(jsonEncode(editedTo.split)),
          updatedAt: Value(editedTo.at),
        );
      } else if (deletedAt != null) {
        firstVersions[eid] = first;
        row = first.copyWith(
          deleted: const Value(true),
          updatedAt: Value(deletedAt),
        );
      }
      return db.into(db.expenses).insert(row);
    }

    Future<void> settlement(
      String gid,
      String from,
      String to,
      int cents, {
      required int when,
      String currency = 'EUR',
      int? dayAgo,
    }) {
      final sid = id('s');
      authors[sid] = from;
      return db
          .into(db.settlements)
          .insert(
            SettlementsCompanion.insert(
              id: sid,
              roomId: gid,
              amountCents: cents,
              currency: currency,
              fromUser: from,
              toUser: to,
              createdAt: when,
              updatedAt: Value(when),
              // G60: back-dated to the day [dayAgo] days ago.
              settlementDate: Value(
                dayAgo == null
                    ? null
                    : storedExpenseDate(
                        DateTime.fromMillisecondsSinceEpoch(at(dayAgo)),
                        when,
                      ),
              ),
            ),
          );
    }

    const anna = kDemoUserId;

    // ── Lisbon trip: four friends, one of them without a Matrix account ────
    const lisbon = 'demo-group-lisbon';
    const davidLocal = 'demo-person-david';
    const souvenirs = 'c:demo-souvenirs';
    await group(
      lisbon,
      'Lisbon trip',
      'EUR',
      categories: const [
        CustomCategory(id: souvenirs, name: 'Souvenirs', icon: 'gift'),
      ],
      categoriesAt: at(18, 16, 20),
    );
    await member(lisbon, anna, 'Anna', mxid: anna);
    await member(lisbon, _ben, 'Ben', mxid: _ben);
    await member(lisbon, _chiara, 'Chiara', mxid: _chiara);
    await member(lisbon, davidLocal, 'David');
    const four = [anna, _ben, _chiara, davidLocal];
    await expense(
      lisbon,
      'Apartment in Alfama (3 nights)',
      48000,
      anna,
      splitEqually(48000, four),
      when: at(19, 9, 12),
      category: ExpenseCategory.accommodation,
      note: 'Check-in after 3 pm, key box code in the chat.',
    );
    await expense(
      lisbon,
      'Tram 28 tickets',
      2400,
      _chiara,
      splitEqually(2400, four),
      when: at(18, 10, 40),
      category: ExpenseCategory.transport,
    );
    await expense(
      lisbon,
      'Pastéis de Belém',
      1860,
      davidLocal,
      splitEqually(1860, four),
      when: at(18, 15, 5),
      category: ExpenseCategory.food,
    );
    await expense(
      lisbon,
      'Azulejo tiles',
      3200,
      anna,
      {anna: 1600, _chiara: 1600},
      when: at(18, 16, 30),
      customCategory: souvenirs,
    );
    await expense(
      lisbon,
      'Seafood dinner',
      13640,
      _ben,
      splitEqually(13640, four),
      when: at(18, 21, 30),
      category: ExpenseCategory.food,
    );
    await expense(
      lisbon,
      'Sintra day trip',
      9200,
      anna,
      splitByShares(9200, {anna: 1, _ben: 1, _chiara: 1, davidLocal: 1}),
      when: at(17, 8, 50),
      category: ExpenseCategory.travel,
    );
    // Entered twice by mistake — Chiara deleted the copy (G48 history).
    await expense(
      lisbon,
      'Sintra day trip',
      9200,
      _chiara,
      splitEqually(9200, four),
      when: at(17, 9, 5),
      category: ExpenseCategory.travel,
      deletedAt: at(17, 9, 40),
    );
    await expense(
      lisbon,
      'Fado night',
      6000,
      _chiara,
      {anna: 3000, _chiara: 3000},
      when: at(17, 22, 15),
      category: ExpenseCategory.entertainment,
    );
    await expense(
      lisbon,
      'Airport taxi',
      3850,
      _ben,
      splitEqually(3850, four),
      when: at(16, 6, 45),
      category: ExpenseCategory.transport,
    );
    await settlement(lisbon, davidLocal, anna, 5000, when: at(12, 19));
    await settlement(lisbon, _chiara, _ben, 2500, when: at(9, 18, 30));

    // ── Flat share: rent split by room size, shared groceries ─────────────
    const flat = 'demo-group-flat';
    await group(flat, 'Flat share', 'EUR');
    await member(flat, anna, 'Anna', mxid: anna);
    await member(flat, _ben, 'Ben', mxid: _ben);
    await member(flat, _chiara, 'Chiara', mxid: _chiara);
    const three = [anna, _ben, _chiara];
    await expense(
      flat,
      'Rent October',
      165000,
      _chiara,
      splitByPercent(165000, {anna: 40, _ben: 30, _chiara: 30}),
      when: at(15, 9),
      category: ExpenseCategory.home,
    );
    await expense(
      flat,
      'Internet',
      3999,
      anna,
      splitEqually(3999, three),
      when: at(14, 11, 20),
      category: ExpenseCategory.home,
    );
    await expense(
      flat,
      'Groceries',
      8375,
      _ben,
      splitEqually(8375, three),
      when: at(11, 18, 10),
      category: ExpenseCategory.groceries,
      // A typo fixed an hour later (G48: shows as an edit).
      editedTo: (
        at: at(11, 19, 20),
        cents: 8735,
        split: splitEqually(8735, three),
      ),
    );
    await expense(
      flat,
      'Cleaning supplies',
      2345,
      anna,
      splitEqually(2345, three),
      when: at(8, 17, 45),
      category: ExpenseCategory.home,
    );
    await expense(
      flat,
      'Electricity (Q3)',
      21480,
      _chiara,
      splitEqually(21480, three),
      when: at(5, 10, 30),
      category: ExpenseCategory.home,
      note: 'Includes the back payment for July.',
    );
    await expense(
      flat,
      'Groceries',
      6420,
      anna,
      splitEqually(6420, three),
      when: at(2, 19, 5),
      category: ExpenseCategory.groceries,
    );
    // G49: paid at the weekend, entered on Monday.
    await expense(
      flat,
      'Window cleaner',
      6000,
      _chiara,
      splitEqually(6000, three),
      when: at(1, 8, 20),
      dayAgo: 4,
      category: ExpenseCategory.home,
    );
    await settlement(flat, _ben, _chiara, 30000, when: at(10, 20));
    await settlement(flat, anna, _chiara, 45000, when: at(6, 8, 15));

    // ── Ski weekend: Swiss francs on the slopes, euros for the drive ───────
    const ski = 'demo-group-ski';
    await group(ski, 'Ski weekend', 'CHF', creator: _david);
    await member(ski, anna, 'Anna', mxid: anna);
    await member(ski, _ben, 'Ben', mxid: _ben);
    await member(ski, _david, 'David', mxid: _david);
    const skiers = [anna, _ben, _david];
    await expense(
      ski,
      'Fuel',
      6420,
      _david,
      splitEqually(6420, skiers),
      when: at(4, 7, 30),
      category: ExpenseCategory.transport,
    );
    await expense(
      ski,
      'Ski passes (2 days)',
      31200,
      anna,
      splitEqually(31200, skiers),
      when: at(3, 9),
      category: ExpenseCategory.entertainment,
      currency: 'CHF',
    );
    await expense(
      ski,
      'Fondue at the hut',
      9650,
      _ben,
      splitEqually(9650, skiers),
      when: at(3, 19, 30),
      category: ExpenseCategory.food,
      currency: 'CHF',
    );
    await expense(
      ski,
      'Chalet',
      42000,
      _david,
      splitEqually(42000, skiers),
      when: at(2, 16),
      category: ExpenseCategory.accommodation,
      currency: 'CHF',
    );
    await settlement(ski, _ben, _david, 6000, when: at(1, 21), currency: 'CHF');
    // G60: handed over in cash at the hut, recorded the next evening.
    await settlement(
      ski,
      anna,
      _david,
      4000,
      when: at(1, 20, 10),
      currency: 'CHF',
      dayAgo: 3,
    );

    // ── Board game night: settled up and archived on this device (G16) ───
    const games = 'demo-group-games';
    await group(games, 'Board game night', 'EUR', creator: _ben);
    await member(games, anna, 'Anna', mxid: anna);
    await member(games, _ben, 'Ben', mxid: _ben);
    await expense(
      games,
      'Pizza',
      3600,
      anna,
      splitEqually(3600, [anna, _ben]),
      when: at(26, 20, 15),
      category: ExpenseCategory.food,
    );
    await settlement(games, _ben, anna, 1800, when: at(25, 9));
    final ledger = ExpensesDao(db);
    await SettingsDao(db).archiveGroup(
      games,
      GroupArchive(
        archivedAt: at(24),
        fingerprint: ledgerFingerprint(
          await ledger.getAllExpensesForGroup(games),
          await ledger.getAllSettlementsForGroup(games),
        ),
      ),
    );

    // Everyone acknowledged everything: the sync icons show "synced".
    final syncStates = SyncStatesDao(db);
    for (final (gid, peers) in [
      (lisbon, [_ben, _chiara]),
      (flat, [_ben, _chiara]),
      (ski, [_ben, _david]),
      (games, [_ben]),
    ]) {
      for (final p in peers) {
        await syncStates.markInSync(gid, p, t0);
      }
    }
    await SettingsDao(db).markOnboardingSeen();
    await _seedHistory(db, setup, authors, firstVersions);
  });
}

/// G48: the version history the seeded ledger would have left — per group
/// the meta + members at [setup] (the group's arrival), then each expense /
/// payment version at its own clock ([firstVersions]: the version before an
/// edit / delete). Anna's writes are `local`, everyone else's `inbound`
/// ([authors]: record / group id → who wrote it). Inserted in time order
/// (history order is the row id).
Future<void> _seedHistory(
  AppDatabase db,
  int setup,
  Map<String, String> authors,
  Map<String, Object> firstVersions,
) async {
  final entries = <RecordHistoryCompanion>[];
  void add(
    String gid,
    RecordKind kind,
    String rid,
    RecordVersion v,
    Map<String, dynamic> content,
    String? author, {
    int? at,
  }) => entries.add(
    RecordHistoryCompanion.insert(
      groupId: gid,
      kind: kind.wire,
      recordId: rid,
      updatedAt: v.at,
      versionHash: v.hash,
      content: jsonEncode(content),
      source:
          (author == kDemoUserId ? HistorySource.local : HistorySource.inbound)
              .wire,
      recordedAt: at ?? v.at,
    ),
  );

  final ledger = ExpensesDao(db);
  for (final g in await GroupsDao(db).getAllGroups()) {
    final gid = g.roomId;
    final creator = authors[gid];
    final firstMeta = firstVersions[gid] as GroupModel?;
    final meta = firstMeta ?? g;
    add(
      gid,
      RecordKind.meta,
      gid,
      groupMetaVersion(meta),
      groupMetaPayload(meta),
      creator,
    );
    if (firstMeta != null) {
      add(
        gid,
        RecordKind.meta,
        gid,
        groupMetaVersion(g),
        groupMetaPayload(g),
        kDemoUserId,
      );
    }
    for (final m in await MembersDao(db).getMembers(gid)) {
      add(
        gid,
        RecordKind.member,
        m.userId,
        memberVersion(m),
        memberPayload(m),
        creator,
        at: setup,
      );
    }
    for (final e in await ledger.getAllExpensesForGroup(gid)) {
      final first = firstVersions[e.id] as ExpensesCompanion?;
      final author = authors[e.id];
      if (first != null) {
        final before = ExpenseModel(
          id: e.id,
          roomId: gid,
          description: first.description.value,
          amountCents: first.amountCents.value,
          currency: first.currency.value,
          paidBy: first.paidBy.value,
          splitsJson: first.splitsJson.value,
          createdAt: e.createdAt,
          updatedAt: e.createdAt,
          category: e.category,
          note: e.note,
          date: e.date,
        );
        add(
          gid,
          RecordKind.expense,
          e.id,
          expenseVersion(before),
          expensePayload(before),
          author,
        );
      }
      add(
        gid,
        RecordKind.expense,
        e.id,
        expenseVersion(e),
        expensePayload(e),
        author,
      );
    }
    for (final s in await ledger.getAllSettlementsForGroup(gid)) {
      add(
        gid,
        RecordKind.settlement,
        s.id,
        settlementVersion(s),
        settlementPayload(s),
        authors[s.id],
      );
    }
  }
  final ordered = [for (final (i, e) in entries.indexed) (i, e)]
    ..sort((a, b) {
      final byTime = a.$2.recordedAt.value.compareTo(b.$2.recordedAt.value);
      return byTime != 0 ? byTime : a.$1.compareTo(b.$1);
    });
  await db.batch((b) {
    for (final (_, e) in ordered) {
      b.insert(db.recordHistory, e);
    }
  });
}
