/// G53 step 2: *Invite with a link* in a **Matrix group** — the pure rule
/// (an active participant of a signed group may open a link), the flow
/// (disclosure → "Also share this group by link?" → the mixed opener →
/// the invite sheet) and the confirmation at 360 dp / 200 % (EN + DE).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:money_ledger/features/expenses/expenses_page.dart';
import 'package:money_ledger/features/groups/group_provider.dart';
import 'package:money_ledger/features/link/link_invite.dart';
import 'package:money_ledger/models/group_model.dart';
import 'package:money_ledger/models/link_model.dart';
import 'package:money_ledger/models/member_model.dart';
import 'package:money_ledger/models/record_signature.dart';

import 'helpers/l10n.dart';
import 'helpers/test_providers.dart';

const _g = 'g1';
const _alice = '@alice:x.org';
const _secret = 'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8';

const _signed = GroupModel(
  roomId: _g,
  name: 'Trip',
  currency: 'EUR',
  updatedAt: 1,
  sig: RecordSignature(user: _alice, device: 'D', key: 'k', sig: 's'),
);

MemberModel _member(String id, String name, {String? mxid, bool on = true}) =>
    MemberModel(
      groupId: _g,
      userId: id,
      displayName: name,
      matrixId: mxid,
      status: on ? 'active' : 'removed',
      updatedAt: 1,
    );

void main() {
  test('linkInviteStateOf: a signed group → canOpenMixed only for an active '
      'participant on a Matrix account', () {
    LinkInviteState of(List<MemberModel> members, {bool local = false}) =>
        linkInviteStateOf(
          channel: null,
          group: _signed,
          members: members,
          localMode: local,
          identity: _alice,
        );
    expect(
      of([_member(_alice, 'A', mxid: _alice)]),
      LinkInviteState.canOpenMixed,
    );
    expect(
      of([_member(_alice, 'A', mxid: _alice, on: false)]),
      LinkInviteState.unavailable,
    );
    expect(
      of([_member('b', 'B', mxid: '@b:x.org')]),
      LinkInviteState.unavailable,
    );
    expect(
      linkInviteStateOf(
        channel: null,
        group: const GroupModel(roomId: _g, name: 'T', currency: 'EUR'),
        members: [_member(_alice, 'A', mxid: _alice)],
        localMode: false,
        identity: _alice,
      ),
      LinkInviteState.unavailable,
      reason: 'an unsigned group on a Matrix account (legacy) gets nothing',
    );
  });

  group('flow', () {
    late List<String> opened;
    setUp(() => opened = []);

    Widget app({Locale locale = const Locale('en')}) {
      final router = GoRouter(
        initialLocation: '/groups/$_g/expenses',
        routes: [
          GoRoute(
            path: '/groups/:id/expenses',
            builder: (_, _) => const ExpensesPage(roomId: _g),
          ),
        ],
      );
      final me = _member(_alice, 'Alice', mxid: _alice);
      return ProviderScope(
        overrides: [
          ...testOverrides(isLoggedIn: true, members: [me], groups: [_signed]),
          currentParticipantProvider.overrideWith((ref, g) async => me),
          linkInviteStateProvider.overrideWith(
            (ref, g) async => LinkInviteState.canOpenMixed,
          ),
          mixedLinkOpenerProvider.overrideWithValue((groupId) async {
            opened.add(groupId);
            return const LinkChannelModel(
              groupId: _g,
              epoch: 1,
              secret: _secret,
              nostrPriv: '11',
              openedAt: 1,
              myParticipantId: _alice,
            );
          }),
        ],
        child: MaterialApp.router(
          locale: locale,
          localizationsDelegates: testLocalizationsDelegates,
          supportedLocales: testSupportedLocales,
          routerConfig: router,
        ),
      );
    }

    Future<void> openMenuItem(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('groupMenu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('inviteLinkMenuItem')));
      await tester.pumpAndSettle();
    }

    testWidgets('⋮ → disclosure → confirmation → opener → sheet', (
      tester,
    ) async {
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      await openMenuItem(tester);
      await tester.tap(find.byKey(const Key('linkDisclosureContinue')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('linkMixedDialog')), findsOneWidget);
      expect(find.text(en.linkMixedTitle), findsOneWidget);
      expect(opened, isEmpty, reason: 'nothing before the confirmation');
      await tester.tap(find.byKey(const Key('linkMixedConfirm')));
      await tester.pumpAndSettle();
      expect(opened, [_g]);
      expect(find.byKey(const Key('linkInviteSheet')), findsOneWidget);
    });

    testWidgets('cancelling the confirmation opens nothing', (tester) async {
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      await openMenuItem(tester);
      await tester.tap(find.byKey(const Key('linkDisclosureContinue')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(en.cancel));
      await tester.pumpAndSettle();
      expect(opened, isEmpty);
      expect(find.byKey(const Key('linkInviteSheet')), findsNothing);
    });

    for (final (name, locale) in [
      ('EN', const Locale('en')),
      ('DE', const Locale('de')),
    ]) {
      testWidgets('$name at 360 dp, 200 % font: the confirmation fits', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(360, 720);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await tester.pumpWidget(app(locale: locale));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'page');
        await openMenuItem(tester);
        expect(tester.takeException(), isNull, reason: 'disclosure');
        await tester.tap(find.byKey(const Key('linkDisclosureContinue')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('linkMixedDialog')), findsOneWidget);
        final l = locale.languageCode == 'de' ? de : en;
        expect(find.text(l.linkMixedConfirm), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
