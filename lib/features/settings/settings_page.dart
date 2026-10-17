import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/widgets/action_error.dart';
import 'package:go_router/go_router.dart';

import '../../core/background/background_scheduler.dart';
import '../../core/background/background_sync_provider.dart';
import '../../core/l10n/l10n.dart';
import '../../core/session/app_session.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/content_width.dart';
import '../../core/widgets/settings_section.dart';
import '../auth/auth_provider.dart';
import '../backup/backup_ui.dart';
import '../devices/device_provider.dart';
import '../groups/group_provider.dart';
import '../local/local_mode_ui.dart';
import '../onboarding/onboarding_provider.dart';

/// G65: route of the app settings page.
const kSettingsLocation = '/settings';

/// G65 (U28, U21): the app settings page (gear on the groups page) — was a
/// bottom sheet. Sections:
///
/// * **Account** — the Matrix account + *Sign out* (U21: was an app-bar
///   icon), or local mode's name / *Connect a Matrix account* / *Delete
///   local data* (G40);
/// * **Sync & devices** (Matrix only) — when this device syncs, background
///   sync (G31), *Only sync with verified devices* (G11), *Devices &
///   security* (G56). G52 step 9 adds the relay list here (link groups also
///   sync in local mode — the section then shows for both);
/// * **Backup & restore** — last backup, back up all groups, restore,
///   restore points (G5 / G34 / G48; G70 merges them into one page);
/// * **Data** — *Import CSV* (U21: was an app-bar icon);
/// * **About**;
/// * **Debug** — debug builds only (G36 one-off background round).
///
/// Every flow runs on this page's context (no sheet to close first).
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final local = ref.watch(localModeActiveProvider);
    final supported = ref.watch(backgroundSyncSupportedProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l.settingsTitle)),
      body: ContentWidth(
        child: ListView(
          key: const Key('settingsList'),
          padding: EdgeInsets.only(
            bottom: Insets.xl + MediaQuery.paddingOf(context).bottom,
          ),
          children: [
            SettingsSectionHeader(l.settingsSectionAccount),
            if (local)
              const LocalModeSettingsSection()
            else
              const _MatrixAccountSection(),
            if (!local) ...[
              SettingsSectionHeader(l.settingsSectionSync),
              const _SyncSection(),
            ],
            SettingsSectionHeader(l.settingsSectionBackup),
            const BackupSettingsSection(),
            SettingsSectionHeader(l.settingsSectionData),
            ListTile(
              key: const Key('importCsvTile'),
              leading: const Icon(Icons.upload_file),
              title: Text(l.importCsv),
              subtitle: Text(l.importCsvTileBody),
              onTap: () => importCsvWithPreview(context, ref),
            ),
            SettingsSectionHeader(l.settingsSectionAbout),
            ListTile(
              key: const Key('aboutTile'),
              leading: const Icon(Icons.info_outline),
              title: Text(l.aboutTitle),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/about'),
            ),
            // G36: debug builds only — queue one background round for a
            // manual test (never shown in release builds).
            if (kDebugMode && supported && !local) ...[
              SettingsSectionHeader(l.settingsSectionDebug),
              const _DebugBackgroundRunTile(),
            ],
          ],
        ),
      ),
    );
  }
}

/// The signed-in Matrix account and *Sign out* (G29 confirmation).
class _MatrixAccountSection extends ConsumerWidget {
  const _MatrixAccountSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final mxid = ref.watch(currentUserIdProvider);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(
          key: const Key('accountTile'),
          leading: const Icon(Icons.account_circle_outlined),
          title: Text(l.settingsMatrixAccount),
          subtitle: mxid.isEmpty
              ? null
              : Text(mxid, maxLines: 2, overflow: TextOverflow.ellipsis),
        ),
        ListTile(
          key: const Key('signOutTile'),
          leading: const Icon(Icons.logout),
          title: Text(l.signOut),
          subtitle: Text(l.signOutTileBody),
          onTap: () => confirmSignOut(context, ref),
        ),
      ],
    );
  }
}

/// Sign-out confirmation (G29). Signing out is non-destructive: this
/// account's ledger DB stays on the device (per-account DB, G4) and is
/// reopened on the next sign-in with the same account.
Future<void> confirmSignOut(BuildContext context, WidgetRef ref) async {
  final l = context.l10n;
  final errors = ActionErrors.of(context);
  final auth = ref.read(authProvider.notifier);
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l.signOutConfirmTitle),
      content: Text(l.signOutConfirmBody),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(l.cancel),
        ),
        FilledButton(
          key: const Key('signOutConfirm'),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(l.signOut),
        ),
      ],
    ),
  );
  if (ok != true) return;
  await auth.logout();
  if (!context.mounted) return;
  final error = ref.read(authProvider).error;
  if (error != null) {
    errors.show(error);
  }
}

