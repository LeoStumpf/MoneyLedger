import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/widgets/action_error.dart';

import '../../core/database/app_database.dart';
import '../../core/l10n/l10n.dart';
import '../../core/session/app_session.dart';
import '../../core/session/device_prefs.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/text_prompt_dialog.dart';
import '../backup/backup_ui.dart' show exportFullBackup;
import '../expenses/expenses_provider.dart';
import '../groups/group_provider.dart';

/// G40: the "Local only" chip in the groups app bar — the always-visible
/// local-mode indicator. Opens [showLocalModeSheet].
class LocalModeChip extends StatelessWidget {
  const LocalModeChip({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Insets.xs),
      child: ActionChip(
        key: const Key('localModeChip'),
        avatar: Icon(
          Icons.phone_android_outlined,
          size: 18,
          color: scheme.onTertiaryContainer,
        ),
        label: Text(context.l10n.localModeChip),
        labelStyle: TextStyle(color: scheme.onTertiaryContainer),
        backgroundColor: scheme.tertiaryContainer,
        side: BorderSide.none,
        visualDensity: VisualDensity.compact,
        tooltip: context.l10n.localModeSheetTitle,
        onPressed: () => showLocalModeSheet(context),
      ),
    );
  }
}

/// G40: what local mode means — nothing leaves this device, back up, connect
/// an account to share — with the two actions.
Future<void> showLocalModeSheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _LocalModeSheet(),
    );

