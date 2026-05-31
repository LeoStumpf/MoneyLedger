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

String _$matrixClientHash() => r'e3824949e7753fe6c00a6ad46689d306e32f6c66';

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

String _$isLoggedInHash() => r'87eb721750548f7ba985a978bfa786f7db2da9df';

/// Resolves a homeserver URL (with .well-known discovery) and returns its
/// login flows. Input can be a bare domain ("matrix.org"), a URL
/// ("https://matrix.org"), or a Matrix ID ("@user:matrix.org").

@ProviderFor(loginFlows)
final loginFlowsProvider = LoginFlowsFamily._();

/// Resolves a homeserver URL (with .well-known discovery) and returns its
/// login flows. Input can be a bare domain ("matrix.org"), a URL
/// ("https://matrix.org"), or a Matrix ID ("@user:matrix.org").

final class LoginFlowsProvider
    extends
        $FunctionalProvider<
          AsyncValue<LoginFlowsResult>,
          LoginFlowsResult,
          FutureOr<LoginFlowsResult>
        >
    with $FutureModifier<LoginFlowsResult>, $FutureProvider<LoginFlowsResult> {
  /// Resolves a homeserver URL (with .well-known discovery) and returns its
  /// login flows. Input can be a bare domain ("matrix.org"), a URL
  /// ("https://matrix.org"), or a Matrix ID ("@user:matrix.org").
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

String _$loginFlowsHash() => r'9275248a8a2c732ce0c24b20d71d5b5666c41376';

/// Resolves a homeserver URL (with .well-known discovery) and returns its
/// login flows. Input can be a bare domain ("matrix.org"), a URL
/// ("https://matrix.org"), or a Matrix ID ("@user:matrix.org").

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

  /// Resolves a homeserver URL (with .well-known discovery) and returns its
  /// login flows. Input can be a bare domain ("matrix.org"), a URL
  /// ("https://matrix.org"), or a Matrix ID ("@user:matrix.org").

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
        isAutoDispose: true,
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

String _$authNotifierHash() => r'8654b30a27a674d84dd5c4da91f7c99baeac3fe9';

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
