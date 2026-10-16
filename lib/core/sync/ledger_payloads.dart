import 'dart:convert';

import '../../models/expense_model.dart';
import '../../models/group_model.dart';
import '../../models/member_model.dart';
import '../../models/record_signature.dart';

/// Protocol version carried by every outgoing payload (`"v"`). Receivers
/// process unknown higher versions best-effort; bumping this is the upgrade
/// path for incompatible changes (e.g. sharded digests).
///
/// v2 (G6): every record version carries its editor's signature (`sig`),
/// expenses / settlements also the creator's `origin`; bootstraps carry the
/// signed group meta (`meta`) and `device_keys` attestations; digests carry
/// signed member entries and the `rejected` map. Unsigned inbound versions are
/// refused (see `record_verifier.dart`).
const protocolVersion = 2;

/// Wire formats for the ledger relay payloads (protocol v1). The single place
/// that builds payload maps from models, shared by the live replication path,
/// the bootstrap, and the anti-entropy repair re-sends — so a repaired record
/// is byte-identical to a freshly replicated one.
Map<String, dynamic> expensePayload(ExpenseModel e) => {
  'v': protocolVersion,
  'id': e.id,
  'group': e.roomId,
  'description': e.description,
  'amount': e.amountCents,
  'currency': e.currency,
  'paid_by': e.paidBy,
  'split': jsonDecode(e.splitsJson),
  'created_at': e.createdAt,
  'updated_at': e.updatedAt,
  'deleted': e.deleted,
  if (e.origin != null) 'origin': e.origin!.toJson(),
  if (e.sig != null) 'sig': e.sig!.toJson(),
};

Map<String, dynamic> settlementPayload(SettlementModel s) => {
  'v': protocolVersion,
  'id': s.id,
  'group': s.roomId,
  'amount': s.amountCents,
  'currency': s.currency,
  'from': s.fromUser,
  'to': s.toUser,
  'created_at': s.createdAt,
  'updated_at': s.updatedAt,
  'deleted': s.deleted,
  if (s.origin != null) 'origin': s.origin!.toJson(),
  if (s.sig != null) 'sig': s.sig!.toJson(),
};

Map<String, dynamic> groupMetaPayload(GroupModel g) => {
  'v': protocolVersion,
  'group': g.roomId,
  'name': g.name,
  'currency': g.currency,
  'updated_at': g.updatedAt,
  if (g.sig != null) 'sig': g.sig!.toJson(),
};

/// Member/participant wire format. `participant_id` is the stable per-group id
/// (not necessarily an MXID); `matrix_id` is the optional claimed account (null
/// for a pure-local participant); `name` is the display name. (`user` is the
/// pre-virtual-users key, still read on the receiver for forward-compat.)
Map<String, dynamic> memberPayload(MemberModel m) => {
  'v': protocolVersion,
  'group': m.groupId,
  'participant_id': m.userId,
  'name': m.displayName,
  'matrix_id': m.matrixId,
  'status': m.status,
  'updated_at': m.updatedAt,
  if (m.sig != null) 'sig': m.sig!.toJson(),
};

/// Full group snapshot ("send my friend the database"): group meta, all
/// members, and the whole ledger **including tombstones** — a stale receiver
/// must learn about deletions or it would re-gossip dead records.
///
/// G6: rows still waiting for their signature (`pendingSign`) are left out —
/// receivers refuse unsigned versions — except in a backup file
/// ([includePending]; a restore accepts unsigned rows as legacy). `meta` is the signed group-meta
/// payload (the top-level name/currency/updated_at mirror it); [deviceKeys]
/// (user → device → key) attests the signers' keys for receivers that trust
/// this snapshot (a new group's inviter, our own devices, a restore).
Map<String, dynamic> buildBootstrapContent(
  String groupId,
  GroupModel? group,
  List<MemberModel> members,
  List<ExpenseModel> expenses,
  List<SettlementModel> settlements, {
  Map<String, Map<String, String>> deviceKeys = const {},
  bool includePending = false,
}) => {
  'v': protocolVersion,
  'group': groupId,
  'name': group?.name ?? groupId,
  'currency': group?.currency ?? 'EUR',
  'updated_at': group?.updatedAt ?? 0,
  if (group != null && (includePending || !group.pendingSign))
    'meta': groupMetaPayload(group),
  'members': [
    for (final m in members)
      if (includePending || !m.pendingSign) memberPayload(m),
  ],
  'expenses': [
    for (final e in expenses)
      if (includePending || !e.pendingSign) expensePayload(e),
  ],
  'settlements': [
    for (final s in settlements)
      if (includePending || !s.pendingSign) settlementPayload(s),
  ],
  if (deviceKeys.isNotEmpty) 'device_keys': deviceKeys,
};

