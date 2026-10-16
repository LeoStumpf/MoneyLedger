import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/l10n.dart';
import '../../core/widgets/text_prompt_dialog.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/content_width.dart';
import '../../core/widgets/person_avatar.dart';
import 'add_person_dialog.dart';
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
    final iAmRemoved =
        all.any((m) => m.matrixId == myId) &&
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
              onPressed: busy
                  ? null
                  : () => showAddPersonDialog(context, ref, roomId),
              icon: const Icon(Icons.person_add_outlined),
              label: Text(l.addPerson),
            ),
      body: Stack(
        children: [
          membersAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) =>
                Center(child: Text(l.errorWithDetail(e.toString()))),
            data: (all) {
              final members = all.where((m) => m.isActive).toList();
              final former = all.where((m) => !m.isActive).toList();
              if (members.isEmpty && former.isEmpty) {
                return Center(child: Text(l.noMembers));
              }
              final headerStyle = Theme.of(context).textTheme.labelLarge
                  ?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  );
              Widget section(List<Widget> tiles) => Card(
                child: Column(
                  children: [
                    for (var i = 0; i < tiles.length; i++) ...[
                      if (i > 0) const Divider(indent: 72),
                      tiles[i],
                    ],
                  ],
                ),
              );
              return ListView(
                padding: const EdgeInsets.fromLTRB(
                  Insets.page,
                  Insets.s,
                  Insets.page,
                  96,
                ), // clear the FAB
                children: [
                  if (members.isNotEmpty)
                    ContentWidth(
                      child: section([
                        for (final m in members)
                          _MemberTile(
                            member: m,
                            myId: myId,
                            roomId: roomId,
                            readOnly: iAmRemoved,
                          ),
                      ]),
                    ),
                  if (former.isNotEmpty)
                    ContentWidth(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(
                              Insets.xs,
                              Insets.xl,
                              Insets.xs,
                              Insets.s,
                            ),
                            child: Text(l.formerMembers, style: headerStyle),
                          ),
                          section([
                            for (final m in former)
                              _FormerMemberTile(
                                member: m,
                                myId: myId,
                                roomId: roomId,
                                canReadd: !iAmRemoved && !busy,
                              ),
                          ]),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
          if (busy)
            ColoredBox(
              color: Theme.of(context).colorScheme.scrim.withValues(alpha: 0.2),
              child: const Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }

  /// Shares the group with a Matrix account without assigning them a slot — the
  /// invitee then self-claims an existing participant on their own device.
  Future<void> _showInviteDialog(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final l = context.l10n;
    final mxid = await showTextPrompt(
      context,
      title: l.inviteByMatrixId,
      label: l.matrixIdLabel,
      hint: '@user:server',
      keyboardType: TextInputType.emailAddress,
      cancelLabel: l.cancel,
      confirmLabel: l.invite,
      accept: (id) => id.startsWith('@') && id.contains(':'),
    );
    if (mxid == null) return;
    await ref.read(memberAdderProvider.notifier).invite(roomId, mxid);
    final error = ref.read(memberAdderProvider).error;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          error != null
              ? l.failedWithError(error.toString())
              : l.invitedMember(mxid),
        ),
      ),
    );
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
  const _FormerMemberTile({
    required this.member,
    required this.myId,
    required this.roomId,
    required this.canReadd,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final title = member.label;
    final isSelf = member.matrixId != null && member.matrixId == myId;
    final mxid = member.matrixId;
    final l = context.l10n;
    return Opacity(
      opacity: 0.6,
      child: ListTile(
        leading: PersonAvatar(id: member.userId, name: title, dimmed: true),
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          mxid != null ? l.formerMemberClaimed(mxid) : l.formerMemberLocal,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
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
    BuildContext context,
    WidgetRef ref,
    String? mxid,
    String name,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final l = context.l10n;
    final adder = ref.read(memberAdderProvider.notifier);
    // A claimed participant goes through add() (reactivates + bootstraps their
    // account); a local person is just reactivated in place.
    await (mxid != null
        ? adder.add(roomId, mxid)
        : adder.reactivate(roomId, member.userId));
    final error = ref.read(memberAdderProvider).error;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          error != null
              ? l.failedWithError(error.toString())
              : l.readdedMember(name),
        ),
      ),
    );
  }
}

class _MemberTile extends ConsumerWidget {
  final MemberModel member;
  final String myId;
  final String roomId;
  final bool readOnly;
  const _MemberTile({
    required this.member,
    required this.myId,
    required this.roomId,
    this.readOnly = false,
  });

  bool get _isSelf => member.matrixId != null && member.matrixId == myId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final title = member.label;
    final l = context.l10n;
    return ListTile(
      leading: PersonAvatar(id: member.userId, name: title),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: member.isClaimed
          ? Text(member.matrixId!, maxLines: 1, overflow: TextOverflow.ellipsis)
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
                    value: 'unclaim',
                    child: Text(l.detachMatrixAccount),
                  )
                else
                  PopupMenuItem(
                    value: 'claim',
                    child: Text(l.linkMatrixAccount),
                  ),
                PopupMenuItem(value: 'remove', child: Text(l.removeFromGroup)),
              ],
            ),
    );
  }

  Future<void> _onAction(
    BuildContext context,
    WidgetRef ref,
    String action,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final l = context.l10n;
    final adder = ref.read(memberAdderProvider.notifier);
    // The write that ran, if any, and how to read its outcome afterwards.
    Object? Function()? errorOf;
    switch (action) {
      case 'rename':
        final name = await _prompt(
          context,
          l.rename,
          label: l.nameLabel,
          initial: member.displayName,
        );
        if (name != null && name.isNotEmpty) {
          await adder.rename(roomId, member.userId, name);
          errorOf = () => ref.read(memberAdderProvider).error;
        }
      case 'claim':
        final mxid = await _prompt(
          context,
          l.linkMatrixAccount,
          label: l.matrixIdLabel,
          hint: '@user:server',
        );
        if (mxid != null && mxid.startsWith('@') && mxid.contains(':')) {
          await adder.claim(roomId, member.userId, mxid);
          errorOf = () => ref.read(memberAdderProvider).error;
        } else if (mxid != null) {
          messenger.showSnackBar(SnackBar(content: Text(l.invalidMatrixId)));
        }
      case 'unclaim':
        await adder.unclaim(roomId, member.userId);
        errorOf = () => ref.read(memberAdderProvider).error;
      case 'remove':
        final ok = await _confirmRemove(context);
        if (ok) {
          await ref
              .read(memberRemoverProvider.notifier)
              .remove(roomId, member.userId);
          errorOf = () => ref.read(memberRemoverProvider).error;
        }
    }
    // A failed write must not vanish silently (G15).
    if (!context.mounted) return;
    final error = errorOf?.call();
    if (error != null) {
      messenger.showSnackBar(
        SnackBar(content: Text(l.failedWithError(error.toString()))),
      );
    }
  }

  Future<bool> _confirmRemove(BuildContext context) async {
    final name = member.label;
    final l = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.removeFromGroup),
        content: Text(l.removeMemberBody(name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l.remove),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  Future<String?> _prompt(
    BuildContext context,
    String title, {
    required String label,
    String? hint,
    String initial = '',
  }) {
    final l = context.l10n;
    return showTextPrompt(
      context,
      title: title,
      label: label,
      hint: hint,
      initial: initial,
      cancelLabel: l.cancel,
      confirmLabel: l.ok,
    );
  }
}
