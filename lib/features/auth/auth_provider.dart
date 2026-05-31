import 'package:matrix/matrix.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../core/matrix/matrix_service.dart';

part 'auth_provider.g.dart';

@Riverpod(keepAlive: true)
Future<Client> matrixClient(Ref ref) async {
  final client = await buildMatrixClient();
  await client.init();
  return client;
}

@riverpod
bool isLoggedIn(Ref ref) {
  final clientAsync = ref.watch(matrixClientProvider);
  return clientAsync.value?.isLoggedIn ?? false;
}

/// Fetches the login flows supported by a homeserver.
/// Uses a lightweight API client so it works before the main client is ready.
@riverpod
Future<List<LoginFlow>> loginFlows(Ref ref, String homeserver) async {
  if (homeserver.isEmpty) return [];
  try {
    // Use the MatrixApi directly — no database or session needed.
    final api = MatrixApi(homeserver: Uri.parse(homeserver));
    final flows = await api.getLoginFlows();
    api.httpClient.close();
    return flows ?? [];
  } catch (_) {
    return [];
  }
}

@riverpod
class AuthNotifier extends _$AuthNotifier {
  @override
  AsyncValue<void> build() => const AsyncData(null);

  Future<void> login({
    required String homeserver,
    required String username,
    required String password,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final client = await ref.read(matrixClientProvider.future);
      await client.checkHomeserver(Uri.parse(homeserver));
      await client.login(
        AuthenticationTypes.password,
        identifier: AuthenticationUserIdentifier(user: username),
        password: password,
        initialDeviceDisplayName: 'MoneyLedger',
      );
      ref.invalidate(matrixClientProvider);
    });
  }

  /// Completes an SSO flow by exchanging the one-time login token the
  /// homeserver passed back in the redirect URL.
  Future<void> loginWithToken({
    required String homeserver,
    required String token,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final client = await ref.read(matrixClientProvider.future);
      await client.checkHomeserver(Uri.parse(homeserver));
      await client.login(
        AuthenticationTypes.token,
        token: token,
        initialDeviceDisplayName: 'MoneyLedger',
      );
      ref.invalidate(matrixClientProvider);
    });
  }

  Future<void> logout() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final client = await ref.read(matrixClientProvider.future);
      await client.logout();
      ref.invalidate(matrixClientProvider);
    });
  }
}
