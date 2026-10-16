/// About page + in-app privacy policy (G12) and the AGPL licensing bits (G21).
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:money_ledger/features/about/about_page.dart';

import 'helpers/l10n.dart';

Widget _app({Locale locale = const Locale('en')}) {
  final router = GoRouter(
    initialLocation: '/about',
    routes: [
      GoRoute(path: '/about', builder: (_, _) => const AboutPage()),
      GoRoute(
          path: '/about/privacy',
          builder: (_, _) => const PrivacyPolicyPage()),
    ],
  );
  return ProviderScope(
    overrides: [appVersionProvider.overrideWith((ref) async => '1.2.3+4')],
    child: MaterialApp.router(
      locale: locale,
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      routerConfig: router,
    ),
  );
}

void main() {
  testWidgets('shows name, version, source link and license', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    expect(find.text('About MoneyLedger'), findsOneWidget);
    expect(find.text('MoneyLedger'), findsOneWidget);
    expect(find.text('Version 1.2.3+4'), findsOneWidget);
    expect(find.text(kSourceCodeUrl), findsOneWidget);
    expect(find.textContaining('AGPL-3.0'), findsOneWidget);
    expect(kSourceCodeUrl, 'https://github.com/LeoStumpf/MoneyLedger');
  });

  testWidgets('"Open-source licenses" opens the Flutter licenses page',
      (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('openSourceLicensesTile')));
    await tester.pumpAndSettle();
    expect(find.byType(LicensePage), findsOneWidget);
  });

  testWidgets('privacy policy page (English)', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('privacyPolicyTile')));
    await tester.pumpAndSettle();

    expect(find.text('Privacy policy'), findsOneWidget);
    expect(find.text('What your Matrix homeserver sees'), findsOneWidget);
    expect(find.textContaining('Last updated: Oct 16, 2026'), findsOneWidget);
  });

  testWidgets('German locale', (tester) async {
    await tester.pumpWidget(_app(locale: const Locale('de')));
    await tester.pumpAndSettle();
    expect(find.text('Über MoneyLedger'), findsOneWidget);
    expect(find.text('Quellcode'), findsOneWidget);
    await tester.tap(find.byKey(const Key('privacyPolicyTile')));
    await tester.pumpAndSettle();
    expect(find.text('Datenschutzerklärung'), findsOneWidget);
    expect(find.textContaining('Stand: 16. Okt. 2026'), findsOneWidget);
  });

  test('ARB files: same keys and placeholders in EN and DE', () {
    Map<String, dynamic> load(String f) =>
        jsonDecode(File('lib/l10n/$f').readAsStringSync())
            as Map<String, dynamic>;
    final enArb = load('app_en.arb');
    final deArb = load('app_de.arb');
    Set<String> keys(Map<String, dynamic> m) =>
        m.keys.where((k) => !k.startsWith('@')).toSet();
    expect(keys(deArb), keys(enArb));
    final placeholder = RegExp(r'\{(\w+)\}');
    for (final k in keys(enArb)) {
      Set<String> names(String v) =>
          placeholder.allMatches(v).map((m) => m[1]!).toSet();
      expect(names(deArb[k] as String), names(enArb[k] as String),
          reason: 'placeholders of "$k"');
    }
  });
}
