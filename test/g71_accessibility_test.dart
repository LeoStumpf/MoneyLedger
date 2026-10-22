/// G71 (U30): Flutter's accessibility guidelines on the main pages — every
/// tap target ≥ 48 dp (Android), every tappable thing has a label, text
/// contrast — at 360 dp in English.
library;

import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:money_ledger/core/link/link_channel.dart' show LinkJoinError;
import 'package:money_ledger/core/link/link_join_probe.dart';
import 'package:money_ledger/features/link/link_join.dart';
import 'package:money_ledger/core/database/account_database.dart';
import 'package:money_ledger/core/database/app_database.dart';
import 'package:money_ledger/core/database/daos/expenses_dao.dart';
import 'package:money_ledger/core/database/daos/groups_dao.dart';
import 'package:money_ledger/core/database/daos/members_dao.dart';
import 'package:money_ledger/core/matrix/transport_provider.dart';
import 'package:money_ledger/core/platform/is_web.dart';
import 'package:money_ledger/core/sync/sync_status_provider.dart';
import 'package:money_ledger/core/theme/app_theme.dart';
import 'package:money_ledger/features/auth/auth_provider.dart';
import 'package:money_ledger/features/devices/device_provider.dart';
import 'package:money_ledger/features/backup/backup_restore_page.dart';
import 'package:money_ledger/features/balance/balance_calculator.dart';
import 'package:money_ledger/features/balance/balance_page.dart';
import 'package:money_ledger/features/balance/record_payment_dialog.dart';
import 'package:money_ledger/features/expenses/add_expense_page.dart';
import 'package:money_ledger/features/expenses/expenses_page.dart';
import 'package:money_ledger/features/expenses/expenses_provider.dart';
import 'package:money_ledger/features/groups/create_group_page.dart';
import 'package:money_ledger/features/groups/group_members_page.dart';
import 'package:money_ledger/features/groups/group_provider.dart';
import 'package:money_ledger/features/groups/group_rates_page.dart';
import 'package:money_ledger/features/groups/group_settings_page.dart';
import 'package:money_ledger/features/groups/groups_page.dart';
import 'package:money_ledger/features/history/restore_points.dart';
import 'package:money_ledger/features/link/link_invite.dart';
import 'package:money_ledger/features/link/relay_settings_page.dart';
import 'package:money_ledger/features/sync/group_sync_sheet.dart';
import 'package:money_ledger/features/receipts/receipt_store.dart';
import 'package:money_ledger/features/settings/settings_page.dart';
import 'package:money_ledger/features/welcome/welcome_page.dart';
import 'package:money_ledger/features/welcome/why_matrix_page.dart';
import 'package:money_ledger/models/exchange_rates.dart';
import 'package:money_ledger/models/expense_model.dart';
import 'package:money_ledger/models/group_model.dart';
import 'package:money_ledger/models/member_model.dart';

import 'helpers/fake_auth_gateway.dart';
import 'package:money_ledger/features/payment/payment_details.dart';
import 'package:money_ledger/features/payment/payment_details_page.dart';

import 'helpers/fake_device_gateway.dart';
import 'helpers/fake_ledger_network.dart';
import 'helpers/in_memory_database.dart';
import 'helpers/l10n.dart';
import 'helpers/test_providers.dart';

const _g = 'g1';
const _me = '@anna:x.org';
const _bob = '@bob:x.org';

MemberModel _member(String id, String name, {String? mxid}) => MemberModel(
  groupId: _g,
  userId: id,
  displayName: name,
  matrixId: mxid,
  status: 'active',
  updatedAt: 1,
);

final _members = [
  _member(_me, 'Anna', mxid: _me),
  _member(_bob, 'Bob', mxid: _bob),
  _member('p-carl', 'Carl'),
];

const _group = GroupModel(roomId: _g, name: 'Rome 2026', currency: 'EUR');

