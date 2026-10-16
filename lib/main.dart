import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_vodozemac/flutter_vodozemac.dart' as vod;
import 'app.dart';
import 'core/background/background_sync.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // G21: MoneyLedger's own license on the in-app licenses page, above the
  // automatically collected package licenses.
  LicenseRegistry.addLicense(() => Stream.value(const LicenseEntryWithLineBreaks(
      ['MoneyLedger'],
      'MoneyLedger is free software: you can redistribute it and/or modify it '
      'under the terms of the GNU Affero General Public License as published '
      'by the Free Software Foundation, either version 3 of the License, or '
      '(at your option) any later version.\n\n'
      'Source code: https://github.com/LeoStumpf/MoneyLedger')));
  // G31: take the app's slot before the Matrix store / ledger DB are opened —
  // a periodic background sync round running in this process (Android
  // WorkManager) is asked to stop and close its stores first, so the two
  // never write the same Olm/sync state concurrently. No-op on web.
  await prepareBackgroundSync();
  // Initialize the vodozemac crypto backend BEFORE any Matrix client is built.
  // The Matrix SDK only enables E2EE when vod.isInitialized() is true (see
  // client.dart), so without this, sendToDeviceEncrypted is a silent no-op.
  // Loads the native library on Android/iOS and the wasm (web/pkg/) on web.
  // Guarded so a crypto-init failure (e.g. a missing web wasm) degrades to
  // encryption-disabled instead of blank-screening the whole app.
  try {
    await vod.init();
  } catch (e, st) {
    debugPrint('[crypto] vodozemac init failed; E2EE disabled: $e\n$st');
  }
  final container = ProviderContainer();
  // A background round that finds the app alive lets the app sync instead.
  attachForegroundSync(container);
  runApp(UncontrolledProviderScope(container: container, child: const App()));
}
