/// UI for the full backup (G5) and the CSV import preview (G13): the settings
/// sheet entries, the export / restore flows with their preview dialog, and
/// the groups-page nudge card.
///
/// Every flow follows the G19 rules: the account-bound objects (backup
/// service, importer, sync engine, messenger) are captured **before** the
/// first await, and `context` is only used after an await when still mounted.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/l10n.dart';
import '../../core/sync/sync_engine.dart';
import '../../core/theme/app_theme.dart';
import '../groups/group_provider.dart';
import 'backup_files.dart';
import 'backup_providers.dart';
import 'backup_service.dart';
import 'csv_import.dart';
import 'ledger_backup.dart';

// ── settings sheet section ───────────────────────────────────────────────────

/// "Backup" section of the settings sheet: last backup date, back up, restore.
class BackupSettingsSection extends ConsumerWidget {
  const BackupSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final last = ref.watch(lastBackupAtProvider).value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(
          title: Text(l.backupSectionTitle),
          subtitle: Text(
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
          onTap: () => _closeSheetThen(context, ref, exportFullBackup),
        ),
        ListTile(
          key: const Key('backupRestoreTile'),
          leading: const Icon(Icons.settings_backup_restore),
          title: Text(l.backupRestoreTitle),
          subtitle: Text(l.backupRestoreBody),
          onTap: () => _closeSheetThen(context, ref, restoreFullBackup),
        ),
      ],
    );
  }
}

/// Closes the settings sheet, then runs [flow] on the navigator's context, so
/// its dialogs and snackbars appear on the page — not hidden under the sheet.
/// The flows read `ref` synchronously before their first await, i.e. while
/// the sheet is still mounted.
void _closeSheetThen(
  BuildContext context,
  WidgetRef ref,
  Future<void> Function(BuildContext, WidgetRef) flow,
) {
  final nav = Navigator.of(context);
  nav.pop();
  flow(nav.context, ref);
}

// ── export ───────────────────────────────────────────────────────────────────

/// Writes the whole account's backup file and records `last_backup_at`.
Future<void> exportFullBackup(BuildContext context, WidgetRef ref) async {
  final l = context.l10n;
  final messenger = ScaffoldMessenger.of(context);
  final service = ref.read(backupServiceProvider);
  final account = ref.read(currentUserIdProvider);
  final now = DateTime.now();
  final name = backupFileName(now);
  try {
    final json = await service.exportJson(
      account: account.isEmpty ? null : account,
      now: now.millisecondsSinceEpoch,
    );
    final saved = await saveTextFile(name, json, LedgerFileKind.backup);
    if (!saved) return; // dialog cancelled
    await service.markBackedUp(now.millisecondsSinceEpoch);
    messenger.showSnackBar(SnackBar(content: Text(l.backupSaved(name))));
  } catch (e) {
    messenger.showSnackBar(
      SnackBar(content: Text(l.exportFailed(e.toString()))),
    );
  }
}

// ── restore ──────────────────────────────────────────────────────────────────

/// The user-facing message for a backup file that can't be read.
String backupErrorMessage(BackupFormatException e, AppLocalizations l) =>
    switch (e.kind) {
      BackupErrorKind.notABackup => l.backupNotABackup,
      BackupErrorKind.newerVersion => l.backupNewerVersion(e.version ?? 0),
      BackupErrorKind.malformed => l.backupMalformed,
    };

/// Pick a backup file → preview → confirm → merge, then nudge peers with a
/// digest per restored group (best-effort; anti-entropy does the rest).
Future<void> restoreFullBackup(BuildContext context, WidgetRef ref) async {
  final l = context.l10n;
  final messenger = ScaffoldMessenger.of(context);
  final service = ref.read(backupServiceProvider);
  final engine = ref.read(syncEngineProvider);
  final me = ref.read(currentUserIdProvider);
  final String? text;
  try {
    text = await pickTextFile(LedgerFileKind.backup);
  } catch (e) {
    messenger.showSnackBar(
      SnackBar(content: Text(l.restoreFailed(e.toString()))),
    );
    return;
  }
  if (text == null) return; // cancelled
  try {
    final backup = parseBackup(text);
    final preview = await service.preview(backup, myMxid: me);
    if (!context.mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => RestorePreviewDialog(preview: preview),
    );
    if (ok != true) return;
    final restored = await service.restore(backup);
    for (final id in restored) {
      engine.pokeGroup(id);
    }
    messenger.showSnackBar(
      SnackBar(content: Text(l.restoredGroups(restored.length))),
    );
  } on BackupFormatException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(backupErrorMessage(e, l))));
  } catch (e) {
    messenger.showSnackBar(
      SnackBar(content: Text(l.restoreFailed(e.toString()))),
    );
  }
}

