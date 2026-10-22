/// G53 — Leo's decisions round 3 (2026-10-22, plan.md "Leo's decisions
/// 2026-10-22", `docs/design/no-login-sharing.md` §10.1 "As built (G53
/// round 3)") end-to-end across the fake relays and the fake Matrix
/// network:
/// * **claims over the link are self-claims only** — a Matrix invite of a
///   person (signed by the inviter) isn't accepted over the link; the
///   invitee's device confirms its claim with its own signature, which the
///   device without an account then accepts (and the invitee's writes reach
///   it); a forged claim for someone else's Matrix ID is refused everywhere
///   and nothing is replicated to that account;
/// * **lock eligibility ignores late arrivals** — a person published back-
///   dated before a lock this device already saw doesn't block the lock
///   once the real blocker is gone.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/database/daos/expenses_dao.dart';
import 'package:money_ledger/core/database/daos/groups_dao.dart';
import 'package:money_ledger/core/database/daos/members_dao.dart';
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
const _bob = '@bob:x.org';
const _mallory = '@mallory:x.org';
const _victim = '@victim:x.org';

void main() {
  late MixedHarness h;
  setUp(() => h = MixedHarness());

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

  Future<MemberModel> person(MixedDevice d, String g, String id) async =>
      (await MembersDao(d.db).getMembers(g)).firstWhere((m) => m.userId == id);

  Future<String> idOf(MixedDevice d, String g, String name) async =>
      (await MembersDao(
        d.db,
      ).getMembers(g)).firstWhere((m) => m.displayName == name).userId;

  /// Alice's Matrix group, opened by link; Ben (no account) joins.
  Future<({MixedDevice alice, MixedDevice ben, String g, String secret})>
  mixedGroup() async {
    final alice = h.device(_alice);
    await h.settle();
    final sub = alice.c.listen(groupCreatorProvider, (_, _) {});
    final g = (await alice.c
        .read(groupCreatorProvider.notifier)
        .create('Hut', 'EUR'))!;
    sub.close();
    final link = await alice.c.read(mixedLinkOpenerProvider)(g);
    await h.settle();
    final ben = h.device(kLocalAccountId);
    await h.join(ben, g, link.secret, name: 'Ben');
    return (alice: alice, ben: ben, g: g, secret: link.secret);
  }

  Future<void> addLocal(MixedDevice d, String g, String name) async {
    final sub = d.c.listen(memberAdderProvider, (_, _) {});
    await d.c.read(memberAdderProvider.notifier).addLocal(g, name);
    sub.close();
    await h.settle();
  }

  test('a Matrix invite of a person reaches the device without an account '
      'only through the invitee\'s own confirmation', () async {
    final s = await mixedGroup();
    await addLocal(s.alice, s.g, 'Cleo');
    final cleoId = await idOf(s.alice, s.g, 'Cleo');
    h.matrix.clientFor(_bob);
    final bob = h.device(_bob);
    await h.settle();
    final adder = s.alice.c.listen(memberAdderProvider, (_, _) {});
    await s.alice.c
        .read(memberAdderProvider.notifier)
        .invite(s.g, _bob, participantId: cleoId);
    adder.close();
    await h.settle();

    // Bob's device holds the group (over Matrix) and confirmed the claim.
    final atBob = await person(bob, s.g, cleoId);
    expect(atBob.matrixId, _bob);
    expect(atBob.sig?.user, _bob, reason: 'confirmed with his own signature');
    // Ben (no account) took it — the version signed by Bob himself.
    final atBen = await person(s.ben, s.g, cleoId);
    expect(atBen.matrixId, _bob);
    expect(atBen.sig?.user, _bob);
    // Alice holds it too; nothing loops.
    expect((await person(s.alice, s.g, cleoId)).matrixId, _bob);
    s.alice.c.read(syncEngineProvider).pokeGroup(s.g);
    await h.settle();

    // Bob's signed writes reach Ben (Bob is a member there now).
    final sub = bob.c.listen(expenseAdderProvider, (_, _) {});
    await addExpense(bob, s.g, 'Lamp oil', cleoId);
    sub.close();
    await h.settle();
    expect(
      (await ExpensesDao(
        s.ben.db,
      ).getAllExpensesForGroup(s.g)).map((e) => e.description),
      contains('Lamp oil'),
    );
  });

  test('a forged claim of a person for someone else\'s Matrix ID over the '
      'link: refused by the Matrix and the no-account device, nothing is '
      'sent to that account', () async {
    final s = await mixedGroup();
    await addLocal(s.alice, s.g, 'Dan');
    final danId = await idOf(s.alice, s.g, 'Dan');
    h.matrix.clientFor(_victim);
    final malloryLocal = h.device(kLocalAccountId);
    await h.join(malloryLocal, s.g, s.secret, name: 'Mallory');
    // Mallory (a real Matrix account) signs a claim of Dan for the victim
    // and publishes it through her link snapshot.
    final danAtMallory = await person(malloryLocal, s.g, danId);
    final forged = await signMember(
      h.matrix.clientFor(_mallory).crypto,
      MemberModel(
        groupId: s.g,
        userId: danId,
        displayName: danAtMallory.displayName,
        matrixId: _victim,
        status: danAtMallory.status,
        updatedAt: nextLwwClock(danAtMallory.updatedAt),
      ),
    );
    await MembersDao(malloryLocal.db).upsertMemberLww(memberCompanion(forged));
    await h.settle();

    for (final d in [s.alice, s.ben]) {
      expect(
        (await person(d, s.g, danId)).matrixId,
        isNull,
        reason: d.identity,
      );
    }
    expect(await MembersDao(s.alice.db).activeClaimedMatrixIds(s.g), [_alice]);
    h.matrix.sent.clear();
    final aliceId = claimedBy(
      await MembersDao(s.alice.db).getMembers(s.g),
      _alice,
    )!.userId;
    final sub = s.alice.c.listen(expenseAdderProvider, (_, _) {});
    await addExpense(s.alice, s.g, 'Bread', aliceId);
    sub.close();
    s.alice.c.read(syncEngineProvider).pokeGroup(s.g);
    await h.settle();
    expect(
      h.matrix.sent.where((m) => m.targets.contains(_victim)),
      isEmpty,
      reason: 'nothing is replicated to the forged claim',
    );
  });

  test('lock eligibility: a person published back-dated after the lock '
      'arrived doesn\'t block it once Ben is gone', () async {
    final s = await mixedGroup();
    h.matrix.clientFor(_bob);
    final bob = h.device(_bob);
    await h.settle();
    final adder = s.alice.c.listen(memberAdderProvider, (_, _) {});
    await s.alice.c.read(memberAdderProvider.notifier).invite(s.g, _bob);
    adder.close();
    await h.settle();
    final benId = await idOf(s.alice, s.g, 'Ben');
    final aliceCrypto = h.matrix.clientFor(_alice).crypto;
    final at = DateTime.now().millisecondsSinceEpoch + 2000;
    // Alice's lock reaches Bob while Ben (no account) is still active:
    // refused.
    final meta = (await GroupsDao(s.alice.db).getGroup(s.g))!;
    final lock = await signGroupMeta(
      aliceCrypto,
      meta.nextVersion(updatedAt: at, link: null, lockedAt: at),
    );
    final alice = h.matrix.clientFor(_alice);
    await alice.sendToUsers({_bob}, groupMetaEventType, groupMetaPayload(lock));
    await h.settle();
    expect((await GroupsDao(bob.db).getGroup(s.g))!.isLocked, isFalse);

    // Ben's device publishes a new person back-dated before the lock.
    await MembersDao(s.ben.db).upsertMemberLww(
      memberCompanion(
        MemberModel(
          groupId: s.g,
          userId: 'ghost-person',
          displayName: 'Ghost',
          status: 'active',
          updatedAt: at - 500,
          linkAuthor: benId,
        ),
      ),
    );
    await h.settle();
    expect(
      (await person(bob, s.g, 'ghost-person')).isActive,
      isTrue,
      reason: 'Bob holds the back-dated person',
    );

    // Ben's removal (stamped before the lock) reaches Bob late, then the
    // lock is re-sent.
    final ben = await person(s.alice, s.g, benId);
    final removal = await signMember(
      aliceCrypto,
      MemberModel(
        groupId: s.g,
        userId: benId,
        displayName: ben.displayName,
        status: 'removed',
        updatedAt: at - 1000,
      ),
    );
    await alice.sendToUsers({_bob}, memberEventType, memberPayload(removal));
    await h.settle();
    await alice.sendToUsers({_bob}, groupMetaEventType, groupMetaPayload(lock));
    await h.settle();
    final atBob = (await GroupsDao(bob.db).getGroup(s.g))!;
    expect(atBob.isLocked, isTrue, reason: 'Ghost arrived after the lock');
    expect(atBob.lockedAt, at);
  });
}
