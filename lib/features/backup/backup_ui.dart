/// UI for the full backup (G5) and the CSV import preview (G13): the settings
/// sheet entries, the export / restore flows with their preview dialog, and
/// the groups-page nudge card.
///
/// Every flow follows the G19 rules: the account-bound objects (backup
/// service, importer, sync engine, messenger) are captured **before** the
/// first await, and `context` is only used after an await when still mounted.
library;

import 'package:flutter/foundation.dart'
    show debugPrint, kIsWeb, visibleForTesting;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/l10n.dart';
import '../../core/sync/sync_engine.dart';
import '../../core/theme/app_theme.dart';
import '../groups/group_provider.dart';
import 'backup_crypto.dart';
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

/// How a backup export ended (G34) — the caller shows [message] as a snackbar
/// or, in the leave/delete dialog, inside the dialog.
class BackupExportOutcome {
  /// False when the user cancelled (passphrase or save dialog).
  final bool saved;
  final String? message;
  const BackupExportOutcome._(this.saved, this.message);
  static const cancelled = BackupExportOutcome._(false, null);
}

/// The snackbar / dialog text for a saved backup: the real file name when the
/// platform reports one ([savedFileDisplayName]), else a neutral text.
String backupSavedMessage(
  AppLocalizations l, {
  required String? fileName,
  required bool encrypted,
}) => switch ((fileName, encrypted)) {
  (null, false) => l.backupSavedNoName,
  (null, true) => l.backupSavedEncryptedNoName,
  (final String n, false) => l.backupSaved(n),
  (final String n, true) => l.backupSavedEncrypted(n),
};

/// Runs [work] behind a modal, non-dismissible progress dialog (the Argon2id
/// key derivation takes a moment).
Future<T> _withProgress<T>(
  BuildContext context,
  String text,
  Future<T> Function() work,
) async {
  final nav = Navigator.of(context, rootNavigator: true);
  final route = DialogRoute<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: AlertDialog(
        key: const Key('backupProgress'),
        content: Row(
          children: [
            const SizedBox.square(
              dimension: 24,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            const SizedBox(width: Insets.l),
            Expanded(child: Text(text)),
          ],
        ),
      ),
    ),
  );
  nav.push(route);
  try {
    return await work();
  } finally {
    if (route.isActive) nav.removeRoute(route);
  }
}

/// Asks for an optional passphrase, builds the backup ([groupId] = one group,
/// else all), encrypts it when a passphrase was set, and saves it. Records
/// `last_backup_at` only for a full backup (a single group's file doesn't
/// protect the others). Never throws: failures come back as the message.
Future<BackupExportOutcome> runBackupExport(
  BuildContext context,
  WidgetRef ref, {
  String? groupId,
  String? groupName,
}) async {
  final l = context.l10n;
  final service = ref.read(backupServiceProvider);
  final params = ref.read(backupKdfParamsProvider);
  final account = ref.read(currentUserIdProvider);
  final passphrase = await showDialog<String>(
    context: context,
    builder: (_) => const BackupPassphraseDialog(),
  );
  if (passphrase == null || !context.mounted) {
    return BackupExportOutcome.cancelled;
  }
  final now = DateTime.now();
  final name = backupFileName(
    now,
    groupName: groupId == null ? null : groupName,
  );
  try {
    var text = await service.exportJson(
      account: account.isEmpty ? null : account,
      now: now.millisecondsSinceEpoch,
      onlyGroup: groupId,
    );
    final encrypted = passphrase.isNotEmpty;
    if (encrypted) {
      if (!context.mounted) return BackupExportOutcome.cancelled;
      final plain = text;
      text = await _withProgress(context, l.backupEncrypting, () async {
        final sw = Stopwatch()..start();
        final enc = await encryptBackup(plain, passphrase, params: params);
        debugPrint(
          '[backup] encrypted in ${sw.elapsedMilliseconds} ms '
          '(argon2id ${params.memoryKib} KiB, t=${params.iterations})',
        );
        return enc;
      });
    }
    final saved = await saveTextFile(name, text, LedgerFileKind.backup);
    if (saved == null) return BackupExportOutcome.cancelled;
    if (groupId == null) await service.markBackedUp(now.millisecondsSinceEpoch);
    return BackupExportOutcome._(
      true,
      backupSavedMessage(
        l,
        fileName: kIsWeb
            ? name
            : savedFileDisplayName(saved.path, LedgerFileKind.backup.extension),
        encrypted: encrypted,
      ),
    );
  } catch (e) {
    return BackupExportOutcome._(false, l.exportFailed(e.toString()));
  }
}

/// Writes the whole account's backup file (optionally encrypted) and records
/// `last_backup_at`; the result shows as a snackbar.
Future<void> exportFullBackup(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.of(context);
  final outcome = await runBackupExport(context, ref);
  if (outcome.message != null) {
    messenger.showSnackBar(SnackBar(content: Text(outcome.message!)));
  }
}

