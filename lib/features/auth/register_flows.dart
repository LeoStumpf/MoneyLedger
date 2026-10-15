/// Pure classification of a homeserver's registration UIA flows — decides
/// whether MoneyLedger can complete sign-up in-app or must defer to the web.
/// No platform/Matrix imports, so it is unit-testable (mirrors `sso_url.dart`).
library;

/// Stages the app can satisfy on its own, with no extra user interaction beyond
/// the username/password already collected. (`m.login.dummy` is a no-op stage
/// that open-registration servers offer.)
const _autoStages = {'m.login.dummy'};

/// The outcome of inspecting a server's registration flows.
class RegistrationPlan {
  /// True when the server offers at least one flow whose stages are all
  /// auto-satisfiable — i.e. we can register the user in-app.
  final bool canRegisterInApp;

  /// When [canRegisterInApp] is false, the human-readable requirements of the
  /// *easiest* flow the server offers (e.g. `['a CAPTCHA', 'accepting the terms
  /// of service']`) — used to tell the user why they must register on the web.
  final List<String> blockingRequirements;

  const RegistrationPlan({
    required this.canRegisterInApp,
    this.blockingRequirements = const [],
  });
}

/// Classifies the server's [flows] (each a list of stage ids that must all be
/// completed). In-app registration is possible iff some flow needs only
/// auto-satisfiable stages; otherwise we report the least-demanding flow's
/// blocking requirements so the UI can explain the web fallback.
RegistrationPlan classifyRegistrationFlows(List<List<String>> flows) {
  for (final f in flows) {
    if (f.every(_autoStages.contains)) {
      return const RegistrationPlan(canRegisterInApp: true);
    }
  }
  List<String>? easiest;
  for (final f in flows) {
    final blocking = f.where((s) => !_autoStages.contains(s)).toList();
    if (easiest == null || blocking.length < easiest.length) easiest = blocking;
  }
  return RegistrationPlan(
    canRegisterInApp: false,
    blockingRequirements: [
      for (final s in easiest ?? const <String>[]) registrationRequirementLabel(s)
    ],
  );
}

/// Requirement label shown when the server refuses client registration
/// outright (see [isClientRegistrationDisabled]).
const kWebSignupRequirement = 'signing up on its own website';

/// True when a `/register` attempt was refused without a UIA challenge because
/// the server disabled client-side registration (`M_FORBIDDEN`, no flows) —
/// e.g. matrix.org, which moved sign-up to its OIDC account portal (MAS). The
/// user must sign up on the web, so this maps to the web fallback rather than a
/// raw error. Other errors (`M_USER_IN_USE`, `M_INVALID_USERNAME`, …) don't.
bool isClientRegistrationDisabled(String? errcode, {required bool hasFlows}) =>
    !hasFlows && errcode == 'M_FORBIDDEN';

/// A friendly label for a registration UIA stage id.
String registrationRequirementLabel(String stage) {
  switch (stage) {
    case 'm.login.recaptcha':
      return 'a CAPTCHA';
    case 'm.login.email.identity':
      return 'email verification';
    case 'm.login.msisdn':
      return 'phone verification';
    case 'm.login.terms':
      return 'accepting the terms of service';
    case 'm.login.registration_token':
      return 'a registration token';
    default:
      return stage;
  }
}
