/// G53 hardening end-to-end — the griefing scenarios of plan.md G53 (Leo
/// 2026-10-22, `docs/design/no-login-sharing.md` §10.1 "receiver checks")
/// across the fake relays and the fake Matrix network:
/// * a link holder with a Matrix account self-claims an unclaimed person and
///   locks while someone without an account is still in the group → every
///   other device refuses the lock (recorded, no repair loop), the link
///   stays open and the person without an account keeps syncing;
/// * a fabricated self-claim on the link path (a device key the homeserver
///   doesn't list) → a Matrix device doesn't trust it and replicates
///   nothing to that account;
/// * a claim whose device list can't be read stays unresolved, but its
///   event is recorded (round 3, Leo 2026-10-22) — looked at again with the
///   publisher's next event, accepted once the homeserver answers.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/database/daos/expenses_dao.dart';
import 'package:money_ledger/core/database/daos/groups_dao.dart';
import 'package:money_ledger/core/database/daos/link_dao.dart';
import 'package:money_ledger/core/database/daos/members_dao.dart';
import 'package:money_ledger/core/link/group_policy.dart';
import 'package:money_ledger/core/matrix/ledger_transport.dart';
import 'package:money_ledger/core/session/app_session.dart';
import 'package:money_ledger/core/sync/ledger_payloads.dart';
import 'package:money_ledger/core/sync/record_signing.dart';
import 'package:money_ledger/core/sync/sync_engine.dart';
import 'package:money_ledger/features/expenses/expenses_provider.dart';
import 'package:money_ledger/features/groups/group_provider.dart';
import 'package:money_ledger/models/member_model.dart';

import '../helpers/mixed_harness.dart';

const _alice = '@alice:x.org';
const _mallory = '@mallory:x.org';
const _eve = '@eve:x.org';

/// [m] claimed by [mxid] (a new version, name / status kept).
MemberModel _claimed(MemberModel m, String mxid) => MemberModel(
  groupId: m.groupId,
  userId: m.userId,
  displayName: m.displayName,
  matrixId: mxid,
  status: m.status,
  updatedAt: nextLwwClock(m.updatedAt),
);

