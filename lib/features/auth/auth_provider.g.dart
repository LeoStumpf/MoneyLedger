// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'auth_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(matrixClient)
final matrixClientProvider = MatrixClientProvider._();

final class MatrixClientProvider
    extends $FunctionalProvider<AsyncValue<Client>, Client, FutureOr<Client>>
    with $FutureModifier<Client>, $FutureProvider<Client> {
  MatrixClientProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'matrixClientProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$matrixClientHash();

  @$internal
  @override
  $FutureProviderElement<Client> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<Client> create(Ref ref) {
    return matrixClient(ref);
  }
}

String _$matrixClientHash() => r'b3d60b04531b01c7184e70c2fd40876d969eeba7';

/// Auth seam: the rest of the app drives login/session through this, never the
/// raw Client. Overridden with an in-memory fake for offline/test login.

@ProviderFor(authGateway)
final authGatewayProvider = AuthGatewayProvider._();

/// Auth seam: the rest of the app drives login/session through this, never the
/// raw Client. Overridden with an in-memory fake for offline/test login.

final class AuthGatewayProvider
    extends
        $FunctionalProvider<
          AsyncValue<AuthGateway>,
          AuthGateway,
          FutureOr<AuthGateway>
        >
    with $FutureModifier<AuthGateway>, $FutureProvider<AuthGateway> {
  /// Auth seam: the rest of the app drives login/session through this, never the
  /// raw Client. Overridden with an in-memory fake for offline/test login.
  AuthGatewayProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'authGatewayProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$authGatewayHash();

  @$internal
  @override
  $FutureProviderElement<AuthGateway> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<AuthGateway> create(Ref ref) {
    return authGateway(ref);
  }
}

String _$authGatewayHash() => r'4c9a2869c96a4c1b5a052be97fc03cda14b9875c';

/// Current login state, kept in sync with the gateway's login/logout stream.

@ProviderFor(loginState)
final loginStateProvider = LoginStateProvider._();

/// Current login state, kept in sync with the gateway's login/logout stream.

final class LoginStateProvider
    extends $FunctionalProvider<AsyncValue<bool>, bool, Stream<bool>>
    with $FutureModifier<bool>, $StreamProvider<bool> {
  /// Current login state, kept in sync with the gateway's login/logout stream.
  LoginStateProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'loginStateProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$loginStateHash();

  @$internal
  @override
  $StreamProviderElement<bool> $createElement($ProviderPointer pointer) =>
      $StreamProviderElement(pointer);

  @override
  Stream<bool> create(Ref ref) {
    return loginState(ref);
  }
}

String _$loginStateHash() => r'a35f1701d3d18ac4ab1510bca7539034337afb7b';

@ProviderFor(isLoggedIn)
final isLoggedInProvider = IsLoggedInProvider._();

final class IsLoggedInProvider extends $FunctionalProvider<bool, bool, bool>
    with $Provider<bool> {
  IsLoggedInProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'isLoggedInProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$isLoggedInHash();

  @$internal
  @override
  $ProviderElement<bool> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  bool create(Ref ref) {
    return isLoggedIn(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(bool value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<bool>(value),
    );
  }
}

String _$isLoggedInHash() => r'a517a967b551e17d5537c8bd4aafdd7d7ab8cf9c';

/// Resolves a homeserver (with .well-known discovery) and returns its login
/// flows. Input can be a bare domain ("matrix.org"), a URL, or a Matrix ID.

@ProviderFor(loginFlows)
final loginFlowsProvider = LoginFlowsFamily._();

/// Resolves a homeserver (with .well-known discovery) and returns its login
/// flows. Input can be a bare domain ("matrix.org"), a URL, or a Matrix ID.

final class LoginFlowsProvider
    extends
        $FunctionalProvider<
          AsyncValue<LoginFlowsResult>,
          LoginFlowsResult,
          FutureOr<LoginFlowsResult>
        >
    with $FutureModifier<LoginFlowsResult>, $FutureProvider<LoginFlowsResult> {
  /// Resolves a homeserver (with .well-known discovery) and returns its login
  /// flows. Input can be a bare domain ("matrix.org"), a URL, or a Matrix ID.
  LoginFlowsProvider._({
    required LoginFlowsFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'loginFlowsProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$loginFlowsHash();

  @override
  String toString() {
    return r'loginFlowsProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<LoginFlowsResult> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<LoginFlowsResult> create(Ref ref) {
    final argument = this.argument as String;
    return loginFlows(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is LoginFlowsProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$loginFlowsHash() => r'711269d3d7c142144a5631a1c7d4d51db6cb4b2f';

/// Resolves a homeserver (with .well-known discovery) and returns its login
/// flows. Input can be a bare domain ("matrix.org"), a URL, or a Matrix ID.

final class LoginFlowsFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<LoginFlowsResult>, String> {
  LoginFlowsFamily._()
    : super(
        retry: null,
        name: r'loginFlowsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Resolves a homeserver (with .well-known discovery) and returns its login
  /// flows. Input can be a bare domain ("matrix.org"), a URL, or a Matrix ID.

  LoginFlowsProvider call(String input) =>
      LoginFlowsProvider._(argument: input, from: this);

  @override
  String toString() => r'loginFlowsProvider';
}

@ProviderFor(AuthNotifier)
final authProvider = AuthNotifierProvider._();

final class AuthNotifierProvider
    extends $NotifierProvider<AuthNotifier, AsyncValue<void>> {
  AuthNotifierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'authProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$authNotifierHash();

  @$internal
  @override
  AuthNotifier create() => AuthNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AsyncValue<void> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AsyncValue<void>>(value),
    );
  }
}

String _$authNotifierHash() => r'a55bb96b762cf116a81e72766e2aee4f0bf17779';

abstract class _$AuthNotifier extends $Notifier<AsyncValue<void>> {
  AsyncValue<void> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<AsyncValue<void>, AsyncValue<void>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<void>, AsyncValue<void>>,
              AsyncValue<void>,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
