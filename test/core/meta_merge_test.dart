/// G57 (C1) per-field meta clocks + G74 payment details in the member record
/// — the wire (only-when-set: old bodies / hashes unchanged), the pure
/// field merge, the content rules, and the `RecordGate` paths (merge written
/// by this device; payment details only from the participant itself).
library;

import 'package:canonical_json/canonical_json.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/database/app_database.dart';
import 'package:money_ledger/core/database/daos/expenses_dao.dart';
import 'package:money_ledger/core/database/daos/groups_dao.dart';
import 'package:money_ledger/core/database/daos/link_dao.dart';
import 'package:money_ledger/core/database/daos/members_dao.dart';
import 'package:money_ledger/core/database/daos/signing_dao.dart';
import 'package:money_ledger/core/sync/ledger_payloads.dart';
import 'package:money_ledger/core/sync/meta_merge.dart';
import 'package:money_ledger/core/sync/record_gate.dart';
import 'package:money_ledger/core/sync/record_signing.dart';
import 'package:money_ledger/core/sync/record_validation.dart';
import 'package:money_ledger/core/sync/record_verifier.dart';
import 'package:money_ledger/core/sync/record_version.dart';
import 'package:money_ledger/models/exchange_rates.dart';
import 'package:money_ledger/models/expense_category.dart';
import 'package:money_ledger/models/group_model.dart';
import 'package:money_ledger/models/link_model.dart';
import 'package:money_ledger/models/member_model.dart';
import 'package:money_ledger/models/payment_details.dart';

import '../helpers/fake_ledger_network.dart';
import '../helpers/in_memory_database.dart';

const _alice = '@alice:x.org';
const _bob = '@bob:y.org';

const _dog = CustomCategory(id: 'c:dog', name: 'Dog', icon: 'pets');
const _fuel = CustomCategory(id: 'c:fuel', name: 'Fuel', icon: 'star');

const _details = PaymentDetails(
  name: 'Anna Example',
  iban: 'DE89370400440532013000',
  bic: 'COBADEFFXXX',
  paypalMe: 'anna',
);

String _sha(Map<String, Object?> m) =>
    sha256.convert(canonicalJson.encode(m)).toString();

GroupModel _meta({
  int at = 100,
  String name = 'Trip',
  String currency = 'EUR',
  List<CustomCategory> categories = const [],
  ExchangeRates? fx,
  Map<String, int> clocks = const {},
}) => GroupModel(
  roomId: 'g1',
  name: name,
  currency: currency,
  updatedAt: at,
  categories: categories,
  exchangeRates: fx,
  fieldClocks: clocks,
);

