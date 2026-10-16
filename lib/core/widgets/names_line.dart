import 'package:flutter/material.dart';

/// A sentence built from a localized template with **name** placeholders
/// (G33), e.g. "Alexandra paid Sam" / "Sam zahlt an dich".
///
/// G18 review 2: it wraps onto up to [maxLines] lines (default 2) — a single
/// line left only a few letters of a name next to a ledger row's amount
/// ("mo… zahlt an dich"). Only when the whole sentence doesn't fit into
/// [maxLines] lines are the names shortened, **each on its own** and never
/// the literal words: every name is capped at the same number of characters
/// (short names stay whole, long ones are cut evenly, with "…"), the largest
/// cap that fits wins ([capNames]).
///
/// [template] is the localized sentence built with [NamesLine.sentinel]s in
/// place of the names (e.g. `l.settlementTitle(sentinel(0), sentinel(1))`);
/// [names] maps those sentinels to the names. The full sentence is exposed
/// to accessibility.
class NamesLine extends StatelessWidget {
  const NamesLine({
    super.key,
    required this.template,
    required this.names,
    this.style,
    this.maxLines = 2,
  });

  /// The placeholder for the [i]-th name — a private-use code point that
  /// never occurs in translations or names.
  static String sentinel(int i) => String.fromCharCode(0xE000 + i);

  final String template;

  /// sentinel → name.
  final Map<String, String> names;
  final TextStyle? style;
  final int maxLines;

  /// The sentence with the names filled in (semantics / tests).
  String get fullText => capNames(template, names, null);

  @override
  Widget build(BuildContext context) {
    final effective = DefaultTextStyle.of(context).style.merge(style);
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    return Semantics(
      label: fullText,
      excludeSemantics: true,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          bool fits(String text) {
            final p = TextPainter(
              text: TextSpan(text: text, style: effective),
              textDirection: direction,
              textScaler: scaler,
              maxLines: maxLines,
            )..layout(maxWidth: width);
            final ok = !p.didExceedMaxLines;
            p.dispose();
            return ok;
          }

          var shown = fullText;
          if (width.isFinite && !fits(shown)) {
            // The largest per-name cap that fits (binary search).
            final longest = names.values.fold<int>(
              0,
              (m, n) => n.characters.length > m ? n.characters.length : m,
            );
            var lo = 1, hi = longest - 1, best = 1;
            while (lo <= hi) {
              final mid = (lo + hi) ~/ 2;
              if (fits(capNames(template, names, mid))) {
                best = mid;
                lo = mid + 1;
              } else {
                hi = mid - 1;
              }
            }
            shown = capNames(template, names, best);
          }
          return Text(
            shown,
            key: const Key('namesLineText'),
            maxLines: maxLines,
            overflow: TextOverflow.ellipsis,
            style: effective,
          );
        },
      ),
    );
  }
}

/// [template] with each sentinel of [names] replaced by its name — cut to
/// at most [cap] characters (graphemes) plus "…" when longer; [cap] null =
/// whole names. Pure.
String capNames(String template, Map<String, String> names, int? cap) {
  final out = StringBuffer();
  for (final ch in template.characters) {
    final name = names[ch];
    if (name == null) {
      out.write(ch);
    } else if (cap == null || name.characters.length <= cap) {
      out.write(name);
    } else {
      out
        ..write(name.characters.take(cap).toString().trimRight())
        ..write('…');
    }
  }
  return out.toString();
}
