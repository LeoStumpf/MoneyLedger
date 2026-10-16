/// G16: how expense categories look — icon, colours (from the theme's
/// avatar palette, so light / dark and contrast come for free) and the
/// localized label — plus the selector used by the add / edit form.
///
/// G47: custom (per-group) categories — their icon set, the selector's
/// "New category…" entry and the create / edit dialog.
library;

import 'package:flutter/material.dart';

import '../../core/l10n/l10n.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/person_avatar.dart' show avatarIndexFor;
import '../../models/expense_category.dart';

extension ExpenseCategoryUi on ExpenseCategory {
  IconData get icon => switch (this) {
    ExpenseCategory.food => Icons.restaurant_outlined,
    ExpenseCategory.groceries => Icons.shopping_cart_outlined,
    ExpenseCategory.transport => Icons.directions_car_outlined,
    ExpenseCategory.accommodation => Icons.hotel_outlined,
    ExpenseCategory.entertainment => Icons.local_activity_outlined,
    ExpenseCategory.shopping => Icons.shopping_bag_outlined,
    ExpenseCategory.home => Icons.home_outlined,
    ExpenseCategory.health => Icons.medical_services_outlined,
    ExpenseCategory.travel => Icons.flight_outlined,
    ExpenseCategory.other => Icons.category_outlined,
  };

  /// Index into [LedgerColors.avatarBackgrounds] / `avatarForegrounds`
  /// (8 hues; neighbours in the picker get different hues).
  int get _paletteIndex => switch (this) {
    ExpenseCategory.food => 6, // coral
    ExpenseCategory.groceries => 5, // green
    ExpenseCategory.transport => 1, // blue
    ExpenseCategory.accommodation => 4, // violet
    ExpenseCategory.entertainment => 2, // pink
    ExpenseCategory.shopping => 3, // amber
    ExpenseCategory.home => 0, // teal
    ExpenseCategory.health => 7, // cyan
    ExpenseCategory.travel => 1, // blue
    ExpenseCategory.other => 3, // amber
  };

  String label(AppLocalizations l) => switch (this) {
    ExpenseCategory.food => l.categoryFood,
    ExpenseCategory.groceries => l.categoryGroceries,
    ExpenseCategory.transport => l.categoryTransport,
    ExpenseCategory.accommodation => l.categoryAccommodation,
    ExpenseCategory.entertainment => l.categoryEntertainment,
    ExpenseCategory.shopping => l.categoryShopping,
    ExpenseCategory.home => l.categoryHome,
    ExpenseCategory.health => l.categoryHealth,
    ExpenseCategory.travel => l.categoryTravel,
    ExpenseCategory.other => l.categoryOther,
  };
}

/// G47: the Material icon of a custom category icon key
/// ([kCustomCategoryIcons]); an unknown key (a newer peer's) → a plain label.
IconData customCategoryIconData(String key) => switch (key) {
  'tag' => Icons.label_outline,
  'star' => Icons.star_outline,
  'heart' => Icons.favorite_outline,
  'pets' => Icons.pets_outlined,
  'child' => Icons.child_care_outlined,
  'gift' => Icons.card_giftcard_outlined,
  'sports' => Icons.sports_soccer_outlined,
  'music' => Icons.music_note_outlined,
  'book' => Icons.menu_book_outlined,
  'work' => Icons.work_outline,
  'tools' => Icons.build_outlined,
  'phone' => Icons.smartphone_outlined,
  'beach' => Icons.beach_access_outlined,
  'coffee' => Icons.local_cafe_outlined,
  'savings' => Icons.savings_outlined,
  'party' => Icons.celebration_outlined,
  _ => Icons.label_outline,
};

/// How a resolved category (built-in or custom, G47) looks.
extension ResolvedCategoryUi on ResolvedCategory {
  IconData get icon =>
      custom != null ? customCategoryIconData(custom!.icon) : builtin!.icon;

  String label(AppLocalizations l) => custom?.name ?? builtin!.label(l);

  /// Palette index: built-ins have fixed hues, a custom category's hue
  /// comes from its id (stable on every device).
  int _paletteIndex(int length) => custom != null
      ? avatarIndexFor(custom!.id, length)
      : builtin!._paletteIndex % length;
}

