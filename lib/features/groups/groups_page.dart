import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../auth/auth_provider.dart';
import '../backup/csv_files.dart';
import '../backup/csv_import.dart';
import '../expenses/ledger_syncer.dart';
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Groups'),
        actions: [
          IconButton(
            icon: const Icon(Icons.upload_file),
            tooltip: 'Import CSV',
            onPressed: () => _importCsv(context, ref),
          ),
          IconButton(
            icon: const Icon(Icons.devices),
            tooltip: 'Devices & security',
            onPressed: () => context.push('/devices'),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => _confirmSignOut(context, ref),
            tooltip: 'Sign out',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/groups/create'),
        icon: const Icon(Icons.add),
        label: const Text('New group'),
      ),
      body: _GroupsBody(groupsAsync: groupsAsync),
    );
  }

  /// Sign-out confirmation (G29). Signing out is non-destructive: this
  /// account's ledger DB stays on the device (per-account DB, G4) and is
  /// reopened on the next sign-in with the same account.
  Future<void> _confirmSignOut(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text(
            'Your groups and expenses stay on this device and are back when '
            'you sign in again with this account. While signed out, this '
            'device doesn\'t sync — other members\' changes arrive once you '
            'sign back in.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Sign out')),
        ],
      ),
    );
    if (ok == true) await ref.read(authProvider.notifier).logout();
  }

  Future<void> _importCsv(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final text = await pickCsvText();
    if (text == null) return; // cancelled
    final count = await ref.read(csvImporterProvider.notifier).importCsv(text);
    final error = ref.read(csvImporterProvider).error;
    messenger.showSnackBar(SnackBar(
        content: Text(error != null
            ? 'Import failed: $error'
            : 'Imported $count expense(s)')));
  }
}

class _GroupsBody extends StatelessWidget {
  final AsyncValue<List<GroupModel>> groupsAsync;
  const _GroupsBody({required this.groupsAsync});

  @override
  Widget build(BuildContext context) {
    return groupsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (groups) {
          if (groups.isEmpty) {
            return const Center(
              child: Text(
                'No groups yet.\nCreate one to get started.',
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
