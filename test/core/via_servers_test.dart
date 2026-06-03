/// Pure unit tests for the federation `via` hint derivation — the heart of the
/// "second user can't join across homeservers" fix. No package:matrix import.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/matrix/ledger_transport.dart';

void main() {
  group('viaServersFrom', () {
    test('uses the room id origin server', () {
      expect(viaServersFrom('!abc:x.org', null), ['x.org']);
    });

    test('includes the inviter server too', () {
      expect(viaServersFrom('!abc:x.org', '@bob:y.org').toSet(),
          {'x.org', 'y.org'});
    });

    test('dedupes when room and inviter share a server', () {
      expect(viaServersFrom('!abc:x.org', '@bob:x.org'), ['x.org']);
    });

    test('malformed room id falls back to inviter only', () {
      expect(viaServersFrom('!abc', '@bob:y.org'), ['y.org']);
    });

    test('nothing resolvable → empty (never throws)', () {
      expect(viaServersFrom('!abc', null), isEmpty);
      expect(viaServersFrom('', ''), isEmpty);
    });
  });
}
