import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/l10n.dart';
import '../theme/app_theme.dart';

/// G66: the device region (ISO-3166 country code of the first system locale
/// that names one, e.g. `CH` for de_CH), or null. Drives the default
/// currency of a new group and the picker's suggestions. Tests override it.
final deviceRegionProvider = Provider<String?>((ref) {
  for (final l in PlatformDispatcher.instance.locales) {
    final c = l.countryCode;
    if (c != null && c.isNotEmpty) return c;
  }
  return null;
});

/// G66: a form field showing the selected currency [value] (code, plus its
/// name when [showName]); a tap opens [showCurrencyPicker] with [suggested]
/// on top. Used by the create / edit group pages, the expense form and the
/// payment dialog.
class CurrencyField extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;

  /// The picker's first section (see `suggestedCurrencies`).
  final List<String> suggested;
  final String? labelText;
  final String? helperText;
  final Widget? prefixIcon;

  /// Show the currency's name next to the code (wide fields).
  final bool showName;

  const CurrencyField({
    super.key,
    required this.value,
    required this.onChanged,
    this.suggested = const [],
    this.labelText,
    this.helperText,
    this.prefixIcon,
    this.showName = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = showName ? currencyName(value, context.localeName) : null;
    return InkWell(
      onTap: () async {
        final picked = await showCurrencyPicker(
          context,
          selected: value,
          suggested: suggested,
        );
        if (picked != null && picked != value) onChanged(picked);
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: labelText ?? context.l10n.currencyLabel,
          helperText: helperText,
          helperMaxLines: 3,
          prefixIcon: prefixIcon,
          suffixIcon: const Icon(Icons.arrow_drop_down),
        ),
        child: Row(
          children: [
            // G71: a narrow field at a large font size fades the code out
            // instead of overflowing.
            if (name == null)
              Flexible(
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.fade,
                  softWrap: false,
                ),
              )
            else
              Text(value),
            if (name != null) ...[
              const SizedBox(width: Insets.s),
              Expanded(
                child: Text(
                  name,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// G66: a bottom sheet listing every currency — [suggested] first (in that
/// order; [selected] is always offered, also an unknown code, and the
/// [kCommonCurrencies] always follow), then all
/// others by code — with a search field (code or name, EN + DE, accent
/// insensitive). Returns the chosen code, or null.
Future<String?> showCurrencyPicker(
  BuildContext context, {
  required String selected,
  List<String> suggested = const [],
}) => showModalBottomSheet<String>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (_) => CurrencyPickerSheet(
    selected: selected,
    suggested: {selected, ...suggested, ...kCommonCurrencies}.toList(),
  ),
);

class CurrencyPickerSheet extends StatefulWidget {
  final String selected;
  final List<String> suggested;

  const CurrencyPickerSheet({
    super.key,
    required this.selected,
    required this.suggested,
  });

  @override
  State<CurrencyPickerSheet> createState() => _CurrencyPickerSheetState();
}

class _CurrencyPickerSheetState extends State<CurrencyPickerSheet> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final locale = context.localeName;
    final query = _search.text;
    final suggested = widget.suggested;
    final others = [
      for (final c in kCurrencyCodes)
        if (!suggested.contains(c)) c,
    ];
    bool match(String c) => currencyMatches(c, query, locale);

    // A flat list of headers (String with a leading '#') and codes.
    final items = <String>[];
    if (query.trim().isEmpty) {
      items
        ..add('#${l.currencySuggested}')
        ..addAll(suggested)
        ..add('#${l.currencyAll}')
        ..addAll(others);
    } else {
      items.addAll([...suggested, ...others].where(match));
    }

    final height = MediaQuery.sizeOf(context).height * 0.85;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: height,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Insets.page,
                Insets.m,
                Insets.page,
                Insets.s,
              ),
              child: Text(
                l.chooseCurrencyTitle,
                style: theme.textTheme.titleLarge,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Insets.page),
              child: TextField(
                key: const Key('currencySearch'),
                controller: _search,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  hintText: l.currencySearchHint,
                  prefixIcon: const Icon(Icons.search),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(height: Insets.s),
            Expanded(
              child: items.isEmpty
                  ? Center(
                      child: Text(
                        l.currencyNoMatch,
                        key: const Key('currencyNoMatch'),
                      ),
                    )
                  : ListView.builder(
                      itemCount: items.length,
                      itemBuilder: (context, i) {
                        final item = items[i];
                        if (item.startsWith('#')) {
                          return Padding(
                            padding: const EdgeInsets.fromLTRB(
                              Insets.page,
                              Insets.m,
                              Insets.page,
                              Insets.xs,
                            ),
                            child: Text(
                              item.substring(1),
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          );
                        }
                        final name = currencyName(item, locale);
                        final selected = item == widget.selected;
                        return ListTile(
                          key: Key('currency-$item'),
                          title: Text(item),
                          subtitle: name == null ? null : Text(name),
                          trailing: selected ? const Icon(Icons.check) : null,
                          selected: selected,
                          onTap: () => Navigator.of(context).pop(item),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
