import 'dart:convert';

import '../../models/expense_model.dart';
import '../../models/group_model.dart';
import '../../models/member_model.dart';

/// Protocol version carried by every outgoing payload (`"v"`). Receivers
/// process unknown higher versions best-effort; bumping this is the upgrade
/// path for incompatible changes (e.g. sharded digests).
const protocolVersion = 1;

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
    };

Map<String, dynamic> groupMetaPayload(GroupModel g) => {
      'v': protocolVersion,
      'group': g.roomId,
      'name': g.name,
      'currency': g.currency,
      'updated_at': g.updatedAt,
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
    };

/// Full group snapshot ("send my friend the database"): group meta, all
/// members, and the whole ledger **including tombstones** — a stale receiver
/// must learn about deletions or it would re-gossip dead records.
Map<String, dynamic> buildBootstrapContent(
  String groupId,
  GroupModel? group,
  List<MemberModel> members,
  List<ExpenseModel> expenses,
  List<SettlementModel> settlements,
) =>
    {
      'v': protocolVersion,
      'group': groupId,
      'name': group?.name ?? groupId,
      'currency': group?.currency ?? 'EUR',
      'updated_at': group?.updatedAt ?? 0,
      'members': members.map(memberPayload).toList(),
      'expenses': expenses.map(expensePayload).toList(),
      'settlements': settlements.map(settlementPayload).toList(),
    };
