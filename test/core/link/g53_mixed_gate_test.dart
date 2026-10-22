/// G53 step 1 — the signed meta's `link` / `locked_at` (wire, signed body,
/// G27 hash, content rules, DAO), the policy derived from it, the record
/// gate's mixed / locked rules on both paths and the signer of a device
/// without a Matrix account in a mixed group
/// (`docs/design/no-login-sharing.md` §0 #10, §6.4, §10.1).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/database/app_database.dart';
import 'package:money_ledger/core/database/daos/expenses_dao.dart';
import 'package:money_ledger/core/database/daos/groups_dao.dart';
import 'package:money_ledger/core/database/daos/link_dao.dart';
import 'package:money_ledger/core/database/daos/members_dao.dart';
import 'package:money_ledger/core/database/daos/signing_dao.dart';
import 'package:money_ledger/core/link/group_policy.dart';
import 'package:money_ledger/core/link/link_channel.dart';
import 'package:money_ledger/core/link/link_uri.dart';
import 'package:money_ledger/core/matrix/hmac_record_crypto.dart';
import 'package:money_ledger/core/session/local_transport.dart';
import 'package:money_ledger/core/sync/ledger_payloads.dart';
import 'package:money_ledger/core/sync/record_gate.dart';
import 'package:money_ledger/core/sync/record_signing.dart';
import 'package:money_ledger/core/sync/record_validation.dart';
import 'package:money_ledger/core/sync/record_verifier.dart';
import 'package:money_ledger/core/sync/record_version.dart';
import 'package:money_ledger/models/expense_model.dart';
import 'package:money_ledger/models/group_model.dart';
import 'package:money_ledger/models/link_model.dart';
import 'package:money_ledger/models/member_model.dart';
import 'package:money_ledger/models/record_signature.dart';

import '../../helpers/fake_ledger_network.dart';
import '../../helpers/in_memory_database.dart';

const alice = '@alice:x.org';
const bob = '@bob:x.org';
const eve = '@eve:x.org';
const via = 'nostr:abcd';

final secret1 = encodeLinkSecret(List.filled(32, 1));
final secret2 = encodeLinkSecret(List.filled(32, 2));

LinkChannelModel channel(String group, {String? me, String? secret}) =>
    LinkChannelModel(
      groupId: group,
      epoch: 1,
      secret: secret ?? secret1,
      nostrPriv: '11' * 32,
      openedAt: 1,
      myParticipantId: me,
    );

ExpenseModel draft({
  String id = 'e1',
  String group = 'g1',
  int updatedAt = 1000,
}) => ExpenseModel(
  id: id,
  roomId: group,
  description: 'Dinner',
  amountCents: 4200,
  currency: 'EUR',
  paidBy: 'p1',
  splitsJson: '{"p1":4200}',
  createdAt: 1000,
  updatedAt: updatedAt,
);

MemberModel member(
  String pid, {
  String group = 'g1',
  String? matrixId,
  int updatedAt = 1,
  String status = 'active',
  String? name,
}) => MemberModel(
  groupId: group,
  userId: pid,
  displayName: name ?? pid,
  matrixId: matrixId,
  status: status,
  updatedAt: updatedAt,
);

GroupModel meta({
  int updatedAt = 10,
  String name = 'Trip',
  GroupLink? link,
  int? lockedAt,
}) => GroupModel(
  roomId: 'g1',
  name: name,
  currency: 'EUR',
  updatedAt: updatedAt,
  link: link,
  lockedAt: lockedAt,
);

