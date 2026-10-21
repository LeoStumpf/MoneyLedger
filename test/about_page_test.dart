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
        builder: (_, _) => const PrivacyPolicyPage(),
      ),
      GoRoute(
        path: '/how-it-works',
        builder: (_, _) => const Scaffold(body: Text('how-it-works')),
      ),
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

/// The About list is longer than the test screen (G39 added a tile).
Future<void> _tapTile(WidgetTester tester, String key) async {
  final tile = find.byKey(Key(key));
  await tester.scrollUntilVisible(tile, 100);
  await tester.ensureVisible(tile);
  await tester.pumpAndSettle();
  await tester.tap(tile);
}

void main() {
  testWidgets('shows name, version, source link and license', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    expect(find.text('About MoneyLedger'), findsOneWidget);
    expect(find.text('MoneyLedger'), findsOneWidget);
    expect(find.text('Version 1.2.3+4'), findsOneWidget);
    expect(find.text(kSourceCodeUrl), findsOneWidget);
    expect(find.textContaining('AGPL-3.0-or-later'), findsOneWidget);
    expect(kAppLicense, 'AGPL-3.0-or-later');
    expect(kSourceCodeUrl, 'https://github.com/LeoStumpf/MoneyLedger');
  });

  testWidgets('"Open-source licenses" opens the Flutter licenses page', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('openSourceLicensesTile')));
    await tester.pumpAndSettle();
    expect(find.byType(LicensePage), findsOneWidget);
  });

  testWidgets('privacy policy page (English)', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await _tapTile(tester, 'privacyPolicyTile');
    await tester.pumpAndSettle();

    expect(find.text('Privacy policy'), findsOneWidget);
    expect(find.textContaining('Last updated: Oct 22, 2026'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('What your Matrix homeserver sees'),
      200,
    );
    // G40: local mode has its own section.
    await tester.scrollUntilVisible(
      find.text('Local mode (without an account)'),
      200,
    );
    expect(
      find.textContaining("groups you don't share send nothing"),
      findsOneWidget,
    );
    // G52 step 6: shared (link) groups have their own section.
    await tester.scrollUntilVisible(
      find.text('Shared groups (invite link)'),
      200,
    );
    expect(find.textContaining('public Nostr relays'), findsWidgets);
    // G78: receipt photos stay on this device.
    await tester.scrollUntilVisible(find.text('Receipt photos (Android)'), 200);
    await tester.scrollUntilVisible(
      find.textContaining('It is never sent anywhere'),
      200,
    );
    expect(find.textContaining('It is never sent anywhere'), findsOneWidget);
  });

  testWidgets('"How MoneyLedger works" opens the welcome pages again (G39)', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('howItWorksTile')));
    await tester.pumpAndSettle();
    expect(find.text('how-it-works'), findsOneWidget);
  });

  testWidgets('German locale', (tester) async {
    await tester.pumpWidget(_app(locale: const Locale('de')));
    await tester.pumpAndSettle();
    expect(find.text('Über MoneyLedger'), findsOneWidget);
    expect(find.text('Quellcode'), findsOneWidget);
    await _tapTile(tester, 'privacyPolicyTile');
    await tester.pumpAndSettle();
    expect(find.text('Datenschutzerklärung'), findsOneWidget);
    expect(find.textContaining('Stand: 22. Okt. 2026'), findsOneWidget);
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
      expect(
        names(deArb[k] as String),
        names(enArb[k] as String),
        reason: 'placeholders of "$k"',
      );
    }
  });

  // G63 / U29: one German typography — en dash with spaces (never "—"), and
  // an ellipsis always set off by a space ("Lädt …", "… und 3 weitere").
  test('German ARB: en dashes and spaced ellipses only', () {
    final de =
        jsonDecode(File('lib/l10n/app_de.arb').readAsStringSync())
            as Map<String, dynamic>;
    for (final MapEntry(:key, :value) in de.entries) {
      if (key.startsWith('@') || value is! String) continue;
      expect(value.contains('—'), isFalse, reason: '"$key" uses an em dash');
      expect(
        RegExp(r'[^\s(\[„]…|…[^\s)\]“.,!?]').hasMatch(value),
        isFalse,
        reason: '"$key": ellipsis without a space',
      );
    }
  });
}
