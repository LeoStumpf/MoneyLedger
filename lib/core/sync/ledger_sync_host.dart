import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/auth_provider.dart';
import '../../features/expenses/ledger_syncer.dart';
import '../background/background_sync_provider.dart';
import '../session/local_adoption.dart';
import 'sync_engine.dart';

/// Whether inbound sync (LedgerSyncer) and anti-entropy (SyncEngine) are
/// running. They run for as long as an account is signed in — **app-wide**, not
/// tied to whichever page happens to be on screen.
///
/// The Matrix SDK's to-device stream is not buffered: a payload that arrives
/// while nobody listens is consumed (the sync token advances) and lost until
/// the next digest cycle. Previously only GroupsPage/ExpensesPage kept the
/// syncer alive, so a bootstrap arriving while a freshly signed-in user was on
/// the onboarding screen was silently dropped (found in the G7a real-device
/// test: the invitee never received the group).
final ledgerSyncActiveProvider = Provider.autoDispose<bool>((ref) {
  if (ref.watch(accountUserIdProvider) == null) return false;
  ref.watch(ledgerSyncerProvider);
  ref.watch(syncEngineProvider);
  return true;
});

/// Wraps the whole app (MaterialApp.router `builder`) and keeps
/// [ledgerSyncActiveProvider] alive while signed in.
class LedgerSyncHost extends ConsumerWidget {
  final Widget child;
  const LedgerSyncHost({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(ledgerSyncActiveProvider);
    // G31: keep the Android periodic background sync registered while signed
    // in with it enabled (no-op on other platforms).
    ref.watch(backgroundSyncSchedulingProvider);
    // G40: move a local-mode ledger into the account just connected.
    ref.watch(localLedgerAdoptionProvider);
    return child;
  }
}
