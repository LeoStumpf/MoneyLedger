/// G68 (U24) + G52 step 9: the tappable sync icon and the per-person sync
/// sheet (Matrix and link groups, *Sync now*), and Settings → Relays (list
/// + status, add with the NIP-11 check, remove, defaults) — EN + DE, 360 dp,
/// 200 % font.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/link/link_relay_policy.dart';
import 'package:money_ledger/core/link/link_sync_engine.dart';
import 'package:money_ledger/core/link/nostr/nip11.dart';
import 'package:money_ledger/core/sync/sync_status_provider.dart';
import 'package:money_ledger/features/expenses/expenses_page.dart';
import 'package:money_ledger/features/groups/group_provider.dart';
import 'package:money_ledger/features/link/link_invite.dart';
import 'package:money_ledger/features/link/relay_settings_page.dart';
import 'package:money_ledger/features/sync/group_sync_sheet.dart';
import 'package:money_ledger/models/expense_model.dart';
import 'package:money_ledger/models/link_model.dart';
import 'package:money_ledger/models/member_model.dart';

import 'helpers/l10n.dart';
import 'helpers/test_providers.dart';

const _g = 'g1';

MemberModel _m(String id, String name, {String? mxid}) => MemberModel(
  groupId: _g,
  userId: id,
  displayName: name,
  matrixId: mxid,
  status: 'active',
  updatedAt: 1,
);

void _phone(WidgetTester tester, {bool big = false}) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(360, 740);
  addTearDown(tester.view.reset);
  if (big) {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }
}

int _minsAgo(int m) =>
    DateTime.now().millisecondsSinceEpoch - m * 60 * 1000 - 5000;

class _SyncNowSpy {
  final calls = <(String, bool)>[];
  GroupSyncNowResult result = GroupSyncNowResult.sent;
  Future<GroupSyncNowResult> call(String groupId, {required bool link}) async {
    calls.add((groupId, link));
    return result;
  }
}

