/// G52 step 4 — group policy (`group_policy.dart`) and the link path of the
/// `RecordGate` (`docs/design/no-login-sharing.md` §6.4), the link-aware
/// `LocalRecordSigner`, `signPendingRows` and the local-mode adoption of
/// link groups — against a real in-memory Drift DB and the fake device keys.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/database/app_database.dart';
import 'package:money_ledger/core/database/daos/expenses_dao.dart';
import 'package:money_ledger/core/database/daos/groups_dao.dart';
import 'package:money_ledger/core/database/daos/history_dao.dart';
import 'package:money_ledger/core/database/daos/link_dao.dart';
import 'package:money_ledger/core/database/daos/members_dao.dart';
import 'package:money_ledger/core/database/daos/signing_dao.dart';
import 'package:money_ledger/core/link/group_policy.dart';
import 'package:money_ledger/core/matrix/hmac_record_crypto.dart';
import 'package:money_ledger/core/session/app_session.dart';
import 'package:money_ledger/core/session/local_adoption.dart';
import 'package:money_ledger/core/sync/ledger_payloads.dart';
import 'package:money_ledger/core/sync/pending_signer.dart';
import 'package:money_ledger/core/sync/record_gate.dart';
import 'package:money_ledger/core/sync/record_signing.dart';
import 'package:money_ledger/core/sync/record_verifier.dart';
import 'package:money_ledger/models/expense_model.dart';
import 'package:money_ledger/models/group_model.dart';
import 'package:money_ledger/models/link_model.dart';
import 'package:money_ledger/models/member_model.dart';
import 'package:money_ledger/models/record_signature.dart';

import '../helpers/fake_ledger_network.dart';
import '../helpers/in_memory_database.dart';

const alice = '@alice:x.org';
const via = 'nostr:abcd';

LinkChannelModel channel(String group, {String? me}) => LinkChannelModel(
  groupId: group,
  epoch: 1,
  secret: 'c2VjcmV0',
  nostrPriv: '11' * 32,
  openedAt: 1,
  myParticipantId: me,
);

ExpenseModel draft({
  String id = 'e1',
  String group = 'g1',
  int updatedAt = 1000,
  String description = 'Dinner',
  String splits = '{"p1":4200}',
}) => ExpenseModel(
  id: id,
  roomId: group,
  description: description,
  amountCents: 4200,
  currency: 'EUR',
  paidBy: 'p1',
  splitsJson: splits,
  createdAt: 1000,
  updatedAt: updatedAt,
);

MemberModel member(
  String pid, {
  String group = 'g1',
  String? matrixId,
  int updatedAt = 1,
  String status = 'active',
}) => MemberModel(
  groupId: group,
  userId: pid,
  displayName: pid,
  matrixId: matrixId,
  status: status,
  updatedAt: updatedAt,
);

