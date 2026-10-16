/// G36: sync-loop watchdog policy + the request (header) timeout that bounds
/// a request hanging on a socket that died in a network switch.
library;

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:money_ledger/core/matrix/request_timeout_http_client.dart';
import 'package:money_ledger/core/sync/sync_watchdog_policy.dart';

void main() {
  group('syncWatchdogDecision', () {
    const t = 1000000;
    SyncWatchdogAction decide({
      int? last = t,
      int now = t,
      bool loggedIn = true,
      bool wanted = true,
      bool pending = true,
    }) => syncWatchdogDecision(
      now: now,
      lastProgressAt: last,
      loggedIn: loggedIn,
      backgroundSyncWanted: wanted,
      syncPending: pending,
    );

    test('a healthy loop needs nothing', () {
      expect(decide(now: t + 30000), SyncWatchdogAction.none);
      expect(decide(last: null, now: t + 600000), SyncWatchdogAction.none);
    });

    test('signed in but no round running → restart the loop', () {
      expect(decide(pending: false), SyncWatchdogAction.restartLoop);
    });

    test('a round pending without progress for 2 min → stall reported', () {
      final stall = kSyncStallAfter.inMilliseconds;
      expect(decide(now: t + stall - 1), SyncWatchdogAction.none);
      expect(decide(now: t + stall), SyncWatchdogAction.reportStall);
    });

    test('signed out / sync not wanted → nothing', () {
      expect(decide(loggedIn: false, pending: false), SyncWatchdogAction.none);
      expect(decide(wanted: false, pending: false), SyncWatchdogAction.none);
    });
  });

  group('RequestTimeoutHttpClient', () {
    test('a request without response headers fails after the timeout', () {
      fakeAsync((async) {
        final never = Completer<http.StreamedResponse>();
        final client = RequestTimeoutHttpClient(
          MockClient.streaming((_, _) => never.future),
          timeout: const Duration(seconds: 90),
        );
        Object? error;
        unawaited(
          client
              .send(
                http.Request(
                  'GET',
                  Uri.parse('https://hs.test/_matrix/client/v3/keys/query'),
                ),
              )
              .then<void>((_) {})
              .catchError((Object e) {
                error = e;
              }),
        );
        async.elapse(const Duration(seconds: 89));
        expect(error, isNull);
        async.elapse(const Duration(seconds: 2));
        expect(error, isA<TimeoutException>());
        expect(error.toString(), contains('/keys/query'));
      });
    });

    test('a normal response passes through', () async {
      final client = RequestTimeoutHttpClient(
        MockClient((_) async => http.Response('{"ok":true}', 200)),
      );
      final r = await client.get(Uri.parse('https://hs.test/x'));
      expect(r.statusCode, 200);
      expect(r.body, '{"ok":true}');
    });
  });
}
