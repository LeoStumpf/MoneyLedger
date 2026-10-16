import 'package:drift/drift.dart';
import '../app_database.dart';
import '../../matrix/ledger_transport.dart';
import '../../sync/left_groups.dart';
import '../../../models/group_archive.dart';

part 'settings_dao.g.dart';

/// Device-local key/value flags. Not replicated — purely for per-device UI state
/// like whether the one-time onboarding has been shown.
@DriftAccessor(tables: [AppSettings])
class SettingsDao extends DatabaseAccessor<AppDatabase>
    with _$SettingsDaoMixin {
  SettingsDao(super.db);

  static const _onboardingSeenKey = 'onboarding_seen';

  /// Emits whether the user has completed the one-time onboarding.
  Stream<bool> watchOnboardingSeen() =>
      (select(appSettings)..where((t) => t.key.equals(_onboardingSeenKey)))
          .watchSingleOrNull()
          .map((row) => row?.value == 'true');

  Future<void> markOnboardingSeen() => into(appSettings).insertOnConflictUpdate(
    const AppSettingsCompanion(
      key: Value(_onboardingSeenKey),
      value: Value('true'),
    ),
  );

  // ── background sync (G31) ───────────────────────────────────────────────────

  static const _backgroundSyncKey = 'background_sync_enabled';

  /// Whether the periodic Android background sync may run for this account
  /// (device-local, per account). Default: on.
  Stream<bool> watchBackgroundSyncEnabled() =>
      (select(appSettings)..where((t) => t.key.equals(_backgroundSyncKey)))
          .watchSingleOrNull()
          .map((row) => row?.value != 'false');

  Future<bool> backgroundSyncEnabled() =>
      (select(appSettings)..where((t) => t.key.equals(_backgroundSyncKey)))
          .getSingleOrNull()
          .then((row) => row?.value != 'false');

  Future<void> setBackgroundSyncEnabled(bool enabled) =>
      into(appSettings).insertOnConflictUpdate(
        AppSettingsCompanion(
          key: const Value(_backgroundSyncKey),
          value: Value(enabled ? 'true' : 'false'),
        ),
      );

  // ── device verification (G11) ───────────────────────────────────────────

  static const _verifiedOnlyKey = 'verified_only_sync';
  static const _verifiedDevicePrefix = 'verified_device:';

  /// "Only sync with verified devices" (device-local, per account). Default
  /// off.
  Stream<bool> watchVerifiedOnlySync() =>
      (select(appSettings)..where((t) => t.key.equals(_verifiedOnlyKey)))
          .watchSingleOrNull()
          .map((row) => row?.value == 'true');

  Future<bool> verifiedOnlySync() =>
      (select(appSettings)..where((t) => t.key.equals(_verifiedOnlyKey)))
          .getSingleOrNull()
          .then((row) => row?.value == 'true');

  Future<void> setVerifiedOnlySync(bool on) =>
      into(appSettings).insertOnConflictUpdate(
        AppSettingsCompanion(
          key: const Value(_verifiedOnlyKey),
          value: Value(on ? 'true' : 'false'),
        ),
      );

  /// Records that this account verified [device] (user, device id, Ed25519
  /// key) by emoji comparison. The Matrix SDK forgets the verified flag of
  /// devices of users we share no room with (roomless app), so the app keeps
  /// its own record; a later key change for the same device id voids it.
  Future<void> markDeviceVerified(SignerId device) =>
      into(appSettings).insertOnConflictUpdate(
        AppSettingsCompanion(
          key: Value('$_verifiedDevicePrefix${device.user}|${device.device}'),
          value: Value(device.key),
        ),
      );

  // `_` is a LIKE wildcard; the Dart-side prefix check in
  // [_verifiedDeviceFrom] makes the match exact.
  Selectable<AppSetting> _verifiedDeviceRows() =>
      select(appSettings)..where((t) => t.key.like('$_verifiedDevicePrefix%'));

  static SignerId? _verifiedDeviceFrom(AppSetting row) {
    if (!row.key.startsWith(_verifiedDevicePrefix)) return null;
    final rest = row.key.substring(_verifiedDevicePrefix.length);
    // MXIDs never contain `|`; device ids might.
    final bar = rest.indexOf('|');
    if (bar <= 0 || bar == rest.length - 1 || row.value.isEmpty) return null;
    return SignerId(
      user: rest.substring(0, bar),
      device: rest.substring(bar + 1),
      key: row.value,
    );
  }

  /// Every device this account verified by emoji comparison.
  Stream<Set<SignerId>> watchVerifiedDevices() => _verifiedDeviceRows()
      .watch()
      .map((rows) => {...rows.map(_verifiedDeviceFrom).nonNulls});

  Future<Set<SignerId>> verifiedDevices() => _verifiedDeviceRows().get().then(
    (rows) => {...rows.map(_verifiedDeviceFrom).nonNulls},
  );

  /// The account's current delivery policy: verified-only on/off + the
  /// devices it verified. Read on every send (`PolicyTransport`).
  Future<DeliveryPolicy> deliveryPolicy() async {
    if (!await verifiedOnlySync()) return DeliveryPolicy.everyone;
    return DeliveryPolicy(verifiedOnly: true, trusted: await verifiedDevices());
  }

  // ── backup (G5) ──────────────────────────────────────────────────────────

  static const _lastBackupKey = 'last_backup_at';
  static const _backupNudgeSnoozeKey = 'backup_nudge_snoozed_until';

  Stream<int?> _watchInt(String key) =>
      (select(appSettings)..where((t) => t.key.equals(key)))
          .watchSingleOrNull()
          .map((row) => row == null ? null : int.tryParse(row.value));

  Future<void> _setInt(String key, int value) =>
      into(appSettings).insertOnConflictUpdate(
        AppSettingsCompanion(key: Value(key), value: Value('$value')),
      );

  /// When this account's ledger was last backed up to a file on this device
  /// (ms epoch), or null if never.
  Stream<int?> watchLastBackupAt() => _watchInt(_lastBackupKey);

  Future<void> setLastBackupAt(int at) => _setInt(_lastBackupKey, at);

  /// Until when the "back up your groups" nudge is snoozed (ms epoch).
  Stream<int?> watchBackupNudgeSnoozedUntil() =>
      _watchInt(_backupNudgeSnoozeKey);

  Future<void> snoozeBackupNudge(int until) =>
      _setInt(_backupNudgeSnoozeKey, until);

  // ── left-group tombstones (G9) ─────────────────────────────────────────────

  static const _leftGroupPrefix = 'left_group:';

  /// Records that this account left / deleted [groupId] (see
  /// [LeftGroupTombstone]). Overwrites an older tombstone.
  Future<void> markGroupLeft(String groupId, LeftGroupTombstone t) =>
      into(appSettings).insertOnConflictUpdate(
        AppSettingsCompanion(
          key: Value('$_leftGroupPrefix$groupId'),
          value: Value(t.encode()),
        ),
      );

  /// The tombstone for [groupId], or null if we never left it (or were
  /// re-added since).
  Future<LeftGroupTombstone?> leftGroup(String groupId) =>
      (select(appSettings)
            ..where((t) => t.key.equals('$_leftGroupPrefix$groupId')))
          .getSingleOrNull()
          .then((row) => LeftGroupTombstone.decode(row?.value));

  /// Purges [groupId] from this device ([AppDatabase.purgeGroup]) and writes
  /// its tombstone, atomically — the common tail of every way a group is
  /// left: [GroupExiter] (leave / delete) and our own leave relayed from
  /// another of our devices (G26, `LedgerSyncer`).
  Future<void> purgeGroupAsLeft(String groupId, LeftGroupTombstone t) =>
      attachedDatabase.transaction(() async {
        await attachedDatabase.purgeGroup(groupId);
        await markGroupLeft(groupId, t);
        await unarchiveGroup(groupId);
      });

  /// Forgets the tombstone — we were re-added to [groupId].
  Future<void> clearGroupLeft(String groupId) => (delete(
    appSettings,
  )..where((t) => t.key.equals('$_leftGroupPrefix$groupId'))).go();

  // ── archived groups (G16) ────────────────────────────────────────────────

  static const _archivedPrefix = 'archived_group:';

  /// Archives [groupId] on this device (see [GroupArchive]).
  Future<void> archiveGroup(String groupId, GroupArchive a) =>
      into(appSettings).insertOnConflictUpdate(
        AppSettingsCompanion(
          key: Value('$_archivedPrefix$groupId'),
          value: Value(a.encode()),
        ),
      );

  Future<void> unarchiveGroup(String groupId) => (delete(
    appSettings,
  )..where((t) => t.key.equals('$_archivedPrefix$groupId'))).go();

  /// Every archive entry, by group id — including ones that no longer hold
  /// because the group had new activity (`GroupArchive.holdsFor`).
  Stream<Map<String, GroupArchive>> watchArchivedGroups() =>
      (select(
        appSettings,
      )..where((t) => t.key.like('$_archivedPrefix%'))).watch().map(
        (rows) => {
          for (final r in rows)
            if (r.key.startsWith(_archivedPrefix))
              r.key.substring(_archivedPrefix.length): ?GroupArchive.decode(
                r.value,
              ),
        },
      );
}
