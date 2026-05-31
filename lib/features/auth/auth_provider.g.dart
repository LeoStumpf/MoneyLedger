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

/// Fetches the login flows supported by a homeserver.
/// Uses a lightweight API client so it works before the main client is ready.

@ProviderFor(loginFlows)
final loginFlowsProvider = LoginFlowsFamily._();

/// Fetches the login flows supported by a homeserver.
/// Uses a lightweight API client so it works before the main client is ready.

final class LoginFlowsProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<LoginFlow>>,
          List<LoginFlow>,
          FutureOr<List<LoginFlow>>
        >
    with $FutureModifier<List<LoginFlow>>, $FutureProvider<List<LoginFlow>> {
  /// Fetches the login flows supported by a homeserver.
  /// Uses a lightweight API client so it works before the main client is ready.
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
  $FutureProviderElement<List<LoginFlow>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<LoginFlow>> create(Ref ref) {
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

String _$loginFlowsHash() => r'87cdcb5ce360b4fa974712a14c949a42152cb072';

/// Fetches the login flows supported by a homeserver.
/// Uses a lightweight API client so it works before the main client is ready.

final class LoginFlowsFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<List<LoginFlow>>, String> {
  LoginFlowsFamily._()
    : super(
        retry: null,
        name: r'loginFlowsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Fetches the login flows supported by a homeserver.
  /// Uses a lightweight API client so it works before the main client is ready.

  LoginFlowsProvider call(String homeserver) =>
      LoginFlowsProvider._(argument: homeserver, from: this);

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

String _$authNotifierHash() => r'66c932cd160b10d5107cbf4dc8747f4280779124';

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