const _expenses = [
  ExpenseModel(
    id: 'e1',
    roomId: _g,
    description: 'Pizza',
    amountCents: 4200,
    currency: 'EUR',
    paidBy: _me,
    splitsJson: '{"$_me":2100,"$_bob":2100}',
    createdAt: 5000,
    category: 'food',
    note: 'Tip included',
    updatedAt: 9000, // newer than the peers' last sync → pending
  ),
  ExpenseModel(
    id: 'e2',
    roomId: _g,
    description: 'Tickets',
    amountCents: 3000,
    currency: 'EUR',
    paidBy: _bob,
    splitsJson: '{"$_me":1500,"$_bob":1500}',
    createdAt: 6000,
  ),
];

const _settlements = [
  SettlementModel(
    id: 's1',
    roomId: _g,
    amountCents: 500,
    currency: 'EUR',
    fromUser: _bob,
    toUser: _me,
    createdAt: 7000,
  ),
];

const _debts = [DebtEntry(from: _bob, to: _me, cents: 100, currency: 'EUR')];

/// A 360 × 780 dp phone.
void _phone(WidgetTester tester, {double height = 780}) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(360, height);
  addTearDown(tester.view.reset);
}

List<dynamic> _overrides({
  List<dynamic> extra = const [],
  PaymentDetails? paymentDetails,
  List<GroupModel> groups = const [_group],
  GroupSyncStatus syncStatus = const GroupSyncStatus(
    pendingPeers: {},
    minPeerInSyncAt: null,
  ),
}) => [
  ...testOverrides(
    syncStatus: syncStatus,
    isLoggedIn: true,
    members: _members,
    groups: groups,
    expenses: _expenses,
    settlements: _settlements,
    debts: _debts,
    paymentDetails: paymentDetails,
  ),
  currentUserIdProvider.overrideWith((_) => _me),
  currentParticipantProvider.overrideWith((ref, g) async => _members.first),
  snapshotsSupportedProvider.overrideWithValue(true),
  // No sync engine (signed-out placeholder DB), never a Matrix client.
  appDatabaseProvider.overrideWithValue(
    AppDatabase.signedOut(SignedOutExecutor()),
  ),
  ledgerTransportProvider.overrideWith(
    (ref) => FakeMatrixNetwork().clientFor(_me),
  ),
  authGatewayProvider.overrideWith(
    (ref) async => FakeAuthGateway(initialUserId: _me),
  ),
  deviceGatewayProvider.overrideWith(
    (ref) async => FakeDeviceGateway(const []),
  ),
  ...extra,
];

/// Every guideline the page must meet. Text contrast is checked where the
/// page has no translucent overlays (it is unstable with them).
Future<void> _expectGuidelines(
  WidgetTester tester, {
  bool contrast = true,
}) async {
  await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  if (contrast) {
    await expectLater(tester, meetsGuideline(textContrastGuideline));
  }
  // Let debounce / animation timers of the page run out.
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(minutes: 1));
}

Widget _routed(Widget page, List<dynamic> overrides) {
  final router = GoRouter(
    initialLocation: '/page',
    routes: [GoRoute(path: '/page', builder: (_, _) => page)],
  );
  return ProviderScope(
    overrides: [...overrides],
    child: MaterialApp.router(
      theme: AppTheme.light(isWeb: false),
      locale: const Locale('en'),
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      routerConfig: router,
    ),
  );
}

Future<AppDatabase> _seed() async {
  final db = openTestDatabase();
  await GroupsDao(db).upsertGroupLww(
    const GroupsCompanion(
      roomId: Value(_g),
      name: Value('Rome 2026'),
      currency: Value('EUR'),
      updatedAt: Value(1000),
    ),
  );
  for (final (id, name) in [(_me, 'Anna'), (_bob, 'Bob')]) {
    await MembersDao(db).upsertMemberLww(
      MembersCompanion(
        groupId: const Value(_g),
        userId: Value(id),
        displayName: Value(name),
        matrixId: Value(id),
        status: const Value('active'),
        updatedAt: const Value(1),
      ),
    );
  }
  return db;
}