void main() {
  late MixedHarness h;
  setUp(() => h = MixedHarness());

  Future<List<String>> refusals(MixedDevice d) async => [
    for (final r in await d.db.select(d.db.rejectedVersions).get())
      '${r.kind}:${r.reason}',
  ];

  Future<void> addExpense(MixedDevice d, String g, String desc, String by) => d
      .c
      .read(expenseAdderProvider.notifier)
      .addExpense(
        roomId: g,
        description: desc,
        amountCents: 1000,
        currency: 'EUR',
        paidBy: by,
        splits: {by: 1000},
      );

  /// Alice's Matrix group, opened by link; Ben (no account) joins.
  Future<({MixedDevice alice, String g, String secret, String benId})>
  mixedGroupWithBen(MixedDevice ben) async {
    final alice = h.device(_alice);
    await h.settle();
    final sub = alice.c.listen(groupCreatorProvider, (_, _) {});
    final g = (await alice.c
        .read(groupCreatorProvider.notifier)
        .create('Hut', 'EUR'))!;
    sub.close();
    final link = await alice.c.read(mixedLinkOpenerProvider)(g);
    await h.settle();
    final benId = await h.join(ben, g, link.secret, name: 'Ben');
    return (alice: alice, g: g, secret: link.secret, benId: benId);
  }

  test('self-claim + lock while Ben has no account: Alice and Ben refuse '
      'the lock, the link stays, Ben keeps syncing', () async {
    final ben = h.device(kLocalAccountId);
    final s = await mixedGroupWithBen(ben);
    // Cleo is in the group without an account (added by name); Mallory
    // got the link, picks Cleo's participant and connects her account.
    final adder = s.alice.c.listen(memberAdderProvider, (_, _) {});
    await s.alice.c.read(memberAdderProvider.notifier).addLocal(s.g, 'Cleo');
    adder.close();
    await h.settle();
    final cleoId = (await MembersDao(
      s.alice.db,
    ).getMembers(s.g)).firstWhere((m) => m.displayName == 'Cleo').userId;
    final malloryLocal = h.device(kLocalAccountId);
    await h.join(malloryLocal, s.g, s.secret, as: cleoId);
    final mallory = await h.connect(malloryLocal, _mallory);
    expect(
      claimedBy(await MembersDao(s.alice.db).getMembers(s.g), _mallory)?.userId,
      cleoId,
      reason: 'the self-claim itself is legitimate (a real device)',
    );

    // Mallory's app would refuse (Ben blocks it) — she forges the lock.
    await expectLater(
      mallory.c.read(groupLockerProvider)(s.g),
      throwsA(isA<LockNotEligibleException>()),
    );
    final meta = (await GroupsDao(mallory.db).getGroup(s.g))!;
    final at = DateTime.now().millisecondsSinceEpoch;
    final lock = await signGroupMeta(
      h.matrix.clientFor(_mallory).crypto,
      meta.nextVersion(updatedAt: at, link: null, lockedAt: at),
    );
    await mallory.engine.lockLink(s.g, lock);
    await h.matrix
        .clientFor(_mallory)
        .sendToUsers({_alice}, groupMetaEventType, groupMetaPayload(lock));
    await h.settle();

    for (final d in [s.alice, ben]) {
      final m = (await GroupsDao(d.db).getGroup(s.g))!;
      expect(m.isLocked, isFalse, reason: d.identity);
      expect(m.link?.secret, s.secret, reason: d.identity);
      expect(await LinkDao(d.db).getChannel(s.g), isNotNull);
      expect(await refusals(d), contains('meta:lock_not_eligible'));
    }
    expect((await LinkDao(s.alice.db).policyOf(s.g)).policy, GroupPolicy.mixed);

    // No repair loop: further digest rounds stay quiet …
    s.alice.c.read(syncEngineProvider).pokeGroup(s.g);
    await h.settle();
    // … and Ben (no account) still writes, Alice still receives.
    final sub = ben.c.listen(expenseAdderProvider, (_, _) {});
    await addExpense(ben, s.g, 'Firewood', s.benId);
    sub.close();
    await h.settle();
    final atAlice = await ExpensesDao(s.alice.db).getAllExpensesForGroup(s.g);
    expect(atAlice.map((e) => e.description), contains('Firewood'));
  });

  test('a fabricated self-claim on the link path: Alice\'s Matrix device '
      'doesn\'t trust it and sends nothing to that account', () async {
    final ben = h.device(kLocalAccountId);
    final s = await mixedGroupWithBen(ben);
    h.matrix.clientFor(_eve); // a real account with a listed device
    final eveLocal = h.device(kLocalAccountId);
    await h.join(eveLocal, s.g, s.secret, name: 'Eve');
    // Eve forges a claim of Ben's participant with a device key she made
    // up and publishes it through her link snapshot.
    final benAtEve = (await MembersDao(
      eveLocal.db,
    ).getMembers(s.g)).firstWhere((m) => m.userId == s.benId);
    final forged = await signMember(
      h.matrix.keys.unlistedCrypto(_eve, 'FAKE'),
      _claimed(benAtEve, _eve),
    );
    await MembersDao(eveLocal.db).upsertMemberLww(memberCompanion(forged));
    await h.settle();

    final atAlice = await MembersDao(s.alice.db).getMembers(s.g);
    expect(atAlice.firstWhere((m) => m.userId == s.benId).matrixId, isNull);
    expect(await MembersDao(s.alice.db).activeClaimedMatrixIds(s.g), [_alice]);
    expect(await refusals(s.alice), contains('member:claim_device_not_listed'));

    h.matrix.sent.clear();
    final sub = s.alice.c.listen(expenseAdderProvider, (_, _) {});
    final aliceId = claimedBy(atAlice, _alice)!.userId;
    await addExpense(s.alice, s.g, 'Bread', aliceId);
    sub.close();
    s.alice.c.read(syncEngineProvider).pokeGroup(s.g);
    await h.settle();
    expect(
      h.matrix.sent.where((m) => m.targets.contains(_eve)),
      isEmpty,
      reason: 'nothing is replicated to the forged claim',
    );
  });

  test(
    'homeserver unreachable (round 3): the claim stays unresolved, the '
    'event is recorded (peer + its "me" in the sync sheet, not merged '
    'again on every fetch); the publisher\'s next event resolves it',
    () async {
      final ben = h.device(kLocalAccountId);
      final s = await mixedGroupWithBen(ben);
      final eveLocal = h.device(kLocalAccountId);
      await h.join(eveLocal, s.g, s.secret, name: 'Eve');
      // A genuine claim (Eve's real device), arriving only by link.
      final eveAtEve = (await MembersDao(
        eveLocal.db,
      ).getMembers(s.g)).firstWhere((m) => m.displayName == 'Eve');
      final claim = await signMember(
        h.matrix.clientFor(_eve).crypto,
        _claimed(eveAtEve, _eve),
      );
      h.matrix.keys.unreachable = true;
      await MembersDao(eveLocal.db).upsertMemberLww(memberCompanion(claim));
      await h.settle();
      Future<String?> claimAtAlice() async =>
          (await MembersDao(s.alice.db).getMembers(
            s.g,
          )).firstWhere((m) => m.userId == eveAtEve.userId).matrixId;
      expect(await claimAtAlice(), isNull);
      expect(
        await refusals(s.alice),
        isNot(contains('member:claim_unverifiable')),
      );
      // The event's bookkeeping is recorded: Eve's publisher with her "me".
      final peer = (await LinkDao(
        s.alice.db,
      ).getPeers(s.g)).where((p) => p.me == eveAtEve.userId).single;
      expect(peer.snapshotDigest, isNotNull);

      // Reachable again: a fetch doesn't merge the same event again …
      h.matrix.keys.unreachable = false;
      await s.alice.engine.refresh(groupId: s.g);
      await h.settle();
      expect(await claimAtAlice(), isNull, reason: 'not re-merged');

      // … Eve's next event (any change) carries the claim again → accepted.
      final sub = eveLocal.c.listen(expenseAdderProvider, (_, _) {});
      await addExpense(eveLocal, s.g, 'Matches', eveAtEve.userId);
      sub.close();
      await h.settle();
      expect(await claimAtAlice(), _eve);
    },
  );
}
