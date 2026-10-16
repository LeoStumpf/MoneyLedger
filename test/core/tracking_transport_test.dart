/// G33 (G15 follow-up): the background round's quiet-window logic —
/// `TrackingTransport.quiet` completes only once no send is in flight and
/// nothing moved for the whole period since the call, or at the deadline.
library;

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/background/background_round.dart';
import 'package:money_ledger/core/matrix/ledger_transport.dart';

/// Inner transport: sends complete when the test says so; inbound payloads
/// are pushed through [inbound].
class _Inner implements LedgerTransport {
  final inbound = StreamController<TransportMessage>.broadcast();
  final pending = <Completer<SendResult>>[];

  @override
  String get userId => '@me:x.org';

  @override
  Stream<TransportMessage> get onMessage => inbound.stream;

  @override
  Future<SendResult> sendToUsers(
    Set<String> userIds,
    String type,
    Map<String, dynamic> content, {
    DeliveryPolicy policy = DeliveryPolicy.everyone,
  }) {
    final c = Completer<SendResult>();
    pending.add(c);
    return c.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  const period = Duration(seconds: 2);
  final t0 = DateTime(2026, 10, 16, 12);

  /// Runs [body] under a fake clock that also drives the transport's `now`.
  void withClock(
    void Function(FakeAsync async, TrackingTransport t, _Inner i) body,
  ) {
    fakeAsync((async) {
      final inner = _Inner();
      final t = TrackingTransport(inner, now: () => t0.add(async.elapsed));
      body(async, t, inner);
    });
  }

  test('no traffic: quiet after exactly the period since the call', () {
    withClock((async, t, _) {
      // Old activity (before the call) doesn't shorten the wait.
      async.elapse(const Duration(seconds: 10));
      var done = false;
      t
          .quiet(period, deadline: t0.add(const Duration(minutes: 1)))
          .then((_) => done = true);
      async.elapse(const Duration(milliseconds: 1900));
      expect(done, isFalse);
      async.elapse(const Duration(milliseconds: 200));
      expect(done, isTrue);
    });
  });

  test('an inbound payload restarts the window', () {
    withClock((async, t, inner) {
      var done = false;
      final sub = t.onMessage.listen((_) {});
      t
          .quiet(period, deadline: t0.add(const Duration(minutes: 1)))
          .then((_) => done = true);
      async.elapse(const Duration(milliseconds: 1500));
      inner.inbound.add(
        const TransportMessage(senderId: '@a:x', type: 't', content: {}),
      );
      async.elapse(const Duration(milliseconds: 1500));
      expect(done, isFalse, reason: 'only 1.5 s since the payload');
      async.elapse(const Duration(milliseconds: 600));
      expect(done, isTrue);
      expect(t.received, 1);
      sub.cancel();
    });
  });

  test('a send in flight keeps it busy, however long it takes', () {
    withClock((async, t, inner) {
      var done = false;
      t.sendToUsers({'@b:x'}, 't', const {});
      t
          .quiet(period, deadline: t0.add(const Duration(minutes: 1)))
          .then((_) => done = true);
      async.elapse(const Duration(seconds: 10));
      expect(done, isFalse);
      inner.pending.single.complete(SendResult.nothingToSend);
      async.elapse(const Duration(milliseconds: 1900));
      expect(done, isFalse, reason: 'the send ending counts as activity');
      async.elapse(const Duration(milliseconds: 200));
      expect(done, isTrue);
      expect(t.sent, 1);
    });
  });

  test('gives up at the deadline even while busy', () {
    withClock((async, t, _) {
      var done = false;
      t.sendToUsers({'@b:x'}, 't', const {}); // never completes
      t
          .quiet(period, deadline: t0.add(const Duration(seconds: 5)))
          .then((_) => done = true);
      async.elapse(const Duration(milliseconds: 4900));
      expect(done, isFalse);
      async.elapse(const Duration(milliseconds: 200));
      expect(done, isTrue);
    });
  });
}
