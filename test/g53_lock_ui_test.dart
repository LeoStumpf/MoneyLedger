/// G53 step 4: *Make group secure* in the group settings (only a mixed
/// group on a Matrix member's device), the "who still needs to sign in"
/// dialog, the confirmation → locker seam, and the read-only secure-only
/// banner of a device without a Matrix participant — EN + DE at 360 dp,
/// 200 % font.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:money_ledger/features/expenses/expenses_page.dart';
import 'package:money_ledger/features/groups/group_provider.dart';
import 'package:money_ledger/features/groups/group_settings_page.dart';
import 'package:money_ledger/features/link/link_invite.dart';
import 'package:money_ledger/models/group_model.dart';
import 'package:money_ledger/models/member_model.dart';
import 'package:money_ledger/models/record_signature.dart';

import 'helpers/l10n.dart';
import 'helpers/test_providers.dart';

const _g = 'g1';
const _me = '@me:x.org';
const _secret = 'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8';
const _sig = RecordSignature(user: _me, device: 'D', key: 'k', sig: 's');

const _mixed = GroupModel(
  roomId: _g,
  name: 'Rome',
  currency: 'EUR',
  updatedAt: 1,
  link: GroupLink(epoch: 1, secret: _secret),
  sig: _sig,
);

const _locked = GroupModel(
  roomId: _g,
  name: 'Rome',
  currency: 'EUR',
  updatedAt: 2,
  lockedAt: 2,
  sig: _sig,
);

MemberModel _member(String id, String name, {String? mxid}) => MemberModel(
  groupId: _g,
  userId: id,
  displayName: name,
  matrixId: mxid,
  status: 'active',
  updatedAt: 1,
);

final _meMember = _member('p-me', 'Me', mxid: _me);

void _phone(WidgetTester tester, {double font = 1}) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(360, 780);
  tester.platformDispatcher.textScaleFactorTestValue = font;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