class _LocalModeSheet extends ConsumerWidget {
  const _LocalModeSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    Widget point(IconData icon, String text) => Padding(
      padding: const EdgeInsets.only(bottom: Insets.l),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: scheme.primary),
          const SizedBox(width: Insets.l),
          Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
    return SafeArea(
      child: SingleChildScrollView(
        key: const Key('localModeSheet'),
        padding: const EdgeInsets.fromLTRB(
          Insets.xl,
          Insets.l,
          Insets.xl,
          Insets.l,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l.localModeSheetTitle,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: Insets.l),
            point(Icons.phone_android_outlined, l.localModeSheetBody),
            point(Icons.backup_outlined, l.localModeBackupHint),
            point(Icons.link, l.localModeConnectHint),
            const SizedBox(height: Insets.s),
            FilledButton.icon(
              key: const Key('localSheetConnect'),
              icon: const Icon(Icons.login),
              label: Text(l.connectMatrixAccount),
              onPressed: () {
                Navigator.of(context).pop();
                startConnectAccount(context, ref);
              },
            ),
            const SizedBox(height: Insets.s),
            OutlinedButton.icon(
              key: const Key('localSheetBackup'),
              icon: const Icon(Icons.save_alt),
              label: Text(l.backupExportTitle),
              onPressed: () {
                final nav = Navigator.of(context);
                nav.pop();
                exportFullBackup(nav.context, ref);
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// G40: "Connect a Matrix account" — the router then shows the login page
/// (with a cancel button) on top of the still-active local profile. After a
/// successful sign-in the local ledger moves into that account.
Future<void> startConnectAccount(BuildContext context, WidgetRef ref) async {
  final errors = ActionErrors.maybeOf(context);
  try {
    await ref.read(devicePrefsProvider.notifier).setConnecting(true);
  } catch (e) {
    errors?.show(e);
  }
}

/// G40: cancels a connect — back to local mode.
Future<void> cancelConnectAccount(WidgetRef ref) async {
  try {
    await ref.read(devicePrefsProvider.notifier).setConnecting(false);
  } catch (_) {
    // In memory it is cancelled already; only the stored flag lags.
  }
}

/// G40: the local-mode part of the settings page (G65: its *Account*
/// section): the profile name,
/// "Connect a Matrix account" and "Delete local data".
class LocalModeSettingsSection extends ConsumerWidget {
  const LocalModeSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final profile = ref.watch(localProfileProvider);
    final error = Theme.of(context).colorScheme.error;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          title: Text(l.localModeSheetTitle),
          subtitle: Text(l.localModeSettingsBody),
        ),
        ListTile(
          key: const Key('localProfileNameTile'),
          leading: const Icon(Icons.badge_outlined),
          title: Text(l.localProfileName(profile?.name ?? '')),
          subtitle: Text(l.localProfileNameHint),
          onTap: () async {
            final name = await showTextPrompt(
              context,
              title: l.rename,
              label: l.localSetupNameLabel,
              initial: profile?.name ?? '',
              cancelLabel: l.cancel,
              confirmLabel: l.ok,
            );
            if (name == null || name.trim().isEmpty) return;
            await ref
                .read(devicePrefsProvider.notifier)
                .renameLocalProfile(name);
          },
        ),
        ListTile(
          key: const Key('connectAccountTile'),
          leading: const Icon(Icons.login),
          title: Text(l.connectMatrixAccount),
          subtitle: Text(l.connectMatrixAccountBody),
          onTap: () => startConnectAccount(context, ref),
        ),
        ListTile(
          key: const Key('deleteLocalDataTile'),
          leading: Icon(Icons.delete_forever_outlined, color: error),
          title: Text(l.deleteLocalData, style: TextStyle(color: error)),
          subtitle: Text(l.deleteLocalDataBody),
          onTap: () => confirmDeleteLocalData(context, ref),
        ),
      ],
    );
  }
}

/// G40: "Delete local data" — after a confirmation every row of the local
/// ledger is deleted and local mode ends (G46: back to the welcome, whose
/// three choices fit someone who didn't want an account).
Future<void> confirmDeleteLocalData(BuildContext context, WidgetRef ref) async {
  final l = context.l10n;
  final errors = ActionErrors.maybeOf(context);
  // Captured before any await (G19).
  final db = ref.read(appDatabaseProvider);
  final prefs = ref.read(devicePrefsProvider.notifier);
  final deleteFiles = ref.read(localDatabaseDeleterProvider);
  final container = ProviderScope.containerOf(context, listen: false);
  final groups = ref.read(ledgerGroupsProvider).value?.length ?? 0;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l.deleteLocalDataConfirmTitle),
      content: Text(l.deleteLocalDataConfirmBody(groups)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(l.cancel),
        ),
        FilledButton(
          key: const Key('deleteLocalDataConfirm'),
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(ctx).colorScheme.error,
            foregroundColor: Theme.of(ctx).colorScheme.onError,
          ),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(l.deleteLocalDataConfirmAction),
        ),
      ],
    ),
  );
  if (ok != true) return;
  // G46: set before local mode ends, so the router's first redirect off the
  // groups page already goes to the welcome (no login page flash).
  container
      .read(signedOutLandingProvider.notifier)
      .set(SignedOutLanding.welcome);
  await deleteLocalLedger(
    db: db,
    prefs: prefs,
    deleteFiles: deleteFiles,
    releaseDb: () => container.invalidate(appDatabaseProvider),
    onError: (e) {
      // Still in local mode: a later exit isn't necessarily this one.
      container
          .read(signedOutLandingProvider.notifier)
          .set(SignedOutLanding.login);
      errors?.show(e);
    },
  );
}

/// Wipes the local ledger [db] and ends local mode. Nothing is ended when
/// the wipe fails ([onError] is told). G41: then [releaseDb] lets
/// `appDatabaseProvider` drop (close) [db] — it rebuilds for whatever comes
/// next, so nothing keeps a closed DB — and once it is closed its files are
/// removed ([deleteFiles]); best-effort, the data is already gone.
Future<void> deleteLocalLedger({
  required AppDatabase db,
  required DevicePrefsNotifier prefs,
  Future<bool> Function()? deleteFiles,
  void Function()? releaseDb,
  void Function(Object e)? onError,
}) async {
  try {
    final real = !db.isSignedOutPlaceholder && !db.isClosed;
    if (real) await db.wipeAll();
    await prefs.endLocalProfile();
    if (real && deleteFiles != null && releaseDb != null) {
      releaseDb();
      await db.close(); // idempotent: waits for the provider's close
      await deleteFiles();
    }
  } catch (e) {
    onError?.call(e);
  }
}
