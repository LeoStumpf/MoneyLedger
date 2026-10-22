import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/widgets/action_error.dart';

import '../../core/database/daos/history_dao.dart';
import '../../core/l10n/l10n.dart';
import '../../core/session/app_session.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/content_width.dart';
import '../../models/member_model.dart';
import '../groups/group_provider.dart';
import 'group_history.dart';
import 'group_reset.dart';
import '../../core/widgets/large_text.dart';

/// Change batches shown at most (newest first).
const kMaxShownChangeBatches = 100;

/// Preview lines listed by name before "…and N more".
const kResetPreviewListMax = 8;

/// G48: group ⋮ → *Reset to an earlier state…* — the group's change batches
/// (from this device's version history, newest first); *Undo from here* on a
/// batch previews and then applies the reset to the state before it
/// ([GroupResetService]). Read-only (removed) groups can't be reset.
class GroupResetPage extends ConsumerWidget {
  const GroupResetPage({super.key, required this.roomId});

  final String roomId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final history = ref.watch(groupHistoryProvider(roomId));
    final floor = ref.watch(historyFloorProvider).value ?? 0;
    final me = ref.watch(currentParticipantProvider(roomId));
    final myId = ref.watch(currentUserIdProvider);
    final local = ref.watch(localModeActiveProvider);
    final members =
        ref.watch(groupMembersProvider(roomId)).value ?? const <MemberModel>[];
    final readOnly = me.hasValue && !(me.value?.isActive ?? false);

    final batches = changeBatches(
      history.value ?? const <HistoryEntry>[],
      floor: floor,
      me: myId.isEmpty ? null : myId,
      meParticipant: me.value?.userId,
    );
    final shown = batches.take(kMaxShownChangeBatches).toList();
    final anyResettable = shown.any((b) => b.resettable);

    return Scaffold(
      appBar: AppBar(title: AppBarTitle(l.groupResetTitle)),
      body: ContentWidth(
        child: ListView(
          padding: const EdgeInsets.only(top: Insets.s, bottom: Insets.xxl),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Insets.page,
                Insets.s,
                Insets.page,
                Insets.l,
              ),
              child: Text(
                readOnly
                    ? l.groupResetReadOnly
                    : local
                    ? l.groupResetLocalIntro
                    : l.groupResetIntro,
                key: const Key('groupResetIntro'),
                style: muted,
              ),
            ),
            if (history.hasError)
              Padding(
                padding: const EdgeInsets.all(Insets.page),
                child: ActionErrorView(
                  error: history.error!,
                  what: l.loadFailedTitle,
                ),
              )
            else if (!history.hasValue)
              const Padding(
                padding: EdgeInsets.all(Insets.xl),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (!anyResettable)
              Padding(
                padding: const EdgeInsets.all(Insets.page),
                child: Text(
                  l.groupResetEmpty,
                  key: const Key('groupResetEmpty'),
                  style: theme.textTheme.bodyLarge,
                ),
              ),
            if (history.hasValue && anyResettable)
              for (final b in shown)
                _BatchTile(
                  batch: b,
                  editors: [
                    ..._editorNames(b.editors, members),
                    ..._linkEditorNames(b.linkEditors, members),
                  ],
                  onUndo: readOnly || !b.resettable
                      ? null
                      : () => _undoFrom(context, ref, b),
                ),
            Padding(
              padding: const EdgeInsets.all(Insets.page),
              child: Text(l.groupResetRetention, style: muted),
            ),
          ],
        ),
      ),
    );
  }

  /// Display names of the accounts in [mxids] (their participant in this
  /// group, else the localpart).
  static List<String> _editorNames(Set<String> mxids, List<MemberModel> ms) => [
    for (final id in mxids)
      claimedBy(ms, id)?.label ??
          (id.startsWith('@') && id.contains(':')
              ? id.substring(1, id.indexOf(':'))
              : id),
  ];

  /// DEV-J: names of the participants link versions name as their writer
  /// (unknown id → left out: it's only a hint).
  static List<String> _linkEditorNames(
    Set<String> ids,
    List<MemberModel> ms,
  ) => [
    for (final id in ids)
      if (ms.where((m) => m.userId == id).firstOrNull case final m?) m.label,
  ];

  Future<void> _undoFrom(
    BuildContext context,
    WidgetRef ref,
    ChangeBatch batch,
  ) async {
    final l = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final errors = ActionErrors.of(context);
    final nav = Navigator.of(context);
    // Captured before the first await (G19).
    final service = ref.read(groupResetServiceProvider);
    final names = ref.read(participantNamesProvider(roomId));
    final local = ref.read(localModeActiveProvider);
    try {
      final plan = await service.plan(roomId, batch.firstId);
      if (!context.mounted) return;
      // Not `context` inside the builder: it rebuilds during the closing
      // animation, when this page may already be gone.
      final time = context.dateTime(batch.startAt);
      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => ResetPreviewDialog(
          plan: plan,
          time: time,
          names: names,
          shared: !local,
        ),
      );
      if (ok != true) return;
      final written = await service.apply(plan);
      messenger.showSnackBar(SnackBar(content: Text(l.resetDone(written))));
      if (nav.mounted) nav.maybePop();
    } catch (e) {
      errors.show(e);
    }
  }
}

