import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/l10n/l10n.dart';
import '../auth/auth_provider.dart';
import '../onboarding/onboarding_provider.dart';
import '../backup/csv_files.dart';
import '../backup/csv_import.dart';
import '../expenses/ledger_syncer.dart';
import '../../core/background/background_sync_provider.dart';
import '../../core/sync/self_recovery.dart';
import '../../core/sync/sync_engine.dart';
import '../../models/group_model.dart';
import 'group_provider.dart';

class GroupsPage extends ConsumerWidget {
  const GroupsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(ledgerSyncerProvider); // keep syncer alive on the main screen
    ref.watch(syncEngineProvider); // run anti-entropy while signed in
    final groupsAsync = ref.watch(ledgerGroupsProvider);
    final l = context.l10n;

    return Scaffold(
      appBar: AppBar(
        title: Text(l.groupsTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.upload_file),
            tooltip: l.importCsvTooltip,
            onPressed: () => _importCsv(context, ref),
          ),
          IconButton(
            icon: const Icon(Icons.devices),
            tooltip: l.devicesTooltip,
            onPressed: () => context.push('/devices'),
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: l.settingsTooltip,
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              builder: (_) => const SyncSettingsSheet(),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => _confirmSignOut(context, ref),
            tooltip: l.signOut,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/groups/create'),
        icon: const Icon(Icons.add),
        label: Text(l.newGroup),
      ),
      body: _GroupsBody(
        groupsAsync: groupsAsync,
        restoring: ref.watch(selfRecoveryProvider),
      ),
    );
  }

  /// Sign-out confirmation (G29). Signing out is non-destructive: this
  /// account's ledger DB stays on the device (per-account DB, G4) and is
  /// reopened on the next sign-in with the same account.
  Future<void> _confirmSignOut(BuildContext context, WidgetRef ref) async {
    final l = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.signOutConfirmTitle),
        content: Text(l.signOutConfirmBody),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(l.cancel)),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(l.signOut)),
        ],
      ),
    );
    if (ok == true) await ref.read(authProvider.notifier).logout();
  }

  Future<void> _importCsv(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final l = context.l10n;
    final text = await pickCsvText();
    if (text == null) return; // cancelled
    final count = await ref.read(csvImporterProvider.notifier).importCsv(text);
    final error = ref.read(csvImporterProvider).error;
    messenger.showSnackBar(SnackBar(
        content: Text(error != null
            ? l.importFailed(error.toString())
            : l.importedExpenses(count))));
  }
}

class _GroupsBody extends StatelessWidget {
  final AsyncValue<List<GroupModel>> groupsAsync;

  /// A fresh device's first recovery is outstanding (G30) — show "Restoring…"
  /// instead of the empty state.
  final bool restoring;
  const _GroupsBody({required this.groupsAsync, required this.restoring});

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return groupsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(l.errorWithDetail(e.toString()))),
        data: (groups) {
          if (groups.isEmpty && restoring) return const _RestoringGroups();
          if (groups.isEmpty) {
            return Center(
              child: Text(
                l.noGroupsYet,
                textAlign: TextAlign.center,
              ),
            );
          }
          return ListView.builder(
            itemCount: groups.length,
            itemBuilder: (context, i) {
              final GroupModel group = groups[i];
              return ListTile(
                leading: const CircleAvatar(child: Icon(Icons.group)),
                title: Text(group.name),
                subtitle: Text(group.currency),
                trailing: const Icon(Icons.chevron_right),
                onTap: () =>
                    context.push('/groups/${group.roomId}/expenses'),
              );
            },
          );
        },
      );
  }
}

/// Empty DB on a freshly signed-in device while the self-resync is out (G30).
class _RestoringGroups extends StatelessWidget {
  const _RestoringGroups();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 24),
            Text(
              context.l10n.restoringGroupsTitle,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              context.l10n.restoringGroupsBody,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

/// Settings sheet (G31 sync settings, G12 about): explains when this device
/// syncs and, on Android, toggles the periodic background sync for the
/// signed-in account; links to the About page.
class SyncSettingsSheet extends ConsumerWidget {
  const SyncSettingsSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final supported = ref.watch(backgroundSyncSupportedProvider);
    final enabled = ref.watch(backgroundSyncEnabledProvider).value ?? true;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              title: Text(l.syncSettingsTitle),
              subtitle: Text(l.syncSettingsBody),
            ),
            if (supported)
              SwitchListTile(
                key: const Key('backgroundSyncSwitch'),
                secondary: const Icon(Icons.sync),
                title: Text(l.backgroundSyncTitle),
                subtitle: Text(l.backgroundSyncBody),
                value: enabled,
                onChanged: (v) => ref
                    .read(settingsDaoProvider)
                    .setBackgroundSyncEnabled(v),
              )
            else
              ListTile(
                leading: const Icon(Icons.sync_disabled),
                title: Text(l.noBackgroundSyncTitle),
                subtitle: Text(l.noBackgroundSyncBody),
              ),
            const Divider(),
            ListTile(
              key: const Key('aboutTile'),
              leading: const Icon(Icons.info_outline),
              title: Text(l.aboutTitle),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.of(context).pop();
                context.push('/about');
              },
            ),
          ],
        ),
      ),
    );
  }
}
