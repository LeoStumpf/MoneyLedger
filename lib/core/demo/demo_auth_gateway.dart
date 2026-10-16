import 'dart:async';

import '../../models/login_flows_result.dart';
import '../matrix/auth_gateway.dart';
import '../../features/auth/register_flows.dart' show kWebSignupStage;
import 'demo_mode.dart';

/// Offline [AuthGateway] for the demo: starts signed in as [kDemoUserId];
/// any password / token login signs back in as the same demo user (so the
/// seeded ledger is always the one shown). Registration is not offered.
class DemoAuthGateway implements AuthGateway {
  String? _userId = kDemoUserId;
  final _changes = StreamController<bool>.broadcast();

  static const _flows = LoginFlowsResult(
    resolvedUrl: 'https://example.org',
    hasPassword: true,
    hasSso: false,
    ssoProviders: [],
  );

  @override
  bool get isLoggedIn => _userId != null;

  @override
  String? get userId => _userId;

  @override
  Stream<bool> get loginStateChanges => _changes.stream;

  @override
  Future<LoginFlowsResult> loginFlows(String input) async => _flows;

  @override
  Future<void> loginWithPassword({
    required String homeserver,
    required String username,
    required String password,
  }) async => _signIn();

  @override
  Future<void> loginWithToken({
    required String homeserver,
    required String token,
  }) async => _signIn();

  @override
  Future<void> register({
    required String homeserver,
    required String username,
    required String password,
  }) async => throw RegistrationRequiresWebException(homeserver, const [
    kWebSignupStage,
  ]);

  @override
  Future<void> logout() async {
    _userId = null;
    _changes.add(false);
  }

  void _signIn() {
    _userId = kDemoUserId;
    _changes.add(true);
  }
}
