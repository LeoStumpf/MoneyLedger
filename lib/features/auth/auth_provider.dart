import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../core/matrix/auth_gateway.dart';
import '../../core/matrix/matrix_auth_gateway.dart';
import '../../core/matrix/matrix_ledger_transport.dart';
import '../../core/matrix/matrix_service.dart';
import '../../core/matrix/matrix_sync_watchdog.dart';
import '../../models/login_flows_result.dart';

part 'auth_provider.g.dart';

@Riverpod(keepAlive: true)
Future<Client> matrixClient(Ref ref) async {
  final sw = Stopwatch()..start();
  final Client client;
  try {
    client = await buildMatrixClient();
  } catch (e, st) {
    debugPrint(
      '[client] buildMatrixClient FAILED after '
      '${sw.elapsedMilliseconds}ms: $e\n$st',
    );
    rethrow;
  }
  debugPrint('[client] buildMatrixClient ${sw.elapsedMilliseconds}ms');
  // Attach the ledger transport's inbound listener BEFORE init(): init starts
  // the background /sync, and the SDK's to-device stream isn't buffered — an
  // event emitted before anyone subscribes is lost until the next digest
  // cycle. The transport buffers until LedgerSyncer/SyncEngine attach (G24).
  MatrixLedgerTransport.forClient(client);
  // waitForFirstSync: false — never block app startup on a network sync. With
  // the default (true), init() awaits the first /sync when a session is
  // restored, so a stalled sync hangs the whole provider chain forever (the
  // login screen spins on both the homeserver field and the sign-in button and
  // can't recover across restarts). Drift is the local source of truth and
  // Matrix is background transport, so local data still loads; sync continues
  // in the background after init returns.
  try {
    await client.init(waitForFirstSync: false);
  } catch (e, st) {
    debugPrint(
      '[client] init FAILED after ${sw.elapsedMilliseconds}ms: $e\n$st',
    );
    rethrow;
  }
  debugPrint(
    '[client] init done (logged in: ${client.isLogged()}) '
    '${sw.elapsedMilliseconds}ms',
  );
  // G36: restart a sync loop that stopped, report one that stalls.
  final watchdog = MatrixSyncWatchdog(client)..start();
  ref.onDispose(watchdog.dispose);
  return client;
}

/// Auth seam: the rest of the app drives login/session through this, never the
/// raw Client. Overridden with an in-memory fake for offline/test login.
@Riverpod(keepAlive: true)
Future<AuthGateway> authGateway(Ref ref) async {
  final client = await ref.watch(matrixClientProvider.future);
  return MatrixAuthGateway(client);
}

/// Current login state, kept in sync with the gateway's login/logout stream.
@riverpod
Stream<bool> loginState(Ref ref) async* {
  final gateway = await ref.watch(authGatewayProvider.future);
  yield gateway.isLoggedIn;
  yield* gateway.loginStateChanges;
}

@riverpod
bool isLoggedIn(Ref ref) {
  return ref.watch(loginStateProvider).value ?? false;
}

/// The signed-in account's MXID, or `null` while signed out / still loading.
/// Selects the per-account ledger database (`appDatabaseProvider`), so it only
/// notifies when the account actually changes (Riverpod filters equal values) —
/// re-validating the login state doesn't reopen the DB.
@Riverpod(keepAlive: true)
String? accountUserId(Ref ref) {
  final loggedIn = ref.watch(loginStateProvider).value ?? false;
  if (!loggedIn) return null;
  final id = ref.watch(authGatewayProvider).value?.userId;
  return (id == null || id.isEmpty) ? null : id;
}

/// Resolves a homeserver (with .well-known discovery) and returns its login
/// flows. Input can be a bare domain ("matrix.org"), a URL, or a Matrix ID.
@riverpod
Future<LoginFlowsResult> loginFlows(Ref ref, String input) async {
  final gateway = await ref.watch(authGatewayProvider.future);
  return gateway.loginFlows(input);
}

// keepAlive: a successful login flips isLoggedIn, the router redirects off the
// login page, and the page (this notifier's only listener) is disposed — an
// autoDispose notifier would then crash setting `state` after the await
// ("Cannot use Ref … after it has been disposed"). Auth is app-global state
// anyway, like matrixClient/authGateway.
@Riverpod(keepAlive: true)
class AuthNotifier extends _$AuthNotifier {
  @override
  AsyncValue<void> build() => const AsyncData(null);

  Future<void> login({
    required String resolvedHomeserver,
    required String username,
    required String password,
  }) async {
    state = const AsyncLoading();
    final result = await AsyncValue.guard(() async {
      final gateway = await ref.read(authGatewayProvider.future);
      await gateway.loginWithPassword(
        homeserver: resolvedHomeserver,
        username: username,
        password: password,
      );
    });
    if (!ref.mounted) return;
    state = result;
    _refreshLoginState();
  }

  Future<void> loginWithToken({
    required String resolvedHomeserver,
    required String token,
  }) async {
    state = const AsyncLoading();
    final result = await AsyncValue.guard(() async {
      final gateway = await ref.read(authGatewayProvider.future);
      await gateway.loginWithToken(
        homeserver: resolvedHomeserver,
        token: token,
      );
    });
    if (!ref.mounted) return;
    state = result;
    _refreshLoginState();
  }

  Future<void> register({
    required String resolvedHomeserver,
    required String username,
    required String password,
  }) async {
    state = const AsyncLoading();
    final result = await AsyncValue.guard(() async {
      final gateway = await ref.read(authGatewayProvider.future);
      await gateway.register(
        homeserver: resolvedHomeserver,
        username: username,
        password: password,
      );
    });
    if (!ref.mounted) return;
    state = result;
    _refreshLoginState();
  }

  Future<void> logout() async {
    state = const AsyncLoading();
    final result = await AsyncValue.guard(() async {
      final gateway = await ref.read(authGatewayProvider.future);
      await gateway.logout();
    });
    if (!ref.mounted) return;
    state = result;
    _refreshLoginState();
  }

  /// Recompute [isLoggedInProvider] immediately after a login/logout instead of
  /// waiting for the gateway's async stream — so the router redirect can't read
  /// a stale value (the old `invalidate(matrixClientProvider)` guarantee).
  void _refreshLoginState() {
    if (!state.hasError) ref.invalidate(loginStateProvider);
  }
}
