import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/router.dart';

void main() {
  group('routerRedirect — not logged in', () {
    test('redirects / to /login', () {
      expect(routerRedirect(false, '/'), '/login');
    });

    test('redirects /groups to /login', () {
      expect(routerRedirect(false, '/groups'), '/login');
    });

    test('redirects /groups/r1/expenses to /login', () {
      expect(routerRedirect(false, '/groups/r1/expenses'), '/login');
    });

    test('stays on /login (no redirect)', () {
      expect(routerRedirect(false, '/login'), isNull);
    });
  });

  group('routerRedirect — logged in', () {
    test('redirects /login to /groups', () {
      expect(routerRedirect(true, '/login'), '/groups');
    });

    test('stays on /groups (no redirect)', () {
      expect(routerRedirect(true, '/groups'), isNull);
    });

    test('stays on /groups/r1/expenses (no redirect)', () {
      expect(routerRedirect(true, '/groups/r1/expenses'), isNull);
    });

    test('stays on /groups/r1/balance (no redirect)', () {
      expect(routerRedirect(true, '/groups/r1/balance'), isNull);
    });
  });
}