/// When this device syncs (G31), the background-sync switch, verified-only
/// (G11) and the devices page (G56).
class _SyncSection extends ConsumerWidget {
  const _SyncSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final supported = ref.watch(backgroundSyncSupportedProvider);
    final enabled = ref.watch(backgroundSyncEnabledProvider).value ?? true;
    final schedulingError = ref.watch(backgroundSyncSchedulingErrorProvider);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            Insets.page,
            Insets.xs,
            Insets.page,
            Insets.s,
          ),
          child: Text(
            l.syncSettingsBody,
            key: const Key('syncSettingsBody'),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        if (supported)
          SwitchListTile(
            key: const Key('backgroundSyncSwitch'),
            secondary: const Icon(Icons.sync),
            title: Text(l.backgroundSyncTitle),
            subtitle: Text(l.backgroundSyncBody),
            value: enabled,
            onChanged: (v) =>
                ref.read(settingsDaoProvider).setBackgroundSyncEnabled(v),
          ),
        // G33: the OS refused to (un)register the task — say so.
        if (supported && schedulingError != null)
          ListTile(
            key: const Key('backgroundSyncError'),
            leading: Icon(Icons.error_outline, color: theme.colorScheme.error),
            title: Text(
              l.backgroundSyncScheduleFailed(schedulingError.toString()),
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ),
        if (!supported)
          ListTile(
            leading: const Icon(Icons.sync_disabled),
            title: Text(l.noBackgroundSyncTitle),
            subtitle: Text(l.noBackgroundSyncBody),
          ),
        const VerifiedOnlySyncTile(),
        // G56: was an app-bar icon on the groups page.
        ListTile(
          key: const Key('devicesTile'),
          leading: const Icon(Icons.devices),
          title: Text(l.devicesTooltip),
          subtitle: Text(l.devicesSettingsBody),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push('/devices'),
        ),
      ],
    );
  }
}

/// G36: queues one WorkManager background round (debug builds only).
class _DebugBackgroundRunTile extends ConsumerWidget {
  const _DebugBackgroundRunTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    return ListTile(
      key: const Key('debugRunBackgroundSync'),
      leading: const Icon(Icons.bug_report_outlined),
      title: Text(l.debugRunBackgroundSync),
      subtitle: Text(
        l.debugRunBackgroundSyncBody(kDebugBackgroundRunDelay.inSeconds),
      ),
      onTap: () async {
        final messenger = ScaffoldMessenger.maybeOf(context);
        final errors = ActionErrors.maybeOf(context);
        try {
          await ref
              .read(backgroundSchedulerProvider)
              .runOnce(delay: kDebugBackgroundRunDelay);
          messenger?.showSnackBar(
            SnackBar(content: Text(l.debugRunBackgroundSyncQueued)),
          );
        } catch (e) {
          errors?.show(e);
        }
      },
    );
  }
}

/// G11: the opt-in "Only sync with verified devices" switch (per account,
/// device-local). Turning it on asks first and spells out the consequence.
class VerifiedOnlySyncTile extends ConsumerWidget {
  const VerifiedOnlySyncTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final on = ref.watch(verifiedOnlySyncProvider).value ?? false;
    return SwitchListTile(
      key: const Key('verifiedOnlySwitch'),
      secondary: const Icon(Icons.verified_user_outlined),
      title: Text(l.verifiedOnlyTitle),
      subtitle: Text(on ? l.verifiedOnlyOnBody : l.verifiedOnlyOffBody),
      value: on,
      onChanged: (v) async {
        final settings = ref.read(settingsDaoProvider);
        if (v) {
          final ok = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: Text(l.verifiedOnlyConfirmTitle),
              content: Text(l.verifiedOnlyConfirmBody),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text(l.cancel),
                ),
                FilledButton(
                  key: const Key('verifiedOnlyConfirm'),
                  onPressed: () => Navigator.pop(ctx, true),
                  child: Text(l.verifiedOnlyTurnOn),
                ),
              ],
            ),
          );
          if (ok != true) return;
        }
        await settings.setVerifiedOnlySync(v);
      },
    );
  }
}
