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

  // ── notifications (G72) ─────────────────────────────────────────────────

  static const _notificationsKey = 'notifications_enabled';
  static const _notificationPermissionAskedKey =
      'notification_permission_asked';

  /// Whether background rounds notify about others' changes (device-local,
  /// per ledger). Default: on (Leo 2026-10-17).
  Stream<bool> watchNotificationsEnabled() =>
      (select(appSettings)..where((t) => t.key.equals(_notificationsKey)))
          .watchSingleOrNull()
          .map((row) => row?.value != 'false');

  Future<bool> notificationsEnabled() =>
      (select(appSettings)..where((t) => t.key.equals(_notificationsKey)))
          .getSingleOrNull()
          .then((row) => row?.value != 'false');

  Future<void> setNotificationsEnabled(bool enabled) =>
      into(appSettings).insertOnConflictUpdate(
        AppSettingsCompanion(
          key: const Value(_notificationsKey),
          value: Value(enabled ? 'true' : 'false'),
        ),
      );

  /// Whether the app already asked for the Android 13+ notification
  /// permission on its own (once per ledger; the settings switch asks again).
  Future<bool> notificationPermissionAsked() =>
      (select(appSettings)
            ..where((t) => t.key.equals(_notificationPermissionAskedKey)))
          .getSingleOrNull()
          .then((row) => row?.value == 'true');

  Future<void> markNotificationPermissionAsked() =>
      into(appSettings).insertOnConflictUpdate(
        const AppSettingsCompanion(
          key: Value(_notificationPermissionAskedKey),
          value: Value('true'),
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

  // ── link groups (G52) ────────────────────────────────────────────────────

  // ── "Why Matrix?" hint (G54) ─────────────────────────────────────────────

  static const _whyMatrixHintKey = 'why_matrix_hint_dismissed';

  /// Whether the one-time groups-page "Why Matrix?" hint was dismissed (or
  /// followed) — device-local, per ledger.
  Stream<bool> watchWhyMatrixHintDismissed() =>
      (select(appSettings)..where((t) => t.key.equals(_whyMatrixHintKey)))
          .watchSingleOrNull()
          .map((row) => row?.value == 'true');

  Future<void> dismissWhyMatrixHint() => _setValue(_whyMatrixHintKey, 'true');

  static const _linkRelaysKey = 'link_relays';
  static const _linkRelayStatePrefix = 'link_relay_state:';

  Future<String?> _getValue(String key) =>
      (select(appSettings)..where((t) => t.key.equals(key)))
          .getSingleOrNull()
          .then((row) => row?.value);

  Future<void> _setValue(String key, String value) =>
      into(appSettings).insertOnConflictUpdate(
        AppSettingsCompanion(key: Value(key), value: Value(value)),
      );

  /// The `link_relays` setting as stored (a JSON list of relay URLs), or
  /// null when unset (= the defaults; parsed by `parseLinkRelays`).
  Future<String?> linkRelaysRaw() => _getValue(_linkRelaysKey);

  Future<void> setLinkRelaysRaw(String json) => _setValue(_linkRelaysKey, json);

  /// G52 step 9: back to the default relays (the setting unset, so a later
  /// app update's defaults apply).
  Future<void> clearLinkRelays() =>
      (delete(appSettings)..where((t) => t.key.equals(_linkRelaysKey))).go();

  /// A relay's persisted state as stored (`LinkRelayState.encode`), or null.
  Future<String?> linkRelayStateRaw(String relay) =>
      _getValue('$_linkRelayStatePrefix$relay');

  Future<void> setLinkRelayStateRaw(String relay, String json) =>
      _setValue('$_linkRelayStatePrefix$relay', json);

  // ── G74: own payment details ─────────────────────────────────────────────

  static const _paymentDetailsKey = 'payment_details';

  /// The user's own payment details as stored (`PaymentDetails.encode`, a
  /// small JSON map), or null — device-local, per ledger, never synced.
  Stream<String?> watchPaymentDetailsRaw() =>
      (select(appSettings)..where((t) => t.key.equals(_paymentDetailsKey)))
          .watchSingleOrNull()
          .map((row) => row?.value);

  Future<String?> paymentDetailsRaw() => _getValue(_paymentDetailsKey);

  Future<void> setPaymentDetailsRaw(String json) =>
      _setValue(_paymentDetailsKey, json);

  Future<void> clearPaymentDetails() => (delete(
    appSettings,
  )..where((t) => t.key.equals(_paymentDetailsKey))).go();

  static const _paymentPublishedKey = 'payment_published';

  /// G74: what this device last wrote into its groups (`PaymentDetails
  /// .encode`, or `none`) — null before the first distribution.
  Future<String?> paymentPublishedRaw() => _getValue(_paymentPublishedKey);

  Future<void> setPaymentPublishedRaw(String value) =>
      _setValue(_paymentPublishedKey, value);

  // ── G53: signed self-claims after "Connect a Matrix account" ─────────────

  static const _linkSelfClaimPrefix = 'link_self_claim:';

  /// G53 step 3: [groupId] (a link group adopted from local mode) still
  /// needs this account's signed claim of its link participant.
  Future<void> markLinkSelfClaimPending(String groupId) =>
      _setValue('$_linkSelfClaimPrefix$groupId', '1');

  /// The groups [markLinkSelfClaimPending] marked, not claimed yet.
  Future<List<String>> linkSelfClaimsPending() async {
    final rows = await (select(
      appSettings,
    )..where((t) => t.key.like('$_linkSelfClaimPrefix%'))).get();
    return [
      for (final r in rows)
        if (r.key.startsWith(_linkSelfClaimPrefix))
          r.key.substring(_linkSelfClaimPrefix.length),
    ];
  }

  Future<void> clearLinkSelfClaimPending(String groupId) => (delete(
    appSettings,
  )..where((t) => t.key.equals('$_linkSelfClaimPrefix$groupId'))).go();

  // ── G52 step 12 follow-up: "this link was replaced" ──────────────────────

  static const linkReplacedPrefix = 'link_replaced:';

  /// The stored `LinkReplacedNotice` of [groupId] (encoded), or null.
  Future<String?> linkReplacedRaw(String groupId) =>
      _getValue('$linkReplacedPrefix$groupId');

  Stream<String?> watchLinkReplacedRaw(String groupId) =>
      (select(appSettings)
            ..where((t) => t.key.equals('$linkReplacedPrefix$groupId')))
          .watchSingleOrNull()
          .map((row) => row?.value);

  Future<void> setLinkReplacedRaw(String groupId, String value) =>
      _setValue('$linkReplacedPrefix$groupId', value);

  /// The channel of [groupId] was replaced or dropped — the notice is moot.
  Future<void> clearLinkReplaced(String groupId) => (delete(
    appSettings,
  )..where((t) => t.key.equals('$linkReplacedPrefix$groupId'))).go();
}
