/// Who is using the app on this device (G39 / G40): nobody yet, a **local
/// profile** ("use without account" — no Matrix at all), or a **Matrix
/// account**. Decides which ledger DB opens, whether a Matrix client is ever
/// built, and where the router sends the user.
///
/// Local mode in one paragraph: the ledger lives in its own device-local DB
/// ([localDatabaseName]); the transport is [LocalOnlyTransport] (nothing is
/// ever sent, nothing can be signed); sync engines and background sync don't
/// start. "Me" works exactly like with an account: this device's identity is
/// the reserved pseudo account [kLocalAccountId] (never a valid MXID — those
/// start with `@`), and the user's own participant in each local group is
/// *claimed* by it, so `currentParticipant` / `claimedBy` need no special
/// case. Connecting a Matrix account later moves the local ledger into that
/// account's DB and re-claims those participants for the new MXID
/// (`local_adoption.dart`).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/auth_provider.dart';
import 'device_prefs.dart';

/// The pseudo account id of local mode — "this device" as the claimant of
/// the user's own participant. Not an MXID (no `@`), so it can never collide
/// with a real account, and every Matrix-only path (replication targets,
/// device lists, invites) is skipped for it.
const kLocalAccountId = 'local:self';

/// Whether [id] is local mode's pseudo account ([kLocalAccountId]).
bool isLocalAccountId(String? id) => id == kLocalAccountId;

/// The device-local ledger DB of local mode. `accountDatabaseName` only ever
/// yields `money_ledger_` + 16 hex digits, so this never collides with an
/// account's DB.
const localDatabaseName = 'money_ledger_local';

/// The local profile, or null when local mode isn't chosen (or still loading).
final localProfileProvider = Provider<LocalProfile?>(
  (ref) => ref.watch(devicePrefsProvider.select((p) => p.value?.localProfile)),
);

/// "Connect a Matrix account" is in progress (G40): login / register pages
/// are shown on top of the still-active local profile.
final connectingAccountProvider = Provider<bool>(
  (ref) => ref.watch(
    devicePrefsProvider.select(
      (p) => (p.value?.connecting ?? false) && p.value?.localProfile != null,
    ),
  ),
);

/// Whether the Matrix session may be consulted at all. False in local mode
/// (unless a connect is in progress) and while the device preferences load —
/// so a local-mode start never builds a Matrix client or opens its store.
final matrixSessionWantedProvider = Provider<bool>((ref) {
  final prefs = ref.watch(devicePrefsProvider).value;
  if (prefs == null) return false;
  return prefs.localProfile == null || prefs.connecting;
});

/// Local mode is active: the local ledger is open and nothing syncs. Ends as
/// soon as a connect's sign-in succeeded (before the preferences are
/// rewritten), so the account's DB opens right away.
final localModeActiveProvider = Provider<bool>((ref) {
  final prefs = ref.watch(devicePrefsProvider).value;
  if (prefs?.localProfile == null) return false;
  if (!prefs!.connecting) return true;
  return ref.watch(accountUserIdProvider) == null;
});

/// Which ledger is open: the signed-in MXID, [kLocalAccountId] in local mode,
/// or null (signed out / loading). `appDatabaseProvider` opens the DB for it.
final ledgerIdentityProvider = Provider<String?>(
  (ref) => ref.watch(localModeActiveProvider)
      ? kLocalAccountId
      : ref.watch(accountUserIdProvider),
);

/// The kind of session the router sees.
enum AppSessionKind {
  /// Device preferences still loading → neutral splash.
  loading,

  /// Nobody: welcome / login / "use without account".
  signedOut,

  /// Local profile (G40).
  local,

  /// Matrix account signed in.
  matrix,
}

final appSessionProvider = Provider<AppSessionKind>((ref) {
  if (!ref.watch(devicePrefsProvider.select((p) => p.hasValue))) {
    return AppSessionKind.loading;
  }
  if (ref.watch(localModeActiveProvider)) return AppSessionKind.local;
  if (ref.watch(isLoggedInProvider)) return AppSessionKind.matrix;
  return AppSessionKind.signedOut;
});

/// The first-open welcome (G39), as the router sees it.
enum WelcomeStatus { unknown, notSeen, seen }

final welcomeStatusProvider = Provider<WelcomeStatus>((ref) {
  final prefs = ref.watch(devicePrefsProvider);
  if (!prefs.hasValue) return WelcomeStatus.unknown;
  return prefs.requireValue.welcomeSeen
      ? WelcomeStatus.seen
      : WelcomeStatus.notSeen;
});