void main() {
  test('canOfferLock: mixed group + Matrix member only', () {
    expect(
      canOfferLock(group: _mixed, members: [_meMember], identity: _me),
      isTrue,
    );
    expect(
      canOfferLock(group: _locked, members: [_meMember], identity: _me),
      isFalse,
    );
    expect(
      canOfferLock(group: _mixed, members: [_meMember], identity: 'local:self'),
      isFalse,
    );
    expect(
      canOfferLock(
        group: _mixed,
        members: [_member('p-x', 'X', mxid: '@x:x.org')],
        identity: _me,
      ),
      isFalse,
    );
  });

  test('lockBlockers: active people without a valid Matrix ID', () {
    final ben = _member('p-ben', 'Ben');
    final gone = MemberModel(
      groupId: _g,
      userId: 'p-gone',
      displayName: 'Gone',
      status: 'removed',
      updatedAt: 1,
    );
    expect(lockBlockers([_meMember, ben, gone]), [ben]);
    expect(lockBlockers([_meMember]), isEmpty);
  });

  group('settings', () {
    late List<String> locked;
    setUp(() => locked = []);

    Widget app(List<MemberModel> members, {Locale? locale}) {
      final router = GoRouter(
        initialLocation: '/groups/$_g/settings',
        routes: [
          GoRoute(
            path: '/groups/:id/settings',
            builder: (_, _) => const GroupSettingsPage(roomId: _g),
          ),
        ],
      );
      return ProviderScope(
        overrides: [
          ...testOverrides(
            isLoggedIn: true,
            members: members,
            groups: const [_mixed],
          ),
          currentUserIdProvider.overrideWith((_) => _me),
          currentParticipantProvider.overrideWith((ref, g) async => _meMember),
          linkInviteStateProvider.overrideWith(
            (ref, g) async => LinkInviteState.open,
          ),
          groupLockerProvider.overrideWithValue((groupId) async {
            locked.add(groupId);
          }),
        ],
        child: MaterialApp.router(
          locale: locale ?? const Locale('en'),
          localizationsDelegates: testLocalizationsDelegates,
          supportedLocales: testSupportedLocales,
          routerConfig: router,
        ),
      );
    }

    Future<void> tapLock(WidgetTester tester) async {
      await tester.scrollUntilVisible(
        find.byKey(const Key('lockGroupTile')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(find.byKey(const Key('lockGroupTile')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('lockGroupTile')));
      await tester.pumpAndSettle();
    }

    testWidgets('someone without an account → the dialog names them, '
        'nothing is locked', (tester) async {
      _phone(tester);
      await tester.pumpWidget(app([_meMember, _member('p-ben', 'Ben')]));
      await tester.pumpAndSettle();
      await tapLock(tester);
      expect(find.byKey(const Key('lockBlockedDialog')), findsOneWidget);
      expect(find.textContaining('Ben'), findsWidgets);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(locked, isEmpty);
    });

    testWidgets('everyone on Matrix → confirm → locked + snackbar', (
      tester,
    ) async {
      _phone(tester);
      await tester.pumpWidget(
        app([_meMember, _member('p-bob', 'Bob', mxid: '@bob:x.org')]),
      );
      await tester.pumpAndSettle();
      await tapLock(tester);
      expect(find.byKey(const Key('lockConfirmDialog')), findsOneWidget);
      await tester.tap(find.byKey(const Key('lockConfirm')));
      await tester.pumpAndSettle();
      expect(locked, [_g]);
      expect(find.text(en.lockDone), findsOneWidget);
    });

    for (final (name, locale) in [
      ('EN', const Locale('en')),
      ('DE', const Locale('de')),
    ]) {
      testWidgets('$name at 360 dp, 200 %: tile + dialogs fit', (tester) async {
        _phone(tester, font: 2);
        await tester.pumpWidget(
          app([_meMember, _member('p-ben', 'Ben')], locale: locale),
        );
        await tester.pumpAndSettle();
        await tapLock(tester);
        expect(find.byKey(const Key('lockBlockedDialog')), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('secure-only banner', () {
    Widget app({Locale? locale}) {
      final router = GoRouter(
        initialLocation: '/groups/$_g/expenses',
        routes: [
          GoRoute(
            path: '/groups/:id/expenses',
            builder: (_, _) => const ExpensesPage(roomId: _g),
          ),
        ],
      );
      return ProviderScope(
        overrides: [
          ...testOverrides(
            localProfile: 'Ben',
            members: [
              _meMember,
              _member('p-ben', 'Ben', mxid: '@ben:x.org'),
            ],
            groups: const [_locked],
          ),
          currentParticipantProvider.overrideWith((ref, g) async => null),
          linkInviteStateProvider.overrideWith(
            (ref, g) async => LinkInviteState.unavailable,
          ),
        ],
        child: MaterialApp.router(
          locale: locale ?? const Locale('en'),
          localizationsDelegates: testLocalizationsDelegates,
          supportedLocales: testSupportedLocales,
          routerConfig: router,
        ),
      );
    }

    for (final (name, locale) in [
      ('EN', const Locale('en')),
      ('DE', const Locale('de')),
    ]) {
      testWidgets('$name at 360 dp, 200 %: read-only, *Connect a Matrix '
          'account*, no "who are you"', (tester) async {
        _phone(tester, font: 2);
        await tester.pumpWidget(app(locale: locale));
        await tester.pumpAndSettle();
        final l = locale.languageCode == 'de' ? de : en;
        expect(find.byKey(const Key('secureOnlyBanner')), findsOneWidget);
        expect(find.text(l.secureOnlyBanner), findsOneWidget);
        expect(find.byKey(const Key('secureOnlyConnect')), findsOneWidget);
        expect(find.byKey(const Key('chooseMeBanner')), findsNothing);
        expect(find.byType(FloatingActionButton), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