void main() {
  group('deriveGroupPolicy', () {
    const meta = GroupModel(roomId: 'g', name: 'G', currency: 'EUR');
    // Only the signature's presence matters here (never verified).
    final signedMeta = meta.withSigning(
      sig: const RecordSignature(user: alice, device: 'D', key: 'k', sig: 's'),
    );
    test('no channel → matrix, whatever the meta', () {
      expect(deriveGroupPolicy(channel: null, meta: meta), GroupPolicy.matrix);
      expect(
        deriveGroupPolicy(channel: null, meta: signedMeta),
        GroupPolicy.matrix,
      );
      expect(deriveGroupPolicy(channel: null, meta: null), GroupPolicy.matrix);
    });
    test('channel + unsigned / no meta → linkOnly; + signed → mixed', () {
      expect(
        deriveGroupPolicy(channel: channel('g'), meta: meta),
        GroupPolicy.linkOnly,
      );
      expect(
        deriveGroupPolicy(channel: channel('g'), meta: null),
        GroupPolicy.linkOnly,
      );
      expect(
        deriveGroupPolicy(channel: channel('g'), meta: signedMeta),
        GroupPolicy.mixed,
      );
      expect(GroupPolicy.linkOnly.matrixSyncs, isFalse);
      expect(GroupPolicy.mixed.matrixSyncs, isTrue);
      expect(GroupPolicy.matrix.acceptsUnsignedViaLink, isFalse);
    });
  });

  group('RecordGate link path', () {
    late AppDatabase db;
    late SigningDao signing;
    late ExpensesDao expenses;
    late MembersDao members;
    late GroupsDao groups;
    late LinkDao link;
    late HmacKeyRegistry keys;
    late HmacRecordCrypto aliceDevice;
    late RecordVerifier verifier;
    late RecordGate linkGate;
    late RecordGate matrixGate;
    var now = 1000000;

    setUp(() async {
      db = openTestDatabase();
      signing = SigningDao(db);
      expenses = ExpensesDao(db);
      members = MembersDao(db);
      groups = GroupsDao(db);
      link = LinkDao(db);
      keys = HmacKeyRegistry();
      aliceDevice = keys.deviceCrypto(alice, 'AAAA');
      now = 1000000;
      verifier = RecordVerifier(
        crypto: aliceDevice,
        directory: keys,
        signing: signing,
        clock: () => now,
        refreshInterval: Duration.zero,
      );
      RecordGate gate({bool linkPath = false}) => RecordGate(
        verifier: verifier,
        signing: signing,
        groups: groups,
        members: members,
        expenses: expenses,
        linkPolicy: linkPath ? link.policyOf : null,
        clock: () => now,
      );
      linkGate = gate(linkPath: true);
      matrixGate = gate();
      // g1: a link-only group (channel + unsigned meta, unclaimed people).
      await groups.upsertGroupLww(
        groupCompanion(
          const GroupModel(
            roomId: 'g1',
            name: 'Trip',
            currency: 'EUR',
            updatedAt: 1,
          ),
        ),
      );
      await members.upsertMemberLww(memberCompanion(member('p1')));
      await link.putChannel(channel('g1', me: 'p1'));
    });
    tearDown(() => db.close());

    Future<int?> rejected([String id = 'e1']) =>
        signing.rejectedClock('g1', 'expense', id);

    test('linkOnly: an unsigned version is accepted — no origin, not '
        'pendingSign, its `by` kept, history source inbound', () async {
      final signed = await signExpense(aliceDevice, draft(), creating: true);
      // Unsigned, but carrying someone's origin + a `by` hint.
      final payload = expensePayload(draft().withSigning(origin: signed.origin))
        ..['by'] = 'p1';
      expect(await linkGate.expense(payload, relayedBy: via), isTrue);
      final stored = (await expenses.getExpenseById('e1'))!;
      expect(stored.sig, isNull);
      expect(stored.origin, isNull, reason: 'attribution never lies');
      expect(stored.pendingSign, isFalse);
      expect(stored.linkAuthor, 'p1');
      final history = await HistoryDao(db).entriesForGroup('g1');
      expect(
        history.where((h) => h.recordId == 'e1').single.source,
        HistorySource.inbound,
      );
    });

    test('the Matrix path refuses the same unsigned version even in a '
        'link-only group', () async {
      expect(
        await matrixGate.expense(expensePayload(draft()), relayedBy: alice),
        isFalse,
      );
      expect(await expenses.getExpenseById('e1'), isNull);
      expect(await rejected(), 1000);
    });

    test('no downgrade: a group without a link channel keeps the G6 rules '
        'on the link path too', () async {
      await groups.upsertGroupLww(
        groupCompanion(
          const GroupModel(roomId: 'm1', name: 'M', currency: 'EUR'),
        ),
      );
      expect(
        await linkGate.expense(
          expensePayload(draft(id: 'em', group: 'm1')),
          relayedBy: via,
        ),
        isFalse,
      );
      expect(await expenses.getExpenseById('em'), isNull);
      expect(await signing.rejectedClock('m1', 'expense', 'em'), 1000);
    });

    test('a signed version with a bad signature is refused', () async {
      final signed = await signExpense(aliceDevice, draft(), creating: true);
      final tampered = expensePayload(signed)..['description'] = 'Forged';
      expect(await linkGate.expense(tampered, relayedBy: via), isFalse);
      expect(await expenses.getExpenseById('e1'), isNull);
      expect(await rejected(), 1000);
    });

    test(
      'invalid content is refused (split not summing to the amount)',
      () async {
        final bad = expensePayload(draft(splits: '{"p1":100}'));
        expect(await linkGate.expense(bad, relayedBy: via), isFalse);
        expect(await expenses.getExpenseById('e1'), isNull);
        expect(await rejected(), 1000);
      },
    );

    test('an id stored for another group is refused', () async {
      await expenses.upsertExpenseLww(
        expenseCompanion(draft(id: 'x1', group: 'other')),
      );
      expect(
        await linkGate.expense(
          expensePayload(draft(id: 'x1', updatedAt: 2000)),
          relayedBy: via,
        ),
        isFalse,
      );
      expect((await expenses.getExpenseById('x1'))!.roomId, 'other');
    });

    test('a future clock (> now + 5 min) is dropped, not clamped nor '
        'recorded — accepted once in range', () async {
      final at = now + const Duration(minutes: 6).inMilliseconds;
      final payload = expensePayload(draft(updatedAt: at));
      expect(await linkGate.expense(payload, relayedBy: via), isFalse);
      expect(await expenses.getExpenseById('e1'), isNull);
      expect(await rejected(), isNull);
      now += const Duration(minutes: 2).inMilliseconds;
      expect(await linkGate.expense(payload, relayedBy: via), isTrue);
      expect((await expenses.getExpenseById('e1'))!.updatedAt, at);
    });

    test('linkOnly: a Matrix-ID claim is refused, an unclaimed person '
        'accepted', () async {
      final claim = memberPayload(member('p2', matrixId: alice));
      expect(await linkGate.member(claim, relayedBy: via), isFalse);
      expect(
        await signing.rejectedClock('g1', 'member', 'p2'),
        1,
        reason: 'recorded as invalid_record',
      );
      // Signed by the claimant itself: still refused (G53 adds that case).
      final signedClaim = await signMember(
        aliceDevice,
        member('p3', matrixId: alice),
      );
      expect(
        await linkGate.member(memberPayload(signedClaim), relayedBy: via),
        isFalse,
      );
      final person = memberPayload(member('p4'))..['by'] = 'p1';
      expect(await linkGate.member(person, relayedBy: via), isTrue);
      final stored = (await members.getMembers(
        'g1',
      )).where((m) => m.userId == 'p4').single;
      expect(stored.linkAuthor, 'p1');
      expect(stored.pendingSign, isFalse);
      expect(
        (await members.getMembers('g1')).map((m) => m.userId),
        isNot(contains('p2')),
      );
    });

    test('linkOnly: an unsigned meta replaces an unsigned meta', () async {
      final meta = groupMetaPayload(
        const GroupModel(
          roomId: 'g1',
          name: 'Renamed',
          currency: 'CHF',
          updatedAt: 5,
        ),
      );
      expect(await linkGate.meta(meta, relayedBy: via), isTrue);
      expect((await groups.getGroup('g1'))!.name, 'Renamed');
      expect(await link.isLinkOnly('g1'), isTrue);
    });

    test('mixed: unsigned records are accepted, but an unsigned meta never '
        'replaces the signed one (no mixed → link-only)', () async {
      await members.upsertMemberLww(
        memberCompanion(member('pa', matrixId: alice)),
      );
      final signedMeta = await signGroupMeta(
        aliceDevice,
        const GroupModel(
          roomId: 'g1',
          name: 'Signed',
          currency: 'EUR',
          updatedAt: 2,
        ),
      );
      expect(
        await linkGate.meta(groupMetaPayload(signedMeta), relayedBy: via),
        isTrue,
      );
      expect((await link.policyOf('g1')).policy, GroupPolicy.mixed);
      final unsignedMeta = groupMetaPayload(
        const GroupModel(
          roomId: 'g1',
          name: 'Hijack',
          currency: 'EUR',
          updatedAt: 9,
        ),
      );
      expect(await linkGate.meta(unsignedMeta, relayedBy: via), isFalse);
      expect((await groups.getGroup('g1'))!.name, 'Signed');
      expect((await link.policyOf('g1')).policy, GroupPolicy.mixed);
      expect(
        await linkGate.expense(expensePayload(draft()), relayedBy: via),
        isTrue,
      );
      // An unsigned claim isn't accepted in a mixed group either.
      expect(
        await linkGate.member(
          memberPayload(member('p9', matrixId: '@eve:x.org')),
          relayedBy: via,
        ),
        isFalse,
      );
    });

    test('a snapshot creates a group being joined (channel, no meta yet) '
        'only on the link path and only with a channel', () async {
      Map<String, dynamic> snap(String g) => buildBootstrapContent(
        g,
        GroupModel(roomId: g, name: 'Joined', currency: 'EUR', updatedAt: 3),
        [member('q1', group: g)],
        [
          draft(
            id: 'e-$g',
            group: g,
            splits: '{"q1":4200}',
          ).asLinkVersion(null),
        ],
        const [],
        includePending: true,
      );
      await link.putChannel(channel('g2'));
      // Matrix path: unsigned → refused, even for a group being joined.
      await matrixGate.snapshot(
        snap('g4'),
        relayedBy: alice,
        trustAttestations: false,
      );
      expect(await groups.getGroup('g4'), isNull);
      // Link path without a channel: a Matrix group → refused.
      await linkGate.snapshot(
        snap('g3'),
        relayedBy: via,
        trustAttestations: false,
      );
      expect(await groups.getGroup('g3'), isNull);
      await linkGate.snapshot(
        snap('g2'),
        relayedBy: via,
        trustAttestations: false,
      );
      expect((await groups.getGroup('g2'))!.name, 'Joined');
      expect(await expenses.getExpenseById('e-g2'), isNotNull);
      expect(await link.isLinkOnly('g2'), isTrue);
    });

    test('the Matrix path drops a `by` hint', () async {
      await link.deleteChannel('g1');
      await members.upsertMemberLww(
        memberCompanion(member('pa', matrixId: alice)),
      );
      final signed = await signExpense(aliceDevice, draft(), creating: true);
      final payload = expensePayload(signed)..['by'] = 'pa';
      expect(await matrixGate.expense(payload, relayedBy: alice), isTrue);
      expect((await expenses.getExpenseById('e1'))!.linkAuthor, isNull);
    });

    test('a new version without `by` clears the stored hint', () async {
      final first = expensePayload(draft())..['by'] = 'p1';
      await linkGate.expense(first, relayedBy: via);
      await linkGate.expense(
        expensePayload(draft(updatedAt: 2000)),
        relayedBy: via,
      );
      expect((await expenses.getExpenseById('e1'))!.linkAuthor, isNull);
    });
  });

  group('LocalRecordSigner / signPendingRows', () {
    late AppDatabase db;
    setUp(() => db = openTestDatabase());
    tearDown(() => db.close());

    test('link-only group: stored unsigned, not pendingSign, `by` = my '
        'participant; any other group: signed', () async {
      final net = FakeMatrixNetwork();
      final link = LinkDao(db);
      await GroupsDao(db).upsertGroupLww(
        groupCompanion(
          const GroupModel(roomId: 'g1', name: 'L', currency: 'EUR'),
        ),
      );
      await link.putChannel(channel('g1', me: 'p1'));
      final signer = LocalRecordSigner(
        Future.value(net.clientFor(alice)),
        policy: link.policyOf,
      );
      final created = await signer.expense(draft(), creating: true);
      expect(created.sig, isNull);
      expect(created.origin, isNull);
      expect(created.pendingSign, isFalse);
      expect(created.linkAuthor, 'p1');
      final m = await signer.member(member('p2'));
      expect((m.sig, m.pendingSign, m.linkAuthor), (null, false, 'p1'));

      final other = await signer.expense(
        draft(id: 'e2', group: 'g2'),
        creating: true,
      );
      expect(other.sig, isNotNull);
      expect(other.origin, isNotNull);
      expect(other.linkAuthor, isNull);
    });

    test('signPendingRows skips a link-only group', () async {
      final crypto = HmacKeyRegistry().deviceCrypto(alice, 'AAAA');
      final groups = GroupsDao(db);
      final members = MembersDao(db);
      final expenses = ExpensesDao(db);
      for (final g in ['g1', 'g2']) {
        await groups.upsertGroupLww(
          groupCompanion(
            GroupModel(
              roomId: g,
              name: g,
              currency: 'EUR',
            ).withSigning(pendingSign: true),
          ),
        );
        await expenses.upsertExpenseLww(
          expenseCompanion(
            draft(id: 'e-$g', group: g).withSigning(pendingSign: true),
          ),
        );
      }
      await LinkDao(db).putChannel(channel('g1'));
      Future<int> sign(String g) => signPendingRows(
        crypto: crypto,
        groups: groups,
        members: members,
        expenses: expenses,
        groupId: g,
        isAlive: () => true,
      );
      expect(await sign('g1'), 0);
      expect((await expenses.getExpenseById('e-g1'))!.sig, isNull);
      expect(await sign('g2'), 2);
      expect((await expenses.getExpenseById('e-g2'))!.sig, isNotNull);
    });
  });

  group('local adoption of a link group', () {
    late AppDatabase local;
    late AppDatabase target;
    setUp(() {
      local = openTestDatabase();
      target = openTestDatabase();
    });
    tearDown(() async {
      await local.close();
      await target.close();
    });

    test('keeps its channel + peers, stays link-only and unsigned; a '
        'leftover local:self claim becomes my_participant_id', () async {
      final groups = GroupsDao(local);
      final members = MembersDao(local);
      final expenses = ExpensesDao(local);
      for (final g in ['link', 'solo']) {
        await groups.upsertGroupLww(
          groupCompanion(
            GroupModel(
              roomId: g,
              name: g,
              currency: 'EUR',
              updatedAt: 1,
            ).withSigning(pendingSign: true),
          ),
        );
        await members.upsertMemberLww(
          memberCompanion(
            member(
              'me-$g',
              group: g,
              matrixId: kLocalAccountId,
            ).withSigning(pendingSign: true),
          ),
        );
        await expenses.upsertExpenseLww(
          expenseCompanion(
            draft(
              id: 'e-$g',
              group: g,
              splits: '{"p1":4200}',
            ).withSigning(pendingSign: true),
          ),
        );
      }
      final localLink = LinkDao(local);
      await localLink.putChannel(channel('link'));
      await localLink.recordPeerEvent(
        groupId: 'link',
        pubkey: 'ab' * 32,
        part: 0,
        eventId: 'ev1',
        createdAt: 10,
        seenAt: 20,
        me: 'p7',
      );

      final crypto = HmacKeyRegistry().deviceCrypto(alice, 'AAAA');
      final r = await adoptLocalLedger(
        target: target,
        local: local,
        mxid: alice,
        crypto: crypto,
      );
      expect(r.groupIds, unorderedEquals(['link', 'solo']));

      final link = LinkDao(target);
      final ch = (await link.getChannel('link'))!;
      expect(ch.myParticipantId, 'me-link');
      expect(ch.nostrPriv, '11' * 32);
      expect((await link.getPeers('link')).single.me, 'p7');
      expect(await link.isLinkOnly('link'), isTrue);

      final tg = GroupsDao(target);
      final tm = MembersDao(target);
      final te = ExpensesDao(target);
      final meta = (await tg.getGroup('link'))!;
      expect((meta.sig, meta.pendingSign), (null, false));
      final me = (await tm.getMembers('link')).single;
      expect(me.matrixId, isNull, reason: 'no claim in a link-only group');
      expect(me.sig, isNull);
      expect(me.pendingSign, isFalse);
      final e = (await te.getExpenseById('e-link'))!;
      expect((e.sig, e.pendingSign), (null, false));

      // The device-only group is adopted as before: claimed + signed.
      expect((await tg.getGroup('solo'))!.sig, isNotNull);
      expect((await tm.getMembers('solo')).single.matrixId, alice);
      expect((await te.getExpenseById('e-solo'))!.sig, isNotNull);
      expect(await link.getChannel('solo'), isNull);

      // The local DB is wiped, its link rows included.
      expect(await localLink.getAllChannels(), isEmpty);
    });

    test('reclaimGroupInPlace leaves a link-only group alone', () async {
      final groups = GroupsDao(target);
      final members = MembersDao(target);
      await groups.upsertGroupLww(
        groupCompanion(
          const GroupModel(roomId: 'g', name: 'G', currency: 'EUR'),
        ),
      );
      await members.upsertMemberLww(
        memberCompanion(member('p', group: 'g', matrixId: kLocalAccountId)),
      );
      await LinkDao(target).putChannel(channel('g'));
      expect(
        await reclaimGroupInPlace(
          groups: groups,
          members: members,
          expenses: ExpensesDao(target),
          groupId: 'g',
          from: kLocalAccountId,
          to: alice,
          signLater: true,
        ),
        isFalse,
      );
      final m = (await members.getMembers('g')).single;
      expect(m.matrixId, kLocalAccountId);
      expect(m.pendingSign, isFalse);
      expect((await groups.getGroup('g'))!.pendingSign, isFalse);
    });
  });
}
