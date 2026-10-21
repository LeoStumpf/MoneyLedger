/// G53 step 4 end-to-end (`docs/design/no-login-sharing.md` §10.1 Lock,
/// "Leo's directions, both covered"): **link → Matrix → lock** and
/// **Matrix → link → lock → reopen** across the fake relays and the fake
/// Matrix network — eligibility, the signed lock meta, the final
/// `locked: true` event, every device dropping its channel, the read-only
/// link-only device, the refusal of later unsigned versions and a reopened
/// link with a new secret and epoch.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/database/daos/expenses_dao.dart';
import 'package:money_ledger/core/database/daos/groups_dao.dart';
import 'package:money_ledger/core/database/daos/link_dao.dart';
import 'package:money_ledger/core/database/daos/members_dao.dart';
import 'package:money_ledger/core/link/group_policy.dart';
import 'package:money_ledger/core/link/link_envelope.dart';
import 'package:money_ledger/core/link/link_keys.dart';
import 'package:money_ledger/core/link/link_snapshot.dart';
import 'package:money_ledger/core/link/link_uri.dart';
import 'package:money_ledger/core/link/nostr/nostr_relay_pool.dart'
    show kDefaultLinkRelays;
import 'package:money_ledger/core/session/app_session.dart';
import 'package:money_ledger/core/sync/record_signing.dart';
import 'package:money_ledger/features/expenses/expenses_provider.dart';
import 'package:money_ledger/features/groups/group_provider.dart';
import 'package:money_ledger/models/member_model.dart';

import '../helpers/mixed_harness.dart';

const _alice = '@alice:x.org';
const _bob = '@bob:x.org';
const _anna = '@anna:x.org';
const _ben = '@ben:x.org';