void main() {
  group('wire: only when set', () {
    test('a meta whose fields all changed with it keeps the pre-G57 body '
        'and hash (no `clocks`)', () {
      final g = _meta(categories: const [_dog]);
      final content = groupMetaContent(g);
      expect(content.containsKey('clocks'), isFalse);
      expect(groupMetaPayload(g).containsKey('clocks'), isFalse);
      expect(
        groupMetaVersionHash(g),
        _sha({
          't': 'com.moneyledger.group',
          'group': 'g1',
          'name': 'Trip',
          'currency': 'EUR',
          'updated_at': 100,
          'categories': [
            {'id': 'c:dog', 'name': 'Dog', 'icon': 'pets'},
          ],
        }),
      );
    });

    test('older fields ride in `clocks` (sorted, only below updated_at), '
        'round-trip through the payload and change the hash', () {
      final next = _meta(
        categories: const [_dog],
      ).nextVersion(updatedAt: 200, name: 'Ski');
      expect(next.wireClocks, {
        'c:dog': 100,
        'currency': 100,
        'exchange_rates': 100,
      });
      final payload = groupMetaPayload(next);
      expect(payload['clocks'], next.wireClocks);
      final back = groupMetaFromPayload(payload)!;
      expect(back.wireClocks, next.wireClocks);
      expect(groupMetaVersionHash(back), groupMetaVersionHash(next));
      expect(back.clockOf('name'), 200);
      expect(back.clockOf('c:dog'), 100);
      // The empty link state never needs (or carries) a clock.
      expect(back.clockOf('link'), 0);
    });

    test('a member without payment details keeps the pre-G74 body and hash; '
        'with them the payload carries `payment`', () {
      const m = MemberModel(
        groupId: 'g1',
        userId: 'p1',
        displayName: 'Anna',
        matrixId: _alice,
        status: 'active',
        updatedAt: 5,
      );
      expect(memberContent(m).containsKey('payment'), isFalse);
      expect(
        memberVersionHash(m),
        _sha({
          't': 'com.moneyledger.member',
          'group': 'g1',
          'participant_id': 'p1',
          'name': 'Anna',
          'matrix_id': _alice,
          'status': 'active',
          'updated_at': 5,
        }),
      );
      final paid = MemberModel(
        groupId: 'g1',
        userId: 'p1',
        displayName: 'Anna',
        matrixId: _alice,
        status: 'active',
        updatedAt: 5,
        payment: _details,
      );
      final payload = memberPayload(paid);
      expect(payload['payment'], {
        'name': 'Anna Example',
        'iban': 'DE89370400440532013000',
        'bic': 'COBADEFFXXX',
        'paypal_me': 'anna',
      });
      final back = memberFromPayload(payload)!;
      expect(back.payment, _details);
      expect(memberVersionHash(back), memberVersionHash(paid));
      expect(memberVersionHash(paid), isNot(memberVersionHash(m)));
    });
  });

  group('nextVersion', () {
    test('changed fields get the new clock, the others keep theirs', () {
      final v1 = _meta(categories: const [_dog]);
      final v2 = v1.nextVersion(updatedAt: 200, currency: 'CHF');
      final v3 = v2.nextVersion(updatedAt: 300, categories: [_dog, _fuel]);
      expect(v3.clockOf('name'), 100);
      expect(v3.clockOf('currency'), 200);
      expect(v3.clockOf('c:dog'), 100);
      expect(v3.clockOf('c:fuel'), 300);
    });

    test('a category left out is kept hidden (never deleted)', () {
      final v1 = _meta(categories: const [_dog, _fuel]);
      final v2 = v1.nextVersion(updatedAt: 200, categories: const [_fuel]);
      expect(v2.categories.map((c) => (c.id, c.hidden)), [
        ('c:fuel', false),
        ('c:dog', true),
      ]);
      expect(v2.clockOf('c:dog'), 200);
      expect(v2.clockOf('c:fuel'), 100);
    });
  });

  group('mergeGroupMeta', () {
    final base = _meta(categories: const [_dog]);
    final renamed = base.nextVersion(updatedAt: 200, name: 'Ski');
    final added = base.nextVersion(updatedAt: 190, categories: [_dog, _fuel]);
    final rates = base.nextVersion(
      updatedAt: 180,
      exchangeRates: ExchangeRates(base: 'EUR', rates: const {'CHF': '1.1'}),
    );

    test('concurrent rename, category add and rate change all survive', () {
      final m = mergeGroupMeta(mergeGroupMeta(renamed, added), rates);
      expect(m.name, 'Ski');
      expect(m.categories.map((c) => c.id), ['c:dog', 'c:fuel']);
      expect(m.exchangeRates?.rates, {'CHF': '1.1'});
      expect(m.clockOf('name'), 200);
      expect(m.clockOf('c:fuel'), 190);
      expect(m.clockOf('exchange_rates'), 180);
    });

    test('commutative, associative, idempotent (same fields)', () {
      final ab = mergeGroupMeta(renamed, added);
      final ba = mergeGroupMeta(added, renamed);
      expect(sameMetaFields(ab, ba), isTrue);
      expect(
        sameMetaFields(
          mergeGroupMeta(ab, rates),
          mergeGroupMeta(renamed, mergeGroupMeta(added, rates)),
        ),
        isTrue,
      );
      expect(sameMetaFields(mergeGroupMeta(ab, ab), ab), isTrue);
      expect(sameMetaFields(mergeGroupMeta(ab, renamed), ab), isTrue);
      expect(sameMetaFields(ab, renamed), isFalse);
    });

    test('the same field: the higher clock wins; a tie by the value hash, '
        'the same on both sides', () {
      final a = base.nextVersion(
        updatedAt: 300,
        categories: [_dog.copyWith(name: 'Doggo')],
      );
      final b = base.nextVersion(
        updatedAt: 250,
        categories: [_dog.copyWith(name: 'Hound')],
      );
      expect(mergeGroupMeta(a, b).categories.single.name, 'Doggo');
      expect(mergeGroupMeta(b, a).categories.single.name, 'Doggo');
      final x = base.nextVersion(updatedAt: 300, name: 'X');
      final y = base.nextVersion(updatedAt: 300, name: 'Y');
      expect(mergeGroupMeta(x, y).name, mergeGroupMeta(y, x).name);
    });

    test('removing the rates later beats setting them earlier — and not '
        'the other way round', () {
      final set = rates; // rates at 180
      final removed = set.nextVersion(updatedAt: 400, exchangeRates: null);
      expect(mergeGroupMeta(set, removed).exchangeRates, isNull);
      // A rename at 500 based on the old state (no rates, clock 100) doesn't
      // remove rates set at 180.
      final renamedLater = base.nextVersion(updatedAt: 500, name: 'Z');
      final m = mergeGroupMeta(renamedLater, set);
      expect(m.exchangeRates?.rates, {'CHF': '1.1'});
      expect(m.name, 'Z');
    });

    test('an opened link survives a concurrent edit that never saw it', () {
      final open = base.nextVersion(
        updatedAt: 150,
        link: const GroupLink(epoch: 1, secret: 's'),
      );
      final m = mergeGroupMeta(renamed, open);
      expect(m.link?.secret, 's');
      expect(m.name, 'Ski');
      // A lock (link dropped, locked_at set) later wins over it.
      final locked = open.nextVersion(
        updatedAt: 600,
        link: null,
        lockedAt: 600,
      );
      final l = mergeGroupMeta(open, locked);
      expect(l.link, isNull);
      expect(l.lockedAt, 600);
    });

    test('atClock stamps a merged version with every field clock explicit', () {
      final m = mergeGroupMeta(renamed, added).atClock(201);
      expect(m.updatedAt, 201);
      expect(m.wireClocks, {
        'c:dog': 100,
        'c:fuel': 190,
        'currency': 100,
        'exchange_rates': 100,
        'name': 200,
      });
      expect(groupMetaProblem(m), isNull);
    });
  });

  group('content rules', () {
    test('field clocks: unknown keys / negative values are refused', () {
      expect(groupMetaProblem(_meta(clocks: {'name': 5})), isNull);
      expect(groupMetaProblem(_meta(clocks: {'bogus': 5})), isNotNull);
      expect(groupMetaProblem(_meta(clocks: {'c:none': 5})), isNotNull);
      expect(groupMetaProblem(_meta(clocks: {'name': -1})), isNotNull);
      final malformed = groupMetaFromPayload({
        'group': 'g1',
        'name': 'Trip',
        'currency': 'EUR',
        'updated_at': 100,
        'clocks': {'name': 'x'},
      })!;
      expect(groupMetaProblem(malformed), isNotNull);
    });

    test('payment details must be in their stored form and usable', () {
      expect(paymentProblem(null), isNull);
      expect(paymentProblem(_details), isNull);
      expect(paymentProblem(const PaymentDetails(paypalMe: 'anna')), isNull);
      for (final bad in [
        const PaymentDetails(iban: 'DE89370400440532013000'), // no holder
        const PaymentDetails(name: ' Anna', paypalMe: 'anna'),
        const PaymentDetails(name: 'A', iban: 'DE89 3704 0044 0532 0130 00'),
        const PaymentDetails(name: 'A', iban: 'DE00370400440532013000'),
        const PaymentDetails(paypalMe: 'anna', bic: 'COBADEFFXXX'),
        const PaymentDetails(paypalMe: 'paypal.me/anna'),
        PaymentDetails.invalid,
      ]) {
        expect(paymentProblem(bad), isNotNull, reason: '$bad');
      }
      expect(PaymentDetails.fromWire({'iban': 3}), PaymentDetails.invalid);
      expect(PaymentDetails.fromWire({'x': 'y'}), PaymentDetails.invalid);
      expect(PaymentDetails.fromWire(const {}), PaymentDetails.invalid);
    });
  });

  group('RecordGate', () {
    late AppDatabase db;
    late GroupsDao groups;
    late MembersDao members;
    late SigningDao signing;
    late FakeMatrixNetwork net;
    late RecordGate gate;
    late RecordGate plainGate;
    late RecordGate linkGate;

    setUp(() async {
      db = openTestDatabase();
      groups = GroupsDao(db);
      members = MembersDao(db);
      signing = SigningDao(db);
      net = FakeMatrixNetwork();
      final me = net.clientFor(_alice);
      final verifier = RecordVerifier(
        crypto: me.crypto,
        directory: net.keys,
        signing: signing,
        refreshInterval: Duration.zero,
      );
      RecordGate build({bool merge = true, bool link = false}) => RecordGate(
        verifier: verifier,
        signing: signing,
        groups: groups,
        members: members,
        expenses: ExpensesDao(db),
        linkPolicy: link ? LinkDao(db).policyOf : null,
        matrixPolicy: LinkDao(db).policyOf,
        mergeMeta: merge
            ? metaMergeSigner(
                transport: Future.value(me),
                members: members,
                policy: LinkDao(db).policyOf,
              )
            : null,
      );
      gate = build();
      plainGate = build(merge: false);
      linkGate = build(link: true);
      for (final (pid, mxid) in [('p1', _alice), ('p2', _bob)]) {
        await members.upsertMemberLww(
          memberCompanion(
            await signMember(
              net.keys.deviceCrypto(mxid, 'D1'),
              MemberModel(
                groupId: 'g1',
                userId: pid,
                displayName: pid,
                matrixId: mxid,
                status: 'active',
                updatedAt: 1,
              ),
            ),
          ),
        );
      }
    });
    tearDown(() => db.close());

    Future<Map<String, dynamic>> signedMeta(String user, GroupModel g) async =>
        groupMetaPayload(
          await signGroupMeta(net.keys.deviceCrypto(user, 'D1'), g),
        );

    test('an older version with a newer field is merged and re-signed by '
        'this device; the merge is idempotent', () async {
      final base = _meta(categories: const [_dog]);
      final mine = base.nextVersion(updatedAt: 200, name: 'Ski');
      await groups.upsertGroupLww(
        groupCompanion(
          await signGroupMeta(net.keys.deviceCrypto(_alice, 'D1'), mine),
        ),
      );
      final theirs = base.nextVersion(
        updatedAt: 190,
        categories: [_dog, _fuel],
      );
      expect(
        await gate.meta(await signedMeta(_bob, theirs), relayedBy: _bob),
        isTrue,
      );
      final stored = (await groups.getGroup('g1'))!;
      expect(stored.name, 'Ski');
      expect(stored.categories.map((c) => c.id), ['c:dog', 'c:fuel']);
      expect(stored.updatedAt, greaterThan(200));
      expect(stored.sig?.user, _alice);
      // The same version again changes nothing.
      expect(
        await gate.meta(await signedMeta(_bob, theirs), relayedBy: _bob),
        isFalse,
      );
      expect(
        groupMetaVersion((await groups.getGroup('g1'))!),
        groupMetaVersion(stored),
      );
    });

    test(
      'a newer version that already holds everything is stored as is',
      () async {
        final base = _meta(categories: const [_dog]);
        await groups.upsertGroupLww(
          groupCompanion(
            await signGroupMeta(net.keys.deviceCrypto(_alice, 'D1'), base),
          ),
        );
        final theirs = base.nextVersion(updatedAt: 300, name: 'Ski');
        expect(
          await gate.meta(await signedMeta(_bob, theirs), relayedBy: _bob),
          isTrue,
        );
        final stored = (await groups.getGroup('g1'))!;
        expect(stored.sig?.user, _bob);
        expect(groupMetaVersion(stored), groupMetaVersion(theirs));
      },
    );

    test(
      'without a merge signer: plain LWW (an older version is dropped)',
      () async {
        final base = _meta();
        await groups.upsertGroupLww(
          groupCompanion(base.nextVersion(updatedAt: 200, name: 'Ski')),
        );
        final theirs = base.nextVersion(updatedAt: 190, categories: [_fuel]);
        expect(
          await plainGate.meta(await signedMeta(_bob, theirs), relayedBy: _bob),
          isFalse,
        );
        expect((await groups.getGroup('g1'))!.categories, isEmpty);
      },
    );

    test('a removed member merges nothing (its merge would be dropped by '
        'every peer)', () async {
      await members.upsertMemberLww(
        memberCompanion(
          await signMember(
            net.keys.deviceCrypto(_alice, 'D1'),
            const MemberModel(
              groupId: 'g1',
              userId: 'p1',
              displayName: 'p1',
              matrixId: _alice,
              status: 'removed',
              updatedAt: 2,
            ),
          ),
        ),
      );
      final base = _meta();
      await groups.upsertGroupLww(
        groupCompanion(base.nextVersion(updatedAt: 200, name: 'Ski')),
      );
      final theirs = base.nextVersion(updatedAt: 190, categories: [_fuel]);
      expect(
        await gate.meta(await signedMeta(_bob, theirs), relayedBy: _bob),
        isFalse,
      );
      expect((await groups.getGroup('g1'))!.name, 'Ski');
    });

    MemberModel p1({
      int at = 10,
      PaymentDetails? payment,
      String? matrixId = _alice,
      String name = 'p1',
    }) => MemberModel(
      groupId: 'g1',
      userId: 'p1',
      displayName: name,
      matrixId: matrixId,
      status: 'active',
      updatedAt: at,
      payment: payment,
    );

    Future<Map<String, dynamic>> signedMember(String by, MemberModel m) async =>
        memberPayload(await signMember(net.keys.deviceCrypto(by, 'D1'), m));

    test('payment details: set by the participant itself → accepted; set by '
        'another member → refused (transient, not recorded)', () async {
      expect(
        await gate.member(
          await signedMember(_bob, p1(payment: _details)),
          relayedBy: _bob,
        ),
        isFalse,
      );
      expect(await signing.rejectedClock('g1', 'member', 'p1'), isNull);
      expect(
        await gate.member(
          await signedMember(_alice, p1(payment: _details)),
          relayedBy: _alice,
        ),
        isTrue,
      );
      expect((await members.getMembers('g1')).first.payment, _details);
      // Another member's rename carries them over unchanged → fine.
      expect(
        await gate.member(
          await signedMember(_bob, p1(at: 20, payment: _details, name: 'A')),
          relayedBy: _bob,
        ),
        isTrue,
      );
      // Alice changes them; an editor that missed it carries the value
      // Alice herself published before → accepted (else the editor's
      // version — a rename, a removal — would never get in) …
      const newer = PaymentDetails(paypalMe: 'anna2');
      expect(
        await gate.member(
          await signedMember(_alice, p1(at: 25, payment: newer)),
          relayedBy: _alice,
        ),
        isTrue,
      );
      expect(
        await gate.member(
          await signedMember(_bob, p1(at: 30, payment: _details, name: 'B')),
          relayedBy: _bob,
        ),
        isTrue,
      );
      // … a value Alice never published → refused …
      expect(
        await gate.member(
          await signedMember(
            _bob,
            p1(at: 35, payment: const PaymentDetails(paypalMe: 'bob')),
          ),
          relayedBy: _bob,
        ),
        isFalse,
      );
      expect(await signing.rejectedClock('g1', 'member', 'p1'), isNull);
      // … an editor that never got any → may hold none (nobody can be paid
      // in Alice's place that way; her device publishes them again).
      expect(
        await gate.member(
          await signedMember(_bob, p1(at: 40, name: 'C')),
          relayedBy: _bob,
        ),
        isTrue,
      );
      expect(
        (await members.getMembers(
          'g1',
        )).firstWhere((m) => m.userId == 'p1').payment,
        isNull,
      );
      // A value Alice published, carried under another claim → refused.
      expect(
        await gate.member(
          await signedMember(
            _bob,
            p1(at: 50, payment: newer, matrixId: '@mallory:x.org'),
          ),
          relayedBy: _bob,
        ),
        isFalse,
      );
    });

    test('link path: only a version `by` the participant itself may change '
        'its payment details', () async {
      await groups.upsertGroupLww(groupCompanion(_meta(at: 1)));
      await LinkDao(db).putChannel(
        const LinkChannelModel(
          groupId: 'g2',
          epoch: 1,
          secret: 'c2VjcmV0',
          nostrPriv:
              '1111111111111111111111111111111111111111111111111111111111111111',
          openedAt: 1,
          myParticipantId: 'q1',
        ),
      );
      await groups.upsertGroupLww(
        groupCompanion(
          const GroupModel(roomId: 'g2', name: 'G', currency: 'EUR'),
        ),
      );
      for (final q in ['q1', 'q2']) {
        await members.upsertMemberLww(
          memberCompanion(
            MemberModel(
              groupId: 'g2',
              userId: q,
              displayName: q,
              status: 'active',
              updatedAt: 1,
              linkAuthor: q,
            ),
          ),
        );
      }
      Map<String, dynamic> q1(String by, int at) => memberPayload(
        MemberModel(
          groupId: 'g2',
          userId: 'q1',
          displayName: 'q1',
          status: 'active',
          updatedAt: at,
          linkAuthor: by,
          payment: const PaymentDetails(paypalMe: 'anna'),
        ),
      );
      expect(await linkGate.member(q1('q2', 5), relayedBy: 'nostr:x'), isFalse);
      expect(await linkGate.member(q1('q1', 6), relayedBy: 'nostr:x'), isTrue);
      expect(
        (await members.getMembers(
          'g2',
        )).firstWhere((m) => m.userId == 'q1').payment?.paypalMe,
        'anna',
      );
    });
  });
}
