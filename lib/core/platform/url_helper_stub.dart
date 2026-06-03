// Non-web (native + VM) implementation.
import 'package:app_links/app_links.dart';
import 'package:url_launcher/url_launcher.dart';

void navigateTo(String url) {}

Map<String, String> get currentUrlParams => {};

void clearUrlParams() {}

/// Opens [url] in the system browser so the user can complete SSO; the result
/// returns to the app via the `moneyledger://sso-callback` deep link
/// ([incomingSsoLinks]).
Future<void> launchExternalUrl(String url) async {
  await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
}

/// Incoming deep links (the SSO callback). Lazily creates [AppLinks] only when
/// listened, so widget tests that override the SSO-callback provider never
/// touch the platform plugin.
Stream<Uri> incomingSsoLinks() => AppLinks().uriLinkStream;