void main() {
  late MixedHarness h;
  setUp(() => h = MixedHarness());

  /// The decrypted headers of the events the first relay holds for
  /// [secret]'s topic.
  Future<List<Map<String, dynamic>>> relaySnapshots(String secret) async {
    final keys = await deriveLinkKeys(decodeLinkSecret(secret));
    final topics = linkPartTopics(keys.topic).toSet();
    return [
      for (final e in h.relays.relay(kDefaultLinkRelays.first).events)
        if (e.kind == kLinkEventKind && topics.contains(e.dTag))
          await openLinkContent(
            e.content,
            keys.encKey,
            d: e.dTag,
            pubkey: e.pubkey,
          ),
    ];
  }

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

  test('link → Matrix → lock: blocked until everyone active has a Matrix '
      'account; then every device drops the link and the link-only phone '
      'is read-only', () async {
    // Anna (no account) creates a link group; Ben joins; Anna's second
    // phone joins as Anna.
    final anna = h.device(kLocalAccountId);
    await anna.engine.ready;
    final sub = anna.c.listen(groupCreatorProvider, (_, _) {});
    final g = (await anna.c
        .read(groupCreatorProvider.notifier)
        .create('Hut', 'EUR'))!;
    sub.close();
    final channel = await anna.engine.openChannel(g);
    await h.settle();
    final annaId = channel.myParticipantId!;
    final benLocal = h.device(kLocalAccountId);
    await h.join(benLocal, g, channel.secret, name: 'Ben');
    final annaPhone2 = h.device(kLocalAccountId);
    await h.join(annaPhone2, g, channel.secret, as: annaId);

    // Ben connects Matrix: mixed. Lock is blocked by Anna (no account).
    final ben = await h.connect(benLocal, _ben);
    expect((await LinkDao(ben.db).policyOf(g)).policy, GroupPolicy.mixed);
    await expectLater(
      ben.c.read(groupLockerProvider)(g),
      throwsA(
        isA<LockNotEligibleException>().having(
          (e) => e.blockers.map((m) => m.userId),
          'blockers',
          [annaId],
        ),
      ),
    );
    expect((await GroupsDao(ben.db).getGroup(g))!.link, isNotNull);

    // Anna connects too (her first phone) → Ben can lock.
    final annaAcc = await h.connect(anna, _anna);
    expect(
      claimedBy(await MembersDao(ben.db).getMembers(g), _anna)?.userId,
      annaId,
    );
    await ben.c.read(groupLockerProvider)(g);
    await h.settle();

    for (final d in [ben, annaAcc, annaPhone2]) {
      final meta = (await GroupsDao(d.db).getGroup(g))!;
      expect(meta.isLocked, isTrue, reason: d.identity);
      expect(meta.link, isNull);
      expect(await LinkDao(d.db).getChannel(g), isNull, reason: d.identity);
    }
    // The final event: part 0, header-only, locked; the old copies gone.
    final left = await relaySnapshots(channel.secret);
    expect(left.where((s) => s['locked'] == true), isNotEmpty);
    expect(
      left.expand((s) => (s['expenses'] as List?) ?? const []),
      isEmpty,
      reason: 'no records stay on the relays',
    );

    // Anna's second phone (no account) is read-only now.
    final adder = annaPhone2.c.listen(expenseAdderProvider, (_, _) {});
    await addExpense(annaPhone2, g, 'After lock', annaId);
    expect(
      annaPhone2.c.read(expenseAdderProvider).error,
      isA<SignatureRequiredException>(),
    );
    adder.close();
    expect(
      (await ExpensesDao(annaPhone2.db).getAllExpensesForGroup(g)),
      isEmpty,
    );
    expect(
      await annaPhone2.c.read(currentParticipantProvider(g).future),
      isNull,
      reason: 'no "me" without the channel → the secure-only banner',
    );

    // The Matrix members keep syncing (signed).
    final bAdder = ben.c.listen(expenseAdderProvider, (_, _) {});
    final benId = claimedBy(await MembersDao(ben.db).getMembers(g), _ben)!;
    await addExpense(ben, g, 'Signed after lock', benId.userId);
    bAdder.close();
    await h.settle();
    final atAnna = await ExpensesDao(annaAcc.db).getAllExpensesForGroup(g);
    expect(atAnna.where((e) => e.description == 'Signed after lock'), [
      isA<Object>(),
    ]);
  });

  test('Matrix → link → lock → reopen: removing the link-only person lets '
      'Alice lock; Bob drops his channel; a reopened link is new', () async {
    final a = h.device(_alice);
    final b = h.device(_bob);
    await h.settle();
    final sub = a.c.listen(groupCreatorProvider, (_, _) {});
    final g = (await a.c
        .read(groupCreatorProvider.notifier)
        .create('Rome', 'EUR'))!;
    sub.close();
    final adderSub = a.c.listen(memberAdderProvider, (_, _) {});
    await a.c.read(memberAdderProvider.notifier).add(g, _bob);
    adderSub.close();
    await h.settle();
    final first = await a.c.read(mixedLinkOpenerProvider)(g);
    await h.settle();
    final ben = h.device(kLocalAccountId);
    final benId = await h.join(ben, g, first.secret, name: 'Ben');

    await expectLater(
      a.c.read(groupLockerProvider)(g),
      throwsA(isA<LockNotEligibleException>()),
    );
    final remover = a.c.listen(memberRemoverProvider, (_, _) {});
    await a.c.read(memberRemoverProvider.notifier).remove(g, benId);
    remover.close();
    await h.settle();
    await a.c.read(groupLockerProvider)(g);
    await h.settle();

    final lockedAt = (await GroupsDao(a.db).getGroup(g))!.lockedAt!;
    for (final d in [a, b, ben]) {
      expect(
        (await GroupsDao(d.db).getGroup(g))!.isLocked,
        isTrue,
        reason: d.identity,
      );
      expect(await LinkDao(d.db).getChannel(g), isNull, reason: d.identity);
    }
    expect((await LinkDao(b.db).policyOf(g)).lockedAt, lockedAt);

    // Reopen: a new signed link — new secret, next epoch; Bob bridges.
    final second = await a.c.read(mixedLinkOpenerProvider)(g);
    await h.settle();
    expect(second.secret, isNot(first.secret));
    final reopened = (await GroupsDao(a.db).getGroup(g))!;
    expect(reopened.link?.epoch, 2);
    expect(reopened.lockedAt, isNull);
    expect((await LinkDao(b.db).getChannel(g))?.secret, second.secret);
    expect(
      (await LinkDao(ben.db).getChannel(g)),
      isNull,
      reason: 'the removed person has no new link',
    );
  });
}
