import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_vodozemac/flutter_vodozemac.dart' as vod;
import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
  runApp(const ProviderScope(child: App()));
}
