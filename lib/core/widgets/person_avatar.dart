import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Up to two initials for [name] (G17): the first letters of the first and
/// last word ("Bea Müller" → "BM"), or one letter for a single word
/// ("alice" → "A"). `-`, `_`, `.` and `:` separate words too, a leading `@`
/// is ignored, and words with digits are skipped when others exist — so a
/// raw MXID localpart like "moneyledger-test-a-c725" becomes "MA". Never
/// empty ("?").
String initialsOf(String name) {
  final cleaned = name.trim().replaceFirst(RegExp(r'^@'), '');
  var words = cleaned
      .split(RegExp(r'[\s._\-:]+'))
      .where((w) => w.isNotEmpty)
      .toList();
  final plain = words.where((w) => !w.contains(RegExp(r'\d'))).toList();
  if (plain.isNotEmpty) words = plain;
  if (words.isEmpty) return '?';
  String first(String w) => String.fromCharCodes(w.runes.take(1)).toUpperCase();
  return words.length == 1
      ? first(words.first)
      : first(words.first) + first(words.last);
}

/// Deterministic palette index for a participant id (FNV-1a over the UTF-16
/// code units — stable on every platform, unlike `String.hashCode`).
int avatarIndexFor(String id, int paletteLength) {
  var h = 0x811c9dc5;
  for (final c in id.codeUnits) {
    h ^= c;
    h = (h * 0x01000193) & 0xffffffff;
  }
  return h % paletteLength;
}

/// A coloured initials circle for a participant (G17). The colour comes from
/// the **participant id** (stable across renames and devices), the letters
/// from the display name. Used everywhere a person appears.
class PersonAvatar extends StatelessWidget {
  const PersonAvatar({
    super.key,
    required this.id,
    required this.name,
    this.size = 40,
    this.dimmed = false,
  });

  final String id;
  final String name;
  final double size;

  /// Former members: greyed.
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final colors = context.ledgerColors;
    final scheme = Theme.of(context).colorScheme;
    final i = avatarIndexFor(id, colors.avatarBackgrounds.length);
    final bg = dimmed
        ? scheme.surfaceContainerHighest
        : colors.avatarBackgrounds[i];
    final fg = dimmed ? scheme.onSurfaceVariant : colors.avatarForegrounds[i];
    return Semantics(
      excludeSemantics: true,
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
        child: Text(
          initialsOf(name),
          maxLines: 1,
          style: TextStyle(
            color: fg,
            fontWeight: FontWeight.w700,
            fontSize: size * 0.38,
            height: 1,
            letterSpacing: 0,
          ),
        ),
      ),
    );
  }
}

/// Overlapping avatars for a group's members: at most [max], then a "+n"
/// bubble (G17).
class AvatarStack extends StatelessWidget {
  const AvatarStack({
    super.key,
    required this.people,
    this.max = 4,
    this.size = 28,
  });

  /// (participant id, display name) in display order.
  final List<({String id, String name})> people;
  final int max;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final shown = people.take(max).toList();
    final extra = people.length - shown.length;
    final overlap = size * 0.32;
    final count = shown.length + (extra > 0 ? 1 : 0);
    if (count == 0) return const SizedBox.shrink();
    Widget ring(Widget child) => Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color ?? scheme.surface,
        shape: BoxShape.circle,
      ),
      child: child,
    );
    final outer = size + 4;
    return SizedBox(
      height: outer,
      width: outer + (count - 1) * (outer - overlap),
      child: Stack(
        children: [
          for (var i = 0; i < shown.length; i++)
            Positioned(
              left: i * (outer - overlap),
              child: ring(
                PersonAvatar(id: shown[i].id, name: shown[i].name, size: size),
              ),
            ),
          if (extra > 0)
            Positioned(
              left: shown.length * (outer - overlap),
              child: ring(
                Container(
                  width: size,
                  height: size,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '+$extra',
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                      fontSize: size * 0.36,
                      height: 1,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