/// G34: backs up one group (group ⋮ menu) — same format, one entry.
Future<void> exportGroupBackup(
  BuildContext context,
  WidgetRef ref, {
  required String groupId,
  required String groupName,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final outcome = await runBackupExport(
    context,
    ref,
    groupId: groupId,
    groupName: groupName,
  );
  if (outcome.message != null) {
    messenger.showSnackBar(SnackBar(content: Text(outcome.message!)));
  }
}

/// Export step 1 (G34): an optional passphrase with a confirmation field and
/// a strength hint. Pops the passphrase — `''` for an unencrypted file — or
/// null when cancelled.
class BackupPassphraseDialog extends StatefulWidget {
  const BackupPassphraseDialog({super.key});

  @override
  State<BackupPassphraseDialog> createState() => _BackupPassphraseDialogState();
}

class _BackupPassphraseDialogState extends State<BackupPassphraseDialog> {
  final _pass = TextEditingController();
  final _confirm = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _pass.dispose();
    _confirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final pass = _pass.text;
    final strength = passphraseStrength(pass);
    final mismatch = pass.isNotEmpty && _confirm.text != pass;
    final strengthText = switch (strength) {
      PassphraseStrength.empty => null,
      PassphraseStrength.weak => l.backupPassphraseWeak,
      PassphraseStrength.fair => l.backupPassphraseFair,
      PassphraseStrength.strong => l.backupPassphraseStrong,
    };
    final strengthColor = switch (strength) {
      PassphraseStrength.weak => theme.colorScheme.error,
      _ => theme.colorScheme.onSurfaceVariant,
    };
    return AlertDialog(
      key: const Key('backupPassphraseDialog'),
      title: Text(l.backupPassphraseTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.backupPassphraseBody),
            const SizedBox(height: Insets.m),
            TextField(
              key: const Key('backupPassphrase'),
              controller: _pass,
              obscureText: _obscure,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: l.backupPassphraseLabel,
                suffixIcon: IconButton(
                  tooltip: _obscure ? l.showPassphrase : l.hidePassphrase,
                  icon: Icon(
                    _obscure
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              onChanged: (_) => setState(() {}),
            ),
            if (pass.isNotEmpty) ...[
              const SizedBox(height: Insets.s),
              TextField(
                key: const Key('backupPassphraseConfirm'),
                controller: _confirm,
                obscureText: _obscure,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  labelText: l.backupPassphraseConfirmLabel,
                  errorText: mismatch && _confirm.text.isNotEmpty
                      ? l.backupPassphraseMismatch
                      : null,
                ),
                onChanged: (_) => setState(() {}),
              ),
            ],
            const SizedBox(height: Insets.s),
            if (strengthText != null)
              Text(
                strengthText,
                key: const Key('backupPassphraseStrength'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: strengthColor,
                ),
              ),
            const SizedBox(height: Insets.s),
            if (pass.isEmpty)
              _Warning(
                key: const Key('backupPlaintextWarning'),
                text: l.backupPlaintextWarning,
              )
            else
              Text(
                l.backupPassphraseKeepSafe,
                key: const Key('backupKeepSafe'),
                style: theme.textTheme.bodySmall,
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.cancel),
        ),
        FilledButton(
          key: const Key('backupPassphraseSave'),
          onPressed: mismatch ? null : () => Navigator.of(context).pop(pass),
          child: Text(l.save),
        ),
      ],
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

/// G34: asks for the passphrase of an encrypted backup [text] and decrypts it
/// — again after a wrong one. Null when the user cancelled.
@visibleForTesting
Future<String?> unlockEncryptedBackup(
  BuildContext context,
  String text,
  BackupDecrypter decrypt,
) async {
  final l = context.l10n;
  String? error;
  while (context.mounted) {
    final pass = await showDialog<String>(
      context: context,
      builder: (_) => BackupUnlockDialog(errorText: error),
    );
    if (pass == null || !context.mounted) return null;
    try {
      return await _withProgress(
        context,
        l.backupDecrypting,
        () => decrypt(text, pass),
      );
    } on WrongPassphraseException {
      error = l.backupWrongPassphrase;
    }
  }
  return null;
}

/// Pick a backup file → (unlock an encrypted one) → preview → confirm →
/// merge, then nudge peers with a digest per restored group (best-effort;
/// anti-entropy does the rest).
Future<void> restoreFullBackup(BuildContext context, WidgetRef ref) async {
  final l = context.l10n;
  final messenger = ScaffoldMessenger.of(context);
  final service = ref.read(backupServiceProvider);
  final engine = ref.read(syncEngineProvider);
  final decrypt = ref.read(backupDecrypterProvider);
  final me = ref.read(currentUserIdProvider);
  String? text;
  try {
    text = await ref.read(backupFilePickerProvider)();
  } catch (e) {
    messenger.showSnackBar(
      SnackBar(content: Text(l.restoreFailed(e.toString()))),
    );
    return;
  }
  if (text == null) return; // cancelled
  try {
    final encrypted = isEncryptedBackup(text);
    if (encrypted) {
      if (!context.mounted) return;
      text = await unlockEncryptedBackup(context, text, decrypt);
      if (text == null) return;
    }
    final backup = parseBackup(text);
    final preview = await service.preview(backup, myMxid: me);
    if (!context.mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) =>
          RestorePreviewDialog(preview: preview, encrypted: encrypted),
    );
    if (ok != true) return;
    List<String> restored;
    try {
      restored = await service.restore(backup);
    } on RestoreIncompleteException catch (e) {
      for (final id in e.restored) {
        engine.pokeGroup(id);
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            l.restoreIncomplete(
              e.failed.length,
              e.failed.values.first.toString(),
            ),
          ),
        ),
      );
      return;
    }
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

/// Restore step: the passphrase of an encrypted backup. Pops it, or null.
class BackupUnlockDialog extends StatefulWidget {
  /// Shown under the field (e.g. "wrong passphrase") on a retry.
  final String? errorText;
  const BackupUnlockDialog({super.key, this.errorText});

  @override
  State<BackupUnlockDialog> createState() => _BackupUnlockDialogState();
}

class _BackupUnlockDialogState extends State<BackupUnlockDialog> {
  final _pass = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _pass.dispose();
    super.dispose();
  }

  void _submit() {
    if (_pass.text.isEmpty) return;
    Navigator.of(context).pop(_pass.text);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return AlertDialog(
      key: const Key('backupUnlockDialog'),
      title: Text(l.backupUnlockTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.backupUnlockBody),
          const SizedBox(height: Insets.m),
          TextField(
            key: const Key('backupUnlockPassphrase'),
            controller: _pass,
            autofocus: true,
            obscureText: _obscure,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: l.backupUnlockLabel,
              errorText: widget.errorText,
              errorMaxLines: 3,
              suffixIcon: IconButton(
                tooltip: _obscure ? l.showPassphrase : l.hidePassphrase,
                icon: Icon(
                  _obscure
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.cancel),
        ),
        FilledButton(
          key: const Key('backupUnlockConfirm'),
          onPressed: _pass.text.isEmpty ? null : _submit,
          child: Text(l.backupUnlockAction),
        ),
      ],
    );
  }
}

