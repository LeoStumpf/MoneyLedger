/// In-memory [AuthGateway] for offline/test login — no real homeserver, no
/// network. Lets login/logout flows and the resulting `isLoggedIn` reactivity
/// be exercised deterministically.
library;

import 'dart:async';

import 'package:money_ledger/core/matrix/auth_gateway.dart';
import 'package:money_ledger/models/login_flows_result.dart';

class FakeAuthGateway implements AuthGateway {
  String? _userId;
  final LoginFlowsResult _flows;

  /// If set, login/loginFlows throw this — for testing failure paths.
  Object? failWith;

  /// If set, [register] throws [RegistrationRequiresWebException] with these
  /// requirements — simulates a CAPTCHA/email/terms homeserver.
  List<String>? registerRequiresWeb;

  final StreamController<bool> _controller = StreamController.broadcast();

  FakeAuthGateway({
    String? initialUserId,
    LoginFlowsResult? flows,
  })  : _userId = initialUserId,
        _flows = flows ??
            const LoginFlowsResult(
              resolvedUrl: 'https://fake.test',
              hasPassword: true,
              hasSso: false,
              ssoProviders: [],
            );

  @override
  bool get isLoggedIn => _userId != null;

  @override
  String? get userId => _userId;

  @override
  Stream<bool> get loginStateChanges => _controller.stream;

  @override
  Future<LoginFlowsResult> loginFlows(String input) async {
    if (failWith != null) throw failWith!;
    return _flows;
  }

  @override
  Future<void> loginWithPassword({
    required String homeserver,
    required String username,
    required String password,
  }) async {
    if (failWith != null) throw failWith!;
    _setUser('@$username:${Uri.parse(homeserver).host}');
  }

  @override
  Future<void> loginWithToken({
    required String homeserver,
    required String token,
  }) async {
    if (failWith != null) throw failWith!;
    _setUser('@token:${Uri.parse(homeserver).host}');
  }

  @override
  Future<void> register({
    required String homeserver,
    required String username,
    required String password,
  }) async {
    if (failWith != null) throw failWith!;
    if (registerRequiresWeb != null) {
      throw RegistrationRequiresWebException(homeserver, registerRequiresWeb!);
    }
    _setUser('@$username:${Uri.parse(homeserver).host}');
  }

  @override
  Future<void> logout() async {
    _userId = null;
    _controller.add(false);
  }

  /// Simulates an **external** session end the app didn't initiate — a remote
  /// logout or token expiry arriving via `client.onLoginStateChanged` — without
  /// anyone calling [logout].
  void simulateRemoteLogout() {
    _userId = null;
    _controller.add(false);
  }

  void _setUser(String id) {
    _userId = id;
    _controller.add(true);
  }

  void dispose() => _controller.close();
}
