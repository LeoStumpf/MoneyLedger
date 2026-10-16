/// G17 design system: theme tokens, semantic colours, avatars, day headers.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:money_ledger/core/l10n/l10n.dart';
import 'package:money_ledger/core/theme/app_theme.dart';
import 'package:money_ledger/core/widgets/person_avatar.dart';

import '../helpers/l10n.dart';

/// WCAG contrast ratio of two opaque colours.
double contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  group('initialsOf', () {
    test('first + last word, one letter for a single word', () {
      expect(initialsOf('Bea Müller'), 'BM');
      expect(initialsOf('Anna Maria Schmidt'), 'AS');
      expect(initialsOf('alice'), 'A');
      expect(initialsOf('  émile  '), 'É');
    });
    test('MXIDs / localparts: separators split, digit words are skipped', () {
      expect(initialsOf('moneyledger-test-a-c725'), 'MA');
      expect(initialsOf('moneyledger-test-b-c725'), 'MB');
      expect(initialsOf('@bob:x.org'), 'BO');
      expect(initialsOf('c725'), 'C');
    });
    test('never empty', () {
      expect(initialsOf(''), '?');
      expect(initialsOf(' - '), '?');
    });
  });

  test('avatar colour index is deterministic and in range', () {
    for (final id in ['@a:x', '@b:x', 'p-123', '']) {
      final i = avatarIndexFor(id, 8);
      expect(i, inInclusiveRange(0, 7));
      expect(avatarIndexFor(id, 8), i);
    }
    // FNV-1a — pinned so colours don't change between releases/platforms.
    expect(avatarIndexFor('a', 8), 0xe40c292c % 8);
  });

  for (final brightness in Brightness.values) {
    group('$brightness theme', () {
      final theme = brightness == Brightness.dark
          ? AppTheme.dark()
          : AppTheme.light();
      final ledger = theme.extension<LedgerColors>()!;
      final scheme = theme.colorScheme;

      test('uses the bundled font and the right brightness', () {
        expect(theme.colorScheme.brightness, brightness);
        expect(theme.textTheme.bodyMedium?.fontFamily, kAppFontFamily);
      });

      test('money colours meet AA contrast on the surfaces', () {
        for (final bg in [
          scheme.surface,
          scheme.surfaceContainerLow,
          AppTheme.cardColor(scheme),
        ]) {
          expect(contrast(ledger.positive, bg), greaterThanOrEqualTo(4.5));
          expect(contrast(ledger.negative, bg), greaterThanOrEqualTo(4.5));
        }
        expect(contrast(ledger.onPositiveContainer, ledger.positiveContainer),
            greaterThanOrEqualTo(4.5));
        expect(contrast(ledger.onNegativeContainer, ledger.negativeContainer),
            greaterThanOrEqualTo(4.5));
      });

      test('avatar letters are readable on every avatar colour', () {
        for (var i = 0; i < ledger.avatarBackgrounds.length; i++) {
          expect(
              contrast(ledger.avatarForegrounds[i], ledger.avatarBackgrounds[i]),
              greaterThanOrEqualTo(4.5),
              reason: 'avatar colour $i');
        }
      });

      testWidgets('builds a page with avatars + money colours', (tester) async {
        await tester.pumpWidget(MaterialApp(
          theme: theme,
          home: Builder(
            builder: (context) => Scaffold(
              appBar: AppBar(title: const Text('Trip')),
              body: Column(children: [
                const PersonAvatar(id: '@bea:x.org', name: 'Bea Müller'),
                const AvatarStack(people: [
                  (id: '1', name: 'Ann'),
                  (id: '2', name: 'Ben'),
                  (id: '3', name: 'Cy'),
                  (id: '4', name: 'Dee'),
                  (id: '5', name: 'Eve'),
                  (id: '6', name: 'Fay'),
                ]),
                Text('owed',
                    style: TextStyle(color: context.ledgerColors.positive)),
                const Card(child: ListTile(title: Text('row'))),
                FilledButton(onPressed: () {}, child: const Text('Go')),
              ]),
            ),
          ),
        ));
        expect(tester.takeException(), isNull);
        expect(find.text('BM'), findsOneWidget);
        expect(find.text('+2'), findsOneWidget); // 4 shown + "+2"
        final owed = tester.widget<Text>(find.text('owed'));
        expect(owed.style?.color, ledger.positive);
      });
    });
  }

  group('day headers', () {
    setUpAll(() async {
      await initializeDateFormatting('en');
      await initializeDateFormatting('de');
    });
    final now = DateTime(2026, 10, 16, 9);
    int at(int y, int m, int d, [int h = 12]) =>
        DateTime(y, m, d, h).millisecondsSinceEpoch;

    test('calendarDaysAgo counts calendar days, not 24 h spans', () {
      expect(calendarDaysAgo(at(2026, 10, 16, 0), now: now), 0);
      expect(calendarDaysAgo(at(2026, 10, 15, 23), now: now), 1);
      expect(calendarDaysAgo(at(2026, 10, 1), now: now), 15);
    });

    test('formatDayHeader omits the year only within the current year', () {
      expect(formatDayHeader(at(2026, 6, 13), 'en', now: now), 'Sat, Jun 13');
      expect(formatDayHeader(at(2025, 6, 13), 'en', now: now),
          'Fri, Jun 13, 2025');
    });

    for (final (locale, today, yesterday) in [
      ('en', 'Today', 'Yesterday'),
      ('de', 'Heute', 'Gestern'),
    ]) {
      testWidgets('dayHeader: Today / Yesterday / date ($locale)',
          (tester) async {
        late BuildContext ctx;
        await tester.pumpWidget(MaterialApp(
          locale: Locale(locale),
          localizationsDelegates: testLocalizationsDelegates,
          supportedLocales: testSupportedLocales,
          home: Builder(builder: (c) {
            ctx = c;
            return const SizedBox();
          }),
        ));
        await tester.pump();
        expect(ctx.dayHeader(at(2026, 10, 16), now: now), today);
        expect(ctx.dayHeader(at(2026, 10, 15), now: now), yesterday);
        expect(ctx.dayHeader(at(2026, 6, 13), now: now),
            formatDayHeader(at(2026, 6, 13), locale, now: now));
      });
    }
  });
}
