import 'dart:async';

import '../../models/expense_model.dart';
import '../../models/group_model.dart';
import '../../models/member_model.dart';
import '../../models/record_signature.dart';
import '../database/daos/signing_dao.dart';
import '../matrix/record_crypto.dart';
import 'record_signing.dart';

/// Why an inbound version was refused (G6). [wire] is stored in
/// `rejected_versions.reason`. [recorded] reasons go into that table (and the
/// digest's `rejected` map, so peers stop re-sending them); a transient one
/// (a clock too far in the future) is just dropped and re-offered later.
enum RejectReason {
  unsigned('unsigned'),
  badSignature('bad_signature'),
  badOrigin('bad_origin'),
  originChanged('origin_changed'),
  keyConflict('key_conflict'),
  wrongSigner('wrong_signer'),
  futureClock('future_clock', recorded: false);

  const RejectReason(this.wire, {this.recorded = true});
  final String wire;
  final bool recorded;
}

/// The outcome of [RecordVerifier]: accept, or refuse for [reason].
class Verdict {
  final RejectReason? reason;
  const Verdict._(this.reason);
  static const accept = Verdict._(null);
  const Verdict.reject(RejectReason this.reason);
  bool get accepted => reason == null;
}

/// How far in the future a signed `updated_at` may be (the same bound
/// `clampInboundClock` applies to unsigned clocks). A signed version can't be
/// stored clamped without breaking its signature, so a later one is dropped
/// (transient) and accepted once the clock is in range.
const kSignedClockSkewTolerance = Duration(minutes: 5);

/// Checks inbound record versions (G6).
///
/// 1. A version must carry a signature (`sig`) that is valid for the key it
///    embeds, over the body rebuilt from the parsed record — objective, every
///    honest device agrees.
/// 2. An `origin` (creation statement, "added by") must be valid too, and is
///    immutable once we hold one for the record.
/// 3. The embedded key must not **contradict** what we know about (user,
///    device): the device-key history ([SigningDao.keysFor]) and the
///    homeserver's current list ([DeviceKeyDirectory], refreshed on demand,
///    at most every [refreshInterval] per user, pinned as first-hand). A key
///    nobody has seen (the device signed out before we pinned it — or was
///    invented) is **accepted**; the UI shows it as unverified (see
///    [signatureStatus]).
class RecordVerifier {
  RecordVerifier({
    required this.crypto,
    required this.directory,
    required this.signing,
    int Function()? clock,
    this.refreshInterval = const Duration(seconds: 30),
    this.directoryTimeout = const Duration(seconds: 5),
  }) : _clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch);

  final RecordCrypto crypto;
  final DeviceKeyDirectory directory;
  final SigningDao signing;
  final Duration refreshInterval;
  final Duration directoryTimeout;
  final int Function() _clock;

  final Map<String, int> _refreshedAt = {};
  final Map<String, Map<String, String>> _lastDevices = {};

  Future<Verdict> expense(ExpenseModel e, {ExpenseModel? stored}) => _check(
    sig: e.sig,
    updatedAt: e.updatedAt,
    body: (s) => expenseBody(e, s),
    origin: e.origin,
    originBody: (s) =>
        originBody(RecordKind.expense, e.id, e.roomId, e.createdAt, s),
    storedOrigin: stored?.origin,
  );

  Future<Verdict> settlement(SettlementModel s, {SettlementModel? stored}) =>
      _check(
        sig: s.sig,
        updatedAt: s.updatedAt,
        body: (id) => settlementBody(s, id),
        origin: s.origin,
        originBody: (id) =>
            originBody(RecordKind.settlement, s.id, s.roomId, s.createdAt, id),
        storedOrigin: stored?.origin,
      );

  /// [requiredSigner]: the account that must have signed (a non-member's
  /// self-claim / join must be signed by the claimant itself).
  Future<Verdict> member(MemberModel m, {String? requiredSigner}) => _check(
    sig: m.sig,
    updatedAt: m.updatedAt,
    body: (s) => memberBody(m, s),
    requiredSigner: requiredSigner,
  );

  Future<Verdict> meta(GroupModel g) => _check(
    sig: g.sig,
    updatedAt: g.updatedAt,
    body: (s) => groupMetaBody(g, s),
  );

  Future<Verdict> _check({
    required RecordSignature? sig,
    required int updatedAt,
    required Map<String, Object?> Function(SignerId) body,
    RecordSignature? origin,
    Map<String, Object?> Function(SignerId)? originBody,
    RecordSignature? storedOrigin,
    String? requiredSigner,
  }) async {
    if (sig == null) return const Verdict.reject(RejectReason.unsigned);
    if (updatedAt > _clock() + kSignedClockSkewTolerance.inMilliseconds) {
      return const Verdict.reject(RejectReason.futureClock);
    }
    if (!signatureMatches(crypto, body(signerOf(sig)), sig)) {
      return const Verdict.reject(RejectReason.badSignature);
    }
    if (requiredSigner != null && sig.user != requiredSigner) {
      return const Verdict.reject(RejectReason.wrongSigner);
    }
    if (origin != null &&
        (originBody == null ||
            !signatureMatches(crypto, originBody(signerOf(origin)), origin))) {
      return const Verdict.reject(RejectReason.badOrigin);
    }
    if (storedOrigin != null && origin != storedOrigin) {
      return const Verdict.reject(RejectReason.originChanged);
    }
    if (await _conflicts(sig)) {
      return const Verdict.reject(RejectReason.keyConflict);
    }
    if (origin != null && origin != sig && await _conflicts(origin)) {
      return const Verdict.reject(RejectReason.keyConflict);
    }
    return Verdict.accept;
  }

  /// Whether [s]'s key contradicts a first-hand binding of its (user,
  /// device): the homeserver lists the device with another key, or we pinned
  /// another key for it from the server earlier (and the server no longer
  /// lists it). Unknown devices are no conflict (accepted as unverified).
  Future<bool> _conflicts(RecordSignature s) async {
    final pins = await signing.keysFor(s.user, s.device);
    if (pins.any((p) => p.isServer && p.key == s.key)) return false;
    // Unknown, or only vouched for: ask the homeserver (a first-hand pin
    // upgrades a vouched-for key).
    final current = (await _currentDevices(s.user))?[s.device];
    if (current == s.key) return false;
    if (current != null) return true; // first-hand beats a vouched-for key
    if (pins.any((p) => p.key == s.key)) return false; // vouched for
    return pins.any((p) => p.isServer);
  }

  /// [user]'s current devices from the homeserver (pinned as first-hand),
  /// at most one lookup per [refreshInterval]; null when unreachable.
  Future<Map<String, String>?> _currentDevices(String user) async {
    final now = _clock();
    final last = _refreshedAt[user];
    if (last != null && now - last < refreshInterval.inMilliseconds) {
      return _lastDevices[user];
    }
    try {
      final all = await directory
          .currentDevices({user})
          .timeout(directoryTimeout);
      _refreshedAt[user] = now;
      final devices = all[user] ?? const <String, String>{};
      _lastDevices[user] = devices;
      if (devices.isNotEmpty) await signing.pinServerKeys({user: devices});
      return devices;
    } catch (_) {
      return null;
    }
  }
}

