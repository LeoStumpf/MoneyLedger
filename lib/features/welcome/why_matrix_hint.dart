import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/l10n.dart';
import '../../core/session/app_session.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/action_error.dart';
import '../expenses/expenses_provider.dart' show linkDaoProvider;
import '../groups/group_overview_provider.dart';
import '../onboarding/onboarding_provider.dart' show settingsDaoProvider;
import 'why_matrix_page.dart';

/// G54 (design doc §10.3): the hint appears once a link group has at least
/// this many live expenses + payments.
const kWhyMatrixHintMinRecords = 10;

/// Pure: whether the groups page shows the one-time "Why Matrix?" hint —
/// only without an account ([noAccount], local mode: a Matrix user is in
/// the secure mode already), only while not dismissed (`false`; null =
/// still loading → hidden) and only once a link group is really in use.
bool shouldShowWhyMatrixHint({
  required bool noAccount,
  required bool? dismissed,
  required Iterable<int> linkGroupRecordCounts,
}) =>
    noAccount &&
    dismissed == false &&
    linkGroupRecordCounts.any((n) => n >= kWhyMatrixHintMinRecords);

/// The `why_matrix_hint_dismissed` setting (G54).
final whyMatrixHintDismissedProvider = StreamProvider.autoDispose<bool>(
  (ref) => ref.watch(settingsDaoProvider).watchWhyMatrixHintDismissed(),
);

/// The ids of the groups with a link channel on this ledger.
final linkGroupIdsProvider = StreamProvider.autoDispose<Set<String>>(
  (ref) => ref
      .watch(linkDaoProvider)
      .watchAllChannels()
      .map((channels) => {for (final c in channels) c.groupId}),
);

/// Whether the groups page shows the hint now ([shouldShowWhyMatrixHint]).
final whyMatrixHintProvider = Provider.autoDispose<bool>((ref) {
  // A Matrix account never reads the streams below.
  if (!ref.watch(localModeActiveProvider)) return false;
  final dismissed = ref.watch(whyMatrixHintDismissedProvider).value;
  if (dismissed != false) return false;
  final ids = ref.watch(linkGroupIdsProvider).value ?? const <String>{};
  return shouldShowWhyMatrixHint(
    noAccount: true,
    dismissed: dismissed,
    linkGroupRecordCounts: [
      for (final id in ids) ref.watch(groupOverviewProvider(id)).recordCount,
    ],
  );
});

/// Dismisses the hint for good (*Not now* and *Tell me more* alike — it is
/// shown once, never again).
final dismissWhyMatrixHintProvider =
    Provider.autoDispose<Future<void> Function()>(
      (ref) => ref.watch(settingsDaoProvider).dismissWhyMatrixHint,
    );

/// G54: the one-time, dismissible card on the groups page.
class WhyMatrixHintCard extends ConsumerWidget {
  const WhyMatrixHintCard({super.key});

  Future<void> _dismiss(BuildContext context, WidgetRef ref) async {
    final errors = ActionErrors.of(context);
    try {
      await ref.read(dismissWhyMatrixHintProvider)();
    } catch (e) {
      errors.show(e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      key: const Key('whyMatrixHint'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Insets.l,
          Insets.l,
          Insets.l,
          Insets.s,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.verified_user_outlined, color: scheme.primary),
                const SizedBox(width: Insets.m),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l.whyMatrixHintTitle,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: Insets.xs),
                      Text(
                        l.whyMatrixHintBody,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: Wrap(
                spacing: Insets.s,
                alignment: WrapAlignment.end,
                children: [
                  TextButton(
                    key: const Key('whyMatrixHintDismiss'),
                    onPressed: () => _dismiss(context, ref),
                    child: Text(l.whyMatrixNotNow),
                  ),
                  FilledButton.tonal(
                    key: const Key('whyMatrixHintMore'),
                    onPressed: () {
                      final router = GoRouter.of(context);
                      _dismiss(context, ref);
                      router.push(kWhyMatrixLocation);
                    },
                    child: Text(l.whyMatrixHintMore),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
