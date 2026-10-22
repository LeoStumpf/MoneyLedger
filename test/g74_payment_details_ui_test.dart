/// G74: Settings → Payment details (form, validation, save / clear) and the
/// balance page's QR button on debts owed to me → GiroCode / PayPal.me
/// sheet — EN + DE, 360 dp, 200 % font.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:money_ledger/core/database/account_database.dart';
import 'package:money_ledger/core/database/app_database.dart';
import 'package:money_ledger/core/database/daos/settings_dao.dart';
import 'package:money_ledger/core/matrix/transport_provider.dart';
import 'package:money_ledger/core/platform/text_sharer.dart';
import 'package:money_ledger/core/theme/app_theme.dart';
import 'package:money_ledger/features/auth/auth_provider.dart';
import 'package:money_ledger/features/balance/balance_calculator.dart';
import 'package:money_ledger/features/balance/balance_page.dart';
import 'package:money_ledger/features/devices/device_provider.dart';
import 'package:money_ledger/features/expenses/expenses_provider.dart';
import 'package:money_ledger/features/groups/group_provider.dart';
import 'package:money_ledger/features/onboarding/onboarding_provider.dart';
import 'package:money_ledger/features/payment/payment_details.dart';
import 'package:money_ledger/features/payment/payment_details_page.dart';
import 'package:money_ledger/features/settings/settings_page.dart';
import 'package:money_ledger/models/group_model.dart';
import 'package:money_ledger/models/member_model.dart';

import 'helpers/eventually.dart';
import 'helpers/fake_auth_gateway.dart';
import 'helpers/fake_device_gateway.dart';
import 'helpers/fake_ledger_network.dart';
import 'helpers/in_memory_database.dart';
import 'helpers/l10n.dart';
import 'helpers/test_providers.dart';

const _g = 'g1';
const _me = '@anna:x.org';
const _ben = '@ben:x.org';

MemberModel _member(String id, String name, {String? mxid}) => MemberModel(
  groupId: _g,
  userId: id,
  displayName: name,
  matrixId: mxid,
  status: 'active',
  updatedAt: 1,
);

final _members = [
  _member(_me, 'Anna', mxid: _me),
  _member(_ben, 'Ben', mxid: _ben),
  _member('p-chris', 'Chris'),
];

const _group = GroupModel(roomId: _g, name: 'Rom 2026', currency: 'EUR');

const _details = PaymentDetails(
  name: 'Anna Muster',
  iban: 'DE89370400440532013000',
  paypalMe: 'annamuster',
);

const _debts = [
  DebtEntry(from: _ben, to: _me, cents: 2350, currency: 'EUR'),
  DebtEntry(from: 'p-chris', to: _me, cents: 1000, currency: 'CHF'),
  DebtEntry(from: 'p-chris', to: _ben, cents: 500, currency: 'EUR'),
];

void _phone(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(360, 780);
  addTearDown(tester.view.reset);
}

List<dynamic> _overrides({
  PaymentDetails? details = _details,
  List<dynamic> extra = const [],
}) => [
  ...testOverrides(
    isLoggedIn: true,
    members: _members,
    groups: const [_group],
    debts: _debts,
    paymentDetails: details,
  ),
  currentUserIdProvider.overrideWith((_) => _me),
  currentParticipantProvider.overrideWith((ref, g) async => _members.first),
  appDatabaseProvider.overrideWithValue(
    AppDatabase.signedOut(SignedOutExecutor()),
  ),
  ledgerTransportProvider.overrideWith(
    (ref) => FakeMatrixNetwork().clientFor(_me),
  ),
  authGatewayProvider.overrideWith(
    (ref) async => FakeAuthGateway(initialUserId: _me),
  ),
  deviceGatewayProvider.overrideWith(
    (ref) async => FakeDeviceGateway(const []),
  ),
  ...extra,
];

Widget _routed(
  Widget page,
  List<dynamic> overrides, {
  Locale locale = const Locale('en'),
  double textScale = 1,
}) {
  final router = GoRouter(
    initialLocation: '/page',
    routes: [
      GoRoute(path: '/page', builder: (_, _) => page),
      GoRoute(
        path: kPaymentDetailsLocation,
        builder: (_, _) => const PaymentDetailsPage(),
      ),
    ],
  );
  return ProviderScope(
    overrides: [...overrides],
    child: MaterialApp.router(
      theme: AppTheme.light(isWeb: false),
      locale: locale,
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      routerConfig: router,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
    ),
  );
}

