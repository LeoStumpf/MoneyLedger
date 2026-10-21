/// G70 (U23): the one "Backup & restore" page. MoneyLedger has four ways to
/// get data back — the backup file (G5 / G34), the automatic restore points
/// (G48 / G58), resetting one group to an earlier state (G48) and the
/// snackbar *Undo* (G67). Each used to be explained only where it lives, and
/// the texts pointed at each other. This page puts them side by side:
///
/// 1. a short **decision aid** ("what do you need?"),
/// 2. **Backup file** — last backup, back up all groups, restore from a file,
///    where the per-group backup lives,
/// 3. **Restore points** — what they are, the list ([RestorePointsPage]);
///    on the web (no snapshot store) only why not,
/// 4. **Undo changes in one group** — pick a group → its reset page.
///
/// Only the entry points and explanations are here; every flow is the
/// existing one ([exportFullBackup], [restoreFullBackup], the restore-points
/// page, `GroupResetPage`).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/background/background_sync_provider.dart'
    show linkGroupsExistProvider;
import '../../core/l10n/l10n.dart';
import '../../core/session/app_session.dart' show localModeActiveProvider;
import '../../core/theme/app_theme.dart';
import '../../core/widgets/content_width.dart';
import '../../core/widgets/settings_section.dart';
import '../../models/group_model.dart';
import '../groups/group_provider.dart';
import '../history/restore_points.dart' show snapshotsSupportedProvider;
import '../history/restore_points_page.dart' show kRestorePointsLocation;
import 'backup_providers.dart';
import 'backup_ui.dart';
import '../../core/widgets/large_text.dart';

/// Route of [BackupRestorePage] (opened from the settings page).
const kBackupLocation = '/backup';

class BackupRestorePage extends ConsumerWidget {
  const BackupRestorePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final local = ref.watch(localModeActiveProvider);
    final snapshots = ref.watch(snapshotsSupportedProvider);
    final last = ref.watch(lastBackupAtProvider).value;
    final groups = ref.watch(ledgerGroupsProvider).value ?? const [];
    final linkGroups = ref.watch(linkGroupsExistProvider).value ?? false;

    return Scaffold(
      appBar: AppBar(title: AppBarTitle(l.settingsSectionBackup)),
      body: ContentWidth(
        child: ListView(
          key: const Key('backupPageList'),
          padding: EdgeInsets.only(
            top: Insets.s,
            bottom: Insets.xl + MediaQuery.paddingOf(context).bottom,
          ),
          children: [
            _DecisionAid(matrix: !local, snapshots: snapshots),

            // ── backup file ──
            SettingsSectionHeader(l.backupFileSection),
            _Para(l.backupFileIntro, key: const Key('backupFileIntro')),
            ListTile(
              leading: const Icon(Icons.event_available_outlined),
              title: Text(
                last == null
                    ? l.lastBackupNever
                    : l.lastBackupAt(context.date(last)),
                key: const Key('lastBackupText'),
              ),
            ),
            ListTile(
              key: const Key('backupExportTile'),
              leading: const Icon(Icons.save_alt),
              title: Text(l.backupExportTitle),
              subtitle: Text(l.backupExportBody),
              onTap: () => exportFullBackup(context, ref),
            ),
            ListTile(
              key: const Key('backupRestoreTile'),
              leading: const Icon(Icons.settings_backup_restore),
              title: Text(l.backupRestoreTitle),
              subtitle: Text(l.backupRestoreBody),
              onTap: () => restoreFullBackup(context, ref),
            ),
            _Para(l.backupFileGroupHint, key: const Key('backupGroupHint')),
            // G52 step 10: link groups' invite keys travel in the file (the
            // export / restore dialogs warn per file).
            if (linkGroups)
              _Para(l.backupFileLinkNote, key: const Key('backupLinkNote')),

            // ── restore points ──
            SettingsSectionHeader(l.restorePointsTitle),
            if (snapshots) ...[
              _Para(l.backupRestorePointsIntro),
              ListTile(
                key: const Key('restorePointsTile'),
                leading: const Icon(Icons.history),
                title: Text(l.backupShowRestorePoints),
                subtitle: Text(l.restorePointsTileBody),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push(kRestorePointsLocation),
              ),
            ] else
              _Para(
                l.backupRestorePointsWeb,
                key: const Key('noSnapshotsHint'),
              ),

            // ── undo in one group ──
            SettingsSectionHeader(l.backupUndoSection),
            _Para(l.backupUndoIntro),
            ListTile(
              key: const Key('resetPickGroupTile'),
              leading: const Icon(Icons.undo),
              title: Text(l.backupUndoPickGroup),
              subtitle: Text(
                groups.isEmpty
                    ? l.backupUndoNoGroups
                    : l.backupUndoPickGroupBody,
              ),
              trailing: const Icon(Icons.chevron_right),
              enabled: groups.isNotEmpty,
              onTap: () => _pickGroupToReset(context, groups),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bottom sheet: which group to reset → that group's reset page (which
/// itself handles a read-only group).
Future<void> _pickGroupToReset(
  BuildContext context,
  List<GroupModel> groups,
) async {
  final l = context.l10n;
  final sorted = [...groups]
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  final id = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(ctx).height * 0.7,
        ),
        child: ListView(
          key: const Key('resetGroupPicker'),
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Insets.page,
                0,
                Insets.page,
                Insets.s,
              ),
              child: Text(
                l.backupUndoPickTitle,
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
            ),
            for (final g in sorted)
              ListTile(
                key: Key('resetPickGroup-${g.roomId}'),
                leading: const Icon(Icons.group_outlined),
                title: Text(
                  g.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(ctx).pop(g.roomId),
              ),
          ],
        ),
      ),
    ),
  );
  if (id == null || !context.mounted) return;
  await context.push('/groups/$id/reset');
}

/// "What do you need?" — one line per situation, pointing at the right tool.
class _DecisionAid extends StatelessWidget {
  final bool matrix;
  final bool snapshots;
  const _DecisionAid({required this.matrix, required this.snapshots});

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    Widget row(IconData icon, String text, {String? extra, Key? key}) =>
        Padding(
          key: key,
          padding: const EdgeInsets.only(top: Insets.m),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 20, color: scheme.secondary),
              const SizedBox(width: Insets.m),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(text, style: theme.textTheme.bodyMedium),
                    if (extra != null)
                      Padding(
                        padding: const EdgeInsets.only(top: Insets.xs),
                        child: Text(
                          extra,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Insets.page),
      child: Card(
        key: const Key('backupDecisionAid'),
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            Insets.l,
            Insets.l,
            Insets.l,
            Insets.l,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l.backupDecisionTitle,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              row(Icons.undo, l.backupDecisionUndo),
              row(Icons.history, l.backupDecisionGroup),
              row(
                Icons.restore_page_outlined,
                snapshots ? l.backupDecisionDevice : l.backupDecisionDeviceWeb,
                key: const Key('backupDecisionDevice'),
              ),
              row(
                Icons.smartphone,
                l.backupDecisionPhone,
                extra: matrix ? l.backupDecisionPhoneMatrix : null,
                key: const Key('backupDecisionPhone'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A muted explanation paragraph.
class _Para extends StatelessWidget {
  final String text;
  const _Para(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Insets.page,
        Insets.xs,
        Insets.page,
        Insets.s,
      ),
      child: Text(
        text,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
