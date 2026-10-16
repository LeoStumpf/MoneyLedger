import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/matrix/sync_filter.dart';

/// G45: the minimal Matrix footprint — `/sync` asks for no rooms, presence or
/// account data, never marks the user online, and installs that still hold
/// the SDK's default filter id define the minimal one again.
void main() {
  group('minimalSyncFilterJson', () {
    final filter = minimalSyncFilterJson();

    test('excludes every room and all room sections', () {
      final room = filter['room']! as Map<String, Object?>;
      expect(room['rooms'], isEmpty);
      expect(room['include_leave'], isFalse);
      for (final section in [
        'account_data',
        'ephemeral',
        'state',
        'timeline',
      ]) {
        expect(
          (room[section]! as Map<String, Object?>)['types'],
          isEmpty,
          reason: section,
        );
      }
    });

    test('excludes presence and global account data', () {
      expect((filter['presence']! as Map)['types'], isEmpty);
      expect((filter['account_data']! as Map)['types'], isEmpty);
    });

    test('names no other section (to-device etc. are not filterable)', () {
      expect(
        filter.keys,
        unorderedEquals(['account_data', 'presence', 'room']),
      );
    });

    test('is stable text (the marker compares it)', () {
      expect(minimalSyncFilterText(), jsonEncode(minimalSyncFilterJson()));
      expect(
        minimalSyncFilterText(),
        '{"account_data":{"types":[]},"presence":{"types":[]},'
        '"room":{"rooms":[],"include_leave":false,'
        '"account_data":{"types":[]},"ephemeral":{"types":[]},'
        '"state":{"types":[]},"timeline":{"types":[]}}}',
      );
    });
  });

  test('sync never marks the user online', () {
    expect(kSyncPresence, 'offline');
  });

  group('sync filter marker', () {
    test('round-trips the filter id', () {
      expect(markedSyncFilterId(syncFilterMarker('7')), '7');
    });

    test('no / malformed marker → none', () {
      expect(markedSyncFilterId(null), isNull);
      expect(markedSyncFilterId({}), isNull);
      expect(
        markedSyncFilterId({'filter_id': 3, 'filter': minimalSyncFilterText()}),
        isNull,
      );
      expect(
        markedSyncFilterId({
          'filter_id': '',
          'filter': minimalSyncFilterText(),
        }),
        isNull,
      );
    });

    test('a marker recorded for another filter → none (define again)', () {
      expect(
        markedSyncFilterId({'filter_id': '7', 'filter': '{"room":{}}'}),
        isNull,
      );
    });
  });

  group('effectiveSyncFilterId', () {
    test('the stored id is used only when it is the marked one', () {
      expect(effectiveSyncFilterId(stored: '7', marked: '7'), '7');
    });

    test('pre-G45 install: default filter id stored, no marker → define', () {
      expect(effectiveSyncFilterId(stored: '0', marked: null), isNull);
    });

    test('marker of an earlier session / filter → define', () {
      expect(effectiveSyncFilterId(stored: '9', marked: '7'), isNull);
    });

    test('nothing stored (fresh login / after logout) → define', () {
      expect(effectiveSyncFilterId(stored: null, marked: null), isNull);
      expect(effectiveSyncFilterId(stored: null, marked: '7'), isNull);
    });
  });

  group('syncCacheFromOtherFilter', () {
    test('pre-G45 install (default filter id, no marker) → clear once', () {
      expect(syncCacheFromOtherFilter(stored: '0', marked: null), isTrue);
    });

    test('stored id is ours → keep', () {
      expect(syncCacheFromOtherFilter(stored: '7', marked: '7'), isFalse);
    });

    test('fresh login (nothing stored) → nothing to clear', () {
      expect(syncCacheFromOtherFilter(stored: null, marked: null), isFalse);
    });

    test('marker for an older minimal filter → clear', () {
      expect(syncCacheFromOtherFilter(stored: '9', marked: '7'), isTrue);
    });
  });

  test('PRIVACY.md and the in-app text say the same about the homeserver', () {
    String norm(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();
    final arb =
        jsonDecode(File('lib/l10n/app_en.arb').readAsStringSync())
            as Map<String, Object?>;
    final privacy = norm(File('PRIVACY.md').readAsStringSync());
    expect(privacy, contains(norm(arb['privacyHomeserverBody']! as String)));
  });
}
