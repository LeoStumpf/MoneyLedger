/// Human-readable per-group CSV (Phase D, G13). One row per (non-deleted)
/// expense **and payment** with a decimal **share column per participant**
/// (header = display name) for the spreadsheet view, plus trailing machine
/// columns (`Expense ID`, `Group`, `Group ID`, `Updated At`) so an import can
/// merge by id via last-writer-wins.
///
/// G16: `Category` (stable English id, e.g. `food`) and `Note` follow
/// `Description`; both are empty when unset (and for payments). A CSV
/// without them (pre-G16) imports with no category / note. They sit before
/// `Paid By`, so older parsers simply ignore them.
///
/// The `Type` column says `Expense` or `Payment`. A payment (settlement) row
/// reads like an expense the payer covered entirely for the recipient:
/// `Paid By` = who paid, the recipient's share column = the amount — so the
/// sheet's per-person sums still add up to the balances. Its id sits in the
/// `Expense ID` column. A CSV without a `Type` column (written before G13) is
/// all expenses.
///
/// Pure Dart (models + strings only) — no DB, no Flutter — so it is fully
/// unit-testable. Participant identity travels **by display name**, not by id:
/// the import resolves names to participants (or creates local ones).
/// Tombstones are intentionally not represented (see the full JSON backup,
/// `ledger_backup.dart`, for a lossless copy).
library;

import 'dart:convert';

import '../../models/expense_category.dart' show normalizeNote;
import '../../models/expense_model.dart';
import '../../models/group_model.dart';
import '../../models/member_model.dart';

// Fixed column headers (the share columns sit between [_paidBy] and [_expenseId]).
const _date = 'Date';
const _type = 'Type';
const _description = 'Description';
const _category = 'Category';
const _note = 'Note';
const _currency = 'Currency';
const _amount = 'Amount';
const _paidBy = 'Paid By';
const _expenseId = 'Expense ID';
const _group = 'Group';
const _groupId = 'Group ID';
const _updatedAt = 'Updated At';

String _nameOf(MemberModel m) =>
    m.displayName.isNotEmpty ? m.displayName : (m.matrixId ?? m.userId);

/// `Type` column values.
const csvTypeExpense = 'Expense';
const csvTypePayment = 'Payment';

/// Builds the CSV text for one group. Participant columns cover every member
/// (active or removed) so historical splits are represented; rows are the
/// non-deleted expenses, then the non-deleted [settlements] (payments).
String buildGroupCsv(
  GroupModel group,
  List<MemberModel> members,
  List<ExpenseModel> expenses, [
  List<SettlementModel> settlements = const [],
]) {
  // Stable participant column order; map id -> column name.
  final cols = [...members]..sort((a, b) => _nameOf(a).compareTo(_nameOf(b)));
  final colNames = cols.map(_nameOf).toList();
  final nameById = {for (final m in members) m.userId: _nameOf(m)};

  final header = [
    _date,
    _type,
    _description,
    _category,
    _note,
    _currency,
    _amount,
    _paidBy,
    ...colNames,
    _expenseId,
    _group,
    _groupId,
    _updatedAt,
  ];

  final rows = <List<String>>[header];
  for (final e in expenses) {
    if (e.deleted) continue;
    final splits = (jsonDecode(e.splitsJson) as Map).map(
      (k, v) => MapEntry(k as String, (v as num).toInt()),
    );
    // Share per column, keyed by the column participant's id.
    final shareByColName = <String, String>{};
    for (final m in cols) {
      final cents = splits[m.userId];
      if (cents != null) shareByColName[_nameOf(m)] = _money(cents);
    }
    rows.add([
      DateTime.fromMillisecondsSinceEpoch(e.createdAt).toIso8601String(),
      csvTypeExpense,
      e.description,
      e.category ?? '',
      e.note ?? '',
      e.currency,
      _money(e.amountCents),
      nameById[e.paidBy] ?? e.paidBy,
      for (final n in colNames) shareByColName[n] ?? '',
      e.id,
      group.name,
      group.roomId,
      '${e.updatedAt}',
    ]);
  }
  for (final s in settlements) {
    if (s.deleted) continue;
    final toName = nameById[s.toUser] ?? s.toUser;
    rows.add([
      DateTime.fromMillisecondsSinceEpoch(s.createdAt).toIso8601String(),
      csvTypePayment,
      csvTypePayment,
      '',
      '',
      s.currency,
      _money(s.amountCents),
      nameById[s.fromUser] ?? s.fromUser,
      for (final n in colNames) n == toName ? _money(s.amountCents) : '',
      s.id,
      group.name,
      group.roomId,
      '${s.updatedAt}',
    ]);
  }
  return rows.map(_encodeRow).join('\r\n');
}

/// A single expense parsed from a CSV row (shares + payer are by display name).
class ParsedExpenseRow {
  final String? id;
  final int createdAt;
  final int updatedAt;
  final String description;
  final String currency;
  final int amountCents;
  final String paidByName;
  final Map<String, int> sharesByName; // display name -> cents

  /// G16: category wire id / note, null when absent or empty.
  final String? category;
  final String? note;

  /// A `Payment` row (settlement): [paidByName] paid the single recipient in
  /// [sharesByName]. See [paymentRecipient].
  final bool isPayment;

  const ParsedExpenseRow({
    this.isPayment = false,
    required this.id,
    required this.createdAt,
    required this.updatedAt,
    required this.description,
    required this.currency,
    required this.amountCents,
    required this.paidByName,
    required this.sharesByName,
    this.category,
    this.note,
  });
}

