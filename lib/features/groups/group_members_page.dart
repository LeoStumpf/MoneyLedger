import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/widgets/large_text.dart';
import '../../core/widgets/action_error.dart';

import '../../core/session/app_session.dart';
import '../../core/l10n/l10n.dart';
import '../../core/widgets/text_prompt_dialog.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/content_width.dart';
import '../../core/widgets/person_avatar.dart';
import 'add_person_dialog.dart';
import 'group_exit_dialog.dart' show removalBalanceWarning;
import '../balance/balance_calculator.dart';
import '../balance/settle_up.dart';
import '../expenses/expenses_provider.dart';
import '../devices/device_provider.dart';
import '../devices/devices_page.dart';
import '../../core/matrix/device_gateway.dart';
import '../../models/member_model.dart';
import 'group_provider.dart';
import '../link/link_invite.dart';

/// Manages a group's participants (virtual users). A participant is a named
/// person who may or may not be linked to a Matrix account:
///  - **Claimed** (`matrixId != null`) — a real account; receives sync.
///  - **Local** — a Tricount-style placeholder; ledger data only.
///
/// Actions: add (name + optional Matrix ID), rename, claim/unclaim a Matrix
/// account (keeps history), and remove from the group (history kept).
///
/// Removed / left participants are listed under **No longer in the group**
/// (G64 wording; greyed — they still appear in the history); a claimed one
/// can be re-added, which reactivates the same participant (G26).
class GroupMembersPage extends ConsumerWidget {
  final String roomId;
  const GroupMembersPage({super.key, required this.roomId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final membersAsync = ref.watch(groupMembersProvider(roomId));
    final myId = ref.watch(currentUserIdProvider);
    final adderState = ref.watch(memberAdderProvider);
    final removerState = ref.watch(memberRemoverProvider);
    // G64 (U10): *Settle up first* in the removal dialog records a payment
    // — keep the adder alive for its result (see recordPaymentFlow).
    ref.watch(expenseAdderProvider);
    final busy = adderState.isLoading || removerState.isLoading;
    // G26: once removed from the group, its membership is read-only for us
    // (peers would reject our changes).
    final all = membersAsync.value ?? const <MemberModel>[];
    final iAmRemoved =
        all.any((m) => m.matrixId == myId) &&
        !all.any((m) => m.matrixId == myId && m.isActive);
    final l = context.l10n;
    // G52 step 6: a link group (a channel on this device) or a local-mode
    // group that can get one → *Invite with a link*.
    final linkState =
        ref.watch(linkInviteStateProvider(roomId)).value ??
        LinkInviteState.unavailable;
    final linkGroup = linkState == LinkInviteState.open;
    // G40: local mode — people are names only; no invites, devices or
    // Matrix accounts. G52: the same in a link group (its participants
    // carry no Matrix ID; "me" is this device's link participant).
    final localMode = ref.watch(localModeActiveProvider);
    final local = localMode || linkGroup;
    final me = ref.watch(currentParticipantProvider(roomId)).value;
    final selfId = me?.userId ?? claimedBy(all, myId)?.userId;

    return Scaffold(
      appBar: AppBar(
        title: AppBarTitle(l.membersTitle),
        actions: [
          if (linkState != LinkInviteState.unavailable)
            IconButton(
              key: const Key('membersInviteLink'),
              icon: const Icon(Icons.link),
              tooltip: l.inviteByLink,
              onPressed: busy || iAmRemoved
                  ? null
                  : () => inviteByLinkFlow(context, ref, roomId),
            ),
          if (!local)
            IconButton(
              icon: const Icon(Icons.share_outlined),
              tooltip: l.inviteByMatrixId,
              onPressed: busy || iAmRemoved
                  ? null
                  : () => _showInviteDialog(context, ref, all),
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
            error: (e, _) => Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: ActionErrorView(error: e, what: l.loadFailedTitle),
              ),
            ),
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
                padding: EdgeInsets.fromLTRB(
                  Insets.page,
                  Insets.s,
                  Insets.page,
                  Insets.fabClearance(context),
                ),
                children: [
                  if (linkGroup)
                    ContentWidth(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: Insets.s),
                        child: Card(
                          key: const Key('linkMembersHint'),
                          child: ListTile(
                            leading: const Icon(Icons.link),
                            title: Text(l.linkMembersHint),
                          ),
                        ),
                      ),
                    )
                  else if (local)
                    ContentWidth(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: Insets.s),
                        child: Card(
                          key: const Key('localMembersHint'),
                          child: ListTile(
                            leading: const Icon(Icons.phone_android_outlined),
                            title: Text(l.localModeMembersHint),
                          ),
                        ),
                      ),
                    ),
                  if (members.isNotEmpty)
                    ContentWidth(
                      child: section([
                        for (final m in members)
                          _MemberTile(
                            member: m,
                            all: all,
                            myId: myId,
                            selfId: selfId,
                            roomId: roomId,
                            readOnly: iAmRemoved,
                            local: local,
                            linkGroup: linkGroup,
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
                                all: all,
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

  /// Invites a Matrix account into the group (G18 review): the inviter picks
  /// which participant the account is — an unclaimed local person (history
  /// kept) or a new participant — and the account receives the group as that
  /// active participant. (A slot-less invite would leave the invitee unable
  /// to join: peers refuse membership changes a non-member makes itself.)
  Future<void> _showInviteDialog(
    BuildContext context,
    WidgetRef ref,
    List<MemberModel> members,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final errors = ActionErrors.of(context);
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
    if (mxid == null || !context.mounted) return;
    final unclaimed = members
        .where((m) => m.isActive && m.matrixId == null)
        .toList();
    String? participantId;
    if (unclaimed.isNotEmpty) {
      // `null` from the dialog = dismissed; '' = a new participant.
      final choice = await showDialog<String>(
        context: context,
        builder: (ctx) => SimpleDialog(
          key: const Key('inviteWhoIs'),
          title: Text(l.inviteWhoIs(mxid)),
          children: [
            for (final m in unclaimed)
              SimpleDialogOption(
                onPressed: () => Navigator.of(ctx).pop(m.userId),
                child: Text(m.label),
              ),
            SimpleDialogOption(
              key: const Key('inviteAsNew'),
              onPressed: () => Navigator.of(ctx).pop(''),
              child: Text(l.inviteAsNewParticipant),
            ),
          ],
        ),
      );
      if (choice == null) return;
      participantId = choice.isEmpty ? null : choice;
    }
    await ref
        .read(memberAdderProvider.notifier)
        .invite(roomId, mxid, participantId: participantId);
    final error = ref.read(memberAdderProvider).error;
    if (error != null) {
      errors.show(error);
      return;
    }
    messenger.showSnackBar(SnackBar(content: Text(l.invitedMember(mxid))));
  }
}

/// A removed / left participant (G26), greyed. Leaving and being removed both
/// store `status: removed` (who did it isn't recorded), hence the neutral
/// "former member". Re-add reactivates this same participant (id, name,
/// history kept) — a claimed one via the normal add path (which also
/// bootstraps their account), a local one in place.
class _FormerMemberTile extends ConsumerWidget {
  final MemberModel member;
  final List<MemberModel> all;
  final String myId;
  final String roomId;
  final bool canReadd;
  const _FormerMemberTile({
    required this.member,
    required this.all,
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
    final account = memberAccountLine(member, all);
    return Opacity(
      opacity: 0.6,
      child: ListTile(
        leading: PersonAvatar(id: member.userId, name: title, dimmed: true),
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        onLongPress: mxid == null
            ? null
            : () => showMatrixIdDialog(context, mxid),
        subtitle: Text(
          account != null
              ? l.formerMemberClaimed(account)
              : l.formerMemberLocal,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: isSelf
            ? Chip(label: Text(l.you))
            // DEV-I: at a large font size the text button took the whole
            // row and the name disappeared — an icon button then.
            : isLargeText(context)
            ? IconButton(
                key: Key('readd-${member.userId}'),
                tooltip: l.readd,
                icon: const Icon(Icons.person_add_alt_1_outlined),
                onPressed: canReadd
                    ? () => _readd(context, ref, mxid, title)
                    : null,
              )
            : TextButton(
                key: Key('readd-${member.userId}'),
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
    final errors = ActionErrors.of(context);
    final l = context.l10n;
    final adder = ref.read(memberAdderProvider.notifier);
    // A claimed participant goes through add() (reactivates + bootstraps their
    // account); a local person is just reactivated in place.
    await (mxid != null
        ? adder.add(roomId, mxid)
        : adder.reactivate(roomId, member.userId));
    final error = ref.read(memberAdderProvider).error;
    if (error != null) {
      errors.show(error);
      return;
    }
    messenger.showSnackBar(SnackBar(content: Text(l.readdedMember(name))));
  }
}

/// G11: a subtle warning under a member whose devices aren't all verified
/// (red "not reachable" when none is verified); tap → their device list with
/// Verify actions. Nothing while loading / on error (offline) — it's a hint,
/// not a gate. G46: only while "Only sync with verified devices" is on — then
/// unverified devices really get nothing; otherwise it is technical noise
/// (the device list stays one tap away: ⋮ → Devices).
class _PeerDeviceWarning extends ConsumerWidget {
  const _PeerDeviceWarning({required this.matrixId, required this.name});
  final String matrixId;
  final String name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final verifiedOnly = ref.watch(verifiedOnlySyncProvider).value ?? false;
    if (!verifiedOnly) return const SizedBox.shrink();
    final devices = ref.watch(memberDevicesProvider(matrixId)).value;
    if (devices == null) return const SizedBox.shrink();
    final trust = peerDeviceTrust(devices);
    if (!trust.needsAttention) return const SizedBox.shrink();
    final l = context.l10n;
    final theme = Theme.of(context);
    final blocked = trust.noneVerified;
    final color = blocked
        ? theme.colorScheme.error
        : theme.colorScheme.onSurfaceVariant;
    return InkWell(
      key: Key('peerDeviceWarning:$matrixId'),
      onTap: () =>
          showMemberDevicesSheet(context, matrixId: matrixId, name: name),
      child: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Row(
          children: [
            Icon(Icons.gpp_maybe_outlined, size: 14, color: color),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                blocked
                    ? l.memberNotReachableUnverified
                    : l.memberUnverifiedDevices(trust.unverified),
                style: theme.textTheme.bodySmall?.copyWith(color: color),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MemberTile extends ConsumerWidget {
  final MemberModel member;

  /// Every participant of the group (active and former) — decides whether
  /// the account line needs the full MXID (G56).
  final List<MemberModel> all;
  final String myId;

  /// This device's participant ("me"; G52: in a link group it carries no
  /// claim, so [myId] alone doesn't find it).
  final String? selfId;
  final String roomId;
  final bool readOnly;
  const _MemberTile({
    required this.member,
    required this.all,
    required this.myId,
    this.selfId,
    required this.roomId,
    this.readOnly = false,
    this.local = false,
    this.linkGroup = false,
  });

  /// G40 local mode: no Matrix accounts / devices.
  final bool local;

  /// G52: a link group — removing someone doesn't take the link away
  /// (step 12: the removal dialog points to *Reset invite link*).
  final bool linkGroup;

  bool get _isSelf =>
      (selfId != null && member.userId == selfId) ||
      (member.matrixId != null && member.matrixId == myId);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final title = member.label;
    final l = context.l10n;
    final mxid = member.matrixId;
    final theme = Theme.of(context);
    return ListTile(
      leading: PersonAvatar(id: member.userId, name: title),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      // G56: the full Matrix ID behind a long-press (and ⋮ → Matrix ID).
      onLongPress: local || mxid == null
          ? null
          : () => showMatrixIdDialog(context, mxid),
      subtitle: local
          ? Text(_isSelf ? l.localModeYouSubtitle : l.localParticipant)
          : mxid != null
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // G56: `@localpart` (muted); the full MXID only when two
                // participants would otherwise look alike.
                Text(
                  memberAccountLine(member, all)!,
                  key: Key('memberAccount:${member.userId}'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (!_isSelf) _PeerDeviceWarning(matrixId: mxid, name: title),
              ],
            )
          : Text(l.localParticipant),
      trailing: _isSelf
          ? Chip(label: Text(l.you))
          : readOnly
          ? null
          : PopupMenuButton<String>(
              tooltip: l.options,
              onSelected: (a) => _onAction(context, ref, a),
              itemBuilder: (_) => [
                if (member.isClaimed && !local) ...[
                  PopupMenuItem(
                    value: 'matrixId',
                    child: Text(l.matrixIdLabel),
                  ),
                  PopupMenuItem(value: 'devices', child: Text(l.devicesTitle)),
                ],
                PopupMenuItem(value: 'rename', child: Text(l.rename)),
                if (local)
                  ...[]
                else if (member.isClaimed)
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
    final errors = ActionErrors.of(context);
    final l = context.l10n;
    final adder = ref.read(memberAdderProvider.notifier);
    // The write that ran, if any, and how to read its outcome afterwards.
    Object? Function()? errorOf;
    switch (action) {
      case 'matrixId':
        await showMatrixIdDialog(context, member.matrixId!);
      case 'devices':
        await showMemberDevicesSheet(
          context,
          matrixId: member.matrixId!,
          name: member.label,
        );
      case 'rename':
        // G75 (G64 leftover): the same duplicate-name hint as *Add
        // person* — another person (also a former one) already has it.
        final others = [
          for (final m in all)
            if (m.userId != member.userId) m.label,
        ];
        final name = await _prompt(
          context,
          l.rename,
          label: l.nameLabel,
          initial: member.displayName,
          helperFor: (v) {
            final dup = duplicateNameOf(v, others);
            return dup == null ? null : l.duplicatePersonRenameHint(dup);
          },
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
        final balance = await _openBalance(ref, l);
        if (!context.mounted) return;
        final choice = await _confirmRemove(context, balance);
        if (!context.mounted) return;
        if (choice == _RemoveChoice.settleFirst && balance != null) {
          await recordPaymentFlow(
            context,
            ref,
            roomId,
            // Only the default payer — the debt prefills both sides.
            myId: selfId ?? claimedBy(all, myId)?.userId ?? '',
            debt: balance.debt,
          );
        } else if (choice == _RemoveChoice.remove) {
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
      errors.show(error);
    }
  }

  /// G64 (U10): this person's open balance ("Ben still gets €23.50 back")
  /// and a suggested payment involving them (for *Settle up first*) — null
  /// when settled, or when the ledger can't be read (the dialog then just
  /// doesn't warn; removing never changes a balance).
  Future<({String warning, DebtEntry? debt})?> _openBalance(
    WidgetRef ref,
    AppLocalizations l,
  ) async {
    final expensesSub = ref.listenManual(
      expensesForRoomProvider(roomId),
      (_, _) {},
    );
    final settlementsSub = ref.listenManual(
      settlementsForRoomProvider(roomId),
      (_, _) {},
    );
    try {
      const wait = Duration(seconds: 3);
      final expenses = await ref
          .read(expensesForRoomProvider(roomId).future)
          .timeout(wait);
      final settlements = await ref
          .read(settlementsForRoomProvider(roomId).future)
          .timeout(wait);
      final warning = removalBalanceWarning(
        member.userId,
        member.label,
        expenses,
        settlements,
        l,
      );
      if (warning == null) return null;
      final debt = calculateDebts(expenses, settlements)
          .where((d) => d.from == member.userId || d.to == member.userId)
          .firstOrNull;
      return (warning: warning, debt: debt);
    } catch (e) {
      debugPrint('[members] open balance unavailable: $e');
      return null;
    } finally {
      expensesSub.close();
      settlementsSub.close();
    }
  }

  Future<_RemoveChoice> _confirmRemove(
    BuildContext context,
    ({String warning, DebtEntry? debt})? balance,
  ) async {
    final name = member.label;
    final l = context.l10n;
    final theme = Theme.of(context);
    final choice = await showDialog<_RemoveChoice>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.removeFromGroup),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l.removeMemberBody(name)),
              if (linkGroup) ...[
                const SizedBox(height: Insets.m),
                Text(
                  l.removeMemberLinkNote(name),
                  key: const Key('removeLinkNote'),
                ),
              ],
              if (balance != null) ...[
                const SizedBox(height: Insets.m),
                Text(
                  balance.warning,
                  key: const Key('removeBalanceWarning'),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.secondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: Insets.xs),
                Text(l.removeMemberBalanceNote),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(_RemoveChoice.cancel),
            child: Text(l.cancel),
          ),
          if (balance?.debt != null)
            TextButton(
              key: const Key('removeSettleFirst'),
              onPressed: () => Navigator.of(ctx).pop(_RemoveChoice.settleFirst),
              child: Text(l.settleUpFirst),
            ),
          FilledButton(
            key: const Key('removeConfirm'),
            onPressed: () => Navigator.of(ctx).pop(_RemoveChoice.remove),
            child: Text(l.remove),
          ),
        ],
      ),
    );
    return choice ?? _RemoveChoice.cancel;
  }

  Future<String?> _prompt(
    BuildContext context,
    String title, {
    required String label,
    String? hint,
    String initial = '',
    String? Function(String value)? helperFor,
  }) {
    final l = context.l10n;
    return showTextPrompt(
      context,
      title: title,
      label: label,
      hint: hint,
      initial: initial,
      helperFor: helperFor,
      cancelLabel: l.cancel,
      confirmLabel: l.ok,
    );
  }
}

/// What the "remove from group" dialog decided (G64: *Settle up first*
/// opens the payment dialog instead and removes nobody).
enum _RemoveChoice { cancel, settleFirst, remove }

/// G56: a member's full Matrix ID (selectable, with *Copy*) — the members
/// list itself shows only the short form ([memberAccountLine]).
Future<void> showMatrixIdDialog(BuildContext context, String mxid) {
  final l = context.l10n;
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l.matrixIdLabel),
      content: SelectableText(mxid, key: const Key('matrixIdDialogValue')),
      actions: [
        TextButton(
          key: const Key('matrixIdCopy'),
          onPressed: () {
            unawaited(Clipboard.setData(ClipboardData(text: mxid)));
            Navigator.of(ctx).pop();
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(l.copiedToClipboard)));
          },
          child: Text(l.copy),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: Text(l.done),
        ),
      ],
    ),
  );
}
