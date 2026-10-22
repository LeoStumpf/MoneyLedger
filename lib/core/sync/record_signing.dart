import 'dart:async';
import 'dart:convert';

import 'package:canonical_json/canonical_json.dart';
import 'package:crypto/crypto.dart';

import '../../models/expense_model.dart';
import '../../models/group_model.dart';
import '../../models/member_model.dart';
import '../../models/record_signature.dart';
import '../link/group_policy.dart';
import '../matrix/ledger_transport.dart';

/// G6 signed records — what is signed, and how (plain Dart, no Flutter/DB).
///
/// Every **version** of an expense, settlement, member (participant) and
/// group meta is signed by the device that wrote it, tombstones included.
/// The signed body is built from the **model** (after parsing / defaulting),
/// never from a raw inbound map, so a record rebuilt from Drift and relayed
/// later verifies exactly like the original. It contains a type tag (no
/// cross-type replay), the `group` and record id (no cross-group replay),
/// every content field, the LWW clock, the tombstone flag and the signer
/// (user, device, key). Transport fields (`v`, `sig`) are not signed.
///
/// Expenses and settlements also carry an `origin`: the creator's signed
/// creation statement (`{t: …#origin, id, group, created_at, signer}`),
/// copied unchanged by every later editor — it backs "added by". It is part
/// of each version's body, so an editor vouches for which creation it
/// continues.
///
/// The bytes are Matrix canonical JSON (`canonical_json`); what the device
/// key signs is the ASCII string `mlsig1:` + base64url(SHA-256(bytes)) —
/// ASCII, so every implementation (vodozemac's `String` API, the test fake)
/// signs exactly the same message whatever the text fields contain.

/// The record kinds that carry signatures. [wire] is the stable name used in
/// the rejected-versions table and the digest's `rejected` map.
enum RecordKind {
  expense('expense', 'com.moneyledger.expense'),
  settlement('settlement', 'com.moneyledger.settlement'),
  member('member', 'com.moneyledger.member'),
  meta('meta', 'com.moneyledger.group');

  const RecordKind(this.wire, this.typeTag);
  final String wire;
  final String typeTag;

  static RecordKind? fromWire(String s) {
    for (final k in values) {
      if (k.wire == s) return k;
    }
    return null;
  }
}

Map<String, Object?> _signer(SignerId s) => s.toJson();

SignerId signerOf(RecordSignature s) =>
    SignerId(user: s.user, device: s.device, key: s.key);

/// The split map of [splitsJson] as a JSON object (malformed → empty).
Map<String, Object?> _splits(String splitsJson) {
  try {
    final decoded = jsonDecode(splitsJson);
    if (decoded is Map<String, dynamic>) return decoded;
  } catch (_) {}
  return const {};
}

/// The creation statement behind "added by" for an expense / settlement.
Map<String, Object?> originBody(
  RecordKind kind,
  String id,
  String group,
  int createdAt,
  SignerId signer,
) => {
  't': '${kind.typeTag}#origin',
  'id': id,
  'group': group,
  'created_at': createdAt,
  'signer': _signer(signer),
};

/// The **content** of an expense version — every field except the
/// signatures (`origin`, `signer`). The signed body adds those; the G27
/// version hash ([expenseVersionHash]) is computed over exactly this.
Map<String, Object?> expenseContent(ExpenseModel e) => {
  't': RecordKind.expense.typeTag,
  'id': e.id,
  'group': e.roomId,
  'description': e.description,
  'amount': e.amountCents,
  'currency': e.currency,
  'paid_by': e.paidBy,
  'split': _splits(e.splitsJson),
  'created_at': e.createdAt,
  'updated_at': e.updatedAt,
  'deleted': e.deleted,
  // G16: only when set — a version without category / note has exactly the
  // pre-G16 body, so older signatures and G27 hashes stay valid.
  if (e.category != null) 'category': e.category,
  if (e.note != null) 'note': e.note,
  // G49: likewise — only a back-dated expense carries its `date`.
  if (e.date != null) 'date': e.date,
};

Map<String, Object?> expenseBody(ExpenseModel e, SignerId signer) => {
  ...expenseContent(e),
  'origin': e.origin?.toJson(),
  'signer': _signer(signer),
};

Map<String, Object?> settlementContent(SettlementModel s) => {
  't': RecordKind.settlement.typeTag,
  'id': s.id,
  'group': s.roomId,
  'amount': s.amountCents,
  'currency': s.currency,
  'from': s.fromUser,
  'to': s.toUser,
  'created_at': s.createdAt,
  'updated_at': s.updatedAt,
  'deleted': s.deleted,
  // G60: only a back-dated payment carries its `date` (an undated one keeps
  // the pre-G60 body, signature and G27 hash).
  if (s.date != null) 'date': s.date,
};

