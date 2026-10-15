/// Registration flow classification (Phase F, M4): decide whether sign-up can
/// complete in-app or must defer to the web. No matrix import — pure functions.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/features/auth/register_flows.dart';

void main() {
  group('classifyRegistrationFlows', () {
    test('a dummy-only flow is registrable in-app', () {
      final p = classifyRegistrationFlows([
        ['m.login.dummy']
      ]);
      expect(p.canRegisterInApp, isTrue);
      expect(p.blockingRequirements, isEmpty);
    });

    test('an open server offering a dummy flow alongside others is in-app', () {
      final p = classifyRegistrationFlows([
        ['m.login.recaptcha'],
        ['m.login.dummy'],
      ]);
      expect(p.canRegisterInApp, isTrue);
    });

    test('a captcha + terms flow defers to the web with friendly labels', () {
      final p = classifyRegistrationFlows([
        ['m.login.recaptcha', 'm.login.terms', 'm.login.dummy']
      ]);
      expect(p.canRegisterInApp, isFalse);
      expect(p.blockingRequirements,
          ['a CAPTCHA', 'accepting the terms of service']);
    });

    test('email-only verification defers to the web', () {
      final p = classifyRegistrationFlows([
        ['m.login.email.identity']
      ]);
      expect(p.canRegisterInApp, isFalse);
      expect(p.blockingRequirements, ['email verification']);
    });

    test('picks the easiest (fewest blocking stages) flow to report', () {
      final p = classifyRegistrationFlows([
        ['m.login.recaptcha', 'm.login.terms'],
        ['m.login.recaptcha'],
      ]);
      expect(p.canRegisterInApp, isFalse);
      expect(p.blockingRequirements, ['a CAPTCHA']);
    });

    test('no advertised flows means web fallback with no specifics', () {
      final p = classifyRegistrationFlows([]);
      expect(p.canRegisterInApp, isFalse);
      expect(p.blockingRequirements, isEmpty);
    });

    test('an unknown stage falls back to its raw id', () {
      final p = classifyRegistrationFlows([
        ['m.login.sms.custom']
      ]);
      expect(p.blockingRequirements, ['m.login.sms.custom']);
    });
  });

  test('registrationRequirementLabel maps known stages', () {
    expect(registrationRequirementLabel('m.login.msisdn'), 'phone verification');
    expect(registrationRequirementLabel('m.login.registration_token'),
        'a registration token');
  });

  group('isClientRegistrationDisabled', () {
    test('M_FORBIDDEN without flows (e.g. matrix.org / MAS) → web sign-up', () {
      expect(isClientRegistrationDisabled('M_FORBIDDEN', hasFlows: false),
          isTrue);
    });

    test('a UIA challenge is classified by its flows instead', () {
      expect(isClientRegistrationDisabled('M_FORBIDDEN', hasFlows: true),
          isFalse);
    });

    test('other errors stay errors (username taken / invalid)', () {
      expect(isClientRegistrationDisabled('M_USER_IN_USE', hasFlows: false),
          isFalse);
      expect(
          isClientRegistrationDisabled('M_INVALID_USERNAME', hasFlows: false),
          isFalse);
      expect(isClientRegistrationDisabled(null, hasFlows: false), isFalse);
    });
  });
}
