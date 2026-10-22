/// G73: the optional `exchange_rates` object of the group meta on the wire —
/// part of the signed content and the G27 version hash only when set (so
/// every pre-G73 meta signature and hash stays valid), and its content rules
/// (`exchangeRatesProblem` via `groupMetaProblem`).
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/matrix/hmac_record_crypto.dart';
import 'package:money_ledger/core/sync/ledger_payloads.dart';
import 'package:money_ledger/core/sync/record_signing.dart';
import 'package:money_ledger/core/sync/record_validation.dart';
import 'package:money_ledger/core/sync/record_version.dart';
import 'package:money_ledger/models/exchange_rates.dart';
import 'package:money_ledger/models/group_model.dart';

const alice = '@alice:x.org';

final chf = ExchangeRates(
  base: 'EUR',
  rates: const {'USD': '0.92', 'CHF': '1.0797'},
  settle: true,
);

GroupModel meta({ExchangeRates? fx}) => GroupModel(
  roomId: 'g1',
  name: 'Trip',
  currency: 'EUR',
  updatedAt: 1000,
  exchangeRates: fx,
);

Map<String, dynamic> overTheWire(Map<String, dynamic> payload) =>
    jsonDecode(jsonEncode(payload)) as Map<String, dynamic>;

void main() {
  final keys = HmacKeyRegistry();
  final crypto = keys.deviceCrypto(alice, 'AAAA');

  test('a meta without rates keeps the pre-G73 body and hash', () {
    expect(groupMetaContent(meta()).containsKey('exchange_rates'), isFalse);
    expect(groupMetaPayload(meta()).containsKey('exchange_rates'), isFalse);
    // Same golden as G47's test (pre-G47 canonical body) — unchanged.
    expect(
      groupMetaVersionHash(meta()),
      '839ee378eb0eda7215bda58b19a73731ce3ddffc12a1032c7797ccda80c94511',
    );
    expect(
      groupMetaVersionHash(meta(fx: chf)),
      isNot(groupMetaVersionHash(meta())),
    );
  });

  test('wire shape: rates sorted, settle only when true', () {
    expect(groupMetaPayload(meta(fx: chf))['exchange_rates'], {
      'base': 'EUR',
      'rates': {'CHF': '1.0797', 'USD': '0.92'},
      'settle': true,
    });
    final off = ExchangeRates(base: 'EUR', rates: const {'CHF': '1.1'});
    expect(off.toJson().containsKey('settle'), isFalse);
    expect(
      groupMetaVersionHash(meta(fx: off)),
      isNot(groupMetaVersionHash(meta(fx: chf))),
    );
  });

  test('round trip: sign → wire → parse → verifies, same hash', () async {
    final signed = await signGroupMeta(crypto, meta(fx: chf));
    final parsed = groupMetaFromPayload(overTheWire(groupMetaPayload(signed)))!;
    expect(parsed.exchangeRates, chf);
    expect(
      signatureMatches(
        crypto,
        groupMetaBody(parsed, signerOf(parsed.sig!)),
        parsed.sig!,
      ),
      isTrue,
    );
    expect(groupMetaVersionHash(parsed), groupMetaVersionHash(signed));
    expect(groupMetaProblem(parsed), isNull);
  });

  test('changing / dropping the rates breaks the signature', () async {
    final signed = await signGroupMeta(crypto, meta(fx: chf));
    final payload = overTheWire(groupMetaPayload(signed));
    for (final tamper in <void Function(Map<String, dynamic>)>[
      (p) => p.remove('exchange_rates'), // what a pre-G73 build does
      (p) => ((p['exchange_rates'] as Map)['rates'] as Map)['CHF'] = '2',
      (p) => (p['exchange_rates'] as Map).remove('settle'),
      (p) => (p['exchange_rates'] as Map)['base'] = 'CHF',
    ]) {
      final p = overTheWire(payload);
      tamper(p);
      final parsed = groupMetaFromPayload(p)!;
      expect(
        signatureMatches(
          crypto,
          groupMetaBody(parsed, signerOf(parsed.sig!)),
          parsed.sig!,
        ),
        isFalse,
      );
    }
  });

  test('the next meta version keeps the rates; a link version too', () {
    final g = meta(fx: chf);
    expect(g.nextVersion(updatedAt: 2000, name: 'X').exchangeRates, chf);
    expect(
      g.nextVersion(updatedAt: 2000, exchangeRates: null).exchangeRates,
      isNull,
    );
    expect(g.asLinkVersion('p1').exchangeRates, chf);
  });

  test('bootstraps (and so backups) carry the rates', () {
    final content = overTheWire(
      buildBootstrapContent('g1', meta(fx: chf), const [], const [], const []),
    );
    final parsed = groupMetaFromPayload(
      Map<String, dynamic>.from(content['meta'] as Map),
    )!;
    expect(parsed.exchangeRates, chf);
  });

  group('content rules', () {
    String? problem(Object? raw) => groupMetaProblem(
      groupMetaFromPayload({
        'group': 'g1',
        'name': 'Trip',
        'currency': 'EUR',
        'updated_at': 1,
        'exchange_rates': raw,
      })!,
    );

    test('valid values', () {
      expect(problem(null), isNull);
      expect(problem(chf.toJson()), isNull);
      expect(
        problem({
          'base': 'JPY',
          'rates': {
            for (var i = 0; i < kMaxExchangeRates; i++)
              'A${String.fromCharCode(65 + i ~/ 26)}${String.fromCharCode(65 + i % 26)}':
                  '0.0000001',
          },
        }),
        isNull,
      );
      expect(
        problem({
          'base': 'EUR',
          'rates': {'IDR': '0.0000565'},
          'settle': false,
        }),
        isNull,
      );
    });

    test('malformed or out-of-bounds values are refused', () {
      for (final bad in <Object?>[
        'EUR',
        {'base': 'EUR', 'rates': <String, Object?>{}},
        {
          'base': 'eur',
          'rates': {'CHF': '1'},
        },
        {
          'base': 'EUR',
          'rates': {'EUR': '1'},
        },
        {
          'base': 'EUR',
          'rates': {'CH': '1'},
        },
        {
          'base': 'EUR',
          'rates': {'CHF': 1.05},
        },
        {
          'base': 'EUR',
          'rates': {'CHF': '0'},
        },
        {
          'base': 'EUR',
          'rates': {'CHF': '-1'},
        },
        {
          'base': 'EUR',
          'rates': {'CHF': '1.10'},
        },
        {
          'base': 'EUR',
          'rates': {'CHF': '01'},
        },
        {
          'base': 'EUR',
          'rates': {'CHF': '1,1'},
        },
        {
          'base': 'EUR',
          'rates': {'CHF': '1.12345678901'},
        },
        {
          'base': 'EUR',
          'rates': {'CHF': '1234567890'},
        },
        {
          'base': 'EUR',
          'rates': {'CHF': '1'},
          'settle': 'yes',
        },
        {
          'base': 'EUR',
          'rates': {'CHF': '1'},
          'extra': 1,
        },
        {
          'base': 'EUR',
          'rates': {
            for (var i = 0; i <= kMaxExchangeRates; i++)
              'A${String.fromCharCode(65 + i ~/ 26)}${String.fromCharCode(65 + i % 26)}':
                  '1',
          },
        },
      ]) {
        expect(problem(bad), isNotNull, reason: '$bad');
      }
    });
  });
}
