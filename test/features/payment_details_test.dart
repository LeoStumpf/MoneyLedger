/// G74: own payment details — IBAN / BIC / PayPal.me parsing, the GiroCode
/// (EPC QR) payload, PayPal.me links, storage (device-local, per ledger)
/// and the move along with a local-mode adoption.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/database/daos/settings_dao.dart';
import 'package:money_ledger/core/session/local_adoption.dart';
import 'package:money_ledger/features/payment/payment_details.dart';

import '../helpers/in_memory_database.dart';

const _me = PaymentDetails(
  name: 'Anna Muster',
  iban: 'DE89370400440532013000',
  bic: 'COBADEFFXXX',
  paypalMe: 'annamuster',
);

void main() {
  group('IBAN', () {
    test('valid examples pass, typos fail', () {
      for (final iban in [
        'DE89370400440532013000',
        'CH9300762011623852957',
        'GB82WEST12345698765432',
        'AT611904300234573201',
      ]) {
        expect(isValidIban(iban), isTrue, reason: iban);
      }
      expect(isValidIban('DE89370400440532013001'), isFalse); // checksum
      expect(isValidIban('DE8937040044053201300'), isFalse); // length (DE 22)
      expect(isValidIban('DE89 3704'), isFalse);
      expect(isValidIban(''), isFalse);
      expect(isValidIban('1234567890123456'), isFalse);
    });

    test('normalised and formatted', () {
      expect(
        normalizeIban(' de89 3704-0044 0532 0130 00 '),
        'DE89370400440532013000',
      );
      expect(
        formatIban('DE89370400440532013000'),
        'DE89 3704 0044 0532 0130 00',
      );
    });

    test('BIC: 8 or 11 characters', () {
      expect(isValidBic(normalizeBic('cobadeff')), isTrue);
      expect(isValidBic('COBADEFFXXX'), isTrue);
      expect(isValidBic('COBADEF'), isFalse);
      expect(isValidBic('COBA1EFFXXX'), isFalse);
    });
  });

  group('PayPal.me', () {
    test('accepts the name, @name and whole links', () {
      for (final input in [
        'annamuster',
        '@annamuster',
        'paypal.me/annamuster',
        'https://www.paypal.me/annamuster/10EUR',
        ' PayPal.Me/annamuster ',
        'https://paypal.me/annamuster?country.x=DE&locale.x=de_DE',
        'paypal.me/annamuster#x',
      ]) {
        expect(normalizePaypalMe(input), 'annamuster', reason: input);
      }
      expect(normalizePaypalMe('anna muster'), isNull);
      expect(normalizePaypalMe(''), isNull);
      expect(normalizePaypalMe('a' * 21), isNull);
    });

    test('link with the amount — two decimals, none for JPY', () {
      expect(
        paypalMeUrl('anna', cents: 1250, currency: 'EUR'),
        'https://paypal.me/anna/12.50EUR',
      );
      expect(
        paypalMeUrl('anna', cents: 100000, currency: 'JPY'),
        'https://paypal.me/anna/1000JPY',
      );
      expect(paypalMeUrl('anna'), 'https://paypal.me/anna');
    });
  });

  group('GiroCode (EPC QR)', () {
    test('exact payload: version 002, UTF-8, amount, reference', () {
      expect(
        epcQrPayload(_me, cents: 2350, currency: 'EUR', remittance: 'Rom 2026'),
        'BCD\n002\n1\nSCT\nCOBADEFFXXX\nAnna Muster\n'
        'DE89370400440532013000\nEUR23.50\n\n\nRom 2026',
      );
    });

    test('no BIC → empty line; no reference → ends after the amount', () {
      const noBic = PaymentDetails(
        name: 'Anna',
        iban: 'DE89370400440532013000',
      );
      expect(
        epcQrPayload(noBic, cents: 5, currency: 'EUR'),
        'BCD\n002\n1\nSCT\n\nAnna\nDE89370400440532013000\nEUR0.05',
      );
    });

    test('euro only, needs a bank account', () {
      expect(epcQrPayload(_me, cents: 100, currency: 'CHF'), isNull);
      expect(
        epcQrPayload(
          const PaymentDetails(paypalMe: 'anna'),
          cents: 100,
          currency: 'EUR',
        ),
        isNull,
      );
    });

    test('an amount beyond the limit is left out', () {
      final p = epcQrPayload(_me, cents: kEpcMaxCents + 1, currency: 'EUR')!;
      expect(p.split('\n')[7], '');
    });

    test('long name / reference cut to the EPC limits (331 bytes)', () {
      final p = epcQrPayload(
        PaymentDetails(name: 'Ä' * 100, iban: _me.iban, bic: _me.bic),
        cents: 100,
        currency: 'EUR',
        remittance: 'ü\n' * 200,
      )!;
      final lines = p.split('\n');
      expect(lines[5].runes.length, 70);
      expect(lines.length, 11, reason: 'newlines in the reference removed');
      expect(lines[10].runes.length, lessThanOrEqualTo(140));
      expect(utf8.encode(p).length, lessThanOrEqualTo(kEpcMaxBytes));
    });

    test('a name of 4-byte characters is shortened to fit too', () {
      final p = epcQrPayload(
        PaymentDetails(name: '😀' * 70, iban: _me.iban, bic: _me.bic),
        cents: 100,
        currency: 'EUR',
        remittance: 'Rom',
      )!;
      expect(utf8.encode(p).length, lessThanOrEqualTo(kEpcMaxBytes));
      final lines = p.split('\n');
      expect(lines.length, 8, reason: 'the reference goes first');
      expect(lines[5], isNotEmpty);
      expect(lines[6], _me.iban);
    });
  });

  group('storage', () {
    test('encode / decode round trip; toString hides the data', () {
      expect(PaymentDetails.decode(_me.encode()), _me);
      expect(PaymentDetails.decode(null), isNull);
      expect(PaymentDetails.decode('nonsense'), isNull);
      expect(PaymentDetails.decode('{}'), isNull);
      expect(_me.toString(), isNot(contains('DE89')));
      expect(_me.isEmpty, isFalse);
      expect(const PaymentDetails(iban: 'DE89').hasBankAccount, isFalse);
    });

    test('SettingsDao keeps them per ledger; clear removes them', () async {
      final db = openTestDatabase();
      addTearDown(db.close);
      final dao = SettingsDao(db);
      expect(await dao.paymentDetailsRaw(), isNull);
      await dao.setPaymentDetailsRaw(_me.encode());
      expect(PaymentDetails.decode(await dao.paymentDetailsRaw()), _me);
      expect(
        PaymentDetails.decode(await dao.watchPaymentDetailsRaw().first),
        _me,
      );
      await dao.clearPaymentDetails();
      expect(await dao.paymentDetailsRaw(), isNull);
    });

    test('they move along with a local-mode adoption (unless the account '
        'has its own)', () async {
      final local = openTestDatabase();
      final account = openTestDatabase();
      addTearDown(local.close);
      addTearDown(account.close);
      await SettingsDao(local).setPaymentDetailsRaw(_me.encode());
      await adoptLocalLedger(
        target: account,
        local: local,
        mxid: '@anna:x.org',
        crypto: null,
      );
      expect(
        PaymentDetails.decode(await SettingsDao(account).paymentDetailsRaw()),
        _me,
      );

      const other = PaymentDetails(paypalMe: 'other');
      final local2 = openTestDatabase();
      addTearDown(local2.close);
      await SettingsDao(local2).setPaymentDetailsRaw(other.encode());
      await adoptLocalLedger(
        target: account,
        local: local2,
        mxid: '@anna:x.org',
        crypto: null,
      );
      expect(
        PaymentDetails.decode(await SettingsDao(account).paymentDetailsRaw()),
        _me,
      );
    });
  });

  test('PRIVACY.md and the in-app text say the same about payment details', () {
    String norm(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();
    final privacy = norm(File('PRIVACY.md').readAsStringSync());
    for (final file in ['app_en', 'app_de']) {
      final arb =
          jsonDecode(File('lib/l10n/$file.arb').readAsStringSync())
              as Map<String, Object?>;
      expect(arb['privacyPaymentBody'], isA<String>(), reason: file);
      if (file == 'app_en') {
        expect(privacy, contains(norm(arb['privacyPaymentBody']! as String)));
        expect(privacy, contains('## ${arb['privacyPaymentTitle']}'));
      }
    }
  });
}
