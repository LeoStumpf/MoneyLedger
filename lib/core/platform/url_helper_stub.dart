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

/// Every deep link opened into the app (the SSO callback, G52 invite
/// links). Lazily creates [AppLinks] only when listened, so widget tests
/// that override the link providers never touch the platform plugin.
///
/// Emits [AppLinks.getInitialLink] first: when SSO redirects back, a
/// backgrounded app (commonly evicted on low-memory devices while the
/// browser is foreground) is cold-started and the callback arrives as the
/// launch intent, which [AppLinks.uriLinkStream] does not reliably replay
/// — same for an invite link that starts the app. The stream replays the
/// launch link once (to the first listener); that **one** replay is skipped
/// (SSO login tokens are single-use), a later identical link — the same
/// invite link tapped again — is not. Nothing is logged here: the links
/// carry secrets (login tokens, invite-link keys).
Stream<Uri> incomingAppLinks() async* {
  final appLinks = AppLinks();
  final initial = await appLinks.getInitialLink();
  if (initial != null) yield initial;
  var replaySkipped = initial == null;
  await for (final uri in appLinks.uriLinkStream) {
    if (!replaySkipped && uri == initial) {
      replaySkipped = true;
      continue;
    }
    yield uri;
  }
}

/// Incoming SSO callback deep links ([incomingAppLinks] without the G52
/// invite links, which `link_join.dart` reads).
Stream<Uri> incomingSsoLinks() => incomingAppLinks()
    .where((uri) => uri.host.toLowerCase() == 'sso-callback')
    .map((uri) {
      debugPrint('[sso] link: ${redactSsoUri(uri)}');
      return uri;
    });
