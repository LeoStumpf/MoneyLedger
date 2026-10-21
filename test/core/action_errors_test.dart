/// G67 (U25): friendly messages for failed user actions.
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/errors/action_errors.dart';
import 'package:money_ledger/core/matrix/ledger_transport.dart';
import 'package:money_ledger/core/sync/payload_budget.dart';
import 'package:money_ledger/core/sync/record_signing.dart'
    show SignatureRequiredException;
import 'package:money_ledger/features/expenses/expenses_provider.dart';
import 'package:money_ledger/features/groups/group_provider.dart';

import '../helpers/l10n.dart';

class _Text implements Exception {
  _Text(this.text);
  final String text;
  @override
  String toString() => text;
}

void main() {
  group('classifyActionError', () {
    final cases = <String, (Object, ActionErrorKind)>{
      'record deleted': (
        const RecordDeletedException(),
        ActionErrorKind.recordGone,
      ),
      'transport': (
        const TransportUnavailableException('not logged in'),
        ActionErrorKind.relayUnavailable,
      ),
      'payload': (
        const PayloadTooLargeException('com.moneyledger.bootstrap', 70000),
        ActionErrorKind.tooLarge,
      ),
      'link only': (const LinkOnlyGroupException(), ActionErrorKind.linkOnly),
      'timeout': (
        TimeoutException('slow', const Duration(seconds: 1)),
        ActionErrorKind.timeout,
      ),
      'format': (
        const FormatException('bad json'),
        ActionErrorKind.invalidData,
      ),
      'db closed (StateError)': (
        StateError('account switched during export'),
        ActionErrorKind.interrupted,
      ),
      'signed-out executor': (
        StateError('No Matrix account signed in: no ledger database'),
        ActionErrorKind.interrupted,
      ),
      'drift reopen': (
        _Text("Bad state: Can't re-open a database after closing it."),
        ActionErrorKind.interrupted,
      ),
      'file': (
        _Text(
          "PathAccessException: Cannot open file, path = '/x' "
          '(OS Error: Permission denied, errno = 13)',
        ),
        ActionErrorKind.file,
      ),
      'file system': (
        _Text('FileSystemException: Cannot write, path = /x'),
        ActionErrorKind.file,
      ),
      'sqlite': (
        _Text('SqliteException(13): database or disk is full'),
        ActionErrorKind.storage,
      ),
      'network': (
        _Text('ClientException with SocketException: Failed host lookup'),
        ActionErrorKind.network,
      ),
      'other StateError': (StateError('disk full?'), ActionErrorKind.storage),
      'unknown': (Exception('boom'), ActionErrorKind.unknown),
    };
    for (final MapEntry(key: name, value: (error, kind)) in cases.entries) {
      test(name, () => expect(classifyActionError(error), kind));
    }
  });

  group('describeActionError', () {
    test('friendly title + hint, raw text only as detail (EN)', () {
      final m = describeActionError(StateError('db closed'), en);
      expect(m.kind, ActionErrorKind.interrupted);
      expect(m.title, en.errorInterruptedTitle);
      expect(m.hint, en.errorInterruptedHint);
      expect(m.title, isNot(contains('StateError')));
      expect(m.detail, 'Bad state: db closed');
    });

    test('German', () {
      final m = describeActionError(const RecordDeletedException(), de);
      expect(m.title, 'Dieser Eintrag wurde inzwischen gelöscht');
      expect(m.hint, 'Es wurde nichts geändert.');
    });

    test('every kind has a title and a hint in both languages', () {
      for (final l in [en, de]) {
        for (final kind in ActionErrorKind.values) {
          final error = switch (kind) {
            ActionErrorKind.interrupted => StateError('closed'),
            ActionErrorKind.relayUnavailable =>
              const TransportUnavailableException('x'),
            ActionErrorKind.recordGone => const RecordDeletedException(),
            ActionErrorKind.tooLarge => const PayloadTooLargeException('t', 1),
            ActionErrorKind.linkOnly => const LinkOnlyGroupException(),
            ActionErrorKind.signatureRequired =>
              const SignatureRequiredException(),
            ActionErrorKind.file => _Text('FileSystemException: x'),
            ActionErrorKind.storage => _Text('SqliteException(1)'),
            ActionErrorKind.timeout => TimeoutException('t'),
            ActionErrorKind.network => _Text('SocketException: x'),
            ActionErrorKind.invalidData => const FormatException('x'),
            ActionErrorKind.unknown => Exception('x'),
          };
          final m = describeActionError(error, l);
          expect(m.kind, kind);
          expect(m.title, isNotEmpty);
          expect(m.hint, isNotEmpty);
        }
      }
    });
  });
}