void main() {
  testWidgets('groups page', (tester) async {
    _phone(tester);
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_routed(const GroupsPage(), _overrides()));
    await tester.pumpAndSettle();
    expect(find.text('Rome 2026'), findsOneWidget);
    await _expectGuidelines(tester);
    handle.dispose();
  });

  // G75 (U31): the one-time web limits notice on the groups page.
  testWidgets('groups page on the web: limits notice', (tester) async {
    _phone(tester);
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _routed(
        const GroupsPage(),
        _overrides(extra: [isWebProvider.overrideWithValue(true)]),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('webLimitsBanner')), findsOneWidget);
    expect(
      tester.getSemantics(find.text(en.webLimitsTitle)),
      isSemantics(isHeader: true),
    );
    await _expectGuidelines(tester);
    handle.dispose();
  });

  testWidgets('group page (ledger), incl. a pending sync cloud', (
    tester,
  ) async {
    _phone(tester);
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _routed(
        const ExpensesPage(roomId: _g),
        _overrides(
          syncStatus: const GroupSyncStatus(
            pendingPeers: {_bob},
            minPeerInSyncAt: null,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Pizza'), findsOneWidget);
    await _expectGuidelines(tester);
    handle.dispose();
  });

  testWidgets('balance page', (tester) async {
    _phone(tester);
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _routed(const BalancePage(roomId: _g), _overrides()),
    );
    await tester.pumpAndSettle();
    await _expectGuidelines(tester);
    handle.dispose();
  });

  testWidgets('balance page: G69 overview + share action', (tester) async {
    _phone(tester);
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _routed(const BalancePage(roomId: _g), _overrides()),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getSemantics(find.byKey(const Key('shareBalances'))),
      isSemantics(tooltip: 'Share who pays whom', isButton: true),
    );
    await tester.scrollUntilVisible(
      find.byKey(const Key('statsCategory-EUR-food')),
      200,
    );
    await tester.pumpAndSettle();
    expect(
      tester.getSemantics(find.text('Overview')),
      isSemantics(isHeader: true),
    );
    expect(
      tester.getSemantics(find.text('By category')),
      isSemantics(isHeader: true),
    );
    await _expectGuidelines(tester);
    handle.dispose();
  });

  testWidgets('payment dialog', (tester) async {
    _phone(tester);
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _routed(
        const Scaffold(
          body: RecordPaymentDialog(
            participants: {'a': 'Anna', 'b': 'Bob'},
            initialFrom: 'a',
            initialTo: 'b',
            currency: 'EUR',
          ),
        ),
        const [],
      ),
    );
    await tester.pumpAndSettle();
    await _expectGuidelines(tester);
    handle.dispose();
  });

  testWidgets('settings page', (tester) async {
    _phone(tester);
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_routed(const SettingsPage(), _overrides()));
    await tester.pumpAndSettle();
    await _expectGuidelines(tester);
    handle.dispose();
  });

  // G74: the payment details page and the balance page's QR sheet.
  const payment = PaymentDetails(
    name: 'Anna Muster',
    iban: 'DE89370400440532013000',
    paypalMe: 'annamuster',
  );

  testWidgets('G74 payment details page', (tester) async {
    _phone(tester);
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _routed(const PaymentDetailsPage(), _overrides(paymentDetails: payment)),
    );
    await tester.pumpAndSettle();
    await _expectGuidelines(tester);
    handle.dispose();
  });

  testWidgets('G74 payment QR sheet (GiroCode)', (tester) async {
    _phone(tester);
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _routed(
        const BalancePage(roomId: _g),
        _overrides(paymentDetails: payment),
      ),
    );
    await tester.pumpAndSettle();
    const qr = Key('paymentQr-$_bob-$_me-EUR');
    await tester.scrollUntilVisible(
      find.byKey(qr),
      150,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(
      tester.getSemantics(find.byKey(qr)),
      isSemantics(tooltip: en.paymentShowDetails, isButton: true),
    );
    await tester.tap(find.byKey(qr));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('paymentGiroCode')), findsOneWidget);
    // The modal barrier is translucent — no contrast check.
    await _expectGuidelines(tester, contrast: false);
    handle.dispose();
  });

  testWidgets('group settings page', (tester) async {
    _phone(tester);
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _routed(const GroupSettingsPage(roomId: _g), _overrides()),
    );
    await tester.pumpAndSettle();
    await _expectGuidelines(tester);
    handle.dispose();
  });

  for (final dialog in [false, true]) {
    testWidgets('G73 exchange rates page${dialog ? ': rate dialog' : ''}', (
      tester,
    ) async {
      _phone(tester);
      final handle = tester.ensureSemantics();
      final group = GroupModel(
        roomId: _g,
        name: 'Rome 2026',
        currency: 'EUR',
        exchangeRates: ExchangeRates(
          base: 'EUR',
          rates: const {'CHF': '1.0797'},
          settle: true,
        ),
      );
      await tester.pumpWidget(
        _routed(const GroupRatesPage(roomId: _g), _overrides(groups: [group])),
      );
      await tester.pumpAndSettle();
      if (dialog) {
        await tester.tap(find.byKey(const Key('rate-CHF')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('fetchRateButton')), findsOneWidget);
      }
      await _expectGuidelines(tester, contrast: !dialog);
      handle.dispose();
    });
  }

  testWidgets('people page', (tester) async {
    _phone(tester);
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _routed(const GroupMembersPage(roomId: _g), [
        currentUserIdProvider.overrideWithValue(_me),
        groupMembersProvider(_g).overrideWith((ref) => Stream.value(_members)),
        ledgerGroupsProvider.overrideWith((_) => Stream.value([_group])),
        ...FakeTrustStore().overrides(FakeDeviceGateway(const [])),
      ]),
    );
    await tester.pumpAndSettle();
    expect(find.text('Bob'), findsOneWidget);
    await _expectGuidelines(tester);
    handle.dispose();
  });

  testWidgets('backup & restore page', (tester) async {
    _phone(tester);
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_routed(const BackupRestorePage(), _overrides()));
    await tester.pumpAndSettle();
    await _expectGuidelines(tester);
    handle.dispose();
  });

  testWidgets('create group page', (tester) async {
    _phone(tester);
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_routed(const CreateGroupPage(), _overrides()));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('createGroupPersonField')),
      'Carl',
    );
    await tester.tap(find.byKey(const Key('createGroupPersonAdd')));
    await tester.pumpAndSettle();
    await _expectGuidelines(tester);
    handle.dispose();
  });

  // G52 step 12: with the reset button / right after a reset.
  for (final afterReset in [false, true]) {
    testWidgets('G52 invite-link sheet${afterReset ? ' after a reset' : ''}', (
      tester,
    ) async {
      _phone(tester, height: 1400);
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _routed(
          Scaffold(
            body: LinkInviteSheet(
              link:
                  'https://leostumpf.github.io/moneyledger/join#v=1&'
                  'k=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA&n=Rome',
              groupName: 'Rome',
              canReset: !afterReset,
              afterReset: afterReset,
            ),
          ),
          _overrides(),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.bySemanticsLabel('QR code of the invite link'),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('linkInviteReset')),
        afterReset ? findsNothing : findsOneWidget,
      );
      await _expectGuidelines(tester);
      handle.dispose();
    });
  }

  testWidgets('G52 step 9 relay settings', (tester) async {
    _phone(tester);
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _routed(
        const RelaySettingsPage(),
        _overrides(
          extra: [
            linkRelaysSetterProvider.overrideWithValue(
              (relays, {info = const {}}) async {},
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('relay-nos.lol')), findsOneWidget);
    await _expectGuidelines(tester);
    handle.dispose();
  });

  testWidgets('G68 sync sheet (Matrix group)', (tester) async {
    _phone(tester);
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _routed(
        const Scaffold(body: GroupSyncSheet(groupId: _g, link: false)),
        _overrides(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('groupSyncNow')), findsOneWidget);
    await _expectGuidelines(tester);
    handle.dispose();
  });

  // G54: the "Why Matrix?" pages (first and last, no account).
  for (final last in [false, true]) {
    testWidgets('G54 Why Matrix (${last ? 'ready' : 'links are easy'})', (
      tester,
    ) async {
      _phone(tester);
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _routed(const WhyMatrixPage(), testOverrides(localProfile: 'Anna')),
      );
      await tester.pumpAndSettle();
      if (last) {
        for (var i = 0; i < 2; i++) {
          await tester.tap(find.byKey(const Key('whyMatrixNext')));
          await tester.pumpAndSettle();
        }
        expect(find.byKey(const Key('whyMatrixConnect')), findsOneWidget);
      }
      await _expectGuidelines(tester);
      handle.dispose();
    });
  }

  testWidgets('G54 welcome choices', (tester) async {
    _phone(tester);
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _routed(const WelcomePage(startAtChoices: true), testOverrides()),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('welcomeChoices')), findsOneWidget);
    await _expectGuidelines(tester);
    handle.dispose();
  });

  testWidgets('G52 link disclosure', (tester) async {
    _phone(tester);
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_routed(const LinkDisclosurePage(), _overrides()));
    await tester.pumpAndSettle();
    await _expectGuidelines(tester);
    handle.dispose();
  });

  testWidgets('G52 step 12 join page: switch to a new link', (tester) async {
    _phone(tester);
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _routed(
        const JoinLinkPage(
          fragment: 'v=1&k=AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8&n=Trip',
        ),
        _overrides(
          extra: [
            linkJoinLookupProvider.overrideWithValue(
              (c, i) async => const LinkJoinLookup(
                preview: LinkGroupPreview(
                  groupId: 'g',
                  name: 'Trip',
                  people: [],
                ),
                blocker: LinkJoinError.otherLink,
              ),
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('joinLinkStart')));
    await tester.pumpAndSettle();
    final more = find.byKey(const Key('linkDisclosureContinue'));
    if (more.evaluate().isNotEmpty) {
      await tester.tap(more);
      await tester.pumpAndSettle();
    }
    expect(find.byKey(const Key('joinLinkSwitch')), findsOneWidget);
    await _expectGuidelines(tester);
    handle.dispose();
  });

  for (final picker in [false, true]) {
    testWidgets('G52 join page (${picker ? 'picker' : 'intro'})', (
      tester,
    ) async {
      _phone(tester);
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _routed(
          const JoinLinkPage(
            fragment:
                'v=1&k=AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8&n=Trip',
          ),
          _overrides(
            extra: [
              linkJoinLookupProvider.overrideWithValue(
                (c, i) async => const LinkJoinLookup(
                  preview: LinkGroupPreview(
                    groupId: 'g',
                    name: 'Trip',
                    people: [
                      LinkJoinPerson(
                        id: 'a',
                        name: 'Anna',
                        usedElsewhere: true,
                      ),
                      LinkJoinPerson(
                        id: 'b',
                        name: 'Ben',
                        usedElsewhere: false,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      if (picker) {
        await tester.tap(find.byKey(const Key('joinLinkStart')));
        await tester.pumpAndSettle();
        final more = find.byKey(const Key('linkDisclosureContinue'));
        if (more.evaluate().isNotEmpty) {
          await tester.tap(more);
          await tester.pumpAndSettle();
        }
        await tester.tap(find.byKey(const Key('joinLinkPerson-b')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('joinLinkPicker')), findsOneWidget);
      }
      await _expectGuidelines(tester);
      handle.dispose();
    });
  }

  group('add expense', () {
    for (final mode in ['Equally', 'Amounts', 'Shares', '%']) {
      testWidgets('split mode $mode', (tester) async {
        // Tall enough that no field is half scrolled out of view.
        _phone(tester, height: 1600);
        final handle = tester.ensureSemantics();
        final db = await _seed();
        addTearDown(db.close);
        final net = FakeMatrixNetwork();
        await tester.pumpWidget(
          _routed(const AddExpensePage(roomId: _g), [
            ...signingUiOverrides(),
            appDatabaseProvider.overrideWithValue(db),
            ledgerTransportProvider.overrideWith((ref) => net.clientFor(_me)),
          ]),
        );
        await tester.pumpAndSettle();
        await tester.enterText(find.byKey(const Key('expenseAmount')), '10');
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text(mode));
        await tester.tap(find.text(mode));
        await tester.pumpAndSettle();
        // Something left, so the "put the rest here" buttons show.
        if (mode == 'Amounts' || mode == '%') {
          final field = find.descendant(
            of: find.byType(Card),
            matching: find.byType(TextField),
          );
          await tester.enterText(field.first, '1');
          await tester.pumpAndSettle();
        }
        await _expectGuidelines(tester);
        handle.dispose();
      });
    }
  });

  testWidgets('G78 receipt photo on the expense form', (tester) async {
    _phone(tester, height: 1600);
    final handle = tester.ensureSemantics();
    final db = await _seed();
    addTearDown(db.close);
    await ExpensesDao(db).upsertExpenseLww(expenseCompanion(_expenses.first));
    final net = FakeMatrixNetwork();
    await tester.pumpWidget(
      _routed(AddExpensePage(roomId: _g, initial: _expenses.first), [
        ...signingUiOverrides(),
        appDatabaseProvider.overrideWithValue(db),
        ledgerTransportProvider.overrideWith((ref) => net.clientFor(_me)),
        receiptStoreProvider.overrideWithValue(
          InMemoryReceiptStore()..files['e1'] = Uint8List(4),
        ),
      ]),
    );
    await tester.pumpAndSettle();
    final thumb = find.byKey(const Key('receiptThumbnail'));
    await tester.ensureVisible(thumb);
    await tester.pumpAndSettle();
    // The thumbnail is a button named for what it does.
    expect(
      tester.getSemantics(thumb),
      matchesSemantics(
        tooltip: 'View receipt photo',
        isButton: true,
        hasTapAction: true,
        hasFocusAction: true,
        isFocusable: true,
      ),
    );
    await _expectGuidelines(tester);
    handle.dispose();
  });

  testWidgets('G77 item editor (split by items)', (tester) async {
    _phone(tester, height: 1600);
    final handle = tester.ensureSemantics();
    final db = await _seed();
    addTearDown(db.close);
    final net = FakeMatrixNetwork();
    await tester.pumpWidget(
      _routed(const AddExpensePage(roomId: _g), [
        ...signingUiOverrides(),
        appDatabaseProvider.overrideWithValue(db),
        ledgerTransportProvider.overrideWith((ref) => net.clientFor(_me)),
      ]),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('expenseAmount')), '10');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('splitItemize')));
    await tester.tap(find.byKey(const Key('splitItemize')));
    await tester.pumpAndSettle();
    // A rest, so the rest-mode choice and the result show.
    await tester.enterText(find.byKey(const Key('itemAmount-0')), '8');
    await tester.tap(find.byKey(const Key('itemsAdd')));
    await tester.pumpAndSettle();
    await _expectGuidelines(tester);
    handle.dispose();
  });

  group('screen reader', () {
    testWidgets('a ledger row reads as one sentence, incl. its category, '
        'note, amount, effect and sync state', (tester) async {
      _phone(tester);
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _routed(
          const ExpensesPage(roomId: _g),
          _overrides(
            syncStatus: const GroupSyncStatus(
              pendingPeers: {_bob},
              minPeerInSyncAt: 8000,
            ),
            extra: [
              // G78: e1 has a receipt photo on this device.
              receiptStoreProvider.overrideWithValue(
                InMemoryReceiptStore()..files['e1'] = Uint8List(1),
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      final data = tester.getSemantics(find.text('Pizza')).getSemanticsData();
      final spoken = '${data.label} ${data.tooltip}';
      for (final part in [
        'Food & drink',
        'Pizza',
        '€42.00',
        'You paid',
        'you lent €21.00',
        'Has a note',
        'Has a receipt photo',
        'Not synced yet',
      ]) {
        expect(spoken, contains(part));
      }
      // The day headers are headings.
      expect(
        tester.getSemantics(find.byKey(const Key('dayHeader')).first),
        isSemantics(isHeader: true),
      );
      // G68: the app-bar cloud is an enabled button (it opens the sync
      // sheet) whose label is the status — never a disabled button.
      final cloud = find.byKey(const Key('groupSyncButton'));
      final button = tester.widget<IconButton>(cloud);
      expect(button.tooltip, startsWith('Waiting for'));
      expect(button.onPressed, isNotNull);
      handle.dispose();
    });

    testWidgets('balance page: sections are headings', (tester) async {
      _phone(tester);
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _routed(const BalancePage(roomId: _g), _overrides()),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getSemantics(find.text('Suggested payments')),
        isSemantics(isHeader: true),
      );
      handle.dispose();
    });

    testWidgets('equal split: each checkbox is read with its person', (
      tester,
    ) async {
      _phone(tester);
      final handle = tester.ensureSemantics();
      final db = await _seed();
      addTearDown(db.close);
      await tester.pumpWidget(
        _routed(const AddExpensePage(roomId: _g), [
          ...signingUiOverrides(),
          appDatabaseProvider.overrideWithValue(db),
          ledgerTransportProvider.overrideWith(
            (ref) => FakeMatrixNetwork().clientFor(_me),
          ),
        ]),
      );
      await tester.pumpAndSettle();
      final box = find.byType(Checkbox).first;
      await tester.ensureVisible(box);
      expect(
        tester.getSemantics(box),
        isSemantics(label: 'Anna\n€0.00', isChecked: true),
      );
      handle.dispose();
    });
  });

  group('form flow (U12)', () {
    Future<AppDatabase> pumpForm(
      WidgetTester tester, {
      ExpenseModel? initial,
    }) async {
      _phone(tester);
      final db = await _seed();
      addTearDown(db.close);
      await tester.pumpWidget(
        _routed(AddExpensePage(roomId: _g, initial: initial), [
          ...signingUiOverrides(),
          appDatabaseProvider.overrideWithValue(db),
          ledgerTransportProvider.overrideWith(
            (ref) => FakeMatrixNetwork().clientFor(_me),
          ),
        ]),
      );
      await tester.pumpAndSettle();
      return db;
    }

    EditableText editable(WidgetTester tester, Key key) =>
        tester.widget<EditableText>(
          find.descendant(
            of: find.byKey(key),
            matching: find.byType(EditableText),
          ),
        );

    testWidgets('new expense: description focused, Next → amount (decimal '
        'keyboard, Done), category after the date', (tester) async {
      await pumpForm(tester);
      final desc = editable(tester, const Key('expenseDescription'));
      expect(desc.focusNode.hasFocus, isTrue);
      expect(desc.textInputAction, TextInputAction.next);

      await tester.enterText(find.byKey(const Key('expenseDescription')), 'X');
      await tester.testTextInput.receiveAction(TextInputAction.next);
      await tester.pumpAndSettle();
      final amount = editable(tester, const Key('expenseAmount'));
      expect(amount.focusNode.hasFocus, isTrue);
      expect(desc.focusNode.hasFocus, isFalse);
      expect(amount.textInputAction, TextInputAction.done);
      expect(
        amount.keyboardType,
        const TextInputType.numberWithOptions(decimal: true),
      );

      // Done closes the keyboard (nothing is submitted).
      await tester.enterText(find.byKey(const Key('expenseAmount')), '12');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(amount.focusNode.hasFocus, isFalse);
      expect(find.byType(AddExpensePage), findsOneWidget);

      // Order: description, amount, payer, date, category.
      double y(Key k) => tester.getTopLeft(find.byKey(k)).dy;
      expect(
        y(const Key('expenseAmount')),
        greaterThan(y(const Key('expenseDescription'))),
      );
      expect(
        y(const Key('expenseDate')),
        greaterThan(y(const Key('expenseAmount'))),
      );
      expect(
        y(const Key('categoryPickerField')),
        greaterThan(y(const Key('expenseDate'))),
      );
    });

    // G75: the edit form's app bar (Duplicate + Delete) meets the
    // guidelines too.
    testWidgets('edit expense page: Duplicate + Delete actions', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpForm(tester, initial: _expenses.first);
      expect(find.byTooltip(en.duplicateExpense), findsOneWidget);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      handle.dispose();
    });

    testWidgets('editing an expense opens without a keyboard', (tester) async {
      await pumpForm(tester, initial: _expenses.first);
      final desc = editable(tester, const Key('expenseDescription'));
      expect(desc.focusNode.hasFocus, isFalse);
    });

    testWidgets('payment dialog: blank amount focused, Done records it', (
      tester,
    ) async {
      _phone(tester);
      Object? result;
      await tester.pumpWidget(
        _routed(
          Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async => result = await showDialog<Object>(
                  context: context,
                  builder: (_) => const RecordPaymentDialog(
                    participants: {'a': 'Anna', 'b': 'Bob'},
                    initialFrom: 'a',
                    initialTo: 'b',
                    currency: 'EUR',
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
          const [],
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      final amount = editable(tester, const Key('paymentAmount'));
      expect(amount.focusNode.hasFocus, isTrue);
      expect(amount.textInputAction, TextInputAction.done);

      // Done with an incomplete draft does nothing …
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.byType(RecordPaymentDialog), findsOneWidget);
      // … with a valid amount it records the payment.
      await tester.enterText(find.byKey(const Key('paymentAmount')), '5');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.byType(RecordPaymentDialog), findsNothing);
      expect(result, isA<PaymentDraft>());
      expect((result! as PaymentDraft).cents, 500);
    });

    testWidgets('payment dialog prefilled from a debt: no keyboard', (
      tester,
    ) async {
      _phone(tester);
      await tester.pumpWidget(
        _routed(
          const Scaffold(
            body: RecordPaymentDialog(
              participants: {'a': 'Anna', 'b': 'Bob'},
              initialFrom: 'a',
              initialTo: 'b',
              initialCents: 100,
              currency: 'EUR',
            ),
          ),
          const [],
        ),
      );
      await tester.pumpAndSettle();
      expect(
        editable(tester, const Key('paymentAmount')).focusNode.hasFocus,
        isFalse,
      );
    });

    testWidgets('create group: name focused, Next → people field, which '
        'keeps the focus after adding (G64)', (tester) async {
      _phone(tester);
      await tester.pumpWidget(_routed(const CreateGroupPage(), _overrides()));
      await tester.pumpAndSettle();
      final name = tester.widget<EditableText>(
        find.descendant(
          of: find.byType(TextFormField),
          matching: find.byType(EditableText),
        ),
      );
      expect(name.focusNode.hasFocus, isTrue);
      expect(name.textInputAction, TextInputAction.next);
      await tester.enterText(find.byType(TextFormField), 'Rome');
      await tester.testTextInput.receiveAction(TextInputAction.next);
      await tester.pumpAndSettle();
      final person = editable(tester, const Key('createGroupPersonField'));
      expect(person.focusNode.hasFocus, isTrue);

      await tester.enterText(
        find.byKey(const Key('createGroupPersonField')),
        'Carl',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('createGroupPersonChip-0')), findsOneWidget);
      expect(person.focusNode.hasFocus, isTrue);
    });
  });
}
