/// G23 regression: the group mutators (GroupCreator / MemberAdder /
/// MemberRemover / GroupExiter) capture every dependency before their first
/// await. A mutation whose auto-dispose notifier is disposed mid-flight (the
/// page that triggered it was popped) must still complete its writes and
/// sends, and never touch the disposed `ref` or set state on it.
library;

import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/database/app_database.dart';
import 'package:money_ledger/core/matrix/ledger_transport.dart';
import 'package:money_ledger/core/matrix/transport_provider.dart';
import 'package:money_ledger/features/expenses/expenses_provider.dart';
import 'package:money_ledger/features/groups/group_provider.dart';

import '../helpers/fake_ledger_network.dart';
import '../helpers/in_memory_database.dart';
import '../helpers/eventually.dart';

const alice = '@alice:x.org';
const bob = '@bob:y.org';

void main() {
  late FakeMatrixNetwork net;
  late Completer<LedgerTransport> transportGate;
  late ProviderContainer c;

  setUp(() {
    net = FakeMatrixNetwork();
    net.clientFor(bob);
    transportGate = Completer<LedgerTransport>();
    final db = openTestDatabase();
    c = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        // The transport resolves only when the test opens the gate — i.e. the
        // mutation is parked on an await while its notifier gets disposed.
        ledgerTransportProvider.overrideWith((ref) => transportGate.future),
      ],
    );
    addTearDown(() {
      c.dispose();
      db.close();
    });
  });

  /// Starts [action] with a listener, then drops the listener so the
  /// auto-dispose notifier is disposed while [action] is still in flight.
  Future<void> runThenDispose(
    ProviderSubscription<Object?> sub,
    bool Function() exists,
    Future<void> Function() action,
  ) async {
    final pending = action();
    sub.close();
    await eventually(() => !exists(), reason: 'notifier disposed mid-flight');
    transportGate.complete(net.clientFor(alice));
    await pending; // must not throw (no ref use / state set after dispose)
  }

  test(
    'GroupCreator.create completes after its notifier is disposed',
    () async {
      await runThenDispose(
        c.listen(groupCreatorProvider, (_, _) {}),
        () => c.exists(groupCreatorProvider),
        () => c.read(groupCreatorProvider.notifier).create('Trip', 'EUR'),
      );

      final groups = await c.read(groupsDaoProvider).getAllGroups();
      expect(groups.map((g) => g.name), ['Trip']);
      expect(
        (await c.read(membersDaoProvider).getMembers(groups.single.roomId))
            .single
            .matrixId,
        alice,
      );
    },
  );

  test(
    'MemberAdder.add still bootstraps the new member after dispose',
    () async {
      // Seed a group directly (no transport needed).
      const groupId = 'g1';
      await c
          .read(groupsDaoProvider)
          .upsertGroupLww(
            GroupsCompanion(
              roomId: Value(groupId),
              name: const Value('Trip'),
              currency: const Value('EUR'),
              updatedAt: const Value(1),
            ),
          );
      await runThenDispose(
        c.listen(memberAdderProvider, (_, _) {}),
        () => c.exists(memberAdderProvider),
        () => c.read(memberAdderProvider.notifier).add(groupId, bob),
      );

      expect(
        net.sent.where(
          (s) => s.type == bootstrapEventType && s.targets.contains(bob),
        ),
        hasLength(1),
      );
      expect(
        (await c.read(membersDaoProvider).memberByMatrixId(groupId, bob))
            ?.status,
        'active',
      );
    },
  );
}