void main() {
  test('linkBridgeAction (step 2): a Matrix member follows the signed '
      'meta; a lock drops every channel', () {
    // An unsigned meta never drives a channel.
    expect(
      linkBridgeAction(
        group: meta(link: GroupLink(epoch: 2, secret: secret2)),
        channel: null,
        me: 'pa',
      ),
      LinkBridgeAction.none,
    );
    final signedLinked = GroupModel(
      roomId: 'g1',
      name: 'Trip',
      currency: 'EUR',
      link: GroupLink(epoch: 2, secret: secret2),
      sig: _sig,
    );
    expect(
      linkBridgeAction(group: signedLinked, channel: null, me: 'pa'),
      LinkBridgeAction.create,
    );
    expect(
      linkBridgeAction(group: signedLinked, channel: null, me: null),
      LinkBridgeAction.none,
      reason: 'no Matrix participant here → no bridging',
    );
    expect(
      linkBridgeAction(
        group: signedLinked,
        channel: channel('g1', me: 'pa'),
        me: 'pa',
      ),
      LinkBridgeAction.replace,
    );
    expect(
      linkBridgeAction(
        group: signedLinked,
        channel: channel('g1', me: 'px', secret: secret2),
        me: 'pa',
      ),
      LinkBridgeAction.setMe,
    );
    expect(
      linkBridgeAction(
        group: signedLinked,
        channel: channel('g1', me: 'pa', secret: secret2),
        me: 'pa',
      ),
      LinkBridgeAction.none,
    );
    final locked = GroupModel(
      roomId: 'g1',
      name: 'Trip',
      currency: 'EUR',
      lockedAt: 5,
      sig: _sig,
    );
    expect(
      linkBridgeAction(group: locked, channel: channel('g1'), me: null),
      LinkBridgeAction.drop,
    );
    expect(
      linkBridgeAction(group: locked, channel: null, me: 'pa'),
      LinkBridgeAction.none,
    );
  });

  group('wire / signed body / hash', () {
    test('a meta without link state keeps its pre-G53 payload, body and '
        'hash', () {
      final plain = meta();
      expect(groupMetaPayload(plain).containsKey('link'), isFalse);
      expect(groupMetaPayload(plain).containsKey('locked_at'), isFalse);
      expect(groupMetaContent(plain).keys, isNot(contains('link')));
      expect(
        groupMetaVersionHash(plain),
        groupMetaVersionHash(meta().asLinkVersion('p1')),
      );
    });

    test('link and locked_at are in the payload, the signed body and the '
        'hash — and round-trip', () {
      final linked = meta(link: GroupLink(epoch: 2, secret: secret1));
      final payload = groupMetaPayload(linked);
      expect(payload['link'], {'epoch': 2, 'secret': secret1});
      expect(groupMetaContent(linked)['link'], {'epoch': 2, 'secret': secret1});
      expect(groupMetaVersionHash(linked), isNot(groupMetaVersionHash(meta())));
      final parsed = groupMetaFromPayload(payload)!;
      expect(parsed.link, GroupLink(epoch: 2, secret: secret1));
      expect(parsed.lockedAt, isNull);

      final locked = meta(lockedAt: 77);
      expect(groupMetaPayload(locked)['locked_at'], 77);
      expect(groupMetaContent(locked)['locked_at'], 77);
      expect(groupMetaFromPayload(groupMetaPayload(locked))!.lockedAt, 77);
      expect(groupMetaVersionHash(locked), isNot(groupMetaVersionHash(meta())));
    });

    test('the secret never shows up in toString', () {
      final link = GroupLink(epoch: 3, secret: secret1);
      expect(link.toString(), isNot(contains(secret1)));
    });

    test('malformed link state parses to values the content rules refuse', () {
      final bad = groupMetaFromPayload({
        ...groupMetaPayload(meta()),
        'link': 'nope',
        'locked_at': 'x',
      })!;
      expect(bad.link, isNotNull);
      expect(groupMetaProblem(bad), isNotNull);
      expect(
        groupMetaProblem(meta(link: const GroupLink(epoch: 1, secret: 'x'))),
        'link secret',
      );
      expect(
        groupMetaProblem(meta(link: GroupLink(epoch: 0, secret: secret1))),
        'link epoch 0',
      );
      expect(groupMetaProblem(meta(lockedAt: -1)), 'locked_at -1');
      expect(
        groupMetaProblem(meta(link: GroupLink(epoch: 1, secret: secret1))),
        isNull,
      );
    });

    test('nextVersion keeps the link state unless told otherwise; an '
        'unsigned link version drops it', () {
      final linked = meta(link: GroupLink(epoch: 1, secret: secret1));
      expect(linked.nextVersion(updatedAt: 20, name: 'X').link, linked.link);
      expect(
        linked.nextVersion(updatedAt: 20, link: null, lockedAt: 5).link,
        isNull,
      );
      expect(linked.asLinkVersion('p1').link, isNull);
    });
  });

  group('DAO + policy', () {
    late AppDatabase db;
    setUp(() => db = openTestDatabase());
    tearDown(() => db.close());

    test('link state is stored, read back and cleared by a lock', () async {
      final groups = GroupsDao(db);
      final crypto = HmacKeyRegistry().deviceCrypto(alice, 'A');
      final linked = await signGroupMeta(
        crypto,
        meta(link: GroupLink(epoch: 2, secret: secret1)),
      );
      await groups.upsertGroupLww(groupCompanion(linked));
      final stored = (await groups.getGroup('g1'))!;
      expect(stored.link, GroupLink(epoch: 2, secret: secret1));
      expect(groupMetaVersion(stored), groupMetaVersion(linked));
      final policy = await LinkDao(db).policyOf('g1');
      expect(policy.policy, GroupPolicy.mixed, reason: 'no channel needed');
      expect(policy.hasChannel, isFalse);

      final lock = await signGroupMeta(
        crypto,
        stored.nextVersion(updatedAt: 30, link: null, lockedAt: 25),
      );
      await groups.upsertGroupLww(groupCompanion(lock));
      final after = (await groups.getGroup('g1'))!;
      expect(after.link, isNull);
      expect(after.lockedAt, 25);
      expect(after.isLocked, isTrue);
      await LinkDao(db).putChannel(channel('g1'));
      final locked = await LinkDao(db).policyOf('g1');
      expect(locked.policy, GroupPolicy.matrix);
      expect(locked.lockedAt, 25);
      expect(locked.hasChannel, isTrue);
    });
  });

  group('RecordGate', () {
    late AppDatabase db;
    late SigningDao signing;
    late ExpensesDao expenses;
    late MembersDao members;
    late GroupsDao groups;
    late LinkDao link;
    late HmacKeyRegistry keys;
    late HmacRecordCrypto aliceDevice;
    late HmacRecordCrypto bobDevice;
    late HmacRecordCrypto eveDevice;
    late RecordGate linkGate;
    late RecordGate matrixGate;
    late RecordGate plainGate;
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
      bobDevice = keys.deviceCrypto(bob, 'BBBB');
      eveDevice = keys.deviceCrypto(eve, 'EEEE');
      now = 1000000;
      final verifier = RecordVerifier(
        crypto: aliceDevice,
        directory: keys,
        signing: signing,
        clock: () => now,
        refreshInterval: Duration.zero,
      );
      RecordGate gate({GroupPolicyLookup? linkP, GroupPolicyLookup? matrixP}) =>
          RecordGate(
            verifier: verifier,
            signing: signing,
            groups: groups,
            members: members,
            expenses: expenses,
            linkPolicy: linkP,
            matrixPolicy: matrixP,
            clock: () => now,
          );
      linkGate = gate(linkP: link.policyOf);
      matrixGate = gate(matrixP: link.policyOf);
      plainGate = gate();
      // g1: Alice's Matrix group (claimed participant pa), plus Ben (p1)
      // without an account.
      await members.upsertMemberLww(
        memberCompanion(
          await signMember(aliceDevice, member('pa', matrixId: alice)),
        ),
      );
      await members.upsertMemberLww(memberCompanion(member('p1')));
    });
    tearDown(() => db.close());

    Future<void> storeMeta(GroupModel g) async {
      await groups.upsertGroupLww(
        groupCompanion(await signGroupMeta(aliceDevice, g)),
      );
    }

    Future<void> openLink() =>
        storeMeta(meta(link: GroupLink(epoch: 1, secret: secret1)));

    test(
      'Matrix path, Matrix group: unsigned versions refused as before',
      () async {
        await storeMeta(meta());
        expect(
          await matrixGate.expense(expensePayload(draft()), relayedBy: alice),
          isFalse,
        );
        expect(await signing.rejectedClock('g1', 'expense', 'e1'), 1000);
      },
    );

    test(
      'Matrix path, mixed group: an unsigned expense relayed by a member '
      'is accepted (unsigned, `by` kept); without matrixPolicy it is not',
      () async {
        await openLink();
        final payload = expensePayload(draft())..['by'] = 'p1';
        expect(await plainGate.expense(payload, relayedBy: alice), isFalse);
        // The plain refusal is recorded — opening the link again forgets it
        // (see below); clear it here to test the mixed gate on its own.
        await signing.clearUnsignedRefusals('g1');
        expect(await matrixGate.expense(payload, relayedBy: alice), isTrue);
        final stored = (await expenses.getExpenseById('e1'))!;
        expect(stored.sig, isNull);
        expect(stored.origin, isNull);
        expect(stored.pendingSign, isFalse);
        expect(stored.linkAuthor, 'p1');
      },
    );

    test('mixed: an unsigned meta is refused on both paths', () async {
      await openLink();
      final unsigned = groupMetaPayload(meta(updatedAt: 99, name: 'Hijack'));
      expect(await matrixGate.meta(unsigned, relayedBy: alice), isFalse);
      expect(await linkGate.meta(unsigned, relayedBy: via), isFalse);
      expect((await groups.getGroup('g1'))!.name, 'Trip');
    });

    test('an unsigned meta carrying link state is invalid', () async {
      await link.putChannel(channel('g1'));
      final forged = groupMetaPayload(
        meta(updatedAt: 99, link: GroupLink(epoch: 5, secret: secret2)),
      );
      expect(await linkGate.meta(forged, relayedBy: via), isFalse);
      expect(
        (await signing.rejectedVersion('g1', 'meta', 'g1'))?.at,
        99,
        reason: 'recorded as invalid_record',
      );
      expect(await groups.getGroup('g1'), isNull);
    });

    test('mixed: unsigned claims and unsigned changes of a claimed '
        'participant are refused on both paths', () async {
      await openLink();
      final claim = memberPayload(member('p1', matrixId: eve, updatedAt: 5));
      expect(await matrixGate.member(claim, relayedBy: alice), isFalse);
      expect(await linkGate.member(claim, relayedBy: via), isFalse);
      final unclaim = memberPayload(
        member('pa', updatedAt: 50, name: 'Renamed'),
      );
      expect(await linkGate.member(unclaim, relayedBy: via), isFalse);
      expect(await matrixGate.member(unclaim, relayedBy: alice), isFalse);
      final stored = (await members.getMembers(
        'g1',
      )).firstWhere((m) => m.userId == 'pa');
      expect(stored.matrixId, alice);
      // An unclaimed person may still be renamed unsigned.
      final rename = memberPayload(member('p1', updatedAt: 6, name: 'Ben'));
      expect(await linkGate.member(rename, relayedBy: via), isTrue);
    });

    test('a meta opening a link forgets earlier unsigned refusals', () async {
      await storeMeta(meta());
      await plainGate.expense(expensePayload(draft()), relayedBy: alice);
      await signing.recordRejected(
        const RefusedVersion(
          groupId: 'g1',
          kind: 'expense',
          recordId: 'e2',
          updatedAt: 5,
          reason: 'bad_signature',
          relayedBy: alice,
          versionHash: 'ab',
        ),
      );
      expect(await signing.rejectedClock('g1', 'expense', 'e1'), 1000);
      final opened = await signGroupMeta(
        aliceDevice,
        meta(updatedAt: 20, link: GroupLink(epoch: 1, secret: secret1)),
      );
      expect(
        await matrixGate.meta(groupMetaPayload(opened), relayedBy: alice),
        isTrue,
      );
      expect(await signing.rejectedClock('g1', 'expense', 'e1'), isNull);
      expect(
        await signing.rejectedClock('g1', 'expense', 'e2'),
        5,
        reason: 'other refusals stay',
      );
      expect(
        await matrixGate.expense(expensePayload(draft()), relayedBy: alice),
        isTrue,
      );
    });

    test('locked: unsigned versions up to locked_at are accepted (link-time '
        'history), newer ones refused and recorded', () async {
      await storeMeta(meta(updatedAt: 20, lockedAt: 5000));
      expect(
        await matrixGate.expense(
          expensePayload(draft(updatedAt: 4000)),
          relayedBy: alice,
        ),
        isTrue,
      );
      expect(
        await matrixGate.expense(
          expensePayload(draft(id: 'e2', updatedAt: 6000)),
          relayedBy: alice,
        ),
        isFalse,
      );
      expect(await signing.rejectedClock('g1', 'expense', 'e2'), 6000);
      // On the link path (a channel not dropped yet) the same.
      await link.putChannel(channel('g1'));
      expect(
        await linkGate.expense(
          expensePayload(draft(id: 'e3', updatedAt: 7000)),
          relayedBy: via,
        ),
        isFalse,
      );
    });

    test(
      'link path: a signed self-claim of an unclaimed participant is '
      'accepted in a link-only group; claiming someone else is not',
      () async {
        await groups.upsertGroupLww(groupCompanion(meta().asLinkVersion(null)));
        await members.upsertMemberLww(
          memberCompanion(member('pb', updatedAt: 1)),
        );
        await link.putChannel(channel('g1', me: 'p1'));
        expect(await link.isLinkOnly('g1'), isTrue);

        // Bob claims p1 with his own signature: accepted.
        final self = await signMember(
          bobDevice,
          member('p1', matrixId: bob, updatedAt: 5),
        );
        expect(
          await linkGate.member(memberPayload(self), relayedBy: via),
          isTrue,
        );
        // Eve signs a claim of pb for Bob: refused (signer ≠ claimed account).
        final other = await signMember(
          eveDevice,
          member('pb', matrixId: bob, updatedAt: 5),
        );
        expect(
          await linkGate.member(memberPayload(other), relayedBy: via),
          isFalse,
        );
        // Eve claims p1, which Bob claims already: refused.
        final taken = await signMember(
          eveDevice,
          member('p1', matrixId: eve, updatedAt: 9),
        );
        expect(
          await linkGate.member(memberPayload(taken), relayedBy: via),
          isFalse,
        );
        // A removed participant can't be claimed by itself.
        await members.upsertMemberLww(
          memberCompanion(member('pr', status: 'removed', updatedAt: 1)),
        );
        final removed = await signMember(
          eveDevice,
          member('pr', matrixId: eve, updatedAt: 5),
        );
        expect(
          await linkGate.member(memberPayload(removed), relayedBy: via),
          isFalse,
        );
        final stored = {
          for (final m in await members.getMembers('g1')) m.userId: m,
        };
        expect(stored['p1']!.matrixId, bob);
        expect(stored['pb']!.matrixId, isNull);
      },
    );

    test('link path, mixed: a member may assign a Matrix account (signed); '
        'a non-member may not', () async {
      await openLink();
      await link.putChannel(channel('g1', me: 'pa'));
      final invite = await signMember(
        aliceDevice,
        member('p1', matrixId: bob, updatedAt: 5),
      );
      expect(
        await linkGate.member(memberPayload(invite), relayedBy: via),
        isTrue,
      );
      final rogue = await signMember(
        eveDevice,
        member('px', matrixId: eve, updatedAt: 5),
      );
      expect(
        await linkGate.member(memberPayload(rogue), relayedBy: via),
        isFalse,
      );
    });
  });

  group('LocalRecordSigner of a Matrix account (review)', () {
    late AppDatabase db;
    setUp(() async {
      db = openTestDatabase();
      final crypto = HmacKeyRegistry().deviceCrypto(alice, 'A');
      await GroupsDao(db).upsertGroupLww(
        groupCompanion(
          await signGroupMeta(
            crypto,
            meta(link: GroupLink(epoch: 1, secret: secret1)),
          ),
        ),
      );
      await MembersDao(
        db,
      ).upsertMemberLww(memberCompanion(member('pa', matrixId: alice)));
      await MembersDao(db).upsertMemberLww(memberCompanion(member('p1')));
    });
    tearDown(() => db.close());

    test('joined a mixed group by link (its "me" is unclaimed): writes '
        'link versions — a signed one by a non-member would be dropped by '
        'every peer', () async {
      await LinkDao(db).putChannel(channel('g1', me: 'p1'));
      final signer = LocalRecordSigner(
        Future.value(FakeMatrixNetwork().clientFor(eve)),
        policy: LinkDao(db).policyOf,
      );
      final e = await signer.expense(draft(), creating: true);
      expect(
        (e.sig, e.origin, e.pendingSign, e.linkAuthor),
        (null, null, false, 'p1'),
      );
      await expectLater(
        signer.group(meta(updatedAt: 99, name: 'X')),
        throwsA(isA<SignatureRequiredException>()),
      );
    });

    test('a member whose channel "me" it claims (bridging) signs', () async {
      await LinkDao(db).putChannel(channel('g1', me: 'pa'));
      final signer = LocalRecordSigner(
        Future.value(FakeMatrixNetwork().clientFor(alice)),
        policy: LinkDao(db).policyOf,
      );
      final e = await signer.expense(draft(), creating: true);
      expect(e.sig, isNotNull);
      expect(e.linkAuthor, isNull);
      final g = await signer.group(meta(updatedAt: 99, name: 'X'));
      expect(g.sig, isNotNull);
    });

    test('a member that has not bridged yet (no channel) signs', () async {
      final signer = LocalRecordSigner(
        Future.value(FakeMatrixNetwork().clientFor(alice)),
        policy: LinkDao(db).policyOf,
      );
      final e = await signer.expense(draft(), creating: true);
      expect(e.sig, isNotNull);
    });
  });

  group('LocalRecordSigner without a Matrix account', () {
    late AppDatabase db;
    late LocalRecordSigner signer;
    setUp(() async {
      db = openTestDatabase();
      final crypto = HmacKeyRegistry().deviceCrypto(alice, 'A');
      await GroupsDao(db).upsertGroupLww(
        groupCompanion(
          await signGroupMeta(
            crypto,
            meta(link: GroupLink(epoch: 1, secret: secret1)),
          ),
        ),
      );
      await LinkDao(db).putChannel(channel('g1', me: 'p1'));
      signer = LocalRecordSigner(
        Future.value(LocalOnlyTransport('Ben')),
        policy: LinkDao(db).policyOf,
      );
    });
    tearDown(() => db.close());

    test(
      'mixed: records and unclaimed people are written as link versions',
      () async {
        final e = await signer.expense(draft(), creating: true);
        expect((e.sig, e.pendingSign, e.linkAuthor), (null, false, 'p1'));
        final m = await signer.member(member('p2'));
        expect((m.sig, m.pendingSign, m.linkAuthor), (null, false, 'p1'));
      },
    );

    test('mixed: the meta and claimed people need a signature', () async {
      await expectLater(
        signer.group(meta(updatedAt: 99, name: 'X')),
        throwsA(isA<SignatureRequiredException>()),
      );
      await expectLater(
        signer.member(member('pa', matrixId: alice, updatedAt: 9)),
        throwsA(isA<SignatureRequiredException>()),
      );
    });

    test('locked: nothing can be written', () async {
      final crypto = HmacKeyRegistry().deviceCrypto(alice, 'A');
      await GroupsDao(db).upsertGroupLww(
        groupCompanion(
          await signGroupMeta(crypto, meta(updatedAt: 50, lockedAt: 40)),
        ),
      );
      await expectLater(
        signer.expense(draft(), creating: true),
        throwsA(isA<SignatureRequiredException>()),
      );
    });
  });
}

/// A syntactically valid signature for pure policy checks (never verified).
const _sig = RecordSignature(user: alice, device: 'D', key: 'k', sig: 's');
