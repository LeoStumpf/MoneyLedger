/// G52 step 7: the join page — link parsing (invalid / newer version /
/// paste), intro → disclosure → look-up → picker → join, "nothing found" +
/// retry, refusals, "already joined", someone new + name, the pure helpers
/// (`isJoinLink`, `joinLocationFor`, `linkGroupPreviewFrom`), the entry
/// points, and EN + DE at 360 dp / 200 % font.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:money_ledger/core/link/link_channel.dart';
import 'package:money_ledger/core/link/link_join_probe.dart';
import 'package:money_ledger/core/link/link_snapshot.dart';
import 'package:money_ledger/core/link/link_uri.dart';
import 'package:money_ledger/core/session/app_session.dart';
import 'package:money_ledger/core/session/device_prefs.dart';
import 'package:money_ledger/features/groups/create_group_page.dart';
import 'package:money_ledger/features/link/link_join.dart';
import 'package:money_ledger/features/welcome/welcome_page.dart';

import 'helpers/l10n.dart';
import 'helpers/test_providers.dart';

const _secret = 'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8';
const _frag = 'v=1&k=$_secret&n=Trip';

const _preview = LinkGroupPreview(
  groupId: 'g1',
  name: 'Trip',
  people: [
    LinkJoinPerson(id: 'p1', name: 'Anna', usedElsewhere: true),
    LinkJoinPerson(id: 'p2', name: 'Ben', usedElsewhere: false),
  ],
);

class _Fakes {
  int lookups = 0;
  LinkJoinLookup? Function() answer = () =>
      const LinkJoinLookup(preview: _preview);
  final requests = <LinkJoinRequest>[];
  Object? joinError;
  final switches = <(String, String)>[];
  Object? switchError;
}

