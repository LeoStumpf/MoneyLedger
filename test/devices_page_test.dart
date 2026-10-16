/// DevicesPage (Phase F, M6): lists devices with verified status and runs an
/// SAS verification against the FakeDeviceGateway. No matrix import.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/matrix/device_gateway.dart';
import 'package:money_ledger/features/devices/devices_page.dart';

import 'helpers/fake_device_gateway.dart';
import 'helpers/l10n.dart';

Widget _app(
  FakeDeviceGateway gateway, {
  FakeTrustStore? store,
  Locale? locale,
}) => ProviderScope(
  overrides: (store ?? FakeTrustStore()).overrides(gateway),
  child: MaterialApp(
    locale: locale,
    localizationsDelegates: testLocalizationsDelegates,
    supportedLocales: testSupportedLocales,
    home: const DevicesPage(),
  ),
);

void main() {
  testWidgets('lists devices with status and a trust summary', (tester) async {
    await tester.pumpWidget(
      _app(
        FakeDeviceGateway([
          const DeviceInfo(
            deviceId: 'ME',
            displayName: 'This phone',
            isThisDevice: true,
            verified: true,
          ),
          const DeviceInfo(
            deviceId: 'OLD',
            displayName: 'Old laptop',
            isThisDevice: false,
            verified: false,
          ),
        ]),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('1 device needs verification.'), findsOneWidget);
    expect(find.text('This phone'), findsOneWidget);
    expect(find.textContaining('This device'), findsOneWidget);
    expect(find.text('Old laptop'), findsOneWidget);
    // Only the unverified other device offers a Verify action.
    expect(find.widgetWithText(TextButton, 'Verify'), findsOneWidget);
  });

  testWidgets('verifying shows the emoji SAS and marks the device verified', (
    tester,
  ) async {
    final gateway = FakeDeviceGateway([
      const DeviceInfo(deviceId: 'ME', isThisDevice: true, verified: true),
      const DeviceInfo(
        deviceId: 'OLD',
        displayName: 'Old laptop',
        isThisDevice: false,
        verified: false,
      ),
    ]);
    await tester.pumpWidget(_app(gateway));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, 'Verify'));
    await tester.pumpAndSettle();

    // SAS emojis shown.
    expect(find.text('🐶'), findsOneWidget);
    expect(find.text('Dog'), findsOneWidget);
    expect(find.text('They match'), findsOneWidget);

    await tester.tap(find.text('They match'));
    await tester.pumpAndSettle();

    expect(find.text('Device verified.'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Done'));
    await tester.pumpAndSettle();

    // List refreshed: the device is now verified, no Verify button left.
    expect(find.widgetWithText(TextButton, 'Verify'), findsNothing);
    expect(find.text('All your devices are verified.'), findsOneWidget);
  });

  testWidgets('"they don\'t match" cancels without verifying', (tester) async {
    final gateway = FakeDeviceGateway([
      const DeviceInfo(deviceId: 'ME', isThisDevice: true, verified: true),
      const DeviceInfo(deviceId: 'OLD', isThisDevice: false, verified: false),
    ]);
    await tester.pumpWidget(_app(gateway));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, 'Verify'));
    await tester.pumpAndSettle();
    await tester.tap(find.text("They don't match"));
    await tester.pumpAndSettle();

    // Still unverified.
    expect(find.widgetWithText(TextButton, 'Verify'), findsOneWidget);
  });

  testWidgets('G36: the SAS emoji names follow the UI language', (
    tester,
  ) async {
    final gateway = FakeDeviceGateway([
      const DeviceInfo(deviceId: 'ME', isThisDevice: true, verified: true),
      const DeviceInfo(deviceId: 'OLD', isThisDevice: false, verified: false),
    ]);
    await tester.pumpWidget(_app(gateway, locale: const Locale('de')));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, 'Verifizieren'));
    await tester.pumpAndSettle();

    expect(find.text('🐶'), findsOneWidget);
    expect(find.text('Hund'), findsOneWidget);
    expect(find.text('Katze'), findsOneWidget);
    expect(find.text('Löwe'), findsOneWidget);
    expect(find.text('Dog'), findsNothing);
  });
}
