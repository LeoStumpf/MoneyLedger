// Non-web (native + VM) implementation.
import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../features/auth/sso_callback.dart';

void navigateTo(String url) {}

Map<String, String> get currentUrlParams => {};

void clearUrlParams() {}

/// Opens [url] in the system browser so the user can complete SSO; the result
/// returns to the app via the `moneyledger://sso-callback` deep link
/// ([incomingSsoLinks]).
Future<void> launchExternalUrl(String url) async {
  debugPrint('[sso] launchExternalUrl: $url');
  await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
}

/// Incoming deep links (the SSO callback). Lazily creates [AppLinks] only when
/// listened, so widget tests that override the SSO-callback provider never
/// touch the platform plugin.
///
/// Emits [getInitialLink] first: when SSO redirects back, a backgrounded app
/// (commonly evicted on low-memory devices while the browser is foreground) is
/// cold-started and the callback arrives as the launch intent, which
/// [uriLinkStream] does NOT replay. Without this the login token is dropped and
/// the user lands back on the login screen with nothing happening.
Stream<Uri> incomingSsoLinks() async* {
  final appLinks = AppLinks();
  final initial = await appLinks.getInitialLink();
  if (initial != null) {
    debugPrint('[sso] initial link: ${redactSsoUri(initial)}');
    yield initial;
  }
  await for (final uri in appLinks.uriLinkStream) {
    // uriLinkStream may also replay the launch link; don't process it twice
    // (SSO login tokens are single-use, so a re-exchange would error).
    if (uri == initial) continue;
    debugPrint('[sso] stream link: ${redactSsoUri(uri)}');
    yield uri;
  }
}
