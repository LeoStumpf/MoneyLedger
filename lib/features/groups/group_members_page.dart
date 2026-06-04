import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/member_model.dart';
import 'group_provider.dart';

/// Lists the group's members (from the local DB) and lets the user remove them.
/// Removing marks the member `removed` (replicated, last-writer-wins) — their
/// expense history is kept in Drift, so balances are preserved.
class GroupMembersPage extends ConsumerWidget {
  final String roomId;
  const GroupMembersPage({super.key, required this.roomId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final membersAsync = ref.watch(groupMembersProvider(roomId));
    final myId = ref.watch(currentUserIdProvider);
    final removerState = ref.watch(memberRemoverProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Members')),
      body: Stack(
        children: [
          membersAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error: $e')),
            data: (all) {
              final members = all.where((m) => m.isActive).toList();
              if (members.isEmpty) {
                return const Center(child: Text('No members.'));
              }
              return ListView.builder(
                itemCount: members.length,
                itemBuilder: (context, i) {
                  final m = members[i];
                  final isSelf = m.userId == myId;
                  return ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.person)),
                    title: Text(m.userId),
                    subtitle: Text(m.userId),
                    trailing: isSelf
                        ? const Chip(label: Text('You'))
                        : IconButton(
                            icon: const Icon(Icons.person_remove_outlined),
                            tooltip: 'Remove',
                            onPressed: removerState.isLoading
                                ? null
                                : () => _remove(context, ref, m),
                          ),
                  );
                },
              );
            },
          ),
          if (removerState.isLoading)
            const ColoredBox(
              color: Colors.black26,
              child: Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }

  Future<void> _remove(
      BuildContext context, WidgetRef ref, MemberModel member) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove member'),
        content: Text('Remove ${member.userId} from this group?\n\n'
            'Their expense history is kept; only their membership is cleared.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await ref
        .read(memberRemoverProvider.notifier)
        .remove(roomId, member.userId);

    final error = ref.read(memberRemoverProvider).error;
    messenger.showSnackBar(SnackBar(
        content: Text(
            error != null ? 'Failed: $error' : 'Removed ${member.userId}')));
  }
}
