import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/router.dart';
import 'core/sync/ledger_sync_host.dart';

class App extends ConsumerWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'MoneyLedger',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      routerConfig: router,
      // Inbound sync must run on every screen while signed in (incl. onboarding).
      builder: (context, child) =>
          LedgerSyncHost(child: child ?? const SizedBox.shrink()),
    );
  }
}