extension ParsedPayment on ParsedExpenseRow {
  /// The recipient of a well-formed payment row (exactly one share), else
  /// null — a malformed payment row is imported as an expense.
  String? get paymentRecipient =>
      isPayment && sharesByName.length == 1 ? sharesByName.keys.first : null;
}

class ParsedCsv {
  final String? groupId;
  final String? groupName;
  final List<String> participantNames; // the share-column headers
  final List<ParsedExpenseRow> rows;

  const ParsedCsv({
    required this.groupId,
    required this.groupName,
    required this.participantNames,
    required this.rows,
  });
}

/// Parses CSV text produced by [buildGroupCsv]. Tolerant of extra/missing
/// optional columns: fixed columns are located by header name, and any column
/// between `Paid By` and `Expense ID` is treated as a participant share column.
ParsedCsv parseGroupCsv(String csv) {
  final table = _decode(csv);
  if (table.isEmpty) {
    return const ParsedCsv(
      groupId: null,
      groupName: null,
      participantNames: [],
      rows: [],
    );
  }
  final header = table.first;
  int idx(String name) => header.indexOf(name);

  final iDate = idx(_date);
  final iType = idx(_type);
  final iDesc = idx(_description);
  final iCat = idx(_category);
  final iNote = idx(_note);
  final iCur = idx(_currency);
  final iAmt = idx(_amount);
  final iPaid = idx(_paidBy);
  final iId = idx(_expenseId);
  final iGroup = idx(_group);
  final iGid = idx(_groupId);
  final iUpd = idx(_updatedAt);

  // Share columns are those strictly between Paid By and Expense ID.
  final shareCols = <int>[];
  if (iPaid >= 0 && iId > iPaid) {
    for (var c = iPaid + 1; c < iId; c++) {
      shareCols.add(c);
    }
  }
  final participantNames = [for (final c in shareCols) header[c]];

  String? groupId;
  String? groupName;
  final rows = <ParsedExpenseRow>[];
  for (final r in table.skip(1)) {
    if (r.every((c) => c.trim().isEmpty)) continue;
    String at(int i) => (i >= 0 && i < r.length) ? r[i] : '';
    groupId ??= at(iGid).isEmpty ? null : at(iGid);
    groupName ??= at(iGroup).isEmpty ? null : at(iGroup);

    final shares = <String, int>{};
    for (final c in shareCols) {
      final v = at(c).trim();
      if (v.isEmpty) continue;
      final cents = _parseMoney(v);
      if (cents != null) shares[header[c]] = cents;
    }
    final created = DateTime.tryParse(at(iDate))?.millisecondsSinceEpoch;
    final updated = int.tryParse(at(iUpd).trim());
    rows.add(
      ParsedExpenseRow(
        isPayment: at(iType).trim().toLowerCase() == 'payment',
        id: at(iId).isEmpty ? null : at(iId),
        createdAt: created ?? updated ?? 0,
        updatedAt: updated ?? created ?? 0,
        description: at(iDesc),
        currency: at(iCur).isEmpty ? 'EUR' : at(iCur),
        amountCents: _parseMoney(at(iAmt)) ?? 0,
        paidByName: at(iPaid),
        sharesByName: shares,
        category: at(iCat).trim().isEmpty ? null : at(iCat).trim(),
        note: normalizeNote(at(iNote)),
      ),
    );
  }
  return ParsedCsv(
    groupId: groupId,
    groupName: groupName,
    participantNames: participantNames,
    rows: rows,
  );
}

// ── money helpers ──────────────────────────────────────────────────────────
String _money(int cents) => (cents / 100).toStringAsFixed(2);

int? _parseMoney(String s) {
  final d = double.tryParse(s.trim().replaceAll(',', '.'));
  return d == null ? null : (d * 100).round();
}

// ── minimal RFC4180 CSV encode/decode ────────────────────────────────────────
String _encodeRow(List<String> fields) => fields.map(_encodeField).join(',');

String _encodeField(String f) {
  if (f.contains(',') ||
      f.contains('"') ||
      f.contains('\n') ||
      f.contains('\r')) {
    return '"${f.replaceAll('"', '""')}"';
  }
  return f;
}

/// Decodes CSV text into rows of fields, handling quoted fields that contain
/// commas, quotes (escaped as `""`), and newlines. Accepts `\n` or `\r\n`.
List<List<String>> _decode(String input) {
  final rows = <List<String>>[];
  var row = <String>[];
  final field = StringBuffer();
  var inQuotes = false;
  var any = false; // saw any char on the current row

  void endField() {
    row.add(field.toString());
    field.clear();
  }

  void endRow() {
    endField();
    rows.add(row);
    row = <String>[];
    any = false;
  }

  for (var i = 0; i < input.length; i++) {
    final ch = input[i];
    any = true;
    if (inQuotes) {
      if (ch == '"') {
        if (i + 1 < input.length && input[i + 1] == '"') {
          field.write('"');
          i++;
        } else {
          inQuotes = false;
        }
      } else {
        field.write(ch);
      }
    } else if (ch == '"') {
      inQuotes = true;
    } else if (ch == ',') {
      endField();
    } else if (ch == '\n') {
      endRow();
    } else if (ch == '\r') {
      // swallow; the following \n (if any) ends the row
    } else {
      field.write(ch);
    }
  }
  if (any || field.isNotEmpty || row.isNotEmpty) endRow();
  return rows;
}
