import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/widgets/action_error.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/l10n.dart';
import '../backup/backup_files.dart';
import '../backup/backup_ui.dart';
import '../backup/csv_export.dart';
import '../backup/ledger_backup.dart' show savedFileDisplayName;
import '../balance/balance_provider.dart';
import '../expenses/expenses_provider.dart';
import '../expenses/group_currencies.dart';
import '../onboarding/onboarding_provider.dart' show settingsDaoProvider;
import 'group_archive_provider.dart';
import 'group_edit_dialog.dart';
import 'group_exit_dialog.dart';
import 'group_provider.dart';

/// G65: the group actions shared by the group page (⋮ menu, banners) and the
/// group settings page. Callers keep the auto-dispose notifiers they use
/// alive by watching them (`groupExiterProvider`, `groupEditorProvider`,
/// `groupArchiverProvider`).

/// Leave / delete [roomId] (G9) after a confirmation that warns about an
/// unsettled balance; then back to the groups list.
Future<void> exitGroupFlow(
  BuildContext context,
  WidgetRef ref,
  String roomId,
  GroupExitKind kind,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final errors = ActionErrors.of(context);
  final l = context.l10n;
  final group = await ref.read(groupsDaoProvider).getGroup(roomId);
  if (!context.mounted) return;
  final me = ref.read(currentParticipantProvider(roomId)).value;
  final warning = unsettledWarning(
    ref.read(balanceForRoomProvider(roomId)),
    me?.userId,
    l,
  );
  final confirmed = await confirmGroupExit(
    context,
    kind: kind,
    groupName: group?.name ?? l.thisGroup,
    warning: warning,
    onBackup: () async => (await runBackupExport(context, ref)).message,
  );
  if (!confirmed) return;
  final exiter = ref.read(groupExiterProvider.notifier);
  await (kind == GroupExitKind.leave
      ? exiter.leave(roomId)
      : exiter.delete(roomId));
  final error = ref.read(groupExiterProvider).error;
  if (error != null) {
    errors.show(error);
    return;
  }
  messenger.showSnackBar(
    SnackBar(
      content: Text(
        kind == GroupExitKind.leave
            ? l.youLeftGroup(group?.name ?? '')
            : l.deletedGroup(group?.name ?? ''),
      ),
    ),
  );
  if (context.mounted) context.go('/groups');
}

/// Archives [roomId] on this device (G16) and goes back to the groups list,
/// where it sits in the collapsed "Archived" section — or brings an archived
/// one back (and stays). Archiving an unsettled group is allowed; the
/// snackbar says that the open balance still counts in the totals.
Future<void> toggleGroupArchive(
  BuildContext context,
  WidgetRef ref,
  String roomId, {
  required bool archived,
  required bool unsettled,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final errors = ActionErrors.of(context);
  final l = context.l10n;
  // Captured for the snackbar's undo, which may run after this page is gone.
  final settings = ref.read(settingsDaoProvider);
  final archiver = ref.read(groupArchiverProvider.notifier);
  final name = (await ref.read(groupsDaoProvider).getGroup(roomId))?.name;
  if (archived) {
    await archiver.unarchive(roomId);
  } else {
    await archiver.archive(roomId);
  }
  final error = ref.read(groupArchiverProvider).error;
  if (error != null) {
    errors.show(error);
    return;
  }
  if (archived) {
    messenger.showSnackBar(
      SnackBar(content: Text(l.groupUnarchived(name ?? ''))),
    );
    return;
  }
  messenger.showSnackBar(
    SnackBar(
      content: Text(
        unsettled
            ? l.groupArchivedUnsettled(name ?? '')
            : l.groupArchived(name ?? ''),
      ),
      // An action makes snackbars persist by default — this one is a
      // short undo window, not something to dismiss by hand.
      persist: false,
      action: SnackBarAction(
        label: l.undo,
        onPressed: () => settings.unarchiveGroup(roomId),
      ),
    ),
  );
  if (context.mounted) context.go('/groups');
}

/// Rename the group / change its default currency (G10).
Future<void> editGroupFlow(
  BuildContext context,
  WidgetRef ref,
  String roomId,
) async {
  final errors = ActionErrors.of(context);
  final group = await ref.read(groupsDaoProvider).getGroup(roomId);
  if (group == null || !context.mounted) return;
  // G66: the group's currencies first in the picker.
  final suggested = await groupCurrencySuggestions(
    ref,
    roomId,
    selected: group.currency,
  );
  if (!context.mounted) return;
  final result = await showEditGroupDialog(
    context,
    name: group.name,
    currency: group.currency,
    suggested: suggested,
  );
  if (result == null) return;
  await ref
      .read(groupEditorProvider.notifier)
      .edit(roomId, name: result.name, currency: result.currency);
  final error = ref.read(groupEditorProvider).error;
  if (error != null) {
    errors.show(error);
  }
}

/// G34: a JSON backup of just [roomId] (same format as the full one).
Future<void> backupGroupFlow(
  BuildContext context,
  WidgetRef ref,
  String roomId,
) async {
  final group = await ref.read(groupsDaoProvider).getGroup(roomId);
  if (group == null || !context.mounted) return;
  await exportGroupBackup(context, ref, groupId: roomId, groupName: group.name);
}

/// G13: [roomId] as a human-readable CSV file.
Future<void> exportGroupCsvFlow(
  BuildContext context,
  WidgetRef ref,
  String roomId,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final errors = ActionErrors.of(context);
  final l = context.l10n;
  final groups = ref.read(groupsDaoProvider);
  final members = ref.read(membersDaoProvider);
  final expenses = ref.read(expensesDaoProvider);
  try {
    final group = await groups.getGroup(roomId);
    if (group == null) return;
    final csv = await buildGroupCsvForExport(groups, members, expenses, roomId);
    final saved = await saveTextFile(
      csvFileName(group.name),
      csv,
      LedgerFileKind.csv,
    );
    if (saved == null) return; // dialog cancelled
    // G34: the name Android actually used, if the platform tells us.
    final name = kIsWeb
        ? csvFileName(group.name)
        : savedFileDisplayName(saved.path, LedgerFileKind.csv.extension);
    messenger.showSnackBar(
      SnackBar(
        content: Text(name == null ? l.exportedNoName : l.exportedFile(name)),
      ),
    );
  } catch (e) {
    // e.g. the file couldn't be written — tell the user (G15); G75: the
    // export can simply run again.
    errors.show(
      e,
      what: l.exportFailedTitle,
      retry: () {
        if (context.mounted) exportGroupCsvFlow(context, ref, roomId);
      },
    );
  }
}
