/// G24: inbound to-device payloads that arrive while no sync component listens
/// (app start, account-DB switch) are buffered and replayed — never dropped.
library;


import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/matrix/buffered_inbox.dart';
import 'package:money_ledger/core/matrix/ledger_transport.dart';

TransportMessage msg(String id) => TransportMessage(
    senderId: '@bob:y.org', type: expenseEventType, content: {'id': id});

List<String> ids(List<TransportMessage> l) =>
    [for (final m in l) m.content['id'] as String];

Future<void> drain() => Future<void>.delayed(const Duration(milliseconds: 5));

void main() {
  test('live messages pass straight through while someone listens', () async {
    final inbox = BufferedInbox(replayDelay: Duration.zero);
    final got = <TransportMessage>[];
    inbox.stream.listen(got.add);
    inbox.add(msg('a'));
    inbox.add(msg('b'));
    await drain();
    expect(ids(got), ['a', 'b']);
    expect(inbox.pending, 0);
  });

  test('messages before the first listener are replayed to every listener '
      'that attaches in the same start-up turn', () async {
    final inbox = BufferedInbox(replayDelay: Duration.zero);
    inbox.add(msg('a'));
    inbox.add(msg('b'));
    expect(inbox.pending, 2);

    final syncer = <TransportMessage>[];
    final engine = <TransportMessage>[];
    inbox.stream.listen(syncer.add);
    inbox.stream.listen(engine.add);
    // A live message arriving while the replay is pending queues behind it.
    inbox.add(msg('c'));
    await drain();

    expect(ids(syncer), ['a', 'b', 'c']);
    expect(ids(engine), ['a', 'b', 'c']);
    expect(inbox.pending, 0);
  });

  test('messages while all listeners are gone (account switch) are kept for '
      'the next listeners', () async {
    final inbox = BufferedInbox(replayDelay: Duration.zero);
    final old = <TransportMessage>[];
    final sub = inbox.stream.listen(old.add);
    inbox.add(msg('a'));
    await drain();
    await sub.cancel();

    inbox.add(msg('b')); // nobody listening
    final next = <TransportMessage>[];
    inbox.stream.listen(next.add);
    await drain();

    expect(ids(old), ['a']);
    expect(ids(next), ['b']);
  });

  test('the backlog is bounded: oldest messages are dropped', () async {
    final inbox = BufferedInbox(capacity: 3, replayDelay: Duration.zero);
    for (final id in ['a', 'b', 'c', 'd', 'e']) {
      inbox.add(msg(id));
    }
    expect(inbox.pending, 3);
    final got = <TransportMessage>[];
    inbox.stream.listen(got.add);
    await drain();
    expect(ids(got), ['c', 'd', 'e']);
  });

  test('a backlog received for another account is discarded on replay',
      () async {
    var account = '@alice:x.org';
    final inbox = BufferedInbox(
        replayDelay: Duration.zero, currentRecipient: () => account);
    inbox.add(msg('for-alice'));
    account = '@carol:x.org'; // account switch while nobody listened
    inbox.add(msg('for-carol'));

    final got = <TransportMessage>[];
    inbox.stream.listen(got.add);
    await drain();
    expect(ids(got), ['for-carol']);
  });

  test('replay waits for the delay so late-attaching listeners get it too',
      () async {
    final inbox =
        BufferedInbox(replayDelay: const Duration(milliseconds: 20));
    inbox.add(msg('a'));
    final first = <TransportMessage>[];
    inbox.stream.listen(first.add);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    final second = <TransportMessage>[];
    inbox.stream.listen(second.add);
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(ids(first), ['a']);
    expect(ids(second), ['a']);
  });
}