/// Background / foreground of [category]'s icon tile; no category → the
/// neutral secondary container (the pre-G16 receipt tile).
({Color background, Color foreground}) categoryColors(
  BuildContext context,
  ResolvedCategory? category,
) {
  if (category == null) {
    final scheme = Theme.of(context).colorScheme;
    return (
      background: scheme.secondaryContainer,
      foreground: scheme.onSecondaryContainer,
    );
  }
  final colors = context.ledgerColors;
  final i = category._paletteIndex(colors.avatarBackgrounds.length);
  return (
    background: colors.avatarBackgrounds[i],
    foreground: colors.avatarForegrounds[i],
  );
}

/// Icon for [category]; no category → the generic receipt.
IconData categoryIcon(ResolvedCategory? category) =>
    category?.icon ?? Icons.receipt_long_outlined;

/// The rounded-square category icon used in the ledger list and selector.
class CategoryIconTile extends StatelessWidget {
  final ResolvedCategory? category;
  final double size;
  const CategoryIconTile({super.key, required this.category, this.size = 44});

  @override
  Widget build(BuildContext context) {
    final c = categoryColors(context, category);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: c.background,
        borderRadius: BorderRadius.circular(size * 0.32),
      ),
      child: Icon(categoryIcon(category), color: c.foreground, size: size / 2),
    );
  }
}

/// What the selector sheet returned.
sealed class _Pick {
  const _Pick();
}

class _PickId extends _Pick {
  final String? id; // null = no category
  const _PickId(this.id);
}

class _PickNew extends _Pick {
  const _PickNew();
}

/// The category selector of the add / edit form (G47, replacing the G16
/// chip row): a form field showing the selected category's icon + name
/// ("No category" when none); tapping it opens a bottom-sheet list — "No
/// category", the built-in categories, the group's visible custom ones and,
/// with [onCreate], "New category…" last.
///
/// [selected] is the expense's category id, kept verbatim: a hidden custom
/// category still shows with its name, an unknown id as "Other".
/// [custom]: every custom category of the group (hidden ones included —
/// they're needed to label the selection, never offered).
class CategoryPicker extends StatelessWidget {
  final String? selected;
  final List<CustomCategory> custom;
  final ValueChanged<String?> onChanged;

  /// "New category…" picked; null hides the entry (e.g. read-only).
  final VoidCallback? onCreate;

  const CategoryPicker({
    super.key = const Key('categoryPicker'),
    required this.selected,
    required this.onChanged,
    this.custom = const [],
    this.onCreate,
  });

