/// Registration flow classification (Phase F, M4): decide whether sign-up can
/// complete in-app or must defer to the web. No matrix import — pure functions.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/features/auth/register_flows.dart';
import '../helpers/l10n.dart';

void main() {
  group('classifyRegistrationFlows', () {
    test('a dummy-only flow is registrable in-app', () {
      final p = classifyRegistrationFlows([
        ['m.login.dummy']
      ]);
      expect(p.canRegisterInApp, isTrue);
      expect(p.blockingStages, isEmpty);
    });

    test('an open server offering a dummy flow alongside others is in-app', () {
      final p = classifyRegistrationFlows([
        ['m.login.recaptcha'],
        ['m.login.dummy'],
      ]);
      expect(p.canRegisterInApp, isTrue);
    });

    test('a captcha + terms flow defers to the web (stages labelled in the UI)', () {
      final p = classifyRegistrationFlows([
        ['m.login.recaptcha', 'm.login.terms', 'm.login.dummy']
      ]);
      expect(p.canRegisterInApp, isFalse);
      expect(p.blockingStages, ['m.login.recaptcha', 'm.login.terms']);
      expect([for (final s in p.blockingStages) registrationRequirementLabel(s, en)],
          ['a CAPTCHA', 'accepting the terms of service']);
    });

    test('email-only verification defers to the web', () {
      final p = classifyRegistrationFlows([
        ['m.login.email.identity']
      ]);
      expect(p.canRegisterInApp, isFalse);
      expect(p.blockingStages, ['m.login.email.identity']);
    });

    test('picks the easiest (fewest blocking stages) flow to report', () {
      final p = classifyRegistrationFlows([
        ['m.login.recaptcha', 'm.login.terms'],
        ['m.login.recaptcha'],
      ]);
      expect(p.canRegisterInApp, isFalse);
      expect(p.blockingStages, ['m.login.recaptcha']);
    });

    test('no advertised flows means web fallback with no specifics', () {
      final p = classifyRegistrationFlows([]);
      expect(p.canRegisterInApp, isFalse);
      expect(p.blockingStages, isEmpty);
    });

    test('an unknown stage falls back to its raw id', () {
      final p = classifyRegistrationFlows([
        ['m.login.sms.custom']
      ]);
      expect(p.blockingStages, ['m.login.sms.custom']);
    });
  });

  test('registrationRequirementLabel maps known stages', () {
    expect(registrationRequirementLabel('m.login.msisdn', en),
        'phone verification');
    expect(registrationRequirementLabel('m.login.registration_token', en),
        'a registration token');
    expect(registrationRequirementLabel(kWebSignupStage, en),
        'signing up on its own website');
    expect(registrationRequirementLabel('m.login.recaptcha', de), 'ein CAPTCHA');
    expect(registrationRequirementLabel('m.login.sms.custom', en),
        'm.login.sms.custom');
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