/// What a restore would do; pops `true` to restore.
class RestorePreviewDialog extends StatelessWidget {
  final RestorePreview preview;
  const RestorePreviewDialog({super.key, required this.preview});

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final exportedAt = preview.backup.exportedAt;
    final anyLeft = preview.groups.any((g) => g.wasLeft);
    return AlertDialog(
      key: const Key('restorePreviewDialog'),
      title: Text(l.restorePreviewTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (exportedAt != null)
              Text(l.restoreBackupFrom(context.date(exportedAt)), style: muted),
            if (preview.otherAccount) ...[
              const SizedBox(height: Insets.m),
              _Warning(
                key: const Key('restoreOtherAccount'),
                text: l.restoreOtherAccount(preview.backup.account!),
              ),
            ],
            const SizedBox(height: Insets.m),
            Text(
              [
                l.groupsCount(preview.groups.length),
                l.expensesCount(preview.expenses),
                l.paymentsCount(preview.settlements),
              ].join(' · '),
              key: const Key('restoreTotals'),
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: Insets.xs),
            Text(
              l.restoreNewGroups(preview.newGroups),
              key: const Key('restoreNewGroups'),
            ),
            Text(
              l.restoreChanges(preview.changes),
              key: const Key('restoreChanges'),
            ),
            const SizedBox(height: Insets.m),
            for (final g in preview.groups)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: Insets.xs),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        g.summary.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: Insets.s),
                    Text(
                      g.wasLeft
                          ? l.restoreTagLeft
                          : g.isNew
                          ? l.restoreTagNew
                          : g.changes == 0
                          ? l.restoreTagUpToDate
                          : l.restoreTagChanges(g.changes),
                      style: muted,
                    ),
                  ],
                ),
              ),
            if (anyLeft) ...[
              const SizedBox(height: Insets.s),
              Text(l.restoreLeftNote, style: muted),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l.cancel),
        ),
        FilledButton(
          key: const Key('restoreConfirm'),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l.restoreAction),
        ),
      ],
    );
  }
}

class _Warning extends StatelessWidget {
  final String text;
  const _Warning({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(Insets.m),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(Radii.s),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.warning_amber_rounded,
            size: 20,
            color: scheme.onErrorContainer,
          ),
          const SizedBox(width: Insets.s),
          Expanded(
            child: Text(text, style: TextStyle(color: scheme.onErrorContainer)),
          ),
        ],
      ),
    );
  }
}

// ── CSV import with preview (G13) ────────────────────────────────────────────

/// Pick a CSV → preview (incl. name-match warnings) → confirm → import.
Future<void> importCsvWithPreview(BuildContext context, WidgetRef ref) async {
  final l = context.l10n;
  final messenger = ScaffoldMessenger.of(context);
  final importer = ref.read(csvImporterProvider.notifier);
  final String? text;
  try {
    text = await pickTextFile(LedgerFileKind.csv);
  } catch (e) {
    // The picked file couldn't be read (G15: never fail silently).
    messenger.showSnackBar(
      SnackBar(content: Text(l.importFailed(e.toString()))),
    );
    return;
  }
  if (text == null) return; // cancelled
  try {
    final preview = await importer.preview(text);
    if (preview.isEmpty) {
      messenger.showSnackBar(SnackBar(content: Text(l.csvImportEmpty)));
      return;
    }
    if (!context.mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => CsvImportPreviewDialog(preview: preview),
    );
    if (ok != true) return;
    final r = await importer.importCsv(text);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          r.payments == 0
              ? l.importedExpenses(r.expenses)
              : l.importedExpensesAndPayments(
                  l.expensesCount(r.expenses),
                  l.paymentsCount(r.payments),
                ),
        ),
      ),
    );
  } catch (e) {
    messenger.showSnackBar(
      SnackBar(content: Text(l.importFailed(e.toString()))),
    );
  }
}

/// What a CSV import would do; pops `true` to import.
class CsvImportPreviewDialog extends StatelessWidget {
  final CsvImportPreview preview;
  const CsvImportPreviewDialog({super.key, required this.preview});

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    return AlertDialog(
      key: const Key('csvPreviewDialog'),
      title: Text(l.csvPreviewTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              preview.isNewGroup
                  ? l.csvPreviewNewGroup(preview.groupName)
                  : l.csvPreviewExistingGroup(preview.groupName),
            ),
            const SizedBox(height: Insets.s),
            Text(
              [
                l.expensesCount(preview.expenseCount),
                l.paymentsCount(preview.paymentCount),
              ].join(' · '),
              style: theme.textTheme.titleSmall,
            ),
            if (preview.unmatched.isNotEmpty) ...[
              const SizedBox(height: Insets.m),
              _Warning(
                key: const Key('csvUnmatched'),
                text: l.csvPreviewUnmatched(preview.unmatched.join(', ')),
              ),
            ],
            if (preview.ambiguous.isNotEmpty) ...[
              const SizedBox(height: Insets.m),
              _Warning(
                key: const Key('csvAmbiguous'),
                text: l.csvPreviewAmbiguous(preview.ambiguous.join(', ')),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l.cancel),
        ),
        FilledButton(
          key: const Key('csvImportConfirm'),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l.csvImportAction),
        ),
      ],
    );
  }
}

// ── nudge card ───────────────────────────────────────────────────────────────

/// Groups-page card shown while [backupNudgeProvider] reports groups only this
/// device could restore and no recent backup. "Later" snoozes it for
/// [kBackupNudgeInterval] (device-local, per account).
class BackupNudgeCard extends ConsumerWidget {
  final int count;
  const BackupNudgeCard({super.key, required this.count});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      key: const Key('backupNudge'),
      color: scheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Insets.l,
          Insets.l,
          Insets.l,
          Insets.s,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.backup_outlined, color: scheme.onSecondaryContainer),
                const SizedBox(width: Insets.m),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l.backupNudgeTitle,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: scheme.onSecondaryContainer,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: Insets.xs),
                      Text(
                        l.backupNudgeBody(count),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSecondaryContainer,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            Align(
              alignment: Alignment.centerRight,
              child: Wrap(
                spacing: Insets.s,
                children: [
                  TextButton(
                    key: const Key('backupNudgeLater'),
                    onPressed: () {
                      final now = ref.read(backupNudgeClockProvider)();
                      ref.read(snoozeBackupNudgeProvider)(
                        now.add(kBackupNudgeInterval).millisecondsSinceEpoch,
                      );
                    },
                    child: Text(l.backupNudgeLater),
                  ),
                  FilledButton(
                    key: const Key('backupNudgeAction'),
                    onPressed: () => exportFullBackup(context, ref),
                    child: Text(l.backupNudgeAction),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
