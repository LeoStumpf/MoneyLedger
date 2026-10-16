import 'dart:convert';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

import '../../core/database/daos/expenses_dao.dart';
import '../../core/database/daos/groups_dao.dart';
import '../../core/database/daos/members_dao.dart';
import '../../core/matrix/transport_provider.dart';
import '../../core/sync/record_signing.dart';
import '../../models/expense_model.dart';
import '../../models/group_model.dart';
import '../../models/member_model.dart';
import '../expenses/expenses_provider.dart';
import 'ledger_csv.dart';

part 'csv_import.g.dart';

/// Which participant each CSV name resolves to, and the names worth a warning
/// before importing (G13).
class CsvNameResolution {
  /// name → participant id, for names matching an existing participant.
  final Map<String, String> pidByName;

  /// Names matching no participant: a new local person will be created.
  final List<String> unmatched;

  /// Names matching several participants: the active (else first) one is used.
  final List<String> ambiguous;
  const CsvNameResolution({
    required this.pidByName,
    required this.unmatched,
    required this.ambiguous,
  });
}

/// Resolves [names] (share columns + payers of a CSV) against the group's
/// existing [members] by display label. Pure — shared by the preview and the
/// import, so the warning matches what the import does.
CsvNameResolution resolveCsvNames(
  Iterable<String> names,
  List<MemberModel> members,
) {
  final byName = <String, List<MemberModel>>{};
  for (final m in members) {
    byName.putIfAbsent(csvParticipantLabel(m), () => []).add(m);
  }
  final pidByName = <String, String>{};
  final unmatched = <String>[];
  final ambiguous = <String>[];
  for (final name in {...names}..removeWhere((n) => n.isEmpty)) {
    final matches = byName[name];
    if (matches == null) {
      unmatched.add(name);
      continue;
    }
    if (matches.length > 1) ambiguous.add(name);
    pidByName[name] = (matches.firstWhere(
      (m) => m.isActive,
      orElse: () => matches.first,
    )).userId;
  }
  return CsvNameResolution(
    pidByName: pidByName,
    unmatched: unmatched,
    ambiguous: ambiguous,
  );
}

/// The name a participant has in a CSV (its share-column header).
String csvParticipantLabel(MemberModel m) =>
    m.displayName.isNotEmpty ? m.displayName : (m.matrixId ?? m.userId);

Set<String> _referencedNames(ParsedCsv parsed) => {
  ...parsed.participantNames,
  for (final r in parsed.rows) r.paidByName,
};

/// What importing a CSV would do — shown for confirmation first (G13).
class CsvImportPreview {
  final String groupName;
  final bool isNewGroup;
  final int expenseCount;
  final int paymentCount;

  /// Names that will become new local participants (only listed for an
  /// existing group — in a new group everyone is new).
  final List<String> unmatched;

  /// Names matching several existing participants.
  final List<String> ambiguous;
  const CsvImportPreview({
    required this.groupName,
    required this.isNewGroup,
    required this.expenseCount,
    required this.paymentCount,
    required this.unmatched,
    required this.ambiguous,
  });

  bool get isEmpty => expenseCount == 0 && paymentCount == 0;
}

/// The outcome of an import.
typedef CsvImportResult = ({int expenses, int payments});

/// Imports a per-group CSV produced by [buildGroupCsv] back into the local DB.
///
/// Merge semantics (Phase D, G13): the group is resolved by `Group ID`
/// (created if absent), participants are resolved **by display name**
/// ([resolveCsvNames] — an unknown name becomes a new local participant), and
/// each expense / payment is **LWW-upserted by id** using the row's
/// `Updated At` clock — so re-importing a backup is idempotent and merging
/// into an existing group lets the newer copy win.
///
/// G6: the CSV carries no signatures. A row that **wins** against the local
/// copy (or is new) becomes a version signed by **this device as its
/// editor** (new records also get this device as their creator, "added
/// by"); rows that don't win are skipped, never re-signed.
@riverpod
class CsvImporter extends _$CsvImporter {
  @override
  FutureOr<void> build() {}

  /// Parses [csv] and compares it with the local group, without writing.
  Future<CsvImportPreview> preview(String csv) async {
    final groupsDao = ref.read(groupsDaoProvider);
    final membersDao = ref.read(membersDaoProvider);
    final parsed = parseGroupCsv(csv);
    final existing = parsed.groupId == null
        ? null
        : await groupsDao.getGroup(parsed.groupId!);
    final names = existing == null
        ? null
        : resolveCsvNames(
            _referencedNames(parsed),
            await membersDao.getMembers(existing.roomId),
          );
    final payments = parsed.rows.where((r) => r.paymentRecipient != null);
    return CsvImportPreview(
      groupName: existing?.name ?? parsed.groupName ?? '',
      isNewGroup: existing == null,
      expenseCount: parsed.rows.length - payments.length,
      paymentCount: payments.length,
      unmatched: names?.unmatched ?? const [],
      ambiguous: names?.ambiguous ?? const [],
    );
  }

