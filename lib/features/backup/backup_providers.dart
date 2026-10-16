import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/member_model.dart';
import '../expenses/expenses_provider.dart';
import '../groups/group_provider.dart';
import '../onboarding/onboarding_provider.dart';
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