const _benQr = Key('paymentQr-$_ben-$_me-EUR');
const _chrisQr = Key('paymentQr-p-chris-$_me-CHF');

/// Scrolls the page's list until [key] is built and visible.
Future<void> _scrollTo(WidgetTester tester, Key key) async {
  await tester.scrollUntilVisible(
    find.byKey(key),
    150,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

void main() {
  group('settings page', () {
    testWidgets('tile: nothing set / what is set (IBAN tail only)', (
      tester,
    ) async {
      _phone(tester);
      await tester.pumpWidget(
        _routed(const SettingsPage(), _overrides(details: null)),
      );
      await tester.pumpAndSettle();
      await _scrollTo(tester, const Key('paymentDetailsTile'));
      expect(find.text(en.paymentDetailsTileNone), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(_routed(const SettingsPage(), _overrides()));
      await tester.pumpAndSettle();
      await _scrollTo(tester, const Key('paymentDetailsTile'));
      expect(
        find.text(
          '${en.paymentDetailsTileIban('3000')} · paypal.me/annamuster',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('DE89'), findsNothing);
      await tester.tap(find.byKey(const Key('paymentDetailsTile')));
      await tester.pumpAndSettle();
      expect(find.byType(PaymentDetailsPage), findsOneWidget);
      final iban = tester.widget<EditableText>(
        find.descendant(
          of: find.byKey(const Key('paymentIbanField')),
          matching: find.byType(EditableText),
        ),
      );
      expect(iban.controller.text, 'DE89 3704 0044 0532 0130 00');
      // Let the settings page's debounce timers run out.
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(minutes: 1));
    });
  });

  group('payment details form', () {
    testWidgets('validates IBAN, name, BIC and PayPal.me; saves normalised', (
      tester,
    ) async {
      _phone(tester);
      final db = openTestDatabase();
      addTearDown(() => tester.runAsync(db.close));
      final dao = SettingsDao(db);
      await tester.pumpWidget(
        _routed(
          const PaymentDetailsPage(),
          _overrides(
            details: null,
            extra: [settingsDaoProvider.overrideWithValue(dao)],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(en.paymentDetailsIntro), findsOneWidget);
      expect(find.byKey(const Key('paymentDetailsClear')), findsNothing);

      await tester.enterText(
        find.byKey(const Key('paymentIbanField')),
        'DE89 3704 0044 0532 0130 01',
      );
      await tester.enterText(find.byKey(const Key('paymentBicField')), 'XX');
      await tester.enterText(
        find.byKey(const Key('paymentPaypalField')),
        'anna muster',
      );
      await _scrollTo(tester, const Key('paymentDetailsSave'));
      await tester.tap(find.byKey(const Key('paymentDetailsSave')));
      await tester.pumpAndSettle();
      expect(find.text(en.paymentIbanInvalid), findsOneWidget);
      expect(find.text(en.paymentNameRequired), findsOneWidget);
      expect(find.text(en.paymentBicInvalid), findsOneWidget);
      expect(find.text(en.paymentPaypalInvalid), findsOneWidget);
      expect(await tester.runAsync<String?>(dao.paymentDetailsRaw), isNull);

      await tester.enterText(
        find.byKey(const Key('paymentNameField')),
        ' Anna Muster ',
      );
      await tester.enterText(
        find.byKey(const Key('paymentIbanField')),
        'de89 3704 0044 0532 0130 00',
      );
      await tester.enterText(find.byKey(const Key('paymentBicField')), '');
      await tester.enterText(
        find.byKey(const Key('paymentPaypalField')),
        'https://paypal.me/annamuster',
      );
      await _scrollTo(tester, const Key('paymentDetailsSave'));
      await tester.tap(find.byKey(const Key('paymentDetailsSave')));
      await tester.runAsync(
        () => eventually(
          () async => await dao.paymentDetailsRaw() != null,
          tester: tester,
        ),
      );
      await tester.pumpAndSettle();
      expect(
        PaymentDetails.decode(
          await tester.runAsync<String?>(dao.paymentDetailsRaw),
        ),
        _details,
      );
      expect(find.text(en.paymentDetailsSaved), findsOneWidget);
    });

    testWidgets('clear all fields + save removes them', (tester) async {
      _phone(tester);
      final db = openTestDatabase();
      addTearDown(() => tester.runAsync(db.close));
      final dao = SettingsDao(db);
      await tester.runAsync(() => dao.setPaymentDetailsRaw(_details.encode()));
      await tester.pumpWidget(
        _routed(
          const PaymentDetailsPage(),
          _overrides(extra: [settingsDaoProvider.overrideWithValue(dao)]),
        ),
      );
      await tester.pumpAndSettle();
      await _scrollTo(tester, const Key('paymentDetailsClear'));
      await tester.tap(find.byKey(const Key('paymentDetailsClear')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('paymentDetailsSave')));
      await tester.runAsync(
        () => eventually(
          () async => await dao.paymentDetailsRaw() == null,
          tester: tester,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(en.paymentDetailsCleared), findsOneWidget);
    });
  });

  group('balance page', () {
    testWidgets('QR button only on debts owed to me, only with details', (
      tester,
    ) async {
      _phone(tester);
      await tester.pumpWidget(
        _routed(const BalancePage(roomId: _g), _overrides(details: null)),
      );
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.qr_code_2), findsNothing);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        _routed(const BalancePage(roomId: _g), _overrides()),
      );
      await tester.pumpAndSettle();
      await _scrollTo(tester, _benQr);
      expect(find.byKey(_benQr), findsOneWidget);
      await _scrollTo(tester, _chrisQr);
      expect(find.byKey(_chrisQr), findsOneWidget);
      expect(
        find.byKey(const Key('paymentQr-p-chris-$_ben-EUR')),
        findsNothing,
      );
      expect(find.byTooltip(en.paymentShowDetails), findsWidgets);
    });

    testWidgets('euro debt: GiroCode with the amount, then PayPal.me + share', (
      tester,
    ) async {
      _phone(tester);
      final shared = <String>[];
      await tester.pumpWidget(
        _routed(
          const BalancePage(roomId: _g),
          _overrides(
            extra: [
              textSharerProvider.overrideWithValue((text, {subject}) async {
                shared.add(text);
                return true;
              }),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _scrollTo(tester, _benQr);
      await tester.tap(find.byKey(_benQr));
      await tester.pumpAndSettle();
      expect(
        find.text(en.paymentRequestTitle('Ben', '€23.50')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('paymentGiroCode')), findsOneWidget);
      expect(find.text('DE89 3704 0044 0532 0130 00'), findsOneWidget);
      expect(find.text(en.paymentRequestLocalNote), findsOneWidget);

      await tester.tap(find.text(en.paymentMethodPaypal));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('paymentPaypalQr')), findsOneWidget);
      expect(
        find.text('https://paypal.me/annamuster/23.50EUR'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('paymentShareLink')));
      await tester.pumpAndSettle();
      expect(shared, ['https://paypal.me/annamuster/23.50EUR']);
    });

    testWidgets('other currency: no GiroCode, the IBAN as text', (
      tester,
    ) async {
      _phone(tester);
      await tester.pumpWidget(
        _routed(
          const BalancePage(roomId: _g),
          _overrides(
            details: const PaymentDetails(
              name: 'Anna Muster',
              iban: 'DE89370400440532013000',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _scrollTo(tester, _chrisQr);
      await tester.tap(find.byKey(_chrisQr));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('paymentGiroCode')), findsNothing);
      expect(find.byKey(const Key('paymentGiroCodeEuroOnly')), findsOneWidget);
      expect(find.byKey(const Key('paymentMethodSwitch')), findsNothing);
      expect(find.byKey(const Key('paymentIbanText')), findsOneWidget);
    });

    for (final locale in const [Locale('en'), Locale('de')]) {
      testWidgets('360 dp, 200 % font: rows, sheet and form fit '
          '(${locale.languageCode})', (tester) async {
        _phone(tester);
        await tester.pumpWidget(
          _routed(
            const BalancePage(roomId: _g),
            _overrides(),
            locale: locale,
            textScale: 2,
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await _scrollTo(tester, _benQr);
        await tester.tap(find.byKey(_benQr));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byKey(const Key('paymentGiroCode')), findsOneWidget);
        await tester.tap(
          find.text(
            locale.languageCode == 'de'
                ? de.paymentMethodPaypal
                : en.paymentMethodPaypal,
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(
          _routed(
            const PaymentDetailsPage(),
            _overrides(),
            locale: locale,
            textScale: 2,
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });
}