class _BatchTile extends StatelessWidget {
  const _BatchTile({
    required this.batch,
    required this.editors,
    required this.onUndo,
  });

  final ChangeBatch batch;
  final List<String> editors;
  final VoidCallback? onUndo;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final parts = [
      if (batch.added > 0) l.changeAdded(batch.added),
      if (batch.changed > 0) l.changeEdited(batch.changed),
      if (batch.deleted > 0) l.changeDeleted(batch.deleted),
      if (batch.otherChanges > 0) l.changeOther(batch.otherChanges),
    ];
    final who = [
      if (batch.byMe) l.changeByYou,
      if (editors.isNotEmpty) l.changeBy(editors.join(', ')),
    ];
    return ListTile(
      key: Key('changeBatch-${batch.firstId}'),
      leading: Icon(
        batch.deleted > 0 ? Icons.delete_sweep_outlined : Icons.history,
        color: batch.deleted > 0
            ? theme.colorScheme.secondary
            : theme.colorScheme.onSurfaceVariant,
      ),
      title: Text(context.dateTime(batch.startAt)),
      subtitle: Text(
        [
          parts.join(' · '),
          if (who.isNotEmpty) who.join(' · '),
          if (!batch.resettable) l.changeEarliest,
        ].where((s) => s.isNotEmpty).join('\n'),
      ),
      isThreeLine: who.isNotEmpty || !batch.resettable,
      trailing: onUndo == null
          ? null
          : TextButton(
              key: Key('undoFrom-${batch.firstId}'),
              onPressed: onUndo,
              child: Text(l.changeUndoFromHere),
            ),
    );
  }
}

/// The reset preview: counts, the first entries by name, confirm.
class ResetPreviewDialog extends StatelessWidget {
  const ResetPreviewDialog({
    super.key,
    required this.plan,
    required this.time,
    required this.names,
    required this.shared,
  });

  final GroupResetPlan plan;

  /// The formatted point in time the group goes back to.
  final String time;

  /// participant id → display name.
  final Map<String, String> names;

  /// Peers receive the reset (false in local mode).
  final bool shared;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    String label(ResetChange c) {
      if (c.expense case final e?) {
        return '${e.description} · ${context.money(e.amountCents, e.currency)}';
      }
      final s = c.settlement!;
      return '${l.settlementTitle(names[s.fromUser] ?? s.fromUser, names[s.toUser] ?? s.toUser)}'
          ' · ${context.money(s.amountCents, s.currency)}';
    }

    String effect(ResetEffect e) => switch (e) {
      ResetEffect.restored => l.resetEffectRestored,
      ResetEffect.reverted => l.resetEffectReverted,
      ResetEffect.removed => l.resetEffectRemoved,
    };

    final listed = plan.changes.take(kResetPreviewListMax).toList();
    return AlertDialog(
      key: const Key('resetPreviewDialog'),
      title: Text(l.resetPreviewTitle(time)),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (plan.isEmpty)
              Text(l.resetPreviewNothing, key: const Key('resetNothing'))
            else ...[
              if (plan.restored > 0)
                Text(l.resetPreviewRestored(plan.restored)),
              if (plan.reverted > 0)
                Text(l.resetPreviewReverted(plan.reverted)),
              if (plan.removed > 0) Text(l.resetPreviewRemoved(plan.removed)),
              if (plan.meta != null) Text(l.resetPreviewMeta),
              const SizedBox(height: Insets.m),
              for (final c in listed)
                Padding(
                  padding: const EdgeInsets.only(bottom: Insets.xs),
                  child: Text(
                    '${label(c)} — ${effect(c.effect)}',
                    style: theme.textTheme.bodySmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              if (plan.changes.length > listed.length)
                Text(
                  l.resetPreviewMore(plan.changes.length - listed.length),
                  style: theme.textTheme.bodySmall,
                ),
              if (shared) ...[
                const SizedBox(height: Insets.m),
                Text(l.resetPreviewShared),
              ],
            ],
            if (plan.skipped > 0) ...[
              const SizedBox(height: Insets.m),
              Text(
                l.resetPreviewSkipped(plan.skipped),
                style: theme.textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l.cancel),
        ),
        if (!plan.isEmpty)
          FilledButton(
            key: const Key('resetConfirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l.resetConfirm),
          ),
      ],
    );
  }
}
