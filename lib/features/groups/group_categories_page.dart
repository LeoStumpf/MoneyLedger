import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/widgets/action_error.dart';

import '../../core/l10n/l10n.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/content_width.dart';
import '../../models/expense_category.dart';
import '../expenses/expense_category_ui.dart';
import 'group_provider.dart';

/// G47: the group's own expense categories (group ⋮ → *Categories*): add,
/// rename / change the icon, hide / show again. They live in the signed
/// group meta, so every change is a new meta version relayed to the
/// members ([GroupEditor]). Any active member may edit them (same rule as
/// the group name); others see the list read-only. There is no delete —
/// hiding keeps older expenses labelled.
class GroupCategoriesPage extends ConsumerWidget {
  final String roomId;
  const GroupCategoriesPage({super.key, required this.roomId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final theme = Theme.of(context);
    // Keep the (auto-dispose) editor alive while a write is in flight.
    final editorState = ref.watch(groupEditorProvider);
    final group = (ref.watch(ledgerGroupsProvider).value ?? const [])
        .where((g) => g.roomId == roomId)
        .firstOrNull;
    final me = ref.watch(currentParticipantProvider(roomId)).value;
    final canEdit = (me?.isActive ?? false) && !editorState.isLoading;
    final categories = group?.categories ?? const <CustomCategory>[];
    final full = categories.length >= kMaxCustomCategories;

    return Scaffold(
      appBar: AppBar(title: Text(l.manageCategories)),
      floatingActionButton: canEdit && !full
          ? FloatingActionButton.extended(
              key: const Key('addCategory'),
              onPressed: () => _add(context, ref, categories),
              icon: const Icon(Icons.add),
              label: Text(l.newCategoryTitle),
            )
          : null,
      body: ContentWidth(
        child: ListView(
          padding: EdgeInsets.only(
            top: Insets.s,
            bottom: Insets.fabClearance(context),
          ),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Insets.page,
                Insets.s,
                Insets.page,
                Insets.l,
              ),
              child: Text(
                l.customCategoriesHint,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            if (full)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Insets.page,
                  0,
                  Insets.page,
                  Insets.l,
                ),
                child: Text(l.categoryLimitReached(kMaxCustomCategories)),
              ),
            if (categories.isEmpty)
              Padding(
                padding: const EdgeInsets.all(Insets.page),
                child: Text(
                  l.noCustomCategories,
                  key: const Key('noCustomCategories'),
                  style: theme.textTheme.bodyLarge,
                ),
              ),
            for (final c in categories)
              ListTile(
                key: Key('customCategory-${c.id}'),
                leading: Opacity(
                  opacity: c.hidden ? 0.45 : 1,
                  child: CategoryIconTile(
                    category: ResolvedCategory.custom(c),
                    size: 36,
                  ),
                ),
                title: Text(c.name),
                subtitle: c.hidden ? Text(l.categoryHidden) : null,
                onTap: canEdit
                    ? () => _edit(context, ref, c, categories)
                    : null,
                trailing: IconButton(
                  key: Key('toggleHidden-${c.id}'),
                  tooltip: c.hidden ? l.showCategory : l.hideCategory,
                  icon: Icon(
                    c.hidden
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                  onPressed: canEdit
                      ? () => _save(context, ref, c.copyWith(hidden: !c.hidden))
                      : null,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _add(
    BuildContext context,
    WidgetRef ref,
    List<CustomCategory> existing,
  ) async {
    final errors = ActionErrors.of(context);
    final input = await showCategoryDialog(context, existing: existing);
    if (input == null) return;
    await ref
        .read(groupEditorProvider.notifier)
        .addCategory(roomId, name: input.name, icon: input.icon);
    _reportError(ref, errors);
  }

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    CustomCategory c,
    List<CustomCategory> existing,
  ) async {
    final input = await showCategoryDialog(
      context,
      initial: c,
      existing: existing,
    );
    if (input == null || !context.mounted) return;
    await _save(context, ref, c.copyWith(name: input.name, icon: input.icon));
  }

  Future<void> _save(
    BuildContext context,
    WidgetRef ref,
    CustomCategory updated,
  ) async {
    final errors = ActionErrors.of(context);
    await ref
        .read(groupEditorProvider.notifier)
        .updateCategory(roomId, updated);
    _reportError(ref, errors);
  }

  void _reportError(WidgetRef ref, ActionErrors errors) {
    final error = ref.read(groupEditorProvider).error;
    if (error != null) errors.show(error);
  }
}
