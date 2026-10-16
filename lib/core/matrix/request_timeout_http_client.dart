import 'dart:async';

import 'package:http/http.dart' as http;

/// G36: every homeserver request must at least **start answering** (response
/// headers) within [timeout]. The Matrix SDK wraps its client in a
/// `FixedTimeoutHttpClient` (35 s) that only times the response *body* — a
/// request written to a socket that died in a network switch (wifi ↔ mobile)
/// waits for headers until the OS gives up (minutes), and when that request
/// sits inside a sync round (to-device queue, key queries) the whole sync loop
/// stalls. Generous on purpose: the `/sync` long-poll legitimately takes ~30 s.
class RequestTimeoutHttpClient extends http.BaseClient {
  RequestTimeoutHttpClient(this._inner, {this.timeout = kHttpHeaderTimeout});

  final http.Client _inner;
  final Duration timeout;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) => _inner
      .send(request)
      .timeout(
        timeout,
        onTimeout: () => throw TimeoutException(
          'No response to ${request.method} ${request.url.path} '
          'within ${timeout.inSeconds} s',
          timeout,
        ),
      );

  @override
  void close() => _inner.close();
}

/// G36: the header timeout of [RequestTimeoutHttpClient].
const kHttpHeaderTimeout = Duration(seconds: 90);
