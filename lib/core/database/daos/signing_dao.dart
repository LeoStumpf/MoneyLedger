import 'package:drift/drift.dart';

import '../app_database.dart';

part 'signing_dao.g.dart';

/// One pinned (user, device) → Ed25519 key binding (G6, [KnownDeviceKeys]).
class KnownKey {
  final String user;
  final String device;
  final String key;

  /// `server` (seen first-hand in the homeserver's device list) or
  /// `attested` (vouched for by [attestedBy] in a trusted snapshot).
  final String source;
  final String? attestedBy;

  const KnownKey({
    required this.user,
    required this.device,
    required this.key,
    required this.source,
    this.attestedBy,
  });

  bool get isServer => source == keySourceServer;
}

const keySourceServer = 'server';
const keySourceAttested = 'attested';

/// One refused inbound version (G6, [RejectedVersions]).
class RefusedVersion {
  final String groupId;
  final String kind;
  final String recordId;
  final int updatedAt;
  final String reason;
  final String relayedBy;
  final String? claimedSigner;
  const RefusedVersion({
    required this.groupId,
    required this.kind,
    required this.recordId,
    required this.updatedAt,
    required this.reason,
    required this.relayedBy,
    this.claimedSigner,
  });
}

/// The G6 signing bookkeeping: the device-key history and refused versions.
@DriftAccessor(tables: [KnownDeviceKeys, RejectedVersions])
class SigningDao extends DatabaseAccessor<AppDatabase> with _$SigningDaoMixin {
  SigningDao(super.db);

  // ── device-key history ────────────────────────────────────────────────────

  /// Pins every binding of [devices] (user → device → key) as seen
  /// first-hand on the homeserver; upgrades an `attested` pin of the same key.
  Future<void> pinServerKeys(
    Map<String, Map<String, String>> devices, {
    int? now,
  }) async {
    if (devices.isEmpty) return;
    final at = now ?? DateTime.now().millisecondsSinceEpoch;
    await batch((b) {
      for (final MapEntry(key: user, value: byDevice) in devices.entries) {
        for (final MapEntry(key: device, value: key) in byDevice.entries) {
          b.insert(
            knownDeviceKeys,
            KnownDeviceKeysCompanion.insert(
              userId: user,
              deviceId: device,
              ed25519Key: key,
              source: keySourceServer,
              firstSeenAt: at,
            ),
            onConflict: DoUpdate(
              (_) => const KnownDeviceKeysCompanion(
                source: Value(keySourceServer),
                attestedBy: Value(null),
              ),
            ),
          );
        }
      }
    });
  }

  /// Stores bindings vouched for by [attestedBy] (never downgrades a
  /// first-hand pin of the same key).
  Future<void> pinAttestedKeys(
    Map<String, Map<String, String>> devices,
    String attestedBy, {
    int? now,
  }) async {
    if (devices.isEmpty) return;
    final at = now ?? DateTime.now().millisecondsSinceEpoch;
    await batch((b) {
      for (final MapEntry(key: user, value: byDevice) in devices.entries) {
        for (final MapEntry(key: device, value: key) in byDevice.entries) {
          b.insert(
            knownDeviceKeys,
            KnownDeviceKeysCompanion.insert(
              userId: user,
              deviceId: device,
              ed25519Key: key,
              source: keySourceAttested,
              attestedBy: Value(attestedBy),
              firstSeenAt: at,
            ),
            mode: InsertMode.insertOrIgnore,
          );
        }
      }
    });
  }

  /// Every key pinned for [device] of [user].
  Future<List<KnownKey>> keysFor(String user, String device) =>
      (select(knownDeviceKeys)
            ..where((t) => t.userId.equals(user) & t.deviceId.equals(device)))
          .get()
          .then((rows) => rows.map(_toKey).toList());

  /// The whole key history — small (members' devices); the UI derives each
  /// record's signature status from it.
  Stream<List<KnownKey>> watchAllKeys() =>
      select(knownDeviceKeys).watch().map((r) => r.map(_toKey).toList());

  /// First-hand pins for the given (user, device, key) triples, as a
  /// bootstrap / backup `device_keys` attestation map (user → device → key).
  /// Attested pins are never re-attested (no laundering).
  Future<Map<String, Map<String, String>>> attestationsFor(
    Iterable<({String user, String device, String key})> signers,
  ) async {
    final wanted = signers.toSet();
    if (wanted.isEmpty) return const {};
    final users = wanted.map((s) => s.user).toSet();
    final rows =
        await (select(knownDeviceKeys)..where(
              (t) => t.userId.isIn(users) & t.source.equals(keySourceServer),
            ))
            .get();
    final out = <String, Map<String, String>>{};
    for (final r in rows) {
      if (wanted.contains((
        user: r.userId,
        device: r.deviceId,
        key: r.ed25519Key,
      ))) {
        (out[r.userId] ??= {})[r.deviceId] = r.ed25519Key;
      }
    }
    return out;
  }

  static KnownKey _toKey(KnownDeviceKey r) => KnownKey(
    user: r.userId,
    device: r.deviceId,
    key: r.ed25519Key,
    source: r.source,
    attestedBy: r.attestedBy,
  );

  // ── refused versions ──────────────────────────────────────────────────────

  /// The highest refused clock of record [recordId] ([kind]) in [groupId].
  Future<int?> rejectedClock(String groupId, String kind, String recordId) =>
      (select(rejectedVersions)..where(
            (t) =>
                t.groupId.equals(groupId) &
                t.kind.equals(kind) &
                t.recordId.equals(recordId),
          ))
          .getSingleOrNull()
          .then((r) => r?.updatedAt);

  /// Records a refused version (keeps the highest clock per record).
  Future<void> recordRejected(RefusedVersion v, {int? now}) {
    final row = RejectedVersionsCompanion.insert(
      groupId: v.groupId,
      kind: v.kind,
      recordId: v.recordId,
      updatedAt: v.updatedAt,
      reason: v.reason,
      relayedBy: v.relayedBy,
      claimedSigner: Value(v.claimedSigner),
      rejectedAt: now ?? DateTime.now().millisecondsSinceEpoch,
    );
    return into(rejectedVersions).insert(
      row,
      onConflict: DoUpdate(
        (_) => row,
        where: (old) => old.updatedAt.isSmallerThanValue(v.updatedAt),
      ),
    );
  }

  /// kind → record id → highest refused clock, for [groupId]'s digest.
  Future<Map<String, Map<String, int>>> rejectedForGroup(String groupId) =>
      (select(
        rejectedVersions,
      )..where((t) => t.groupId.equals(groupId))).get().then((rows) {
        final out = <String, Map<String, int>>{};
        for (final r in rows) {
          (out[r.kind] ??= {})[r.recordId] = r.updatedAt;
        }
        return out;
      });

  /// The refused version of one record, if any — for the edit page notice.
  Stream<RefusedVersion?> watchRejected(
    String groupId,
    String kind,
    String recordId,
  ) =>
      (select(rejectedVersions)..where(
            (t) =>
                t.groupId.equals(groupId) &
                t.kind.equals(kind) &
                t.recordId.equals(recordId),
          ))
          .watchSingleOrNull()
          .map(
            (r) => r == null
                ? null
                : RefusedVersion(
                    groupId: r.groupId,
                    kind: r.kind,
                    recordId: r.recordId,
                    updatedAt: r.updatedAt,
                    reason: r.reason,
                    relayedBy: r.relayedBy,
                    claimedSigner: r.claimedSigner,
                  ),
          );
}
