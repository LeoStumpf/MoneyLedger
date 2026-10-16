import 'dart:convert';

import 'package:drift/drift.dart';

import '../../features/expenses/split_calculator.dart';
import '../database/app_database.dart';
import '../database/daos/expenses_dao.dart';
import '../database/daos/settings_dao.dart';
import '../database/daos/sync_states_dao.dart';
import '../../models/expense_category.dart';
import '../../models/group_archive.dart';
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

    Future<void> group(String gid, String name, String currency) => db
        .into(db.groups)
        .insert(
          GroupsCompanion.insert(
            roomId: gid,
            name: name,
            currency: Value(currency),
            updatedAt: Value(setup),
          ),
        );

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
      String? note,
    }) {
      assert(split.values.fold(0, (a, b) => a + b) == cents);
      return db
          .into(db.expenses)
          .insert(
            ExpensesCompanion.insert(
              id: id('e'),
              roomId: gid,
              description: description,
              amountCents: cents,
              currency: currency,
              paidBy: paidBy,
              splitsJson: jsonEncode(split),
              createdAt: when,
              updatedAt: Value(when),
              category: Value(category?.wire),
              note: Value(note),
            ),
          );
    }

    Future<void> settlement(
      String gid,
      String from,
      String to,
      int cents, {
      required int when,
      String currency = 'EUR',
    }) => db
        .into(db.settlements)
        .insert(
          SettlementsCompanion.insert(
            id: id('s'),
            roomId: gid,
            amountCents: cents,
            currency: currency,
            fromUser: from,
            toUser: to,
            createdAt: when,
            updatedAt: Value(when),
          ),
        );

    const anna = kDemoUserId;

    // ── Lisbon trip: four friends, one of them without a Matrix account ────
    const lisbon = 'demo-group-lisbon';
    const davidLocal = 'demo-person-david';
    await group(lisbon, 'Lisbon trip', 'EUR');
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
      8735,
      _ben,
      splitEqually(8735, three),
      when: at(11, 18, 10),
      category: ExpenseCategory.groceries,
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
    await settlement(flat, _ben, _chiara, 30000, when: at(10, 20));
    await settlement(flat, anna, _chiara, 45000, when: at(6, 8, 15));

    // ── Ski weekend: Swiss francs on the slopes, euros for the drive ───────
    const ski = 'demo-group-ski';
    await group(ski, 'Ski weekend', 'CHF');
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

    // ── Board game night: settled up and archived on this device (G16) ───
    const games = 'demo-group-games';
    await group(games, 'Board game night', 'EUR');
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
  });
}
