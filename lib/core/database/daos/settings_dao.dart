import 'package:drift/drift.dart';
import '../app_database.dart';
import '../../sync/left_groups.dart';

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
      });

  /// Forgets the tombstone — we were re-added to [groupId].
  Future<void> clearGroupLeft(String groupId) => (delete(
    appSettings,
  )..where((t) => t.key.equals('$_leftGroupPrefix$groupId'))).go();
}
