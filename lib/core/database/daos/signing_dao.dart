import 'package:drift/drift.dart';

import '../../sync/record_version.dart';
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

  /// G18 review: the group whose snapshot attested this key — an attested
  /// key only vouches for records of that group. Null for a first-hand pin.
  final String? group;

  const KnownKey({
    required this.user,
    required this.device,
    required this.key,
    required this.source,
    this.attestedBy,
    this.group,
  });

  bool get isServer => source == keySourceServer;
}

const keySourceServer = 'server';

/// G18 review 2: how many refused versions are remembered per record.
const kMaxRefusedVersionsPerRecord = 4;
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

  /// The refused version's G27 content hash ('' = unknown).
  final String versionHash;
  const RefusedVersion({
    required this.groupId,
    required this.kind,
    required this.recordId,
    required this.updatedAt,
    required this.reason,
    required this.relayedBy,
    this.claimedSigner,
    this.versionHash = '',
  });

  RecordVersion get version => (at: updatedAt, hash: versionHash);
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

  /// Stores bindings vouched for by [attestedBy] in the snapshot of [group]
  /// — they vouch for that group's records only (G18 review). A first-hand
  /// pin of the same key is a separate row and always wins.
  Future<void> pinAttestedKeys(
    Map<String, Map<String, String>> devices,
    String attestedBy, {
    required String group,
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
              attestedGroup: Value(group),
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

  /// Every pinned key (tests / tooling; the UI streams [watchAllKeys]).
  Future<List<KnownKey>> allKeys() =>
      select(knownDeviceKeys).get().then((r) => r.map(_toKey).toList());

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
    group: r.attestedGroup.isEmpty ? null : r.attestedGroup,
  );

  // ── refused versions ──────────────────────────────────────────────────────

  /// The **highest** refused version of record [recordId] ([kind]) in
  /// [groupId], if any.
  Future<RecordVersion?> rejectedVersion(
    String groupId,
    String kind,
    String recordId,
  ) => _rejectedRows(groupId, kind, recordId).then(
    (rows) => rows.isEmpty
        ? null
        : (at: rows.first.updatedAt, hash: rows.first.versionHash),
  );

  /// The clock of the highest refused version of [recordId], if any.
  Future<int?> rejectedClock(String groupId, String kind, String recordId) =>
      rejectedVersion(groupId, kind, recordId).then((v) => v?.at);

  /// Whether exactly [version] of [recordId] was refused (same clock and,
  /// when both hashes are known, the same G27 hash).
  Future<bool> isRejected(
    String groupId,
    String kind,
    String recordId,
    RecordVersion version,
  ) async {
    for (final r in await _rejectedRows(groupId, kind, recordId)) {
      if (r.updatedAt == version.at &&
          compareVersions(version, (at: r.updatedAt, hash: r.versionHash)) ==
              0) {
        return true;
      }
    }
    return false;
  }

  /// The refused versions of one record, highest first.
  Future<List<RejectedVersion>> _rejectedRows(
    String groupId,
    String kind,
    String recordId,
  ) =>
      (select(rejectedVersions)
            ..where(
              (t) =>
                  t.groupId.equals(groupId) &
                  t.kind.equals(kind) &
                  t.recordId.equals(recordId),
            )
            ..orderBy([
              (t) => OrderingTerm.desc(t.updatedAt),
              (t) => OrderingTerm.desc(t.versionHash),
            ]))
          .get();

  /// Records a refused version. G18 review 2: a small **set** per record —
  /// the [kMaxRefusedVersionsPerRecord] highest refused versions (clock,
  /// then G27 hash) are kept, so a lower refused version a peer still holds
  /// isn't forgotten (and re-sent on every digest) once a higher one is
  /// refused too.
  Future<void> recordRejected(RefusedVersion v, {int? now}) =>
      transaction(() async {
        await into(rejectedVersions).insertOnConflictUpdate(
          RejectedVersionsCompanion.insert(
            groupId: v.groupId,
            kind: v.kind,
            recordId: v.recordId,
            updatedAt: v.updatedAt,
            reason: v.reason,
            relayedBy: v.relayedBy,
            claimedSigner: Value(v.claimedSigner),
            rejectedAt: now ?? DateTime.now().millisecondsSinceEpoch,
            versionHash: Value(v.versionHash),
          ),
        );
        final rows = await _rejectedRows(v.groupId, v.kind, v.recordId);
        if (rows.length <= kMaxRefusedVersionsPerRecord) return;
        // Keep the highest versions (G27 order: clock, then hash).
        rows.sort(
          (a, b) => compareVersions(
            (at: b.updatedAt, hash: b.versionHash),
            (at: a.updatedAt, hash: a.versionHash),
          ),
        );
        for (final r in rows.skip(kMaxRefusedVersionsPerRecord)) {
          await (delete(rejectedVersions)..where(
                (t) =>
                    t.groupId.equals(r.groupId) &
                    t.kind.equals(r.kind) &
                    t.recordId.equals(r.recordId) &
                    t.updatedAt.equals(r.updatedAt) &
                    t.versionHash.equals(r.versionHash),
              ))
              .go();
        }
      });

  /// Forgets every refusal of one record (tests / tooling).
  Future<void> clearRejected(String groupId, String kind, String recordId) =>
      (delete(rejectedVersions)..where(
            (t) =>
                t.groupId.equals(groupId) &
                t.kind.equals(kind) &
                t.recordId.equals(recordId),
          ))
          .go();

  /// G53: forgets every refusal of [groupId] for being **unsigned** — the
  /// group just opened a link (mixed: unsigned versions are accepted now),
  /// so peers may re-send them and they are looked at again.
  Future<void> clearUnsignedRefusals(String groupId) =>
      (delete(rejectedVersions)..where(
            (t) => t.groupId.equals(groupId) & t.reason.equals('unsigned'),
          ))
          .go();

  /// Forgets the refusals of one record up to (and including) [version] — a
  /// restore the user started stored that version after all (G18 review).
  Future<void> clearRejectedUpTo(
    String groupId,
    String kind,
    String recordId,
    RecordVersion version,
  ) => transaction(() async {
    for (final r in await _rejectedRows(groupId, kind, recordId)) {
      if (compareVersions((at: r.updatedAt, hash: r.versionHash), version) >
          0) {
        continue;
      }
      await (delete(rejectedVersions)..where(
            (t) =>
                t.groupId.equals(groupId) &
                t.kind.equals(kind) &
                t.recordId.equals(recordId) &
                t.updatedAt.equals(r.updatedAt) &
                t.versionHash.equals(r.versionHash),
          ))
          .go();
    }
  });

  /// kind → record id → **highest** refused version, for [groupId]'s digest
  /// (`rejected`).
  Future<Map<String, Map<String, RecordVersion>>> rejectedForGroup(
    String groupId,
  ) => rejectedSetsForGroup(groupId).then(
    (all) => {
      for (final MapEntry(key: kind, value: byId) in all.entries)
        kind: {
          for (final MapEntry(key: id, value: vs) in byId.entries) id: vs.first,
        },
    },
  );

  /// kind → record id → every refused version (highest first), for
  /// [groupId]'s digest comparison and its `rejected_more` section.
  Future<Map<String, Map<String, List<RecordVersion>>>> rejectedSetsForGroup(
    String groupId,
  ) => (select(rejectedVersions)..where((t) => t.groupId.equals(groupId)))
      .get()
      .then((rows) {
        final out = <String, Map<String, List<RecordVersion>>>{};
        for (final r in rows) {
          ((out[r.kind] ??= {})[r.recordId] ??= []).add((
            at: r.updatedAt,
            hash: r.versionHash,
          ));
        }
        for (final byId in out.values) {
          for (final vs in byId.values) {
            vs.sort((a, b) => compareVersions(b, a));
          }
        }
        return out;
      });

  /// The highest refused version of one record, if any — for the edit page
  /// notice.
  Stream<RefusedVersion?> watchRejected(
    String groupId,
    String kind,
    String recordId,
  ) =>
      (select(rejectedVersions)
            ..where(
              (t) =>
                  t.groupId.equals(groupId) &
                  t.kind.equals(kind) &
                  t.recordId.equals(recordId),
            )
            ..orderBy([
              (t) => OrderingTerm.desc(t.updatedAt),
              (t) => OrderingTerm.desc(t.versionHash),
            ])
            ..limit(1))
          .watch()
          .map((rows) => rows.firstOrNull)
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
                    versionHash: r.versionHash,
                  ),
          );
}
