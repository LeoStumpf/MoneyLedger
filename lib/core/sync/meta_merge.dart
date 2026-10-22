import 'package:canonical_json/canonical_json.dart';
import 'package:crypto/crypto.dart';

import '../../models/expense_category.dart';
import '../../models/group_model.dart';
import '../database/daos/members_dao.dart';
import '../link/group_policy.dart';
import '../matrix/ledger_transport.dart';
import 'record_signing.dart';
import 'record_version.dart';

/// G57 (C1) — merging concurrent group-meta versions field by field
/// (`docs/design/g57-category-merge.md`, "As built (C1)").
///
/// The signed group meta carries a clock per **field** ([GroupModel.clockOf]:
/// name, currency, exchange rates, the link state, and every custom
/// category). Two versions merge by taking, per field, the value with the
/// higher `(clock, hash of the value)` — the G27 rule, applied per field —
/// and the **union** of the categories by id (categories are never deleted,
/// only hidden). The merge is commutative, associative and idempotent, so
/// every device that has seen the same versions holds the same fields.
///
/// A merged state that equals neither input is written by the merging device
/// as **its own new version** (`nextLwwClock` over both, signed by it — or
/// `pendingSign`, or an unsigned link version in a link-only group); see
/// `RecordGate.meta`. The stored meta's clock therefore never goes back, and
/// the digests' ordinary "who has the newer meta" exchange converges: the
/// side with the newer version sends it, the other merges.

String _hash(Object? value) =>
    sha256.convert(canonicalJson.encode({'v': value})).toString();

/// The value of the scalar meta [field] of [g] (canonical-JSON encodable).
Object? _scalar(GroupModel g, String field) => switch (field) {
  kMetaFieldName => g.name,
  kMetaFieldCurrency => g.currency,
  kMetaFieldExchangeRates => g.exchangeRates?.toJson(),
  kMetaFieldLink => {'link': g.link?.toJson(), 'locked_at': g.lockedAt},
  _ => throw ArgumentError(field),
};

/// The version of scalar [field] in [g]: its clock + the hash of its value.
RecordVersion metaFieldVersion(GroupModel g, String field) =>
    (at: g.clockOf(field), hash: _hash(_scalar(g, field)));

/// The version of custom category [c] in [g].
RecordVersion _categoryVersion(GroupModel g, CustomCategory c) =>
    (at: g.clockOf(c.id), hash: _hash(c.toJson()));

/// [a] and [b] merged field by field (see the library doc). The result has
/// every field's winning clock as an explicit [GroupModel.fieldClocks]
/// entry, `updated_at` = the higher of both (the caller stamps the version
/// it writes with [GroupModel.atClock]), no signature, no author hint.
/// Category order: [a]'s, then the ones only [b] has, in [b]'s order.
GroupModel mergeGroupMeta(GroupModel a, GroupModel b) {
  GroupModel pick(String field) =>
      compareVersions(metaFieldVersion(b, field), metaFieldVersion(a, field)) >
          0
      ? b
      : a;
  final name = pick(kMetaFieldName);
  final currency = pick(kMetaFieldCurrency);
  final fx = pick(kMetaFieldExchangeRates);
  final link = pick(kMetaFieldLink);
  final clocks = <String, int>{
    kMetaFieldName: name.clockOf(kMetaFieldName),
    kMetaFieldCurrency: currency.clockOf(kMetaFieldCurrency),
    kMetaFieldExchangeRates: fx.clockOf(kMetaFieldExchangeRates),
    kMetaFieldLink: link.clockOf(kMetaFieldLink),
  };
  final bById = {for (final c in b.categories) c.id: c};
  final aIds = {for (final c in a.categories) c.id};
  final categories = <CustomCategory>[];
  for (final c in a.categories) {
    final other = bById[c.id];
    final useB =
        other != null &&
        compareVersions(_categoryVersion(b, other), _categoryVersion(a, c)) > 0;
    categories.add(useB ? other : c);
    clocks[c.id] = useB ? b.clockOf(c.id) : a.clockOf(c.id);
  }
  for (final c in b.categories) {
    if (aIds.contains(c.id)) continue;
    categories.add(c);
    clocks[c.id] = b.clockOf(c.id);
  }
  return GroupModel(
    roomId: a.roomId,
    name: name.name,
    currency: currency.currency,
    updatedAt: a.updatedAt > b.updatedAt ? a.updatedAt : b.updatedAt,
    categories: categories,
    link: link.link,
    lockedAt: link.lockedAt,
    exchangeRates: fx.exchangeRates,
    fieldClocks: clocks,
  );
}

/// Whether [a] and [b] hold the same fields — every field (and category) at
/// the same clock with the same value; the category order, `updated_at`,
/// signatures and author hints don't count.
bool sameMetaFields(GroupModel a, GroupModel b) {
  for (final f in kMetaScalarFields) {
    if (compareVersions(metaFieldVersion(a, f), metaFieldVersion(b, f)) != 0) {
      return false;
    }
  }
  if (a.categories.length != b.categories.length) return false;
  final bById = {for (final c in b.categories) c.id: c};
  for (final c in a.categories) {
    final other = bById[c.id];
    if (other == null) return false;
    final va = _categoryVersion(a, c);
    final vb = _categoryVersion(b, other);
    if (va.at != vb.at || va.hash != vb.hash) return false;
  }
  return true;
}

/// G57: writes a merged meta as this device's own new version — signed,
/// `pendingSign`, or an unsigned link version (in a link-only group), like
/// any local meta write — or null when this device must not / can't: it is
/// no active participant of the group (a removed member's merge would be
/// dropped by every peer, `signer_not_member`, and re-sent forever), or the
/// group needs a signature it can't give (a device without a Matrix account
/// in a mixed / locked group). The gate then falls back to whole-meta LWW.
typedef MetaMergeSigner = Future<GroupModel?> Function(GroupModel merged);

/// The [MetaMergeSigner] of a gate: signs with [transport]'s device via the
/// same [LocalRecordSigner] the local writes use ([policy] = the link
/// policy lookup), after checking that "me" ([transport]'s account, or the
/// link channel's participant) is an active participant of the group.
MetaMergeSigner metaMergeSigner({
  required Future<LedgerTransport> transport,
  required MembersDao members,
  required GroupPolicyLookup policy,
}) {
  final signer = LocalRecordSigner(transport, policy: policy);
  return (merged) async {
    try {
      final info = await policy(merged.roomId);
      final t = await transport.timeout(kSignerWaitTimeout);
      final people = await members.getMembers(merged.roomId);
      final me = info.myParticipantId;
      final active = people.any(
        (p) =>
            p.isActive &&
            ((!info.isLinkOnly && p.matrixId == t.userId) ||
                (me != null && p.userId == me)),
      );
      if (!active) return null;
      return await signer.group(merged);
    } catch (_) {
      // SignatureRequiredException (mixed / locked group, no account), a
      // transport or policy lookup failure: fall back to plain LWW.
      return null;
    }
  };
}
