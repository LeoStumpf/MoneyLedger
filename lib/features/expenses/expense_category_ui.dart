/// G16: how expense categories look — icon, colours (from the theme's
/// avatar palette, so light / dark and contrast come for free) and the
/// localized label — plus the picker used by the add / edit form.
library;

import 'package:flutter/material.dart';

import '../../core/l10n/l10n.dart';
import '../../core/theme/app_theme.dart';
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

/// Background / foreground of [category]'s icon tile; no category → the
/// neutral secondary container (the pre-G16 receipt tile).
({Color background, Color foreground}) categoryColors(
  BuildContext context,
  ExpenseCategory? category,
) {
  if (category == null) {
    final scheme = Theme.of(context).colorScheme;
    return (
      background: scheme.secondaryContainer,
      foreground: scheme.onSecondaryContainer,
    );
  }
  final colors = context.ledgerColors;
  final i = category._paletteIndex % colors.avatarBackgrounds.length;
  return (
    background: colors.avatarBackgrounds[i],
    foreground: colors.avatarForegrounds[i],
  );
}

/// Icon for [category]; no category → the generic receipt.
IconData categoryIcon(ExpenseCategory? category) =>
    category?.icon ?? Icons.receipt_long_outlined;

/// The rounded-square category icon used in the ledger list and picker.
class CategoryIconTile extends StatelessWidget {
  final ExpenseCategory? category;
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

/// Category chips for the add / edit form (G16): a horizontally scrolling
/// row with one choice chip per category; tapping the selected one clears it
/// (no category). A selection made from outside (the description
/// suggestion) is scrolled into view.
class CategoryPicker extends StatefulWidget {
  final ExpenseCategory? selected;
  final ValueChanged<ExpenseCategory?> onChanged;
  const CategoryPicker({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  @override
  State<CategoryPicker> createState() => _CategoryPickerState();
}

class _CategoryPickerState extends State<CategoryPicker> {
  final _keys = {for (final c in ExpenseCategory.values) c: GlobalKey()};
  final _rowKey = GlobalKey();
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _revealSelected();
  }

  @override
  void didUpdateWidget(CategoryPicker old) {
    super.didUpdateWidget(old);
    if (old.selected != widget.selected) _revealSelected();
  }

  void _revealSelected() {
    final selected = widget.selected;
    if (selected == null) return;
    // Only this row scrolls (Scrollable.ensureVisible would also move the
    // surrounding form).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final chip = _keys[selected]?.currentContext?.findRenderObject();
      final row = _rowKey.currentContext?.findRenderObject();
      if (chip is! RenderBox || row is! RenderBox) return;
      final x = chip.localToGlobal(Offset.zero, ancestor: row).dx;
      final p = _scroll.position;
      final target = (x + chip.size.width / 2 - p.viewportDimension / 2).clamp(
        0.0,
        p.maxScrollExtent,
      );
      _scroll.animateTo(
        target,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return SingleChildScrollView(
      key: const Key('categoryPicker'),
      scrollDirection: Axis.horizontal,
      controller: _scroll,
      child: Row(
        key: _rowKey,
        children: [
          for (final c in ExpenseCategory.values)
            Padding(
              key: _keys[c],
              padding: const EdgeInsets.only(right: Insets.s),
              child: ChoiceChip(
                key: Key('category-${c.wire}'),
                avatar: Icon(c.icon, size: 18),
                label: Text(c.label(l)),
                selected: c == widget.selected,
                showCheckmark: false,
                onSelected: (on) => widget.onChanged(on ? c : null),
              ),
            ),
        ],
      ),
    );
  }
}
