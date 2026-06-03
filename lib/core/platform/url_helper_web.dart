import 'package:web/web.dart' as web;

void navigateTo(String url) {
  web.window.location.href = url;
}

/// On web, "launching" the SSO URL is a same-tab redirect — the callback comes
/// back as page query params (see [currentUrlParams]), not a new tab.
Future<void> launchExternalUrl(String url) async => navigateTo(url);

/// Web receives the SSO callback via page query params, not deep links.
Stream<Uri> incomingSsoLinks() => const Stream.empty();

Map<String, String> get currentUrlParams =>
    Uri.parse(web.window.location.href).queryParameters;

void clearUrlParams() {
  // Replace URL without the query string so the token isn't reused on reload
  web.window.history.replaceState(null, '', web.window.location.pathname);
}
