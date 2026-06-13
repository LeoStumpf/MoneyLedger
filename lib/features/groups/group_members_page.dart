import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/member_model.dart';
import 'group_provider.dart';

/// Manages a group's participants (virtual users). A participant is a named
/// person who may or may not be linked to a Matrix account:
///  - **Claimed** (`matrixId != null`) — a real account; receives sync.
///  - **Local** — a Tricount-style placeholder; ledger data only.
///
/// Actions: add (name + optional Matrix ID), rename, claim/unclaim a Matrix
/// account (keeps history), and remove from the group (history kept).
class GroupMembersPage extends ConsumerWidget {
  final String roomId;
  const GroupMembersPage({super.key, required this.roomId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final membersAsync = ref.watch(groupMembersProvider(roomId));
    final myId = ref.watch(currentUserIdProvider);
    final adderState = ref.watch(memberAdderProvider);
    final removerState = ref.watch(memberRemoverProvider);
    final busy = adderState.isLoading || removerState.isLoading;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Members'),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined),
            tooltip: 'Invite by Matrix ID',
            onPressed: busy ? null : () => _showInviteDialog(context, ref),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: busy ? null : () => _showAddDialog(context, ref),
        icon: const Icon(Icons.person_add_outlined),
        label: const Text('Add person'),
      ),
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
                itemBuilder: (context, i) =>
                    _MemberTile(member: members[i], myId: myId, roomId: roomId),
              );
            },
          ),
          if (busy)
            const ColoredBox(
              color: Colors.black26,
              child: Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }

  /// Shares the group with a Matrix account without assigning them a slot — the
  /// invitee then self-claims an existing participant on their own device.
  Future<void> _showInviteDialog(BuildContext context, WidgetRef ref) async {
    final ctrl = TextEditingController();
    final messenger = ScaffoldMessenger.of(context);
    final mxid = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Invite by Matrix ID'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(
            labelText: 'Matrix ID',
            hintText: '@user:server',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final id = ctrl.text.trim();
              if (id.startsWith('@') && id.contains(':')) {
                Navigator.of(ctx).pop(id);
              }
            },
            child: const Text('Invite'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (mxid == null) return;
    await ref.read(memberAdderProvider.notifier).invite(roomId, mxid);
    final error = ref.read(memberAdderProvider).error;
    messenger.showSnackBar(SnackBar(
        content: Text(error != null ? 'Failed: $error' : 'Invited $mxid')));
  }

  Future<void> _showAddDialog(BuildContext context, WidgetRef ref) async {
    final nameCtrl = TextEditingController();
    final idCtrl = TextEditingController();
    final messenger = ScaffoldMessenger.of(context);

    final result = await showDialog<({String name, String matrixId})>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add person'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Name',
                hintText: 'e.g. Alex',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: idCtrl,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Matrix ID (optional)',
                hintText: '@user:server — leave blank for a local person',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final name = nameCtrl.text.trim();
              if (name.isEmpty) return;
              Navigator.of(ctx)
                  .pop((name: name, matrixId: idCtrl.text.trim()));
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
    nameCtrl.dispose();
    idCtrl.dispose();
    if (result == null) return;

    final notifier = ref.read(memberAdderProvider.notifier);
    final mxid = result.matrixId;
    if (mxid.isEmpty) {
      await notifier.addLocal(roomId, result.name);
    } else if (mxid.startsWith('@') && mxid.contains(':')) {
      await notifier.add(roomId, mxid, displayName: result.name);
    } else {
      messenger.showSnackBar(
          const SnackBar(content: Text('Invalid Matrix ID')));
      return;
    }
    final error = ref.read(memberAdderProvider).error;
    if (error != null) {
      messenger.showSnackBar(SnackBar(content: Text('Failed: $error')));
    }
  }
}

class _MemberTile extends ConsumerWidget {
  final MemberModel member;
  final String myId;
  final String roomId;
  const _MemberTile(
      {required this.member, required this.myId, required this.roomId});

  bool get _isSelf => member.matrixId != null && member.matrixId == myId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final title = member.displayName.isNotEmpty
        ? member.displayName
        : (member.matrixId ?? member.userId);
    return ListTile(
      leading: CircleAvatar(
        child: Icon(member.isClaimed ? Icons.person : Icons.person_outline),
      ),
      title: Text(title),
      subtitle: member.isClaimed
          ? Text(member.matrixId!)
          : const Text('Local'),
      trailing: _isSelf
          ? const Chip(label: Text('You'))
          : PopupMenuButton<String>(
              tooltip: 'Options',
              onSelected: (a) => _onAction(context, ref, a),
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'rename', child: Text('Rename')),
                if (member.isClaimed)
                  const PopupMenuItem(
                      value: 'unclaim', child: Text('Detach Matrix account'))
                else
                  const PopupMenuItem(
                      value: 'claim', child: Text('Link Matrix account')),
                const PopupMenuItem(
                    value: 'remove', child: Text('Remove from group')),
              ],
            ),
    );
  }

  Future<void> _onAction(
      BuildContext context, WidgetRef ref, String action) async {
    final messenger = ScaffoldMessenger.of(context);
    final adder = ref.read(memberAdderProvider.notifier);
    switch (action) {
      case 'rename':
        final name = await _prompt(context, 'Rename',
            label: 'Name', initial: member.displayName);
        if (name != null && name.isNotEmpty) {
          await adder.rename(roomId, member.userId, name);
        }
      case 'claim':
        final mxid = await _prompt(context, 'Link Matrix account',
            label: 'Matrix ID', hint: '@user:server');
        if (mxid != null && mxid.startsWith('@') && mxid.contains(':')) {
          await adder.claim(roomId, member.userId, mxid);
        } else if (mxid != null) {
          messenger.showSnackBar(
              const SnackBar(content: Text('Invalid Matrix ID')));
        }
      case 'unclaim':
        await adder.unclaim(roomId, member.userId);
      case 'remove':
        final ok = await _confirmRemove(context);
        if (ok) {
          await ref
              .read(memberRemoverProvider.notifier)
              .remove(roomId, member.userId);
        }
    }
  }

  Future<bool> _confirmRemove(BuildContext context) async {
    final name = member.displayName.isNotEmpty
        ? member.displayName
        : (member.matrixId ?? member.userId);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove from group'),
        content: Text('Remove $name from this group?\n\n'
            'Their expense history is kept; only their membership is cleared.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Remove')),
        ],
      ),
    );
    return confirmed ?? false;
  }

  Future<String?> _prompt(BuildContext context, String title,
      {required String label, String? hint, String initial = ''}) async {
    final ctrl = TextEditingController(text: initial);
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(labelText: label, hintText: hint),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()),
              child: const Text('OK')),
        ],
      ),
    );
    ctrl.dispose();
    return value;
  }
}