Map<String, Object?> settlementBody(SettlementModel s, SignerId signer) => {
  ...settlementContent(s),
  'origin': s.origin?.toJson(),
  'signer': _signer(signer),
};

Map<String, Object?> memberContent(MemberModel m) => {
  't': RecordKind.member.typeTag,
  'group': m.groupId,
  'participant_id': m.userId,
  'name': m.displayName,
  'matrix_id': m.matrixId,
  'status': m.status,
  'updated_at': m.updatedAt,
};

Map<String, Object?> memberBody(MemberModel m, SignerId signer) => {
  ...memberContent(m),
  'signer': _signer(signer),
};

Map<String, Object?> groupMetaContent(GroupModel g) => {
  't': RecordKind.meta.typeTag,
  'group': g.roomId,
  'name': g.name,
  'currency': g.currency,
  'updated_at': g.updatedAt,
  // G47: only when the group has custom categories — a meta without them
  // has exactly the pre-G47 body, so older signatures and hashes stay valid.
  if (g.categories.isNotEmpty)
    'categories': [for (final c in g.categories) c.toJson()],
  // G53: only while a link is open / once the group was locked — every
  // other meta keeps exactly its pre-G53 body and hash.
  if (g.link != null) 'link': g.link!.toJson(),
  if (g.lockedAt != null) 'locked_at': g.lockedAt,
  // G73: only when the group has exchange rates — every other meta keeps
  // exactly its pre-G73 body and hash.
  if (g.exchangeRates != null) 'exchange_rates': g.exchangeRates!.toJson(),
};

Map<String, Object?> groupMetaBody(GroupModel g, SignerId signer) => {
  ...groupMetaContent(g),
  'signer': _signer(signer),
};

/// The ASCII message the device key signs for [body]. Throws
/// `ArgumentError` for a body canonical JSON can't encode (e.g. a float).
String signingMessage(Map<String, Object?> body) {
  final canonical = canonicalJson.encode(body);
  final digest = base64Url.encode(sha256.convert(canonical).bytes);
  return 'mlsig1:${digest.replaceAll('=', '')}';
}

/// Whether [sig] is a valid signature of [body] (built for `signerOf(sig)`)
/// by the key embedded in [sig]. Never throws.
bool signatureMatches(
  RecordCrypto crypto,
  Map<String, Object?> body,
  RecordSignature sig,
) {
  try {
    return crypto.verify(sig.key, signingMessage(body), sig.sig);
  } catch (_) {
    return false;
  }
}

Future<RecordSignature> _sign(
  RecordCrypto crypto,
  SignerId id,
  Map<String, Object?> body,
) async => RecordSignature(
  user: id.user,
  device: id.device,
  key: id.key,
  sig: await crypto.sign(signingMessage(body)),
);

/// Signs [e] as a new version by [crypto]'s device. [creating] also mints the
/// creator's `origin` (otherwise the existing one is kept, possibly null for a
/// legacy record).
Future<ExpenseModel> signExpense(
  RecordCrypto crypto,
  ExpenseModel e, {
  bool creating = false,
}) async {
  final id = crypto.identity!;
  final origin = creating
      ? await _sign(
          crypto,
          id,
          originBody(RecordKind.expense, e.id, e.roomId, e.createdAt, id),
        )
      : e.origin;
  final withOrigin = e.withSigning(origin: origin);
  return withOrigin.withSigning(
    origin: origin,
    sig: await _sign(crypto, id, expenseBody(withOrigin, id)),
  );
}

Future<SettlementModel> signSettlement(
  RecordCrypto crypto,
  SettlementModel s, {
  bool creating = false,
}) async {
  final id = crypto.identity!;
  final origin = creating
      ? await _sign(
          crypto,
          id,
          originBody(RecordKind.settlement, s.id, s.roomId, s.createdAt, id),
        )
      : s.origin;
  final withOrigin = s.withSigning(origin: origin);
  return withOrigin.withSigning(
    origin: origin,
    sig: await _sign(crypto, id, settlementBody(withOrigin, id)),
  );
}

Future<MemberModel> signMember(RecordCrypto crypto, MemberModel m) async {
  final id = crypto.identity!;
  return m.withSigning(sig: await _sign(crypto, id, memberBody(m, id)));
}

Future<GroupModel> signGroupMeta(RecordCrypto crypto, GroupModel g) async {
  final id = crypto.identity!;
  return g.withSigning(sig: await _sign(crypto, id, groupMetaBody(g, id)));
}

/// How long a local write waits for the relay identity before it is saved
/// `pendingSign` instead (local-first: a write never fails for lack of a
/// signer).
const kSignerWaitTimeout = Duration(seconds: 5);