  Future<void> _open(BuildContext context) async {
    final pick = await showModalBottomSheet<_Pick>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _CategorySheet(
        selected: selected,
        custom: [
          for (final c in custom)
            if (!c.hidden) c,
        ],
        canCreate: onCreate != null,
      ),
    );
    switch (pick) {
      case null:
        return;
      case _PickNew():
        onCreate?.call();
      case _PickId(:final id):
        if (id != selected) onChanged(id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final resolved = resolveCategory(selected, custom);
    final theme = Theme.of(context);
    return InkWell(
      key: const Key('categoryPickerField'),
      borderRadius: BorderRadius.circular(Radii.m),
      onTap: () => _open(context),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: l.categoryLabel,
          suffixIcon: const Icon(Icons.arrow_drop_down),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: Insets.m,
            vertical: Insets.s,
          ),
        ),
        child: Row(
          children: [
            CategoryIconTile(category: resolved, size: 28),
            const SizedBox(width: Insets.m),
            Expanded(
              child: Text(
                resolved?.label(l) ?? l.categoryNone,
                key: const Key('categoryPickerValue'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: resolved == null
                    ? theme.textTheme.bodyLarge?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      )
                    : theme.textTheme.bodyLarge,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategorySheet extends StatelessWidget {
  final String? selected;
  final List<CustomCategory> custom;
  final bool canCreate;
  const _CategorySheet({
    required this.selected,
    required this.custom,
    required this.canCreate,
  });

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    Widget header(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(
        Insets.page,
        Insets.m,
        Insets.page,
        Insets.xs,
      ),
      child: Text(
        text.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          letterSpacing: 0.8,
        ),
      ),
    );
    Widget entry(String key, ResolvedCategory? c, String? id) => ListTile(
      key: Key('category-$key'),
      leading: CategoryIconTile(category: c, size: 32),
      title: Text(c?.label(l) ?? l.categoryNone),
      selected: id == selected,
      trailing: id == selected ? const Icon(Icons.check) : null,
      onTap: () => Navigator.of(context).pop(_PickId(id)),
    );
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.8,
      ),
      child: _SheetWidth(
        child: ListView(
          key: const Key('categorySheet'),
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: Insets.l),
          children: [
            entry('none', null, null),
            header(l.builtInCategories),
            for (final c in ExpenseCategory.values)
              entry(c.wire, ResolvedCategory.builtin(c), c.wire),
            if (custom.isNotEmpty) header(l.groupCategories),
            for (final c in custom)
              entry(c.id, ResolvedCategory.custom(c), c.id),
            if (canCreate) ...[
              const Divider(),
              ListTile(
                key: const Key('category-new'),
                leading: const SizedBox(width: 32, child: Icon(Icons.add)),
                title: Text(l.newCategoryEntry),
                onTap: () => Navigator.of(context).pop(const _PickNew()),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Caps the sheet's list at the content width on wide screens.
class _SheetWidth extends StatelessWidget {
  final Widget child;
  const _SheetWidth({required this.child});

  @override
  Widget build(BuildContext context) => Center(
    heightFactor: 1,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: kContentMaxWidth),
      child: child,
    ),
  );
}

/// G47: the "New category" / "Edit category" dialog — a name (trimmed,
/// 1 … [kMaxCategoryNameLength], unique among [existing] ignoring case) and
/// an icon from [kCustomCategoryIcons]. [initial] edits that category.
/// Returns the values, or null when cancelled.
Future<({String name, String icon})?> showCategoryDialog(
  BuildContext context, {
  CustomCategory? initial,
  List<CustomCategory> existing = const [],
}) => showDialog<({String name, String icon})>(
  context: context,
  builder: (_) => _CategoryDialog(initial: initial, existing: existing),
);

class _CategoryDialog extends StatefulWidget {
  final CustomCategory? initial;
  final List<CustomCategory> existing;
  const _CategoryDialog({required this.initial, required this.existing});

  @override
  State<_CategoryDialog> createState() => _CategoryDialogState();
}

class _CategoryDialogState extends State<_CategoryDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _nameCtrl = TextEditingController(text: widget.initial?.name);
  late String _icon = widget.initial?.icon ?? kDefaultCustomCategoryIcon;

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  String? _validate(String? raw) {
    final l = context.l10n;
    final name = raw?.trim() ?? '';
    if (name.isEmpty) return l.required;
    if (name.length > kMaxCategoryNameLength) {
      return l.categoryNameTooLong(kMaxCategoryNameLength);
    }
    final taken = widget.existing.any(
      (c) =>
          c.id != widget.initial?.id &&
          c.name.toLowerCase() == name.toLowerCase(),
    );
    return taken ? l.categoryNameTaken : null;
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop((name: _nameCtrl.text.trim(), icon: _icon));
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final preview = ResolvedCategory.custom(
      CustomCategory(
        id: widget.initial?.id ?? '${kCustomCategoryPrefix}new',
        name: '',
        icon: _icon,
      ),
    );
    return AlertDialog(
      title: Text(
        widget.initial == null ? l.newCategoryTitle : l.editCategoryTitle,
      ),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                key: const Key('categoryNameField'),
                controller: _nameCtrl,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: l.categoryNameLabel,
                  prefixIcon: Padding(
                    padding: const EdgeInsets.all(Insets.s),
                    child: CategoryIconTile(category: preview, size: 28),
                  ),
                ),
                validator: _validate,
                onFieldSubmitted: (_) => _save(),
              ),
              const SizedBox(height: Insets.l),
              Text(l.categoryIconLabel, style: theme.textTheme.labelLarge),
              const SizedBox(height: Insets.s),
              Wrap(
                spacing: Insets.xs,
                runSpacing: Insets.xs,
                children: [
                  for (final key in kCustomCategoryIcons)
                    IconButton(
                      key: Key('categoryIcon-$key'),
                      isSelected: key == _icon,
                      icon: Icon(customCategoryIconData(key)),
                      style: IconButton.styleFrom(
                        backgroundColor: key == _icon
                            ? theme.colorScheme.primary
                            : null,
                        foregroundColor: key == _icon
                            ? theme.colorScheme.onPrimary
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                      onPressed: () => setState(() => _icon = key),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.cancel),
        ),
        FilledButton(
          key: const Key('categoryDialogSave'),
          onPressed: _save,
          child: Text(widget.initial == null ? l.create : l.save),
        ),
      ],
    );
  }
}
