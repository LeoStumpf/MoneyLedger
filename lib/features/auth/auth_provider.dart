import 'package:matrix/matrix.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../core/matrix/auth_gateway.dart';
import '../../core/matrix/matrix_auth_gateway.dart';
import '../../core/matrix/matrix_service.dart';
import '../../models/login_flows_result.dart';

part 'auth_provider.g.dart';

@Riverpod(keepAlive: true)
Future<Client> matrixClient(Ref ref) async {
  final client = await buildMatrixClient();
  await client.init();
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

/// Resolves a homeserver (with .well-known discovery) and returns its login
/// flows. Input can be a bare domain ("matrix.org"), a URL, or a Matrix ID.
@riverpod
Future<LoginFlowsResult> loginFlows(Ref ref, String input) async {
  final gateway = await ref.watch(authGatewayProvider.future);
  return gateway.loginFlows(input);
}

@riverpod
class AuthNotifier extends _$AuthNotifier {
  @override
  AsyncValue<void> build() => const AsyncData(null);

  Future<void> login({
    required String resolvedHomeserver,
    required String username,
    required String password,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final gateway = await ref.read(authGatewayProvider.future);
      await gateway.loginWithPassword(
        homeserver: resolvedHomeserver,
        username: username,
        password: password,
      );
    });
    _refreshLoginState();
  }

  Future<void> loginWithToken({
    required String resolvedHomeserver,
    required String token,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final gateway = await ref.read(authGatewayProvider.future);
      await gateway.loginWithToken(
        homeserver: resolvedHomeserver,
        token: token,
      );
    });
    _refreshLoginState();
  }

  Future<void> logout() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final gateway = await ref.read(authGatewayProvider.future);
      await gateway.logout();
    });
    _refreshLoginState();
  }

  /// Recompute [isLoggedInProvider] immediately after a login/logout instead of
  /// waiting for the gateway's async stream — so the router redirect can't read
  /// a stale value (the old `invalidate(matrixClientProvider)` guarantee).
  void _refreshLoginState() {
    if (!state.hasError) ref.invalidate(loginStateProvider);
  }
}