/// Signs local writes with this device's key (G6). Built from the transport
/// future captured **before the first await** (G19). When the signer isn't
/// ready (transport unavailable, encryption not set up) the record comes back
/// marked `pendingSign` — saved locally, signed later by the sync engine
/// before it is ever sent.
class LocalRecordSigner {
  /// [policy] (G52 step 4): looks up the written record's group policy — in
  /// a **link-only** group a version is stored unsigned and **not**
  /// `pendingSign` (nothing signs it later), without `origin`, with this
  /// device's link participant as the `by` hint (§6.3). Without it (or when
  /// the lookup fails) every version is signed as before.
  LocalRecordSigner(this._transport, {this.policy}) {
    // The policy lookup is awaited first: a failing transport must not
    // surface as an unhandled error meanwhile (it is handled in [_crypto]).
    _transport.ignore();
  }

  final Future<LedgerTransport> _transport;
  final GroupPolicyLookup? policy;

  /// The group's policy for a write into [groupId] (null without a lookup /
  /// when it fails — then every version is signed as before).
  Future<GroupPolicyInfo?> _policy(String groupId) async {
    final lookup = policy;
    if (lookup == null) return null;
    try {
      return await lookup(groupId);
    } catch (_) {
      // Fail towards the stricter path: a signed version is valid anywhere.
      return null;
    }
  }

  /// This device's signing key, or null when it can't sign (yet).
  /// [noAccount] = the transport belongs to no Matrix account at all (local
  /// mode — it never can).
  /// [userId] = the transport's account (null when it isn't available).
  Future<({RecordCrypto? crypto, bool noAccount, String? userId})>
  _signer() async {
    try {
      final t = await _transport.timeout(kSignerWaitTimeout);
      return (
        crypto: t.crypto.identity == null ? null : t.crypto,
        noAccount: !t.userId.startsWith('@'),
        userId: t.userId,
      );
    } catch (_) {
      return (crypto: null, noAccount: false, userId: null);
    }
  }

  /// [claimed]: the written participant version claims a Matrix account;
  /// [meta]: a group-meta version — G53: neither can be written unsigned in
  /// a mixed / locked group (peers refuse it), so a device without a Matrix
  /// account throws [SignatureRequiredException] there.
  Future<T> _run<T>(
    String groupId,
    Future<T> Function(RecordCrypto c) sign,
    T Function() pending,
    T Function(String? author) linkVersion, {
    bool meta = false,
    bool claimed = false,
  }) async {
    final info = await _policy(groupId);
    if (info != null && info.isLinkOnly) {
      return linkVersion(info.myParticipantId);
    }
    final s = await _signer();
    final c = s.crypto;
    // G53 review: a Matrix account that uses a mixed group from the link
    // side (joined by link — its "me" is a participant it doesn't claim)
    // isn't a member there: peers drop versions it signs (signer rule), so
    // it writes link versions like a device without an account.
    final linkSide =
        info != null &&
        info.isMixed &&
        info.myParticipantId != null &&
        s.userId != null &&
        !s.noAccount &&
        info.myMatrixId != s.userId;
    if (c == null || linkSide) {
      // G53: local mode in a mixed group (shared by link with Matrix
      // members) writes plain link versions — unsigned, `by` = "me" —
      // except what only a signature may change.
      if ((s.noAccount || linkSide) &&
          info != null &&
          info.policy == GroupPolicy.mixed) {
        if (meta || claimed) throw const SignatureRequiredException();
        return linkVersion(info.myParticipantId);
      }
      if (s.noAccount && info?.lockedAt != null) {
        throw const SignatureRequiredException();
      }
      return pending();
    }
    try {
      return await sign(c);
    } catch (_) {
      return pending();
    }
  }

  Future<ExpenseModel> expense(ExpenseModel e, {bool creating = false}) => _run(
    e.roomId,
    (c) => signExpense(c, e, creating: creating),
    () => e.withSigning(origin: e.origin, pendingSign: true),
    e.asLinkVersion,
  );

  Future<SettlementModel> settlement(
    SettlementModel s, {
    bool creating = false,
  }) => _run(
    s.roomId,
    (c) => signSettlement(c, s, creating: creating),
    () => s.withSigning(origin: s.origin, pendingSign: true),
    s.asLinkVersion,
  );

  Future<MemberModel> member(MemberModel m) => _run(
    m.groupId,
    (c) => signMember(c, m),
    () => m.withSigning(pendingSign: true),
    m.asLinkVersion,
    claimed: m.matrixId != null,
  );

  Future<GroupModel> group(GroupModel g) => _run(
    g.roomId,
    (c) => signGroupMeta(c, g),
    () => g.withSigning(pendingSign: true),
    g.asLinkVersion,
    meta: true,
  );
}

/// G53: a write that must be signed — the group meta or a participant a
/// Matrix account claims in a group shared with Matrix members (mixed), or
/// anything in a group that was made secure-only (locked) — was attempted
/// on a device without a Matrix account. Nothing was written.
class SignatureRequiredException implements Exception {
  const SignatureRequiredException();

  @override
  String toString() => 'SignatureRequiredException';
}