void main() {
  group('Matrix group: sync sheet per person (G68)', () {
    final members = [
      _m('@me:x.org', 'Me', mxid: '@me:x.org'),
      _m('@ben:x.org', 'Ben', mxid: '@ben:x.org'),
      _m('@cleo:x.org', 'Cleo', mxid: '@cleo:x.org'),
      _m('p-fritz', 'Fritz'),
    ];
    final status = GroupSyncStatus(
      pendingPeers: const {'@cleo:x.org'},
      minPeerInSyncAt: 1,
      peerInSyncAt: {'@ben:x.org': _minsAgo(3), '@cleo:x.org': _minsAgo(90)},
      maxRecordUpdatedAt: _minsAgo(10),
    );

    Widget app(_SyncNowSpy spy, {Locale? locale}) => testApp(
      const ExpensesPage(roomId: _g),
      locale: locale,
      overrides: [
        ...testOverrides(
          isLoggedIn: true,
          members: members,
          syncStatus: status,
        ),
        currentUserIdProvider.overrideWith((_) => '@me:x.org'),
        groupSyncNowProvider.overrideWithValue(spy.call),
      ],
    );

    for (final (locale, l) in [
      (const Locale('en'), en),
      (const Locale('de'), de),
    ]) {
      testWidgets('the cloud opens the sheet: one row per person, Sync now '
          '($locale, 360 dp, 200 %)', (tester) async {
        _phone(tester, big: true);
        final spy = _SyncNowSpy();
        await tester.pumpWidget(app(spy, locale: locale));
        await tester.pumpAndSettle();
        final cloud = find.byKey(const Key('groupSyncButton'));
        expect(
          tester.widget<IconButton>(cloud).tooltip,
          l.waitingForPeer('@cleo:x.org'),
        );
        await tester.tap(cloud);
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('groupSyncSheet')), findsOneWidget);
        expect(find.text(l.syncSheetPending), findsOneWidget);
        expect(
          find.text(l.peerUpToDateAt(l.agoMinutes(3))),
          findsOneWidget,
          reason: 'Ben',
        );
        expect(
          find.text(l.peerWaitingSince(l.agoHours(1))),
          findsOneWidget,
          reason: 'Cleo',
        );
        expect(find.byKey(const Key('peerSync-@ben:x.org')), findsOneWidget);
        expect(find.byKey(const Key('peerSync-p-fritz')), findsNothing);
        expect(find.byKey(const Key('groupSyncRelays')), findsNothing);
        final now = find.byKey(const Key('groupSyncNow'));
        await _show(tester, now, list: const Key('groupSyncSheet'));
        expect(find.text(l.syncSheetLocalPeople), findsOneWidget);
        await tester.tap(now);
        await tester.pumpAndSettle();
        expect(spy.calls, [(_g, false)]);
        expect(find.text(l.syncNowSent), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('link group: the link status + peers sheet (G52 step 9)', () {
    final members = [_m('p1', 'Anna'), _m('p2', 'Ben'), _m('p3', 'Cleo')];
    final channel = LinkChannelModel(
      groupId: _g,
      epoch: 1,
      secret: 's',
      nostrPriv: '11' * 32,
      openedAt: 1,
      myParticipantId: 'p1',
      lastPublishedHash: 'D',
      lastPublishedAt: _minsAgo(2),
    );
    final peers = [
      LinkPeerModel(
        groupId: _g,
        pubkey: 'a',
        me: 'p2',
        lastCreatedAt: _minsAgo(5) ~/ 1000,
        snapshotDigest: 'D',
        eventIds: const {0: 'x'},
      ),
      LinkPeerModel(
        groupId: _g,
        pubkey: 'b',
        me: 'p3',
        lastCreatedAt: _minsAgo(30) ~/ 1000,
        snapshotDigest: 'old',
        eventIds: const {0: 'y'},
      ),
    ];

    Widget app(
      _SyncNowSpy spy,
      LinkGroupSyncStatus status, {
      Locale? locale,
      String? localProfile,
      List<ExpenseModel> expenses = const [],
    }) => testApp(
      const ExpensesPage(roomId: _g),
      locale: locale,
      overrides: [
        ...testOverrides(
          isLoggedIn: localProfile == null,
          localProfile: localProfile,
          members: members,
          expenses: expenses,
          // The Matrix status would say "waiting" — never shown here.
          syncStatus: const GroupSyncStatus(
            pendingPeers: {'@x:y.org'},
            minPeerInSyncAt: 0,
          ),
        ),
        linkInviteStateProvider(
          _g,
        ).overrideWith((ref) async => LinkInviteState.open),
        linkGroupSyncStatusProvider(
          _g,
        ).overrideWith((ref) => Stream.value(status)),
        groupLinkPeersProvider(_g).overrideWith((ref) => Stream.value(peers)),
        groupLinkChannelProvider(
          _g,
        ).overrideWith((ref) => Stream.value(channel)),
        currentParticipantProvider(
          _g,
        ).overrideWith((ref) async => members.first),
        groupSyncNowProvider.overrideWithValue(spy.call),
      ],
    );

    for (final (locale, l) in [
      (const Locale('en'), en),
      (const Locale('de'), de),
    ]) {
      testWidgets('synced: link cloud, rows from the publishers, relays '
          'entry, Sync now ($locale, 360 dp, 200 %)', (tester) async {
        _phone(tester, big: true);
        final spy = _SyncNowSpy()..result = GroupSyncNowResult.checked;
        await tester.pumpWidget(
          app(
            spy,
            LinkGroupSyncStatus(
              phase: LinkSyncPhase.synced,
              lastPublishedAt: _minsAgo(2),
            ),
            locale: locale,
          ),
        );
        await tester.pumpAndSettle();
        final cloud = find.byKey(const Key('groupSyncButton'));
        expect(tester.widget<IconButton>(cloud).tooltip, l.linkCloudSynced);
        expect(find.byIcon(Icons.cloud_done_outlined), findsOneWidget);
        await tester.tap(cloud);
        await tester.pumpAndSettle();
        expect(find.text(l.linkSyncSynced(l.agoMinutes(2))), findsOneWidget);
        expect(find.text(l.peerUpToDate), findsOneWidget, reason: 'Ben');
        expect(
          find.text(l.peerPublishedAt(l.agoMinutes(30))),
          findsOneWidget,
          reason: 'Cleo',
        );
        final now = find.byKey(const Key('groupSyncNow'));
        await _show(tester, now, list: const Key('groupSyncSheet'));
        expect(find.byKey(const Key('groupSyncRelays')), findsOneWidget);
        await tester.tap(now);
        await tester.pumpAndSettle();
        expect(spy.calls, [(_g, true)]);
        expect(find.text(l.syncNowChecked), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('failing: error cloud, the problem in the sheet; local mode '
        'shows the link cloud too', (tester) async {
      _phone(tester);
      final spy = _SyncNowSpy()..result = GroupSyncNowResult.unreachable;
      await tester.pumpWidget(
        app(
          spy,
          const LinkGroupSyncStatus(
            phase: LinkSyncPhase.failing,
            problem: LinkSyncProblem.relaysReject,
          ),
          localProfile: 'Anna',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.cloud_off), findsOneWidget);
      await tester.tap(find.byKey(const Key('groupSyncButton')));
      await tester.pumpAndSettle();
      expect(find.text(en.linkSyncRelaysReject), findsOneWidget);
      // Ours isn't on the relays → nobody "has everything".
      expect(find.text(en.peerUpToDate), findsNothing);
      await tester.tap(find.byKey(const Key('groupSyncNow')));
      await tester.pumpAndSettle();
      expect(find.text(en.syncNowUnreachable), findsOneWidget);
    });

    for (final (locale, l) in [
      (const Locale('en'), en),
      (const Locale('de'), de),
    ]) {
      testWidgets('offline (DEV-J): offline cloud + sheet text; only the '
          'expense newer than the last publish is "not synced yet" '
          '($locale)', (tester) async {
        _phone(tester);
        final published = _minsAgo(10);
        ExpenseModel e(String id, int at) => ExpenseModel(
          id: id,
          roomId: _g,
          description: id,
          amountCents: 1000,
          currency: 'EUR',
          paidBy: 'p1',
          splitsJson: '{"p1":500,"p2":500}',
          createdAt: at,
          updatedAt: at,
        );
        await tester.pumpWidget(
          app(
            _SyncNowSpy(),
            LinkGroupSyncStatus(
              phase: LinkSyncPhase.pending,
              lastPublishedAt: published,
              problem: LinkSyncProblem.offline,
            ),
            locale: locale,
            localProfile: 'Anna',
            expenses: [e('Old', published - 1000), e('New', published + 1000)],
          ),
        );
        await tester.pumpAndSettle();
        final cloud = find.byKey(const Key('groupSyncButton'));
        expect(tester.widget<IconButton>(cloud).tooltip, l.linkCloudOffline);
        expect(find.text('New'), findsOneWidget);
        expect(find.byIcon(Icons.cloud_queue), findsOneWidget);
        await tester.tap(cloud);
        await tester.pumpAndSettle();
        expect(find.text(l.linkSyncOffline), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('local mode, not a link group: no sync icon', (tester) async {
      _phone(tester);
      await tester.pumpWidget(
        testApp(
          const ExpensesPage(roomId: _g),
          overrides: [
            ...testOverrides(localProfile: 'Anna', members: members),
            linkInviteStateProvider(
              _g,
            ).overrideWith((ref) async => LinkInviteState.canOpen),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('groupSyncButton')), findsNothing);
    });
  });

  group('disclosure names the configured relays (G52 step 9)', () {
    for (final (locale, l) in [
      (const Locale('en'), en),
      (const Locale('de'), de),
    ]) {
      testWidgets('defaults: "one operator" + Settings → Relays ($locale)', (
        tester,
      ) async {
        _phone(tester, big: true);
        await tester.pumpWidget(
          testApp(const LinkDisclosurePage(), locale: locale),
        );
        await tester.pumpAndSettle();
        expect(
          find.text(l.linkDisclosureRelaysOneOperator('nos.lol, nostr.mom')),
          findsOneWidget,
        );
        await tester.ensureVisible(find.text(l.linkDisclosureOwnRelay));
        expect(find.text(l.linkDisclosureOwnRelay), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('a custom list is named as it is', (tester) async {
      await tester.pumpWidget(
        testApp(
          const LinkDisclosurePage(
            relays: ['wss://nos.lol', 'wss://relay.example.org'],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(en.linkDisclosureRelays('nos.lol, relay.example.org')),
        findsOneWidget,
      );
    });

    testWidgets('the invite flow passes the configured list', (tester) async {
      Future<List<String>> relays() async => const ['wss://mine.example.org'];
      late WidgetRef captured;
      await tester.pumpWidget(
        testApp(
          Consumer(
            builder: (context, ref, _) {
              captured = ref;
              return TextButton(
                onPressed: () => ensureLinkDisclosure(context, ref),
                child: const Text('go'),
              );
            },
          ),
          overrides: [
            ...testOverrides(localProfile: 'Anna'),
            linkDisclosureRelaysProvider.overrideWithValue(relays),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(captured, isNotNull);
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      expect(
        find.text(en.linkDisclosureRelays('mine.example.org')),
        findsOneWidget,
      );
    });
  });

  group('Settings → Relays (G52 step 9)', () {
    late List<(List<String>, Map<String, RelayInfo>)> sets;
    setUp(() => sets = []);

    Future<void> setter(
      List<String> relays, {
      Map<String, RelayInfo> info = const {},
    }) async => sets.add((relays, info));

    Widget app({
      List<LinkRelayView>? relays,
      RelayInfoFetcher? fetcher,
      Locale? locale,
    }) => testApp(
      const RelaySettingsPage(),
      locale: locale,
      overrides: [
        ...testOverrides(isLoggedIn: true, relayViews: relays),
        linkRelaysSetterProvider.overrideWithValue(setter),
        linkRelayInfoFetcherProvider.overrideWithValue(fetcher),
      ],
    );

    final states = [
      LinkRelayView(
        url: 'wss://nos.lol',
        state: LinkRelayState(lastOkAt: _minsAgo(4)),
      ),
      const LinkRelayView(
        url: 'wss://nostr.mom',
        rejectingMessage: 'blocked: not here',
      ),
      const LinkRelayView(
        url: 'wss://relay.example.org',
        state: LinkRelayState(info: RelayInfo(authRequired: true)),
      ),
    ];

    for (final (locale, l) in [
      (const Locale('en'), en),
      (const Locale('de'), de),
    ]) {
      testWidgets('list + status, terms, defaults button ($locale, 360 dp, '
          '200 %)', (tester) async {
        _phone(tester, big: true);
        await tester.pumpWidget(app(relays: states, locale: locale));
        await tester.pumpAndSettle();
        expect(find.text(l.relaysIntro), findsOneWidget);
        await _show(tester, find.byKey(const Key('relaysOneOperator')));
        await _show(tester, find.text(l.relayStatusOk(l.agoMinutes(4))));
        expect(find.byKey(const Key('relayTerms-nos.lol')), findsOneWidget);
        await _show(
          tester,
          find.text(l.relayStatusRejects('blocked: not here')),
        );
        await _show(tester, find.text(l.relayStatusNeedsAccount));
        expect(
          find.byKey(const Key('relayTerms-relay.example.org')),
          findsNothing,
        );
        await _show(tester, find.byKey(const Key('relaysRestoreDefaults')));
        await tester.tap(find.byKey(const Key('relaysRestoreDefaults')));
        await tester.pumpAndSettle();
        expect(sets.single.$1, ['wss://nos.lol', 'wss://nostr.mom']);
        expect(find.text(l.relaysDefaultsRestored), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('defaults: no "use the defaults"; the last relay can\'t be '
        'removed; remove asks first', (tester) async {
      _phone(tester);
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('relaysRestoreDefaults')), findsNothing);
      await tester.tap(find.byKey(const Key('relayRemove-nostr.mom')));
      await tester.pumpAndSettle();
      expect(
        find.text(en.relayRemoveConfirmTitle('nostr.mom')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('relayRemoveConfirm')));
      await tester.pumpAndSettle();
      expect(sets.single.$1, ['wss://nos.lol']);
      expect(find.text(en.relayRemoved), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        app(relays: const [LinkRelayView(url: 'wss://nos.lol')]),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<IconButton>(find.byKey(const Key('relayRemove-nos.lol')))
            .onPressed,
        isNull,
      );
    });

    testWidgets('add: address errors, NIP-11 refusal, success with the '
        'document', (tester) async {
      _phone(tester);
      final fetcher = _Fetcher();
      await tester.pumpWidget(app(fetcher: fetcher));
      await tester.pumpAndSettle();
      Future<void> submit(String text) async {
        await tester.enterText(find.byKey(const Key('relayAddField')), text);
        await tester.tap(find.byKey(const Key('relayAddConfirm')));
        await tester.pumpAndSettle();
      }

      await _show(tester, find.byKey(const Key('relayAdd')));
      await tester.tap(find.byKey(const Key('relayAdd')));
      await tester.pumpAndSettle();
      await submit('ws://relay.example.org');
      expect(find.text(en.relayAddNotSecure), findsOneWidget);
      await submit('nos.lol');
      expect(find.text(en.relayAddDuplicate), findsOneWidget);
      await submit('not a relay');
      expect(find.text(en.relayAddInvalid), findsOneWidget);
      fetcher.info = const RelayInfo(paymentRequired: true);
      await submit('paid.example.org');
      expect(find.text(en.relayAddNeedsAccount), findsOneWidget);
      fetcher.info = const RelayInfo(supportedNips: [1, 11]);
      await submit('old.example.org');
      expect(find.text(en.relayAddNoExpiration), findsOneWidget);
      expect(sets, isEmpty);

      fetcher.info = const RelayInfo(supportedNips: [1, 40], name: 'mine');
      await submit('relay.example.org');
      expect(fetcher.asked, contains('wss://relay.example.org'));
      expect(sets.single.$1, [
        'wss://nos.lol',
        'wss://nostr.mom',
        'wss://relay.example.org',
      ]);
      expect(sets.single.$2['wss://relay.example.org']?.name, 'mine');
      expect(find.text(en.relayAdded), findsOneWidget);
    });

    testWidgets('add: a relay that doesn\'t answer the check can be added '
        'anyway (without a document)', (tester) async {
      _phone(tester);
      final fetcher = _Fetcher()..fail = true;
      await tester.pumpWidget(app(fetcher: fetcher));
      await tester.pumpAndSettle();
      await _show(tester, find.byKey(const Key('relayAdd')));
      await tester.tap(find.byKey(const Key('relayAdd')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('relayAddField')),
        'quiet.example.org',
      );
      await tester.tap(find.byKey(const Key('relayAddConfirm')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('relayAddUnchecked')), findsOneWidget);
      expect(sets, isEmpty);
      await tester.tap(find.text(en.relayAddAnyway));
      await tester.pumpAndSettle();
      expect(sets.single.$1.last, 'wss://quiet.example.org');
      expect(sets.single.$2, isEmpty);
    });
  });
}

/// Scrolls [finder] into view in [list] (default: the relay settings).
Future<void> _show(
  WidgetTester tester,
  Finder finder, {
  Key list = const Key('relaySettingsList'),
}) async {
  await tester.scrollUntilVisible(
    finder,
    100,
    scrollable: find.descendant(
      of: find.byKey(list),
      matching: find.byType(Scrollable),
    ),
  );
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

class _Fetcher implements RelayInfoFetcher {
  RelayInfo info = const RelayInfo();
  bool fail = false;
  final asked = <String>[];
  @override
  Future<RelayInfo> fetch(String relay) async {
    asked.add(relay);
    if (fail) throw StateError('offline');
    return info;
  }
}
