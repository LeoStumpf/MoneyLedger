/// G73 widget tests: the group settings tile, the exchange-rates page (list,
/// settle switch, add / edit / remove through [GroupEditor], read-only for
/// non-members), the rate dialog (typed input, *Fetch current rate* with a
/// fake fetcher — no network), the balance page notes, and 360 dp / 200 %
/// font in EN + DE.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/features/balance/balance_calculator.dart';
import 'package:money_ledger/features/balance/balance_page.dart';
import 'package:money_ledger/features/balance/exchange_rate_fetcher.dart';
import 'package:money_ledger/features/groups/group_archive_provider.dart';
import 'package:money_ledger/features/groups/group_provider.dart';
import 'package:money_ledger/features/groups/group_rates_page.dart';
import 'package:money_ledger/features/groups/group_settings_page.dart';
import 'package:money_ledger/models/exchange_rates.dart';
import 'package:money_ledger/models/expense_model.dart';
import 'package:money_ledger/models/group_model.dart';
import 'package:money_ledger/models/member_model.dart';

import 'helpers/l10n.dart';
import 'helpers/test_providers.dart';

const _roomId = 'g1';
const _me = '@alice:x.org';
const _bob = '@bob:x.org';

final _fx = ExchangeRates(
  base: 'EUR',
  rates: const {'CHF': '1.0797'},
  settle: true,
);

GroupModel _group({ExchangeRates? fx}) => GroupModel(
  roomId: _roomId,
  name: 'Trip',
  currency: 'EUR',
  exchangeRates: fx,
);

ExpenseModel _e(String id, String currency) => ExpenseModel(
  id: id,
  roomId: _roomId,
  description: id,
  amountCents: 2000,
  currency: currency,
  paidBy: _me,
  splitsJson: '{"$_me":1000,"$_bob":1000}',
  createdAt: 5000,
);

final _expenses = [_e('e1', 'EUR'), _e('e2', 'CHF'), _e('e3', 'USD')];

const _alice = MemberModel(
  groupId: _roomId,
  userId: _me,
  displayName: 'Alice',
  matrixId: _me,
  status: 'active',
  updatedAt: 1,
);

/// Records the editor calls instead of writing (no DB, no transport).
class _RecordingEditor extends GroupEditor {
  final written = <ExchangeRates?>[];

  @override
  Future<void> setExchangeRates(String groupId, ExchangeRates? fx) async =>
      written.add(fx);
}

List<dynamic> _overrides({
  MemberModel me = _alice,
  ExchangeRates? fx,
  _RecordingEditor? editor,
  ExchangeRateFetcher? fetcher,
  List<DebtEntry> debts = const [],
}) => [
  ...testOverrides(
    isLoggedIn: true,
    expenses: _expenses,
    members: [me],
    groups: [_group(fx: fx)],
    debts: debts,
  ),
  currentUserIdProvider.overrideWith((_) => _me),
  currentParticipantProvider.overrideWith((_, _) async => me),
  groupLedgerFingerprintProvider.overrideWith((_, _) => 'fp'),
  if (editor != null) groupEditorProvider.overrideWith(() => editor),
  exchangeRateFetcherProvider.overrideWithValue(
    fetcher ??
        (from, to) async => throw StateError('no network in tests ($from)'),
  ),
];

