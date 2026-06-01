import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart' show Room;
import '../auth/auth_provider.dart';
import '../../models/group_model.dart';
import 'group_provider.dart';

class GroupsPage extends ConsumerWidget {
  const GroupsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groupsAsync = ref.watch(ledgerGroupsProvider);
    final invitesAsync = ref.watch(pendingInvitesProvider);
    final acceptorState = ref.watch(inviteAcceptorProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Groups'),
        actions: [
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
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              // ── Pending invites ──────────────────────────────────────
              invitesAsync.when(
                loading: () => const SliverToBoxAdapter(child: SizedBox()),
                error: (_, _) => const SliverToBoxAdapter(child: SizedBox()),
                data: (invites) {
                  if (invites.isEmpty) {
                    return const SliverToBoxAdapter(child: SizedBox());
                  }
                  return SliverList(
                    delegate: SliverChildListDelegate([
                      const Padding(
                        padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
                        child: Text('Pending invites',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                      ...invites.map((r) => _InviteTile(room: r)),
                      const Divider(),
                    ]),
                  );
                },
              ),
              // ── Groups ───────────────────────────────────────────────
              groupsAsync.when(
                loading: () => const SliverFillRemaining(
                    child: Center(child: CircularProgressIndicator())),
                error: (e, _) => SliverFillRemaining(
                    child: Center(child: Text('Error: $e'))),
                data: (groups) {
                  if (groups.isEmpty) {
                    return const SliverFillRemaining(
                      child: Center(
                        child: Text(
                          'No groups yet.\nCreate one to get started.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    );
                  }
                  return SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, i) {
                        final GroupModel group = groups[i];
                        return ListTile(
                          leading:
                              const CircleAvatar(child: Icon(Icons.group)),
                          title: Text(group.name),
                          subtitle: Text(group.currency),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => context
                              .push('/groups/${group.roomId}/expenses'),
                        );
                      },
                      childCount: groups.length,
                    ),
                  );
                },
              ),
            ],
          ),
          if (acceptorState.isLoading)
            const ColoredBox(
              color: Colors.black26,
              child: Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }
}

class _InviteTile extends ConsumerWidget {
  final Room room;
  const _InviteTile({required this.room});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final acceptor = ref.read(inviteAcceptorProvider.notifier);
    return ListTile(
      leading: const CircleAvatar(child: Icon(Icons.mail_outline)),
      title: Text(room.name.isNotEmpty ? room.name : room.id),
      subtitle: const Text('Invited you to join'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextButton(
            onPressed: () => acceptor.decline(room.id),
            child: const Text('Decline'),
          ),
          const SizedBox(width: 4),
          FilledButton(
            onPressed: () => acceptor.accept(room.id),
            child: const Text('Accept'),
          ),
        ],
      ),
    );
  }
}
