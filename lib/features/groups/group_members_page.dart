import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/matrix/ledger_transport.dart';
import '../../core/matrix/transport_provider.dart';
import 'group_provider.dart';

/// Lists the Matrix members of a group and lets the user remove (kick) them.
/// Removing only clears Matrix membership — expense history is kept in Drift.
class GroupMembersPage extends ConsumerStatefulWidget {
  final String roomId;
  const GroupMembersPage({super.key, required this.roomId});

  @override
  ConsumerState<GroupMembersPage> createState() => _GroupMembersPageState();
}

class _GroupMembersPageState extends ConsumerState<GroupMembersPage> {
  List<TransportMember>? _members; // null = loading
  String? _myId;

  @override
  void initState() {
    super.initState();
    _loadMembers();
  }

  Future<void> _loadMembers() async {
    final transport = await ref.read(ledgerTransportProvider.future);
    if (!mounted) return;
    final members = await transport.participants(
      widget.roomId,
      memberships: {TransportMembership.join, TransportMembership.invite},
    );
    if (mounted) {
      setState(() {
        _members = members;
        _myId = transport.userId;
      });
    }
  }

  Future<void> _remove(TransportMember member) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove member'),
        content: Text(
            'Remove ${member.displayName ?? member.id} from this group?\n\n'
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
        .remove(widget.roomId, member.id);

    final error = ref.read(memberRemoverProvider).error;
    if (error != null) {
      messenger.showSnackBar(SnackBar(content: Text('Failed: $error')));
    } else {
      messenger.showSnackBar(SnackBar(content: Text('Removed ${member.id}')));
      await _loadMembers();
    }
  }

  @override
  Widget build(BuildContext context) {
    final removerState = ref.watch(memberRemoverProvider);
    final members = _members;

    return Scaffold(
      appBar: AppBar(title: const Text('Members')),
      body: Stack(
        children: [
          if (members == null)
            const Center(child: CircularProgressIndicator())
          else if (members.isEmpty)
            const Center(child: Text('No members.'))
          else
            ListView.builder(
              itemCount: members.length,
              itemBuilder: (context, i) {
                final m = members[i];
                final isSelf = m.id == _myId;
                final isInvited = m.membership == TransportMembership.invite;
                return ListTile(
                  leading: CircleAvatar(
                    child: Icon(isInvited ? Icons.mail_outline : Icons.person),
                  ),
                  title: Text(m.displayName ?? m.id),
                  subtitle: Text(isInvited ? 'Invited · ${m.id}' : m.id),
                  trailing: isSelf
                      ? const Chip(label: Text('You'))
                      : IconButton(
                          icon: const Icon(Icons.person_remove_outlined),
                          tooltip: 'Remove',
                          onPressed: removerState.isLoading
                              ? null
                              : () => _remove(m),
                        ),
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
}
