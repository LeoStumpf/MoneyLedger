/// In-memory [AuthGateway] for offline/test login — no real homeserver, no
/// network. Lets login/logout flows and the resulting `isLoggedIn` reactivity
/// be exercised deterministically.
library;

import 'dart:async';

import 'package:money_ledger/core/matrix/auth_gateway.dart';
import 'package:money_ledger/features/auth/auth_errors.dart';
import 'package:money_ledger/models/login_flows_result.dart';

class FakeAuthGateway implements AuthGateway {
  String? _userId;
  final LoginFlowsResult _flows;

  /// If set, login/loginFlows throw this — for testing failure paths.
  Object? failWith;

  /// If set, [register] throws [RegistrationRequiresWebException] with these
  /// blocking UIA stage ids — simulates a CAPTCHA/email/terms homeserver.
  List<String>? registerRequiresWeb;

  /// The sign-up page carried by that [RegistrationRequiresWebException].
  String? registerSignUpUrl;

  final StreamController<bool> _controller = StreamController.broadcast();

  /// G36: when set, the homeserver request of a login / registration waits
  /// for it (a stalled server) — completing it later is a **late success**
  /// (the account signs in, like the SDK would); completing with an error a
  /// late failure.
  Completer<void>? pendingRequest;

  /// G36: the UI timeout applied to that request (like `kAuthRequestTimeout`).
  Duration requestTimeout = kAuthRequestTimeout;

  /// G36: how many homeserver login / registration requests were started.
  int requestsStarted = 0;

  /// G43: every server whose login flows were asked for (each is a
  /// `.well-known` + `/login` request in the real gateway).
  final List<String> loginFlowsRequests = [];

  /// The same single-flight guard as the real gateway.
  final AuthSingleFlight _flight = AuthSingleFlight();

  /// One guarded login / registration: the request (which signs [user] in on
  /// success) may outlive its timeout and still sign in.
  Future<void> _guarded(String user, String step) =>
      _flight.operation(() async {
        if (failWith != null) throw failWith!;
        requestsStarted++;
        final request = (pendingRequest?.future ?? Future<void>.value()).then(
          (_) => _setUser(user),
        );
        await withAuthTimeout(_flight.track(request), requestTimeout, step);
      });

  FakeAuthGateway({String? initialUserId, LoginFlowsResult? flows})
    : _userId = initialUserId,
      _flows =
          flows ??
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
    loginFlowsRequests.add(input);
    if (failWith != null) throw failWith!;
    return _flows;
  }

  @override
  Future<void> loginWithPassword({
    required String homeserver,
    required String username,
    required String password,
  }) => _guarded('@$username:${Uri.parse(homeserver).host}', 'login');

  @override
  Future<void> loginWithToken({
    required String homeserver,
    required String token,
  }) => _guarded('@token:${Uri.parse(homeserver).host}', 'login');

  @override
  Future<void> register({
    required String homeserver,
    required String username,
    required String password,
  }) async {
    if (failWith != null) throw failWith!;
    if (registerRequiresWeb != null) {
      throw RegistrationRequiresWebException(
        homeserver,
        registerRequiresWeb!,
        signUpUrl: registerSignUpUrl,
      );
    }
    await _guarded('@$username:${Uri.parse(homeserver).host}', 'register');
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