/// How trustworthy a stored record's signature is **on this device** (G6) —
/// derived from the device-key history at display time, so a key pinned later
/// upgrades old records automatically.
enum SigStatus {
  /// No signature: a row from before G6 (grandfathered).
  legacy,

  /// The key was seen first-hand on the homeserver for that device.
  verified,

  /// The key was vouched for by a trusted snapshot sender ([vouchedBy]).
  vouched,

  /// Nobody we trust ever listed that device (it may have signed out).
  unverified,

  /// We know a different key for that device — the signature isn't theirs.
  conflict,
}

typedef SignatureState = ({SigStatus status, String? vouchedBy});

/// The [SigStatus] of [sig] given every pinned key in [keys].
SignatureState signatureStatus(RecordSignature? sig, Iterable<KnownKey> keys) {
  if (sig == null) return (status: SigStatus.legacy, vouchedBy: null);
  String? vouchedBy;
  var otherServerKey = false;
  for (final k in keys) {
    if (k.user != sig.user || k.device != sig.device) continue;
    if (k.key == sig.key) {
      if (k.isServer) return (status: SigStatus.verified, vouchedBy: null);
      vouchedBy ??= k.attestedBy ?? '';
    } else if (k.isServer) {
      otherServerKey = true;
    }
  }
  if (otherServerKey) return (status: SigStatus.conflict, vouchedBy: null);
  if (vouchedBy != null) {
    return (status: SigStatus.vouched, vouchedBy: vouchedBy);
  }
  return (status: SigStatus.unverified, vouchedBy: null);
}
