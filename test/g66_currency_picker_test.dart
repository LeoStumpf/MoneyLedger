/// G66 (U16): the currency picker — region default for a new group, the
/// full ISO-4217 list with search (code / EN / DE name), at 360 dp.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/widgets/currency_field.dart';
import 'package:money_ledger/features/groups/create_group_page.dart';

import 'helpers/test_providers.dart';

/// A phone-sized window (360 × 780 dp).
void _phone(WidgetTester tester) {
  tester.view.devicePixelRatio = 3;
  tester.view.physicalSize = const Size(360 * 3, 780 * 3);
  addTearDown(tester.view.reset);
}

Future<void> _pumpCreate(
  WidgetTester tester, {
  String? region,
  Locale? locale,
}) async {
  _phone(tester);
  await tester.pumpWidget(
    testApp(
      const CreateGroupPage(),
      locale: locale,
      overrides: [deviceRegionProvider.overrideWithValue(region)],
    ),
  );
  await tester.pumpAndSettle();
}

Finder get _field => find.byKey(const Key('createGroupCurrency'));

String? _fieldCode(WidgetTester tester) => tester
    .widgetList<Text>(find.descendant(of: _field, matching: find.byType(Text)))
    .map((t) => t.data)
    .firstWhere((d) => d != null && RegExp(r'^[A-Z]{3}$').hasMatch(d));

void main() {
  group('region default (new group)', () {
    for (final (region, code) in [
      ('CH', 'CHF'),
      ('GB', 'GBP'),
      ('DE', 'EUR'),
      (null, 'EUR'),
      ('ZZ', 'EUR'),
    ]) {
      testWidgets('$region → $code', (tester) async {
        await _pumpCreate(tester, region: region);
        expect(_fieldCode(tester), code);
      });
    }

    testWidgets('the field shows the localized name', (tester) async {
      await _pumpCreate(tester, region: 'CH', locale: const Locale('de'));
      expect(
        find.descendant(of: _field, matching: find.text('Schweizer Franken')),
        findsOneWidget,
      );
    });
  });

  group('picker search at 360 dp', () {
    testWidgets('en: suggestions first, search by name, no match, pick', (
      tester,
    ) async {
      await _pumpCreate(tester, region: 'CH');
      await tester.tap(_field);
      await tester.pumpAndSettle();
      expect(find.text('Choose currency'), findsOneWidget);
      expect(find.text('Suggested'), findsOneWidget);
      // Region currency (selected) first, then the common ones.
      final first = tester.getTopLeft(find.byKey(const Key('currency-CHF')));
      final eur = tester.getTopLeft(find.byKey(const Key('currency-EUR')));
      expect(first.dy, lessThan(eur.dy));

      final search = find.byKey(const Key('currencySearch'));
      await tester.enterText(search, 'zlo');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('currency-PLN')), findsOneWidget);
      // (In the sheet — the page below has the G52 link switch tile.)
      expect(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.byType(ListTile),
        ),
        findsOneWidget,
      );
      expect(find.text('Suggested'), findsNothing);

      await tester.enterText(search, 'qqq');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('currencyNoMatch')), findsOneWidget);

      await tester.enterText(search, 'forint');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('currency-HUF')));
      await tester.pumpAndSettle();
      expect(find.text('Choose currency'), findsNothing);
      expect(_fieldCode(tester), 'HUF');
      expect(tester.takeException(), isNull);
    });

    testWidgets('de: German names, search "krone" finds the crowns', (
      tester,
    ) async {
      await _pumpCreate(tester, region: 'DE', locale: const Locale('de'));
      await tester.tap(_field);
      await tester.pumpAndSettle();
      expect(find.text('Währung wählen'), findsOneWidget);
      expect(find.text('Vorschläge'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('currencySearch')), 'krone');
      await tester.pumpAndSettle();
      for (final c in ['CZK', 'DKK', 'NOK', 'SEK', 'ISK']) {
        expect(find.byKey(Key('currency-$c')), findsOneWidget, reason: c);
      }
      expect(find.text('Tschechische Krone'), findsOneWidget);
      await tester.tap(find.byKey(const Key('currency-CZK')));
      await tester.pumpAndSettle();
      expect(_fieldCode(tester), 'CZK');
      expect(tester.takeException(), isNull);
    });

    testWidgets('an unknown code stays offered and selected', (tester) async {
      _phone(tester);
      String? picked;
      await tester.pumpWidget(
        testApp(
          Consumer(
            builder: (context, ref, _) => Scaffold(
              body: TextButton(
                onPressed: () async =>
                    picked = await showCurrencyPicker(context, selected: 'XYZ'),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('currency-XYZ')), findsOneWidget);
      await tester.tap(find.byKey(const Key('currency-USD')));
      await tester.pumpAndSettle();
      expect(picked, 'USD');
    });
  });
}
