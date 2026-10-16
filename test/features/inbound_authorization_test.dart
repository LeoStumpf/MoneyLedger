/// Inbound authorization (Phase F, M1): the membership gate + clock clamp that
/// `LedgerSyncer` applies to E2EE-authenticated to-device records. No
/// package:matrix import — pure functions over plain Dart.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/matrix/ledger_transport.dart';
import 'package:money_ledger/features/expenses/ledger_syncer.dart';
import 'package:money_ledger/models/member_model.dart';

MemberModel _m(String userId, {String? matrixId, String status = 'active'}) =>
    MemberModel(
      groupId: 'g1',
      userId: userId,
      matrixId: matrixId,
      status: status,
      updatedAt: 1,
    );

bool _auth({
  required String type,
  required String sender,
  Map<String, dynamic> content = const {},
  required List<MemberModel> members,
  bool groupKnown = true,
}) => LedgerSyncer.isSenderAuthorized(
  type: type,
  senderId: sender,
  content: content,
  members: members,
  groupKnown: groupKnown,
);

void main() {
  // alice (claimed), a local-only participant "bobby", and bob's account.
  final members = [
    _m('@alice:x.org', matrixId: '@alice:x.org'),
    _m('p-bobby'), // unclaimed local participant
  ];

  group('expense / settlement / group meta', () {
    test('an active claimed member is authorized', () {
      expect(
        _auth(type: expenseEventType, sender: '@alice:x.org', members: members),
        isTrue,
      );
      expect(
        _auth(
          type: settlementEventType,
          sender: '@alice:x.org',
          members: members,
        ),
        isTrue,
      );
      expect(
        _auth(
          type: groupMetaEventType,
          sender: '@alice:x.org',
          members: members,
        ),
        isTrue,
      );
    });

    test('a non-member is rejected (the forge-a-record hole)', () {
      expect(
        _auth(
          type: expenseEventType,
          sender: '@mallory:x.org',
          members: members,
        ),
        isFalse,
      );
    });

    test('a removed member is rejected', () {
      final removed = [
        _m('@bob:x.org', matrixId: '@bob:x.org', status: 'removed'),
      ];
      expect(
        _auth(type: expenseEventType, sender: '@bob:x.org', members: removed),
        isFalse,
      );
    });
  });

  group('bootstrap', () {
    test('an unknown group is TOFU-accepted from anyone', () {
      expect(
        _auth(
          type: bootstrapEventType,
          sender: '@whoever:x.org',
          members: const [],
          groupKnown: false,
        ),
        isTrue,
      );
    });

    test('a known group is re-snapshotted only by an active member', () {
      expect(
        _auth(
          type: bootstrapEventType,
          sender: '@alice:x.org',
          members: members,
        ),
        isTrue,
      );
      expect(
        _auth(
          type: bootstrapEventType,
          sender: '@mallory:x.org',
          members: members,
        ),
        isFalse,
      );
    });
  });

  group('member (claim / membership)', () {
    test('an active member may gossip any membership change', () {
      // Alice marks the local participant removed.
      expect(
        _auth(
          type: memberEventType,
          sender: '@alice:x.org',
          content: const {'participant_id': 'p-bobby', 'status': 'removed'},
          members: members,
        ),
        isTrue,
      );
    });

    // G18 review: a non-member can never make itself a participant — no
    // self-claim of a local person, no join-as-new, no rejoin after removal.
    test(
      'self-claim of an unclaimed participant by a non-member is refused',
      () {
        expect(
          _auth(
            type: memberEventType,
            sender: '@bob:y.org',
            content: const {
              'participant_id': 'p-bobby',
              'matrix_id': '@bob:y.org',
              'status': 'active',
            },
            members: members,
          ),
          isFalse,
        );
      },
    );

    test('join-as-new (a fresh participant for yourself) is refused', () {
      expect(
        _auth(
          type: memberEventType,
          sender: '@bob:y.org',
          content: const {
            'participant_id': 'p-new',
            'matrix_id': '@bob:y.org',
            'status': 'active',
          },
          members: members,
        ),
        isFalse,
      );
    });

    test('a removed member can neither reactivate itself nor rejoin with a '
        'fresh participant', () {
      final withRemoved = [
        ...members,
        _m('p-carol', matrixId: '@carol:z.org', status: 'removed'),
      ];
      for (final pid in ['p-carol', 'p-again']) {
        expect(
          _auth(
            type: memberEventType,
            sender: '@carol:z.org',
            content: {
              'participant_id': pid,
              'matrix_id': '@carol:z.org',
              'status': 'active',
            },
            members: withRemoved,
          ),
          isFalse,
          reason: pid,
        );
      }
    });

    test('hijacking a participant another account owns is rejected', () {
      expect(
        _auth(
          type: memberEventType,
          sender: '@mallory:x.org',
          content: const {
            'participant_id': '@alice:x.org', // alice's participant
            'matrix_id': '@mallory:x.org',
          },
          members: members,
        ),
        isFalse,
      );
    });

    test('forging membership for another account is rejected', () {
      expect(
        _auth(
          type: memberEventType,
          sender: '@mallory:x.org',
          content: const {
            'participant_id': 'p-victim',
            'matrix_id': '@victim:x.org',
          },
          members: members,
        ),
        isFalse,
      );
    });

    test('a non-member cannot gossip a local participant', () {
      expect(
        _auth(
          type: memberEventType,
          sender: '@mallory:x.org',
          content: const {'participant_id': 'p-x', 'name': 'X'},
          members: members,
        ),
        isFalse,
      );
    });
  });

  group('clampInboundClock', () {
    const now = 1_000_000_000_000;
    const tolerance = 5 * 60 * 1000;

    test('a past or present clock is unchanged', () {
      expect(LedgerSyncer.clampInboundClock(now - 1000, now: now), now - 1000);
      expect(LedgerSyncer.clampInboundClock(now, now: now), now);
    });

    test('a clock within tolerance is unchanged', () {
      expect(
        LedgerSyncer.clampInboundClock(now + tolerance, now: now),
        now + tolerance,
      );
    });

    test('a far-future clock is clamped to now + tolerance', () {
      expect(
        LedgerSyncer.clampInboundClock(now + 999999999, now: now),
        now + tolerance,
      );
    });
  });
}
