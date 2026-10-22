/// G52 step 12 follow-up (design doc §7.3): the device-local "link
/// replaced" notice (pure) and the join look-up's handling of markers.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/link/link_join_probe.dart';
import 'package:money_ledger/core/link/link_replaced.dart';
import 'package:money_ledger/core/link/link_snapshot.dart';
import 'package:money_ledger/models/link_model.dart';

LinkChannelModel channel({int epoch = 1}) => LinkChannelModel(
  groupId: 'g',
  epoch: epoch,
  secret: 'c2VjcmV0',
  nostrPriv: '11' * 32,
  openedAt: 1,
);

void main() {
  group('LinkReplacedNotice', () {
    test('encode / decode round trip; corrupt → null', () {
      const n = LinkReplacedNotice(
        epoch: 2,
        eventId: 'ev',
        createdAt: 10,
        by: 'p1',
      );
      final back = LinkReplacedNotice.decode(n.encode())!;
      expect(
        (back.epoch, back.eventId, back.createdAt, back.by, back.dismissed),
        (2, 'ev', 10, 'p1', false),
      );
      expect(
        LinkReplacedNotice.decode(n.asDismissed.encode())!.dismissed,
        isTrue,
      );
      for (final bad in [null, '', 'x', '[]', '{"epoch":"1"}']) {
        expect(LinkReplacedNotice.decode(bad), isNull, reason: bad);
      }
    });

    test('nextLinkReplacedNotice: new / newer → store; same, older or '
        'dismissed on this channel → keep; another epoch → fresh', () {
      LinkReplacedNotice? next(LinkReplacedNotice? e, String id, int at) =>
          nextLinkReplacedNotice(
            e,
            epoch: 1,
            eventId: id,
            createdAt: at,
            by: 'p2',
          );
      final first = next(null, 'a', 10)!;
      expect((first.eventId, first.by), ('a', 'p2'));
      expect(next(first, 'a', 10), isNull);
      expect(next(first, 'b', 9), isNull);
      expect(next(first, 'b', 11)!.eventId, 'b');
      expect(next(first.asDismissed, 'b', 11), isNull);
      const old = LinkReplacedNotice(
        epoch: 0,
        eventId: 'a',
        createdAt: 99,
        dismissed: true,
      );
      expect(next(old, 'a', 1)!.dismissed, isFalse);
    });

    test('visibleLinkReplacedNotice: only on the same channel, not '
        'dismissed', () {
      const n = LinkReplacedNotice(epoch: 1, eventId: 'a', createdAt: 1);
      expect(visibleLinkReplacedNotice(n, channel()), same(n));
      expect(visibleLinkReplacedNotice(n, channel(epoch: 2)), isNull);
      expect(visibleLinkReplacedNotice(n, null), isNull);
      expect(visibleLinkReplacedNotice(n.asDismissed, channel()), isNull);
      expect(visibleLinkReplacedNotice(null, channel()), isNull);
    });
  });

  group('linkGroupPreviewFrom with markers', () {
    OpenedLinkPart part(Map<String, dynamic> content, int at) => (
      content: content,
      header: parseLinkSnapshotHeader(content),
      createdAt: at,
    );
    Map<String, dynamic> snapshot() => buildLinkSnapshotPart(
      {
        'group': 'g',
        'meta': {
          'group': 'g',
          'name': 'Trip',
          'currency': 'EUR',
          'updated_at': 5,
        },
        'members': [
          {
            'v': 2,
            'group': 'g',
            'participant_id': 'p2',
            'name': 'Ben',
            'status': 'active',
            'updated_at': 5,
          },
        ],
      },
      me: 'p2',
      app: 't',
    );

    test('a marker beside a real copy: the copy wins, `replaced`, the '
        "marker's `me` isn't 'used elsewhere'", () {
      final p = linkGroupPreviewFrom([
        part(snapshot(), 10),
        part(buildLinkReplacedPart(group: 'g', me: 'p9', app: 't'), 20),
      ])!;
      expect(
        (p.groupId, p.name, p.replaced, p.onlyReplaced),
        ('g', 'Trip', true, false),
      );
      expect(p.people.map((x) => (x.id, x.usedElsewhere)), [('p2', true)]);
    });

    test('no marker → not replaced; only markers → onlyReplaced', () {
      final plain = linkGroupPreviewFrom([part(snapshot(), 10)])!;
      expect((plain.replaced, plain.onlyReplaced), (false, false));
      final only = linkGroupPreviewFrom([
        part(buildLinkReplacedPart(group: 'g', me: 'p1', app: 't'), 20),
      ])!;
      expect(
        (only.groupId, only.name, only.replaced, only.onlyReplaced),
        ('g', null, true, true),
      );
      expect(only.people, isEmpty);
    });
  });
}