  /// Imports [csv]; returns the number of expense / payment rows written.
  /// Throws on failure (the notifier state carries the error too, while
  /// mounted).
  Future<CsvImportResult> importCsv(String csv) async {
    state = const AsyncLoading();
    try {
      final result = await _doImport(csv);
      if (ref.mounted) state = const AsyncData(null);
      return result;
    } catch (e, st) {
      if (ref.mounted) state = AsyncError(e, st);
      rethrow;
    }
  }

  Future<CsvImportResult> _doImport(String csv) async {
    final parsed = parseGroupCsv(csv);
    if (parsed.rows.isEmpty && parsed.participantNames.isEmpty) {
      return (expenses: 0, payments: 0);
    }

    // Captured before the first await (G19).
    final db = ref.read(appDatabaseProvider);
    final groupsDao = ref.read(groupsDaoProvider);
    final membersDao = ref.read(membersDaoProvider);
    final expensesDao = ref.read(expensesDaoProvider);
    final signer = LocalRecordSigner(ref.read(ledgerTransportProvider.future));
    final now = DateTime.now().millisecondsSinceEpoch;

    // 1) Ensure the group. New id when the CSV carries none; never clobber an
    //    existing group's meta (LWW upsert only creates it when absent).
    final groupId = parsed.groupId ?? const Uuid().v7();
    final existing = await groupsDao.getGroup(groupId);
    if (db.isClosed) return (expenses: 0, payments: 0);
    if (existing == null) {
      final currency = parsed.rows.isNotEmpty
          ? parsed.rows.first.currency
          : 'EUR';
      final group = await signer.group(
        GroupModel(
          roomId: groupId,
          name: parsed.groupName ?? 'Imported group',
          currency: currency,
          updatedAt: now,
        ),
      );
      if (db.isClosed) return (expenses: 0, payments: 0);
      await groupsDao.upsertGroupLww(groupCompanion(group));
    }

    // 2) Resolve every referenced name to a participant id, creating local
    //    participants for names not already in the group (matched by name).
    final resolution = resolveCsvNames(
      _referencedNames(parsed),
      await membersDao.getMembers(groupId),
    );
    final pidByName = {...resolution.pidByName};
    for (final name in resolution.unmatched) {
      if (db.isClosed) return (expenses: 0, payments: 0);
      final pid = const Uuid().v7();
      final member = await signer.member(
        MemberModel(
          groupId: groupId,
          userId: pid,
          displayName: name,
          status: 'active',
          updatedAt: now,
        ),
      );
      if (db.isClosed) return (expenses: 0, payments: 0);
      await membersDao.upsertMemberLww(memberCompanion(member));
      pidByName[name] = pid;
    }

    // 3) LWW-upsert each expense / payment by id.
    var expenses = 0;
    var payments = 0;
    for (final row in parsed.rows) {
      if (db.isClosed) break;
      final id = row.id ?? const Uuid().v7();
      final payer = pidByName[row.paidByName] ?? row.paidByName;
      final recipient = row.paymentRecipient;
      if (recipient != null) {
        final stored = await expensesDao.getSettlementById(id);
        if (stored != null && stored.updatedAt >= row.updatedAt) {
          payments++; // already up to date here — counted, not re-signed
          continue;
        }
        final signed = await signer.settlement(
          SettlementModel(
            id: id,
            roomId: groupId,
            amountCents: row.amountCents,
            currency: row.currency,
            fromUser: payer,
            toUser: pidByName[recipient] ?? recipient,
            createdAt: row.createdAt,
            updatedAt: row.updatedAt,
            origin: stored?.origin,
          ),
          creating: stored == null,
        );
        if (db.isClosed) break;
        await expensesDao.upsertSettlementLww(settlementCompanion(signed));
        payments++;
        continue;
      }
      final splits = <String, int>{
        for (final e in row.sharesByName.entries)
          if (pidByName[e.key] != null) pidByName[e.key]!: e.value,
      };
      final stored = await expensesDao.getExpenseById(id);
      if (stored != null && stored.updatedAt >= row.updatedAt) {
        expenses++; // already up to date here — counted, not re-signed
        continue;
      }
      final signed = await signer.expense(
        ExpenseModel(
          id: id,
          roomId: groupId,
          description: row.description,
          amountCents: row.amountCents,
          currency: row.currency,
          paidBy: payer,
          splitsJson: jsonEncode(splits),
          createdAt: row.createdAt,
          updatedAt: row.updatedAt,
          category: row.category,
          note: row.note,
          origin: stored?.origin,
        ),
        creating: stored == null,
      );
      if (db.isClosed) break;
      await expensesDao.upsertExpenseLww(expenseCompanion(signed));
      expenses++;
    }
    return (expenses: expenses, payments: payments);
  }
}
