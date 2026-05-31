import 'package:web/web.dart' as web;

void navigateTo(String url) {
  web.window.location.href = url;
}

Map<String, String> get currentUrlParams =>
    Uri.parse(web.window.location.href).queryParameters;

void clearUrlParams() {
  // Replace URL without the query string so the token isn't reused on reload
  web.window.history.replaceState(null, '', web.window.location.pathname);
}
