/// Pure classification of a homeserver's registration UIA flows — decides
/// whether MoneyLedger can complete sign-up in-app or must defer to the web.
/// No platform/Matrix imports, so it is unit-testable (mirrors `sso_url.dart`).
library;

import '../../l10n/app_localizations.dart';

/// Stages the app can satisfy on its own, with no extra user interaction beyond
/// the username/password already collected. (`m.login.dummy` is a no-op stage
/// that open-registration servers offer.)
const _autoStages = {'m.login.dummy'};

/// The outcome of inspecting a server's registration flows.
class RegistrationPlan {
  /// True when the server offers at least one flow whose stages are all
  /// auto-satisfiable — i.e. we can register the user in-app.
  final bool canRegisterInApp;

  /// When [canRegisterInApp] is false, the blocking stage ids of the
  /// *easiest* flow the server offers (e.g. `['m.login.recaptcha',
  /// 'm.login.terms']`) — the UI labels them via [registrationRequirementLabel]
  /// to tell the user why they must register on the web.
  final List<String> blockingStages;

  const RegistrationPlan({
    required this.canRegisterInApp,
    this.blockingStages = const [],
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
    blockingStages: easiest ?? const <String>[],
  );
}

/// Pseudo stage id used when the server refuses client registration outright
/// (see [isClientRegistrationDisabled]) — labelled "signing up on its own
/// website".
const kWebSignupStage = 'moneyledger.web_signup';

/// True when a `/register` attempt was refused without a UIA challenge because
/// the server disabled client-side registration (`M_FORBIDDEN`, no flows) —
/// e.g. matrix.org, which moved sign-up to its OIDC account portal (MAS). The
/// user must sign up on the web, so this maps to the web fallback rather than a
/// raw error. Other errors (`M_USER_IN_USE`, `M_INVALID_USERNAME`, …) don't.
bool isClientRegistrationDisabled(String? errcode, {required bool hasFlows}) =>
    !hasFlows && errcode == 'M_FORBIDDEN';

/// A friendly, localized label for a registration UIA stage id (unknown
/// stages fall back to their raw id).
String registrationRequirementLabel(String stage, AppLocalizations l) {
  switch (stage) {
    case 'm.login.recaptcha':
      return l.regReqCaptcha;
    case 'm.login.email.identity':
      return l.regReqEmail;
    case 'm.login.msisdn':
      return l.regReqPhone;
    case 'm.login.terms':
      return l.regReqTerms;
    case 'm.login.registration_token':
      return l.regReqToken;
    case kWebSignupStage:
      return l.regReqWebSignup;
    default:
      return stage;
  }
}