/// Every (user, device, key) that signed something in a snapshot — the
/// signers whose keys a bootstrap / backup attests.
Set<({String user, String device, String key})> snapshotSigners(
  GroupModel? group,
  List<MemberModel> members,
  List<ExpenseModel> expenses,
  List<SettlementModel> settlements,
) {
  ({String user, String device, String key}) t(RecordSignature s) =>
      (user: s.user, device: s.device, key: s.key);
  return {
    if (group?.sig != null) t(group!.sig!),
    for (final m in members)
      if (m.sig != null) t(m.sig!),
    for (final e in expenses) ...[
      if (e.sig != null) t(e.sig!),
      if (e.origin != null) t(e.origin!),
    ],
    for (final s in settlements) ...[
      if (s.sig != null) t(s.sig!),
      if (s.origin != null) t(s.origin!),
    ],
  };
}

/// Parses a `device_keys` attestation map (user → device → key); malformed
/// entries are skipped.
Map<String, Map<String, String>> parseDeviceKeys(Object? raw) {
  if (raw is! Map) return const {};
  final out = <String, Map<String, String>>{};
  for (final MapEntry(key: user, value: devices) in raw.entries) {
    if (user is! String || devices is! Map) continue;
    for (final MapEntry(key: device, value: key) in devices.entries) {
      if (device is String && key is String && key.isNotEmpty) {
        (out[user] ??= {})[device] = key;
      }
    }
  }
  return out;
}

// ── inbound parsing (G6) ────────────────────────────────────────────────────
// Payload → model with the same defaults the receiver stores, so the signed
// body a receiver verifies is exactly what a later relay rebuilds from Drift.

/// The expense in [c], or null without `id` / `group`.
ExpenseModel? expenseFromPayload(Map<String, dynamic> c) {
  final id = c['id'];
  final group = c['group'];
  if (id is! String || group is! String) return null;
  final createdAt = c['created_at'] as int? ?? 0;
  return ExpenseModel(
    id: id,
    roomId: group,
    description: c['description'] as String? ?? '',
    amountCents: c['amount'] as int? ?? 0,
    currency: c['currency'] as String? ?? 'EUR',
    paidBy: c['paid_by'] as String? ?? '',
    splitsJson: jsonEncode(c['split'] ?? {}),
    createdAt: createdAt,
    updatedAt: c['updated_at'] as int? ?? createdAt,
    deleted: c['deleted'] as bool? ?? false,
    sig: RecordSignature.fromJson(c['sig']),
    origin: RecordSignature.fromJson(c['origin']),
  );
}

/// The settlement in [c], or null without `id` / `group`.
SettlementModel? settlementFromPayload(Map<String, dynamic> c) {
  final id = c['id'];
  final group = c['group'];
  if (id is! String || group is! String) return null;
  final createdAt = c['created_at'] as int? ?? 0;
  return SettlementModel(
    id: id,
    roomId: group,
    amountCents: c['amount'] as int? ?? 0,
    currency: c['currency'] as String? ?? 'EUR',
    fromUser: c['from'] as String? ?? '',
    toUser: c['to'] as String? ?? '',
    createdAt: createdAt,
    updatedAt: c['updated_at'] as int? ?? createdAt,
    deleted: c['deleted'] as bool? ?? false,
    sig: RecordSignature.fromJson(c['sig']),
    origin: RecordSignature.fromJson(c['origin']),
  );
}

/// The participant in [c] (`participant_id`, or the older `user` key), or
/// null without group / id.
MemberModel? memberFromPayload(Map<String, dynamic> c) {
  final group = c['group'];
  final pid = c['participant_id'] as String? ?? c['user'] as String?;
  if (group is! String || pid == null) return null;
  return MemberModel(
    groupId: group,
    userId: pid,
    displayName: c['name'] as String? ?? '',
    matrixId: c['matrix_id'] as String?,
    status: c['status'] as String? ?? 'active',
    updatedAt: c['updated_at'] as int? ?? 0,
    sig: RecordSignature.fromJson(c['sig']),
  );
}

/// The group meta in [c], or null without `group`.
GroupModel? groupMetaFromPayload(Map<String, dynamic> c) {
  final group = c['group'];
  if (group is! String) return null;
  return GroupModel(
    roomId: group,
    name: c['name'] as String? ?? group,
    currency: c['currency'] as String? ?? 'EUR',
    updatedAt: c['updated_at'] as int? ?? 0,
    sig: RecordSignature.fromJson(c['sig']),
  );
}
