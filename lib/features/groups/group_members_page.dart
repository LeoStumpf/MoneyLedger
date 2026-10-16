import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/l10n.dart';
import '../../models/member_model.dart';
import 'group_provider.dart';

/// Manages a group's participants (virtual users). A participant is a named
/// person who may or may not be linked to a Matrix account:
///  - **Claimed** (`matrixId != null`) — a real account; receives sync.
///  - **Local** — a Tricount-style placeholder; ledger data only.
///
/// Actions: add (name + optional Matrix ID), rename, claim/unclaim a Matrix
/// account (keeps history), and remove from the group (history kept).
///
/// Removed / left participants are listed under **Former members** (greyed —
/// they still appear in the history); a claimed one can be re-added, which
/// reactivates the same participant (G26).
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
    // G26: once removed from the group, its membership is read-only for us
    // (peers would reject our changes).
    final all = membersAsync.value ?? const <MemberModel>[];
    final iAmRemoved = all.any((m) => m.matrixId == myId) &&
        !all.any((m) => m.matrixId == myId && m.isActive);
    final l = context.l10n;

    return Scaffold(
      appBar: AppBar(
        title: Text(l.membersTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined),
            tooltip: l.inviteByMatrixId,
            onPressed: busy || iAmRemoved
                ? null
                : () => _showInviteDialog(context, ref),
          ),
        ],
      ),
      floatingActionButton: iAmRemoved
          ? null
          : FloatingActionButton.extended(
              onPressed: busy ? null : () => _showAddDialog(context, ref),
              icon: const Icon(Icons.person_add_outlined),
              label: Text(l.addPerson),
            ),
      body: Stack(
        children: [
          membersAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text(l.errorWithDetail(e.toString()))),
            data: (all) {
              final members = all.where((m) => m.isActive).toList();
              final former = all.where((m) => !m.isActive).toList();
              if (members.isEmpty && former.isEmpty) {
                return Center(child: Text(l.noMembers));
              }
              return ListView(
                padding: const EdgeInsets.only(bottom: 88), // clear the FAB
                children: [
                  for (final m in members)
                    _MemberTile(
                        member: m,
                        myId: myId,
                        roomId: roomId,
                        readOnly: iAmRemoved),
                  if (former.isNotEmpty) ...[
                    const Divider(),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                      child: Text(l.formerMembers,
                          style: Theme.of(context).textTheme.titleSmall),
                    ),
                    for (final m in former)
                      _FormerMemberTile(
                          member: m,
                          myId: myId,
                          roomId: roomId,
                          canReadd: !iAmRemoved && !busy),
                  ],
                ],
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
    final l = context.l10n;
    final mxid = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.inviteByMatrixId),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.emailAddress,
          decoration: InputDecoration(
            labelText: l.matrixIdLabel,
            hintText: '@user:server',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(l.cancel)),
          FilledButton(
            onPressed: () {
              final id = ctrl.text.trim();
              if (id.startsWith('@') && id.contains(':')) {
                Navigator.of(ctx).pop(id);
              }
            },
            child: Text(l.invite),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (mxid == null) return;
    await ref.read(memberAdderProvider.notifier).invite(roomId, mxid);
    final error = ref.read(memberAdderProvider).error;
    messenger.showSnackBar(SnackBar(
        content: Text(error != null
            ? l.failedWithError(error.toString())
            : l.invitedMember(mxid))));
  }

  Future<void> _showAddDialog(BuildContext context, WidgetRef ref) async {
    final nameCtrl = TextEditingController();
    final idCtrl = TextEditingController();
    final messenger = ScaffoldMessenger.of(context);
    final l = context.l10n;

    final result = await showDialog<({String name, String matrixId})>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.addPerson),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              autofocus: true,
              decoration: InputDecoration(
                labelText: l.nameLabel,
                hintText: l.nameHint,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: idCtrl,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                labelText: l.matrixIdOptionalLabel,
                hintText: l.matrixIdOptionalHint,
                hintMaxLines: 2,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l.cancel),
          ),
          FilledButton(
            onPressed: () {
              final name = nameCtrl.text.trim();
              if (name.isEmpty) return;
              Navigator.of(ctx)
                  .pop((name: name, matrixId: idCtrl.text.trim()));
            },
            child: Text(l.add),
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
          SnackBar(content: Text(l.invalidMatrixId)));
      return;
    }
    final error = ref.read(memberAdderProvider).error;
    if (error != null) {
      messenger.showSnackBar(
          SnackBar(content: Text(l.failedWithError(error.toString()))));
    }
  }
}

