/// G36: queued `resync_request`s (an offline device gets them all at once —
/// a new device's request + its G30 retries) are answered with **one**
/// bootstrap per (requesting device, scope/group) within a window, not one
/// each.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/matrix/ledger_transport.dart';
import 'package:money_ledger/core/matrix/transport_provider.dart';
import 'package:money_ledger/core/sync/ledger_payloads.dart';
import 'package:money_ledger/core/sync/sync_engine.dart';
import 'package:money_ledger/features/expenses/expenses_provider.dart';
import 'package:money_ledger/features/expenses/ledger_syncer.dart';
import 'package:money_ledger/features/groups/group_provider.dart';

import '../helpers/fake_ledger_network.dart';
import '../helpers/in_memory_database.dart';

const _alice = '@alice:x.org';
const _bob = '@bob:x.org';

void main() {
  ProviderContainer makeDevice(
    FakeMatrixNetwork net,
    String userId, {
    String device = 'D1',
    Duration window = const Duration(seconds: 60),
  }) {
    final db = openTestDatabase();
    net.clientFor(userId, device: device);
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        ledgerTransportProvider.overrideWith(
          (ref) => net.clientFor(userId, device: device),
        ),
        pokeDebounceProvider.overrideWithValue(const Duration(milliseconds: 1)),
        syncIntervalProvider.overrideWithValue(const Duration(hours: 1)),
        resyncAnswerWindowProvider.overrideWithValue(window),
      ],
    );
    addTearDown(() {
      container.dispose();
      db.close();
    });
    container.listen(ledgerSyncerProvider, (_, _) {});
    container.listen(syncEngineProvider, (_, _) {});
    return container;
  }

  Future<String> createGroup(FakeMatrixNetwork net, ProviderContainer c) async {
    await net.settle();
    await c.read(groupCreatorProvider.notifier).create('Trip', 'EUR');
    await net.settle();
    return (await c.read(groupsDaoProvider).getAllGroups()).single.roomId;
  }

  int bootstrapsTo(FakeMatrixNetwork net, String target) => net.sent
      .where((s) => s.type == bootstrapEventType && s.targets.contains(target))
      .length;

  test('four queued scope:all requests from one device → one answer', () async {
    final net = FakeMatrixNetwork();
    final d1 = makeDevice(net, _alice);
    await createGroup(net, d1);
    // A second device of Alice's that is only a transport (no engine): its
    // request + three retries reach D1 back to back.
    final d2 = net.clientFor(_alice, device: 'D2');
    for (var i = 0; i < 4; i++) {
      await d2.sendToUsers(
        {_alice},
        resyncRequestEventType,
        {'v': protocolVersion, 'scope': 'all'},
      );
    }
    await net.settle();
    expect(bootstrapsTo(net, _alice), 1);

    // Another new device of the same account gets its own answer.
    final d3 = net.clientFor(_alice, device: 'D3');
    await d3.sendToUsers(
      {_alice},
      resyncRequestEventType,
      {'v': protocolVersion, 'scope': 'all'},
    );
    await net.settle();
    expect(bootstrapsTo(net, _alice), 2);
  });

  test('scope:group requests dedupe per (device, group)', () async {
    final net = FakeMatrixNetwork();
    final alice = makeDevice(net, _alice);
    final groupId = await createGroup(net, alice);
    final bobTransport = net.clientFor(_bob);
    await alice.read(memberAdderProvider.notifier).add(groupId, _bob);
    await net.settle();
    final before = bootstrapsTo(net, _bob);

    for (var i = 0; i < 3; i++) {
      await bobTransport.sendToUsers(
        {_alice},
        resyncRequestEventType,
        {'v': protocolVersion, 'scope': 'group', 'group': groupId},
      );
    }
    await net.settle();
    // One answer, despite the member-add bootstrap a moment ago (different
    // path) — and the three requests collapsed into it.
    expect(bootstrapsTo(net, _bob) - before, 1);
  });

  test('after the window a repeated request is answered again', () async {
    final net = FakeMatrixNetwork();
    final d1 = makeDevice(net, _alice, window: Duration.zero);
    await createGroup(net, d1);
    final d2 = net.clientFor(_alice, device: 'D2');
    for (var i = 0; i < 2; i++) {
      await d2.sendToUsers(
        {_alice},
        resyncRequestEventType,
        {'v': protocolVersion, 'scope': 'all'},
      );
      await net.settle();
    }
    expect(bootstrapsTo(net, _alice), 2);
  });

  test('shouldAnswerResync (pure)', () {
    const w = Duration(seconds: 60);
    expect(SyncEngine.shouldAnswerResync(null, 1000, w), isTrue);
    expect(SyncEngine.shouldAnswerResync(1000, 1000 + 59999, w), isFalse);
    expect(SyncEngine.shouldAnswerResync(1000, 1000 + 60000, w), isTrue);
  });
}
