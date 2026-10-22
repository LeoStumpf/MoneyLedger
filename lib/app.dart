import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/l10n/l10n.dart';
import 'core/router.dart';
import 'core/theme/app_theme.dart';
import 'core/sync/ledger_sync_host.dart';
import 'features/devices/devices_page.dart';
import 'features/link/link_join.dart';
import 'features/notifications/notifications_provider.dart';

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
      builder: (context, child) => LedgerSyncHost(
        // G11: answer device-verification requests on any screen.
        child: IncomingVerificationListener(
          navigatorContext: () =>
              router.routerDelegate.navigatorKey.currentContext,
          // G52 step 7: an opened invite link → the join page.
          child: JoinLinkListener(
            go: router.go,
            // G72: a tapped change notification opens its group.
            child: NotificationTapListener(
              go: router.go,
              location: () =>
                  router.routerDelegate.currentConfiguration.uri.path,
              locationChanges: router.routerDelegate,
              child: child ?? const SizedBox.shrink(),
            ),
          ),
        ),
      ),
    );
  }
}