/// What a restore would do; pops `true` to restore.
class RestorePreviewDialog extends StatelessWidget {
  final RestorePreview preview;

  /// The file was an encrypted backup (unlocked with the passphrase).
  final bool encrypted;
  const RestorePreviewDialog({
    super.key,
    required this.preview,
    this.encrypted = false,
  });

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final exportedAt = preview.backup.exportedAt;
    final anyLeft = preview.groups.any((g) => g.wasLeft || g.removed);
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
            if (encrypted)
              Text(
                l.restoreEncryptedNote,
                key: const Key('restoreEncrypted'),
                style: muted,
              ),
            if (preview.takeover != RestoreTakeover.none) ...[
              const SizedBox(height: Insets.m),
              _Note(
                key: const Key('restoreTakeover'),
                text: preview.takeover == RestoreTakeover.localIntoAccount
                    ? l.restoreLocalIntoAccount(preview.myAccount ?? '')
                    : l.restoreAccountIntoLocal(preview.backup.account!),
              ),
            ],
            // G18 review 2: the file isn't authenticated — this device will
            // sign its truly local groups as the user's own.
            if (preview.takeover == RestoreTakeover.localIntoAccount) ...[
              const SizedBox(height: Insets.m),
              _Warning(
                key: const Key('restoreLocalOwnFile'),
                text: l.restoreLocalOwnFile,
              ),
            ],
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
                      g.removed
                          ? l.restoreTagRemoved
                          : g.wasLeft
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
              Text(
                l.restoreLeftNote,
                key: const Key('restoreLeftNote'),
                style: muted,
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
          key: const Key('restoreConfirm'),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l.restoreAction),
        ),
      ],
    );
  }
}

/// G41: an informational box (no warning) in the restore preview.
class _Note extends StatelessWidget {
  final String text;
  const _Note({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(Insets.m),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(Radii.s),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.swap_horiz_rounded,
            size: 20,
            color: scheme.onSecondaryContainer,
          ),
          const SizedBox(width: Insets.s),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: scheme.onSecondaryContainer),
            ),
          ),
        ],
      ),
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
  } on CsvImportException catch (e) {
    // G18 review: nothing was imported (all-or-nothing).
    messenger.showSnackBar(
      SnackBar(
        content: Text(l.importFailed(l.csvImportInvalidRow(e.row, e.problem))),
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
