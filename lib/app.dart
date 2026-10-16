import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/l10n/l10n.dart';
import 'core/router.dart';
import 'core/theme/app_theme.dart';
import 'core/sync/ledger_sync_host.dart';

class App extends ConsumerWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      onGenerateTitle: (context) => context.l10n.appTitle,
      // G12: follows the device locale (EN / DE), falling back to English.
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      // G17: light + dark theme, following the system setting.
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      routerConfig: router,
      // Inbound sync must run on every screen while signed in (incl. onboarding).
      builder: (context, child) =>
          LedgerSyncHost(child: child ?? const SizedBox.shrink()),
    );
  }
}