Widget _app(
  _Fakes f, {
  String location = '$kJoinLocation?$_frag',
  AppSessionKind session = AppSessionKind.signedOut,
  bool disclosureSeen = true,
  Locale locale = const Locale('en'),
}) {
  final router = GoRouter(
    initialLocation: location,
    routes: [
      GoRoute(
        path: kJoinLocation,
        builder: (_, s) => JoinLinkPage(fragment: s.uri.query),
      ),
      GoRoute(
        path: '/groups',
        builder: (_, _) => const Scaffold(body: Text('groups')),
      ),
      GoRoute(
        path: '/groups/:id/expenses',
        builder: (_, s) =>
            Scaffold(body: Text('group ${s.pathParameters['id']}')),
      ),
    ],
  );
  return ProviderScope(
    overrides: [
      appSessionProvider.overrideWithValue(session),
      devicePrefsStoreProvider.overrideWithValue(
        InMemoryDevicePrefsStore({
          'welcome_seen': '1',
          if (disclosureSeen) 'link_disclosure_seen': '1',
        }),
      ),
      linkJoinLookupProvider.overrideWithValue((c, invite) async {
        f.lookups++;
        expect(invite.name, 'Trip');
        return f.answer();
      }),
      linkJoinActionProvider.overrideWithValue((c, r) async {
        f.requests.add(r);
        if (f.joinError != null) throw f.joinError!;
        return r.groupId;
      }),
      linkSwitchActionProvider.overrideWithValue((c, invite, groupId) async {
        f.switches.add((encodeLinkSecret(invite.secret), groupId));
        if (f.switchError != null) throw f.switchError!;
        return groupId;
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

void main() {
  group('pure helpers', () {
    test('isJoinLink / joinLocationFor', () {
      final web = Uri.parse(
        'https://leostumpf.github.io/moneyledger/join#$_frag',
      );
      final app = Uri.parse('moneyledger://join#$_frag');
      expect(isJoinLink(web), isTrue);
      expect(isJoinLink(app), isTrue);
      expect(isJoinLink(Uri.parse('moneyledger://sso-callback?x=1')), isFalse);
      expect(isJoinLink(Uri.parse('https://example.org/join#v=1')), isFalse);
      expect(joinLocationFor(web), '/join?$_frag');
      expect(joinLocationFor(Uri.parse('moneyledger://join')), '/join');
      // The route's query parses back to the same invite.
      expect(
        parseLinkFragment(Uri.parse(joinLocationFor(app)).query).name,
        'Trip',
      );
    });

    test('linkGroupPreviewFrom: newest meta, LWW people, claims / removed '
        'left out, "used" from the headers', () {
      OpenedLinkPart part(
        int at,
        String me,
        String name,
        List<Map<String, dynamic>> members, {
        String group = 'g1',
      }) => (
        content: {
          'meta': {
            'group': group,
            'name': name,
            'currency': 'EUR',
            'updated_at': at,
          },
          'members': members,
        },
        header: LinkSnapshotHeader(
          group: group,
          me: me,
          part: 0,
          parts: 1,
          app: 't',
        ),
        createdAt: at,
      );
      Map<String, dynamic> m(
        String id,
        String name,
        int at, {
        String status = 'active',
        String? mxid,
        String group = 'g1',
      }) => {
        'group': group,
        'participant_id': id,
        'name': name,
        'status': status,
        'updated_at': at,
        'matrix_id': mxid,
      };
      final p = linkGroupPreviewFrom([
        part(10, 'p1', 'Old', [m('p1', 'Anna', 1), m('p2', 'Ben', 1)]),
        part(20, 'p3', 'Trip', [
          m('p2', 'Benny', 5),
          m('p3', 'Cleo', 1),
          m('p4', 'Gone', 1, status: 'removed'),
          m('p5', 'Matrix', 1, mxid: '@m:x.org'),
          {'broken': true},
        ]),
      ])!;
      expect(p.groupId, 'g1');
      expect(p.name, 'Trip');
      expect(
        [for (final x in p.people) '${x.name}:${x.usedElsewhere}'],
        ['Anna:true', 'Benny:false', 'Cleo:true'],
      );
      expect(linkGroupPreviewFrom(const []), isNull);
      // Another group's part (older) is ignored.
      final q = linkGroupPreviewFrom([
        part(30, 'p1', 'Trip', [m('p1', 'Anna', 1)]),
        part(5, 'x', 'Evil', [m('x', 'X', 1, group: 'g2')], group: 'g2'),
      ])!;
      expect(q.people.map((x) => x.name), ['Anna']);
    });

    test('linkJoinBlocker', () {
      final ch = newLinkChannel(
        'g1',
        myParticipantId: null,
        openedAt: 1,
        secret: _secret,
      );
      expect(
        linkJoinBlocker(channel: null, groupStored: false, secret: _secret),
        isNull,
      );
      expect(
        linkJoinBlocker(channel: null, groupStored: true, secret: _secret),
        LinkJoinError.notALinkGroup,
      );
      expect(
        linkJoinBlocker(channel: ch, groupStored: true, secret: _secret),
        isNull,
      );
      expect(
        linkJoinBlocker(
          channel: newLinkChannel('g1', myParticipantId: null, openedAt: 1),
          groupStored: true,
          secret: _secret,
        ),
        LinkJoinError.otherLink,
      );
    });
  });

  testWidgets('JoinLinkListener: every opened link navigates — also the '
      'same link opened again (review)', (tester) async {
    final links = StreamController<JoinLinkEvent>();
    addTearDown(links.close);
    final went = <String>[];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [joinLinkStreamProvider.overrideWith((_) => links.stream)],
        child: JoinLinkListener(go: went.add, child: const SizedBox()),
      ),
    );
    final link = Uri.parse('moneyledger://join#$_frag');
    links.add(JoinLinkEvent(link));
    await tester.pump();
    links.add(JoinLinkEvent(Uri.parse('moneyledger://join#$_frag')));
    await tester.pump();
    expect(went, ['/join?$_frag', '/join?$_frag']);
  });

  group('join page', () {
    testWidgets('intro → look-up → pick a person → join → the group', (
      tester,
    ) async {
      final f = _Fakes();
      await tester.pumpWidget(_app(f));
      await tester.pumpAndSettle();
      expect(find.text(en.joinLinkInvitedTo('Trip')), findsOneWidget);
      expect(find.byKey(const Key('joinLinkNoAccountHint')), findsOneWidget);
      expect(f.lookups, 0, reason: 'nothing is fetched before Join');
      await tester.tap(find.byKey(const Key('joinLinkStart')));
      await tester.pumpAndSettle();
      expect(f.lookups, 1);
      expect(find.text(en.joinLinkPickTitle('Trip')), findsOneWidget);
      expect(find.text(en.joinLinkUsedElsewhere), findsOneWidget);
      final confirm = find.byKey(const Key('joinLinkConfirm'));
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
      await tester.tap(find.byKey(const Key('joinLinkPerson-p2')));
      await tester.pumpAndSettle();
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(f.requests.single.participantId, 'p2');
      expect(f.requests.single.name, 'Ben');
      expect(f.requests.single.groupId, 'g1');
      expect(find.text('group g1'), findsOneWidget);
    });

    testWidgets('someone new: a name is required, the duplicate hint shows', (
      tester,
    ) async {
      final f = _Fakes();
      await tester.pumpWidget(_app(f, session: AppSessionKind.local));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('joinLinkNoAccountHint')), findsNothing);
      await tester.tap(find.byKey(const Key('joinLinkStart')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('joinLinkNewPerson')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('joinLinkNameField')), 'ben');
      await tester.pumpAndSettle();
      expect(find.text(en.duplicatePersonHint('Ben')), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('joinLinkNameField')),
        'Cleo',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('joinLinkConfirm')));
      await tester.pumpAndSettle();
      expect(f.requests.single.participantId, isNull);
      expect(f.requests.single.name, 'Cleo');
    });

    testWidgets('first use: the disclosure comes first; cancel = no '
        'look-up', (tester) async {
      final f = _Fakes();
      await tester.pumpWidget(_app(f, disclosureSeen: false));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('joinLinkStart')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('linkDisclosure')), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(f.lookups, 0);
      await tester.tap(find.byKey(const Key('joinLinkStart')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('linkDisclosureContinue')));
      await tester.pumpAndSettle();
      expect(f.lookups, 1);
      expect(find.byKey(const Key('joinLinkPicker')), findsOneWidget);
    });

    testWidgets('nothing found → retry finds it', (tester) async {
      final f = _Fakes()..answer = () => null;
      await tester.pumpWidget(_app(f));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('joinLinkStart')));
      await tester.pumpAndSettle();
      expect(find.text(en.joinLinkNotFoundTitle), findsOneWidget);
      f.answer = () => const LinkJoinLookup(preview: _preview);
      await tester.tap(find.byKey(const Key('joinLinkRetry')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('joinLinkPicker')), findsOneWidget);
    });

    testWidgets('refused: held as a non-link group', (tester) async {
      final f = _Fakes()
        ..answer = () => const LinkJoinLookup(
          preview: _preview,
          blocker: LinkJoinError.notALinkGroup,
        );
      await tester.pumpWidget(_app(f));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('joinLinkStart')));
      await tester.pumpAndSettle();
      expect(find.text(en.joinLinkNotALinkGroup), findsOneWidget);
      expect(find.byKey(const Key('joinLinkConfirm')), findsNothing);
      expect(find.byKey(const Key('joinLinkSwitch')), findsNothing);
    });

    group('G52 step 12 follow-up: a replaced link', () {
      const replaced = LinkGroupPreview(
        groupId: 'g1',
        name: 'Trip',
        people: [LinkJoinPerson(id: 'p2', name: 'Ben', usedElsewhere: false)],
        replaced: true,
      );
      for (final (name, locale) in [
        ('English', const Locale('en')),
        ('German', const Locale('de')),
      ]) {
        final l = locale.languageCode == 'de' ? de : en;
        void phone(WidgetTester tester) {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = const Size(360, 740);
          tester.platformDispatcher.textScaleFactorTestValue = 2;
          addTearDown(tester.view.reset);
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        }

        Future<void> start(WidgetTester tester, _Fakes f) async {
          await tester.pumpWidget(
            _app(f, session: AppSessionKind.local, locale: locale),
          );
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.byKey(const Key('joinLinkStart')));
          await tester.tap(find.byKey(const Key('joinLinkStart')));
          await tester.pumpAndSettle();
        }

        testWidgets('$name: the picker warns (still joinable)', (tester) async {
          phone(tester);
          final f = _Fakes()
            ..answer = () => const LinkJoinLookup(preview: replaced);
          await start(tester, f);
          expect(find.text(l.joinLinkPickReplaced), findsOneWidget);
          expect(find.byKey(const Key('joinLinkPerson-p2')), findsOneWidget);
          expect(tester.takeException(), isNull);
        });

        testWidgets('$name: the switch page warns it is probably the old '
            'link', (tester) async {
          phone(tester);
          final f = _Fakes()
            ..answer = () => const LinkJoinLookup(
              preview: replaced,
              blocker: LinkJoinError.otherLink,
            );
          await start(tester, f);
          await tester.ensureVisible(
            find.byKey(const Key('joinLinkSwitchReplaced')),
          );
          expect(find.text(l.joinLinkSwitchReplaced), findsOneWidget);
          expect(tester.takeException(), isNull);
        });

        testWidgets('$name: only markers → "this link was replaced", no '
            'picker', (tester) async {
          phone(tester);
          final f = _Fakes()
            ..answer = () => const LinkJoinLookup(
              preview: LinkGroupPreview(
                groupId: 'g1',
                name: null,
                people: [],
                replaced: true,
                onlyReplaced: true,
              ),
            );
          await start(tester, f);
          expect(find.byKey(const Key('joinLinkReplaced')), findsOneWidget);
          expect(find.text(l.joinLinkReplacedTitle), findsOneWidget);
          expect(find.byKey(const Key('joinLinkPicker')), findsNothing);
          expect(tester.takeException(), isNull);
        });
      }
    });

    group('G52 step 12: shared with another link → switch', () {
      _Fakes other() => _Fakes()
        ..answer = () => const LinkJoinLookup(
          preview: _preview,
          blocker: LinkJoinError.otherLink,
        );

      testWidgets('asks first; "Use this link" switches (no picker) and '
          'opens the group', (tester) async {
        final f = other();
        await tester.pumpWidget(_app(f, session: AppSessionKind.local));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('joinLinkStart')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('joinLinkSwitch')), findsOneWidget);
        expect(find.text(en.joinLinkSwitchTitle('Trip')), findsOneWidget);
        expect(find.text(en.joinLinkSwitchBody), findsOneWidget);
        expect(find.byKey(const Key('joinLinkPicker')), findsNothing);
        expect(f.switches, isEmpty);
        await tester.tap(find.byKey(const Key('joinLinkSwitchConfirm')));
        await tester.pumpAndSettle();
        expect(f.switches, [(_secret, 'g1')]);
        expect(f.requests, isEmpty);
        expect(find.text('group g1'), findsOneWidget);
      });

      testWidgets('"Keep the old link" leaves without switching', (
        tester,
      ) async {
        final f = other();
        await tester.pumpWidget(_app(f, session: AppSessionKind.local));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('joinLinkStart')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('joinLinkSwitchCancel')));
        await tester.pumpAndSettle();
        expect(f.switches, isEmpty);
        expect(find.text('groups'), findsOneWidget);
      });

      testWidgets('a failed switch shows the error and stays', (tester) async {
        final f = other()..switchError = StateError('boom');
        await tester.pumpWidget(_app(f, session: AppSessionKind.local));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('joinLinkStart')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('joinLinkSwitchConfirm')));
        await tester.pumpAndSettle();
        expect(find.byType(SnackBar), findsOneWidget);
        expect(find.byKey(const Key('joinLinkSwitch')), findsOneWidget);
        expect(
          tester
              .widget<FilledButton>(
                find.byKey(const Key('joinLinkSwitchConfirm')),
              )
              .onPressed,
          isNotNull,
        );
      });

      testWidgets('another link found at join time → the switch page', (
        tester,
      ) async {
        final f = _Fakes()
          ..joinError = const LinkJoinException(LinkJoinError.otherLink);
        await tester.pumpWidget(_app(f, session: AppSessionKind.local));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('joinLinkStart')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('joinLinkPerson-p2')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('joinLinkConfirm')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('joinLinkSwitch')), findsOneWidget);
      });

      for (final (name, locale) in [
        ('English', const Locale('en')),
        ('German', const Locale('de')),
      ]) {
        testWidgets('$name at 360 dp, 200 % font: the switch page fits', (
          tester,
        ) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = const Size(360, 740);
          tester.platformDispatcher.textScaleFactorTestValue = 2;
          addTearDown(tester.view.reset);
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          final f = other();
          await tester.pumpWidget(
            _app(f, session: AppSessionKind.local, locale: locale),
          );
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.byKey(const Key('joinLinkStart')));
          await tester.tap(find.byKey(const Key('joinLinkStart')));
          await tester.pumpAndSettle();
          final l = locale.languageCode == 'de' ? de : en;
          expect(find.byKey(const Key('joinLinkSwitch')), findsOneWidget);
          await tester.ensureVisible(find.text(l.joinLinkSwitchCaution));
          await tester.ensureVisible(
            find.byKey(const Key('joinLinkSwitchCancel')),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        });
      }
    });

    testWidgets('a refusal at join time shows the same', (tester) async {
      final f = _Fakes()
        ..joinError = const LinkJoinException(LinkJoinError.notALinkGroup);
      await tester.pumpWidget(_app(f));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('joinLinkStart')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('joinLinkPerson-p1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('joinLinkConfirm')));
      await tester.pumpAndSettle();
      expect(find.text(en.joinLinkNotALinkGroup), findsOneWidget);
    });

    testWidgets('already joined → straight to the group', (tester) async {
      final f = _Fakes()
        ..answer = () =>
            const LinkJoinLookup(preview: _preview, joinedAs: 'p1');
      await tester.pumpWidget(_app(f, session: AppSessionKind.local));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('joinLinkStart')));
      await tester.pumpAndSettle();
      expect(find.text('group g1'), findsOneWidget);
      expect(f.requests, isEmpty);
    });

    testWidgets('a broken link / a newer version / paste', (tester) async {
      final f = _Fakes();
      await tester.pumpWidget(_app(f, location: '/join?v=1&k=short'));
      await tester.pumpAndSettle();
      expect(find.text(en.joinLinkInvalidTitle), findsOneWidget);
      expect(find.text(en.joinLinkInvalidBody), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(_app(f, location: '/join?v=2&k=$_secret'));
      await tester.pumpAndSettle();
      expect(find.text(en.joinLinkUpdateApp), findsOneWidget);
      await tester.tap(find.byKey(const Key('joinLinkPasteInstead')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('joinLinkPasteField')),
        'https://example.org/',
      );
      await tester.tap(find.byKey(const Key('joinLinkPasteContinue')));
      await tester.pumpAndSettle();
      expect(find.text(en.joinLinkInvalidBody), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('joinLinkPasteField')),
        ' moneyledger://join#$_frag ',
      );
      await tester.tap(find.byKey(const Key('joinLinkPasteContinue')));
      await tester.pumpAndSettle();
      expect(find.text(en.joinLinkInvitedTo('Trip')), findsOneWidget);
    });

    testWidgets('still loading the session: a spinner, no intro', (
      tester,
    ) async {
      await tester.pumpWidget(_app(_Fakes(), session: AppSessionKind.loading));
      await tester.pump();
      expect(find.byKey(const Key('joinLinkIntro')), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    for (final (name, locale) in [
      ('English', const Locale('en')),
      ('German', const Locale('de')),
    ]) {
      testWidgets('$name at 360 dp, 200 % font: intro + picker fit', (
        tester,
      ) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(360, 740);
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final l = locale.languageCode == 'de' ? de : en;
        await tester.pumpWidget(_app(_Fakes(), locale: locale));
        await tester.pumpAndSettle();
        expect(find.text(l.joinLinkTitle), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.byKey(const Key('joinLinkStart')));
        await tester.tap(find.byKey(const Key('joinLinkStart')));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byKey(const Key('joinLinkNewPerson')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('joinLinkNewPerson')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('joinLinkNameField')), findsOneWidget);
        expect(find.text(l.joinLinkUsedElsewhere), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('entry points', () {
    testWidgets('create group offers "Join with an invite link"', (
      tester,
    ) async {
      await tester.pumpWidget(
        testApp(const CreateGroupPage(), overrides: testOverrides()),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('createGroupJoinLink')));
      expect(find.text(en.joinLinkEntry), findsOneWidget);
    });

    testWidgets('the welcome choices offer it too', (tester) async {
      await tester.pumpWidget(
        testApp(
          const WelcomePage(startAtChoices: true),
          overrides: testOverrides(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('welcomeJoinLink')));
      expect(find.text(en.joinLinkEntry), findsOneWidget);
    });
  });
}
