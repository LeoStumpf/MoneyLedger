import 'package:flutter/material.dart';

/// One line of text built from a localized template with **name**
/// placeholders, where every name ellipsizes on its own (G33): "Alexandra
/// Longname… paid Sam Otherlo…" instead of the whole sentence being cut after
/// the first name. Literal parts ("paid", "hat … bezahlt") are never cut.
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
  });

  /// The placeholder for the [i]-th name — a private-use code point that
  /// never occurs in translations or names.
  static String sentinel(int i) => String.fromCharCode(0xE000 + i);

  final String template;

  /// sentinel → name.
  final Map<String, String> names;
  final TextStyle? style;

  /// The sentence with the names filled in (semantics / tests).
  String get fullText {
    var s = template;
    names.forEach((k, v) => s = s.replaceAll(k, v));
    return s;
  }

  @override
  Widget build(BuildContext context) {
    final effective = DefaultTextStyle.of(context).style.merge(style);
    final segments = splitNameTemplate(template, names.keys.toSet());
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    double widthOf(String text) {
      final p = TextPainter(
        text: TextSpan(text: text, style: effective),
        textDirection: direction,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      // Ceil: a Text never needs more than this, so the measured row
      // can't exceed the line by a rounding hair.
      final w = p.width.ceilToDouble();
      p.dispose();
      return w;
    }

    return Semantics(
      label: fullText,
      excludeSemantics: true,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final literal = segments
              .where((s) => !s.isName)
              .fold<double>(0, (sum, s) => sum + widthOf(s.text));
          final natural = [
            for (final s in segments)
              if (s.isName) widthOf(names[s.text] ?? ''),
          ];
          final widths = constraints.maxWidth.isFinite
              ? allocateNameWidths(constraints.maxWidth - literal, natural)
              : natural;
          var n = 0;
          // Unconstrained + clipped: on an absurdly narrow line even the
          // literal words don't fit — clip instead of an overflow error.
          return UnconstrainedBox(
            alignment: AlignmentDirectional.centerStart,
            constrainedAxis: Axis.vertical,
            clipBehavior: Clip.hardEdge,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final s in segments)
                  if (s.isName)
                    SizedBox(
                      width: widths[n++],
                      child: Text(
                        names[s.text] ?? '',
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                        style: effective,
                      ),
                    )
                  else
                    Text(
                      s.text,
                      maxLines: 1,
                      softWrap: false,
                      style: effective,
                    ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// A [NamesLine] template split into literal text and name sentinels. Pure.
List<({String text, bool isName})> splitNameTemplate(
  String template,
  Set<String> sentinels,
) {
  final out = <({String text, bool isName})>[];
  final buf = StringBuffer();
  for (final rune in template.runes) {
    final ch = String.fromCharCode(rune);
    if (sentinels.contains(ch)) {
      if (buf.isNotEmpty) out.add((text: buf.toString(), isName: false));
      buf.clear();
      out.add((text: ch, isName: true));
    } else {
      buf.write(ch);
    }
  }
  if (buf.isNotEmpty) out.add((text: buf.toString(), isName: false));
  return out;
}

/// Shares [available] width between names of the given [natural] widths
/// ("water filling"): names that fit get their full width, the rest split
/// what's left equally — so a short name never forces a long one to be cut
/// more than necessary, and two long names are cut evenly. Pure.
List<double> allocateNameWidths(double available, List<double> natural) {
  final result = List<double>.filled(natural.length, 0);
  if (natural.isEmpty) return result;
  var left = available < 0 ? 0.0 : available;
  final order = List<int>.generate(natural.length, (i) => i)
    ..sort((a, b) => natural[a].compareTo(natural[b]));
  for (var k = 0; k < order.length; k++) {
    final i = order[k];
    final share = left / (order.length - k);
    final w = natural[i] <= share ? natural[i] : share;
    result[i] = w;
    left -= w;
  }
  return result;
}