/// A removed / left participant (G26), greyed. Leaving and being removed both
/// store `status: removed` (who did it isn't recorded), hence the neutral
/// "former member". Re-add reactivates this same participant (id, name,
/// history kept) — a claimed one via the normal add path (which also
/// bootstraps their account), a local one in place.
class _FormerMemberTile extends ConsumerWidget {
  final MemberModel member;
  final String myId;
  final String roomId;
  final bool canReadd;
  const _FormerMemberTile(
      {required this.member,
      required this.myId,
      required this.roomId,
      required this.canReadd});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final title = member.displayName.isNotEmpty
        ? member.displayName
        : (member.matrixId ?? member.userId);
    final isSelf = member.matrixId != null && member.matrixId == myId;
    final mxid = member.matrixId;
    final l = context.l10n;
    return Opacity(
      opacity: 0.6,
      child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.person_off_outlined)),
        title: Text(title),
        subtitle: Text(mxid != null
            ? l.formerMemberClaimed(mxid)
            : l.formerMemberLocal),
        trailing: isSelf
            ? Chip(label: Text(l.you))
            : TextButton(
                onPressed: canReadd
                    ? () => _readd(context, ref, mxid, title)
                    : null,
                child: Text(l.readd),
              ),
      ),
    );
  }

  Future<void> _readd(
      BuildContext context, WidgetRef ref, String? mxid, String name) async {
    final messenger = ScaffoldMessenger.of(context);
    final l = context.l10n;
    final adder = ref.read(memberAdderProvider.notifier);
    // A claimed participant goes through add() (reactivates + bootstraps their
    // account); a local person is just reactivated in place.
    await (mxid != null
        ? adder.add(roomId, mxid)
        : adder.reactivate(roomId, member.userId));
    final error = ref.read(memberAdderProvider).error;
    messenger.showSnackBar(SnackBar(
        content: Text(error != null
            ? l.failedWithError(error.toString())
            : l.readdedMember(name))));
  }
}

class _MemberTile extends ConsumerWidget {
  final MemberModel member;
  final String myId;
  final String roomId;
  final bool readOnly;
  const _MemberTile(
      {required this.member,
      required this.myId,
      required this.roomId,
      this.readOnly = false});

  bool get _isSelf => member.matrixId != null && member.matrixId == myId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final title = member.displayName.isNotEmpty
        ? member.displayName
        : (member.matrixId ?? member.userId);
    final l = context.l10n;
    return ListTile(
      leading: CircleAvatar(
        child: Icon(member.isClaimed ? Icons.person : Icons.person_outline),
      ),
      title: Text(title),
      subtitle: member.isClaimed
          ? Text(member.matrixId!)
          : Text(l.localParticipant),
      trailing: _isSelf
          ? Chip(label: Text(l.you))
          : readOnly
              ? null
              : PopupMenuButton<String>(
              tooltip: l.options,
              onSelected: (a) => _onAction(context, ref, a),
              itemBuilder: (_) => [
                PopupMenuItem(value: 'rename', child: Text(l.rename)),
                if (member.isClaimed)
                  PopupMenuItem(
                      value: 'unclaim', child: Text(l.detachMatrixAccount))
                else
                  PopupMenuItem(
                      value: 'claim', child: Text(l.linkMatrixAccount)),
                PopupMenuItem(
                    value: 'remove', child: Text(l.removeFromGroup)),
              ],
            ),
    );
  }

  Future<void> _onAction(
      BuildContext context, WidgetRef ref, String action) async {
    final messenger = ScaffoldMessenger.of(context);
    final l = context.l10n;
    final adder = ref.read(memberAdderProvider.notifier);
    switch (action) {
      case 'rename':
        final name = await _prompt(context, l.rename,
            label: l.nameLabel, initial: member.displayName);
        if (name != null && name.isNotEmpty) {
          await adder.rename(roomId, member.userId, name);
        }
      case 'claim':
        final mxid = await _prompt(context, l.linkMatrixAccount,
            label: l.matrixIdLabel, hint: '@user:server');
        if (mxid != null && mxid.startsWith('@') && mxid.contains(':')) {
          await adder.claim(roomId, member.userId, mxid);
        } else if (mxid != null) {
          messenger.showSnackBar(
              SnackBar(content: Text(l.invalidMatrixId)));
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
    final l = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.removeFromGroup),
        content: Text(l.removeMemberBody(name)),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(l.cancel)),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(l.remove)),
        ],
      ),
    );
    return confirmed ?? false;
  }

  Future<String?> _prompt(BuildContext context, String title,
      {required String label, String? hint, String initial = ''}) async {
    final ctrl = TextEditingController(text: initial);
    final l = context.l10n;
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
              child: Text(l.cancel)),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()),
              child: Text(l.ok)),
        ],
      ),
    );
    ctrl.dispose();
    return value;
  }
}
