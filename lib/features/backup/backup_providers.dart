import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/member_model.dart';
import '../devices/device_provider.dart';
import '../expenses/expenses_provider.dart';
import '../groups/group_provider.dart';
import '../onboarding/onboarding_provider.dart';
import 'backup_crypto.dart';
import 'backup_files.dart';
import 'ledger_backup.dart';

/// When this account was last backed up on this device (G5), null = never.
final lastBackupAtProvider = StreamProvider.autoDispose<int?>(
  (ref) => ref.watch(settingsDaoProvider).watchLastBackupAt(),
);

/// Until when the backup nudge is snoozed ("Later").
final backupNudgeSnoozedUntilProvider = StreamProvider.autoDispose<int?>(
  (ref) => ref.watch(settingsDaoProvider).watchBackupNudgeSnoozedUntil(),
);

/// "Later" on the nudge: snooze it until the given time (ms epoch).
final snoozeBackupNudgeProvider =
    Provider.autoDispose<Future<void> Function(int until)>(
      (ref) => ref.watch(settingsDaoProvider).snoozeBackupNudge,
    );

/// Every participant of every group of this account.
final allMembersProvider = StreamProvider.autoDispose<List<MemberModel>>(
  (ref) => ref.watch(membersDaoProvider).watchAllMembers(),
);

/// G34: when another device of this account last proved it holds our state
/// (newest `lastInSyncAt` for our own MXID), null = never / signed out.
final lastOwnDeviceInSyncProvider = StreamProvider.autoDispose<int?>((ref) {
  final me = ref.watch(currentUserIdProvider);
  if (me.isEmpty) return Stream.value(null);
  return ref.watch(syncStatesDaoProvider).watchLatestInSyncWith(me);
});

/// G34: whether one of our other current devices is verified — null while the
/// device list loads; false when it can't be fetched (offline): then only the
/// in-sync proof counts.
final otherVerifiedOwnDeviceProvider = Provider.autoDispose<bool?>((ref) {
  final devices = ref.watch(myDevicesProvider);
  if (devices.hasError) return false;
  final list = devices.value;
  if (list == null) return null;
  return list.any((d) => !d.isThisDevice && d.verified);
});

/// G34: another device of this account holds the solo groups too
/// ([secondOwnDeviceProtects]); null while unknown.
final ownDeviceProtectionProvider = Provider.autoDispose<bool?>((ref) {
  final verified = ref.watch(otherVerifiedOwnDeviceProvider);
  final seen = ref.watch(lastOwnDeviceInSyncProvider);
  if (verified == null || !seen.hasValue) return null;
  return secondOwnDeviceProtects(
    otherVerifiedOwnDevice: verified,
    lastOwnDeviceInSyncAt: seen.value,
    now: ref.watch(backupNudgeClockProvider)().millisecondsSinceEpoch,
  );
});

/// Injectable clock for the nudge (tests).
final backupNudgeClockProvider = Provider<DateTime Function()>(
  (_) => DateTime.now,
);

/// The number of groups only this device could restore when the backup nudge
/// should show (see [shouldShowBackupNudge]), else 0. Stays 0 while anything
/// is still loading, so the card never flashes.
final backupNudgeProvider = Provider.autoDispose<int>((ref) {
  final myMxid = ref.watch(currentUserIdProvider);
  if (myMxid.isEmpty) return 0;
  final groups = ref.watch(ledgerGroupsProvider).value;
  if (groups == null || groups.isEmpty) return 0;
  final members = ref.watch(allMembersProvider).value;
  final lastBackup = ref.watch(lastBackupAtProvider);
  final snoozed = ref.watch(backupNudgeSnoozedUntilProvider);
  if (members == null || !lastBackup.hasValue || !snoozed.hasValue) return 0;
  // G34: a second device of this account (verified, or recently in sync
  // with us) keeps a copy of the solo groups too.
  final ownDevice = ref.watch(ownDeviceProtectionProvider);
  if (ownDevice != false) return 0;
  final unprotected = unprotectedGroups(
    groups: groups,
    members: members,
    myMxid: myMxid,
  ).length;
  final show = shouldShowBackupNudge(
    unprotectedCount: unprotected,
    lastBackupAt: lastBackup.value,
    snoozedUntil: snoozed.value,
    now: ref.watch(backupNudgeClockProvider)().millisecondsSinceEpoch,
  );
  return show ? unprotected : 0;
});

/// G34: Argon2id cost of new encrypted backups (tests use cheap parameters).
final backupKdfParamsProvider = Provider<BackupKdfParams>(
  (_) => BackupKdfParams.standard,
);

/// Decrypts an encrypted backup (injectable for widget tests, where the real
/// key derivation would need `runAsync`).
typedef BackupDecrypter =
    Future<String> Function(String text, String passphrase);

final backupDecrypterProvider = Provider<BackupDecrypter>((_) => decryptBackup);

/// Picks a backup file and returns its text (null = cancelled). Injectable
/// for widget tests (the real one opens the system picker).
final backupFilePickerProvider = Provider<Future<String?> Function()>(
  (_) =>
      () => pickTextFile(LedgerFileKind.backup),
);