Future<void> _pump(
  WidgetTester tester,
  Widget page,
  List overrides, {
  Locale? locale,
}) async {
  await tester.pumpWidget(testApp(page, overrides: overrides, locale: locale));
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('group settings tile summarises the rates', (tester) async {
    await _pump(
      tester,
      const GroupSettingsPage(roomId: _roomId),
      _overrides(fx: _fx),
    );
    expect(find.byKey(const Key('exchangeRatesTile')), findsOneWidget);
    expect(find.text('1 rate in EUR · settle up in EUR'), findsOneWidget);
  });

  testWidgets('group settings tile without rates', (tester) async {
    await _pump(tester, const GroupSettingsPage(roomId: _roomId), _overrides());
    expect(find.text(en.exchangeRatesTileNone), findsOneWidget);
  });

  testWidgets('rates page: list (German decimal), missing currencies, '
      'switch and remove write new rates', (tester) async {
    final editor = _RecordingEditor();
    await _pump(
      tester,
      const GroupRatesPage(roomId: _roomId),
      _overrides(fx: _fx, editor: editor),
      locale: const Locale('de'),
    );
    expect(find.text('1 CHF = 1,0797 EUR'), findsOneWidget);
    expect(find.text(de.ratesMissingFor('USD')), findsOneWidget);
    expect(find.text(de.settleInBase('EUR')), findsOneWidget);

    await tester.tap(find.byKey(const Key('settleInBaseSwitch')));
    await tester.pump();
    expect(editor.written.single!.settle, isFalse);
    expect(editor.written.single!.rates, {'CHF': '1.0797'});

    await tester.tap(find.byKey(const Key('removeRate-CHF')));
    await tester.pump();
    expect(editor.written.last, isNull); // last rate gone → no rates at all
  });

  testWidgets('add a rate: pick the currency, fetch it (on tap only), save', (
    tester,
  ) async {
    final editor = _RecordingEditor();
    final asked = <String>[];
    await _pump(
      tester,
      const GroupRatesPage(roomId: _roomId),
      _overrides(
        fx: _fx,
        editor: editor,
        fetcher: (from, to) async {
          asked.add('$from→$to');
          return const FetchedRate(rate: '0.92', date: '2026-10-21');
        },
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('addRate')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('currency-USD')).first);
    await tester.pumpAndSettle();
    expect(find.text('1 USD in EUR'), findsOneWidget);
    expect(find.text(en.fetchRateSource(kRateSourceHost)), findsOneWidget);
    expect(asked, isEmpty); // nothing is fetched by opening the dialog

    await tester.tap(find.byKey(const Key('fetchRateButton')));
    await tester.pumpAndSettle();
    expect(asked, ['USD→EUR']);
    expect(find.byKey(const Key('fetchedRateInfo')), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('rateField')))
          .controller!
          .text,
      '0.92',
    );
    await tester.tap(find.byKey(const Key('rateSave')));
    await tester.pumpAndSettle();
    expect(editor.written.single!.rates, {'CHF': '1.0797', 'USD': '0.92'});
    expect(editor.written.single!.settle, isTrue);
    expect(editor.written.single!.base, 'EUR');
  });

  testWidgets('first rate: base = group currency; typed input is checked', (
    tester,
  ) async {
    final editor = _RecordingEditor();
    await _pump(
      tester,
      const GroupRatesPage(roomId: _roomId),
      _overrides(
        editor: editor,
        fetcher: (from, to) async => throw RateUnavailableException(from, to),
      ),
    );
    expect(find.byKey(const Key('noRatesYet')), findsOneWidget);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('addRate')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('currency-CHF')).first);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('fetchRateButton')));
    await tester.pumpAndSettle();
    expect(find.text(en.fetchRateUnavailable), findsOneWidget);

    await tester.enterText(find.byKey(const Key('rateField')), '0');
    await tester.tap(find.byKey(const Key('rateSave')));
    await tester.pumpAndSettle();
    expect(find.text(en.rateInvalid), findsOneWidget);
    expect(editor.written, isEmpty);

    await tester.enterText(find.byKey(const Key('rateField')), '1,25');
    await tester.tap(find.byKey(const Key('rateSave')));
    await tester.pumpAndSettle();
    final fx = editor.written.single!;
    expect(fx.base, 'EUR');
    expect(fx.rates, {'CHF': '1.25'});
    expect(fx.settle, isFalse);
  });

  testWidgets('a failed fetch shows a friendly error inline', (tester) async {
    await _pump(
      tester,
      const GroupRatesPage(roomId: _roomId),
      _overrides(
        fx: _fx,
        fetcher: (_, _) async => throw const FormatException('odd answer'),
      ),
    );
    await tester.tap(find.byKey(const Key('rate-CHF')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('fetchRateButton')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('actionErrorView')), findsOneWidget);
    expect(find.text('odd answer'), findsNothing); // raw text behind Details
  });

  testWidgets('read-only for someone no longer in the group', (tester) async {
    final editor = _RecordingEditor();
    await _pump(
      tester,
      const GroupRatesPage(roomId: _roomId),
      _overrides(
        fx: _fx,
        editor: editor,
        me: const MemberModel(
          groupId: _roomId,
          userId: _me,
          displayName: 'Alice',
          matrixId: _me,
          status: 'removed',
          updatedAt: 2,
        ),
      ),
    );
    expect(find.byKey(const Key('addRate')), findsNothing);
    await tester.tap(find.byKey(const Key('settleInBaseSwitch')));
    await tester.tap(find.byKey(const Key('rate-CHF')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('rateField')), findsNothing);
    expect(editor.written, isEmpty);
  });

  group('balance page', () {
    testWidgets('settling in EUR says so', (tester) async {
      await _pump(
        tester,
        const BalancePage(roomId: _roomId),
        _overrides(
          fx: _fx,
          debts: const [
            DebtEntry(from: _bob, to: _me, cents: 2080, currency: 'EUR'),
          ],
        ),
      );
      expect(find.text(en.settledInBaseNote('EUR')), findsOneWidget);
      expect(find.byKey(const Key('openRatesFromBalance')), findsOneWidget);
      expect(find.byKey(const Key('setExchangeRates')), findsNothing);
    });

    testWidgets('several currencies without rates offer to set them', (
      tester,
    ) async {
      await _pump(
        tester,
        const BalancePage(roomId: _roomId),
        _overrides(
          debts: const [
            DebtEntry(from: _bob, to: _me, cents: 1000, currency: 'EUR'),
            DebtEntry(from: _bob, to: _me, cents: 1000, currency: 'CHF'),
          ],
        ),
      );
      expect(find.byKey(const Key('perCurrencyNote')), findsOneWidget);
      expect(find.byKey(const Key('setExchangeRates')), findsOneWidget);
      expect(find.byKey(const Key('settledInBaseNote')), findsNothing);
    });
  });

  for (final locale in const [Locale('en'), Locale('de')]) {
    testWidgets('360 dp, 200 % font (${locale.languageCode}): page + dialog '
        'fit', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(360, 780);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await _pump(
        tester,
        const GroupRatesPage(roomId: _roomId),
        _overrides(
          fx: _fx,
          fetcher: (from, to) async => throw RateUnavailableException(from, to),
        ),
        locale: locale,
      );
      expect(tester.takeException(), isNull);
      // Past the FAB (the list's bottom padding makes room for it).
      await tester.drag(find.byType(ListView), const Offset(0, -2000));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('rate-CHF')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('fetchRateButton')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('360 dp, 200 % font (${locale.languageCode}): balance note', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(360, 780);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await _pump(
        tester,
        const BalancePage(roomId: _roomId),
        _overrides(
          fx: _fx,
          debts: const [
            DebtEntry(from: _bob, to: _me, cents: 2080, currency: 'EUR'),
          ],
        ),
        locale: locale,
      );
      expect(find.byKey(const Key('settledInBaseNote')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  test('PRIVACY.md and the in-app text say the same about exchange rates', () {
    String norm(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();
    final privacy = norm(File('PRIVACY.md').readAsStringSync());
    for (final file in ['app_en', 'app_de']) {
      final arb =
          jsonDecode(File('lib/l10n/$file.arb').readAsStringSync())
              as Map<String, Object?>;
      expect(arb['privacyRatesBody'], isA<String>(), reason: file);
      expect(arb['privacyRatesBody'] as String, contains(kRateSourceHost));
      if (file == 'app_en') {
        expect(privacy, contains(norm(arb['privacyRatesBody']! as String)));
        expect(privacy, contains('## ${arb['privacyRatesTitle']}'));
      }
    }
  });
}
