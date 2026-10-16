import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_vodozemac/flutter_vodozemac.dart' as vod;
import 'app.dart';
import 'core/background/background_sync.dart';
import 'core/background/background_wait_app.dart';
import 'core/demo/demo_mode.dart';
import 'core/matrix/crypto_status.dart';
import 'core/demo/demo_overrides.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // G21: MoneyLedger's own license on the in-app licenses page, above the
  // automatically collected package licenses.
  LicenseRegistry.addLicense(
    () => Stream.value(
      const LicenseEntryWithLineBreaks(
        ['MoneyLedger'],
        'MoneyLedger is free software: you can redistribute it and/or modify it '
        'under the terms of the GNU Affero General Public License as published '
        'by the Free Software Foundation, either version 3 of the License, or '
        '(at your option) any later version.\n\n'
        'Source code: https://github.com/LeoStumpf/MoneyLedger',
      ),
    ),
  );
  // G36: the SAS emoji names (EN/DE) come from the Matrix spec (Apache-2.0).
  LicenseRegistry.addLicense(
    () => Stream.value(
      const LicenseEntryWithLineBreaks(
        ['Matrix specification (SAS emoji names)'],
        'SAS emoji descriptions and translations from the Matrix '
        'specification (data-definitions/sas-emoji.json, '
        'https://github.com/matrix-org/matrix-spec).\n\n'
        'Copyright The Matrix.org Foundation C.I.C.\n\n'
        'Licensed under the Apache License, Version 2.0 (the "License"); you '
        'may not use this file except in compliance with the License. You may '
        'obtain a copy of the License at '
        'http://www.apache.org/licenses/LICENSE-2.0\n\n'
        'Unless required by applicable law or agreed to in writing, software '
        'distributed under the License is distributed on an "AS IS" BASIS, '
        'WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or '
        'implied. See the License for the specific language governing '
        'permissions and limitations under the License.',
      ),
    ),
  );
  // G15: offline demo (`--dart-define=OFFLINE_DEMO=true`) — seeded ledger,
  // fake relay + auth; no Matrix client, crypto or background sync at all.
  // A compile-time constant, so a normal build tree-shakes this branch.
  if (kOfflineDemo) {
    runApp(ProviderScope(overrides: demoOverrides(), child: const App()));
    return;
  }
  // G31: take the app's slot before the Matrix store / ledger DB are opened —
  // a periodic background sync round running in this process (Android
  // WorkManager) is asked to stop and close its stores first, so the two
  // never write the same Olm/sync state concurrently — meanwhile a small
  // "Finishing background sync…" screen is shown (G18 review). No-op on web.
  await prepareBackgroundSync(
    onWaiting: () => runApp(const BackgroundSyncWaitApp()),
  );
  // Initialize the vodozemac crypto backend BEFORE any Matrix client is built.
  // The Matrix SDK only enables E2EE when vod.isInitialized() is true (see
  // client.dart), so without this, sendToDeviceEncrypted is a silent no-op.
  // Loads the native library on Android/iOS and the wasm (web/pkg/) on web.
  // Guarded so a crypto-init failure (e.g. a missing web wasm) degrades to
  // encryption-disabled instead of blank-screening the whole app.
  var cryptoAvailable = true;
  try {
    await vod.init();
  } catch (e, st) {
    debugPrint('[crypto] vodozemac init failed; E2EE disabled: $e\n$st');
    cryptoAvailable = false;
  }
  final container = ProviderContainer(
    overrides: [
      // G33: surfaced as a banner on the groups page.
      if (!cryptoAvailable) cryptoAvailableProvider.overrideWithValue(false),
    ],
  );
  // A background round that finds the app alive lets the app sync instead.
  attachForegroundSync(container);
  runApp(UncontrolledProviderScope(container: container, child: const App()));
}
