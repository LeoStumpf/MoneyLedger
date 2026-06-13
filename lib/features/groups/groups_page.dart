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
            onPressed: () => ref.read(authProvider.notifier).logout(),
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
